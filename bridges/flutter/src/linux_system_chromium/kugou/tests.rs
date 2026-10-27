use super::*;
use kugou_client::web_playback_candidate::{CaptureSource, MediaFormat, WebQuality};
use provider_kugou::web_playback_candidate::CandidateSessionState;

#[path = "test_support.rs"]
mod support;
use support::*;

#[tokio::test]
async fn abort_before_profile_read_then_exactly_one_rust_owned_upstream_request() {
    let upstream = Upstream::start().await;
    let mut browser = SyntheticBrowser::start(Scenario::default(), upstream.address).await;
    let owner = AuthenticatedStandardCandidate::new(upstream.transport());
    let attempt = owner.begin_capture(&track_id()).unwrap();
    assert!(owner.is_capture_current(&attempt));
    assert_eq!(
        owner.begin_capture(&track_id()).unwrap_err(),
        WebPlaybackError::AttemptConsumed
    );

    assert!(browser.handle_next().await.unwrap().is_none());
    assert_eq!(
        browser.cdp.events.len(),
        2,
        "frame and pause precede navigate response"
    );
    assert!(browser.handle_next().await.unwrap().is_none());
    assert_eq!(
        browser.cdp.events.len(),
        1,
        "pause must not be lost while commanding"
    );
    let capture = browser.handle_next().await.unwrap().unwrap();
    assert_eq!(capture.source(), CaptureSource::OfficialWebGenerated);
    upstream.assert_counts(0, 0, 0);
    assert!(browser.commands("Fetch.continueRequest").is_empty());
    let aborts = browser.commands("Fetch.failRequest");
    assert_eq!(aborts.len(), 1);
    assert_eq!(aborts[0]["sessionId"], SESSION);
    assert_eq!(
        aborts[0]["params"],
        json!({"requestId":REQUEST, "errorReason":"Aborted"})
    );
    let methods = browser.methods();
    assert_eq!(
        methods,
        [
            "Target.setAutoAttach",
            "Fetch.enable",
            "Page.enable",
            "Network.setBypassServiceWorker",
            "Target.setAutoAttach",
            "Runtime.runIfWaitingForDebugger",
            "Page.navigate",
            "Fetch.failRequest",
            "Storage.getCookies",
        ]
    );
    for method in [
        "Fetch.enable",
        "Page.enable",
        "Network.setBypassServiceWorker",
        "Runtime.runIfWaitingForDebugger",
        "Page.navigate",
    ] {
        assert_eq!(browser.commands(method)[0]["sessionId"], SESSION);
    }
    assert_eq!(
        browser.commands("Target.setAutoAttach")[0]["params"],
        auto_attach_params()
    );
    assert_eq!(
        browser.commands("Fetch.enable")[0]["params"],
        json!({
            "patterns":[{"urlPattern":"*://*/play/songinfo*", "requestStage":"Request"}]
        })
    );
    assert_eq!(
        browser.commands("Page.navigate")[0]["params"]["url"],
        OFFICIAL_PAGE
    );
    assert!(
        browser.commands("Storage.getCookies")[0]
            .get("sessionId")
            .is_none()
    );

    let bound = owner
        .finish_capture(attempt, capture, unix_seconds().unwrap())
        .unwrap();
    upstream.assert_counts(0, 0, 0);
    let source = owner.resolve_captured_once(bound).await.unwrap();
    assert_eq!(source.media_format(), MediaFormat::Mp3);
    assert_eq!(source.quality(), Some(WebQuality::Standard));
    assert_eq!(source.media_host(), "offline-media.example.org");
    assert_eq!(owner.state(), CandidateSessionState::AttemptConsumed);
    owner.clear();
    assert_eq!(
        owner.begin_capture(&track_id()).unwrap_err(),
        WebPlaybackError::AttemptConsumed
    );
    browser.finish().await;
    upstream.assert_counts(1, 1, 0);
}

#[tokio::test]
async fn continue_control_really_forwards_a_browser_songinfo_request_to_the_listener() {
    let upstream = Upstream::start().await;
    let mut browser = SyntheticBrowser::start(Scenario::default(), upstream.address).await;
    browser.attach_and_navigate().await;
    upstream.assert_counts(0, 0, 0);
    // Intentionally bypass the interceptor to verify the negative oracle is live.
    browser
        .cdp
        .session_command(
            Some(SESSION),
            "Fetch.continueRequest",
            json!({"requestId":REQUEST}),
        )
        .await
        .unwrap();
    upstream.assert_counts(1, 0, 1);
    assert!(browser.commands("Fetch.failRequest").is_empty());
    assert!(browser.commands("Storage.getCookies").is_empty());
    browser.finish().await;
}

#[tokio::test]
async fn invalid_songinfo_routes_and_methods_are_aborted_without_cookie_read_or_replay() {
    let upstream = Upstream::start().await;
    for (name, url, method, extra) in [
        (
            "http",
            songinfo_url().replacen("https:", "http:", 1),
            "GET",
            json!({}),
        ),
        (
            "lookalike",
            songinfo_url().replace("wwwapi.kugou.com", "wwwapi.kugou.com.evil.invalid"),
            "GET",
            json!({}),
        ),
        (
            "wrong path",
            songinfo_url().replace("/play/songinfo?", "/play/songinfo/extra?"),
            "GET",
            json!({}),
        ),
        (
            "port",
            songinfo_url().replace("wwwapi.kugou.com", "wwwapi.kugou.com:8443"),
            "GET",
            json!({}),
        ),
        ("post", songinfo_url(), "POST", json!({})),
        (
            "body",
            songinfo_url(),
            "GET",
            json!({"postData":"synthetic-body"}),
        ),
        (
            "response stage",
            songinfo_url(),
            "GET",
            json!({"responseStatusCode":200}),
        ),
        (
            "omitted body",
            songinfo_url(),
            "GET",
            json!({"hasPostData":true}),
        ),
        (
            "response error stage",
            songinfo_url(),
            "GET",
            json!({"responseErrorReason":"Failed"}),
        ),
    ] {
        let mut event = paused();
        event["params"]["request"]["url"] = json!(url);
        event["params"]["request"]["method"] = json!(method);
        if let Some(body) = extra.get("postData") {
            event["params"]["request"]["postData"] = body.clone();
        }
        if let Some(body) = extra.get("hasPostData") {
            event["params"]["request"]["hasPostData"] = body.clone();
        }
        if let Some(error) = extra.get("responseErrorReason") {
            event["params"]["responseErrorReason"] = error.clone();
        }
        if let Some(status) = extra.get("responseStatusCode") {
            event["params"]["responseStatusCode"] = status.clone();
        }
        let mut browser = SyntheticBrowser::start(
            Scenario {
                events: vec![event],
                ..Default::default()
            },
            upstream.address,
        )
        .await;
        browser.attach_and_navigate().await;
        assert_eq!(
            browser.handle_next().await.unwrap_err(),
            GateFailure::Playback(WebPlaybackError::InvalidCapture),
            "{name}"
        );
        assert_eq!(browser.commands("Fetch.failRequest").len(), 1, "{name}");
        assert!(
            browser.commands("Fetch.continueRequest").is_empty(),
            "{name}"
        );
        assert!(browser.commands("Storage.getCookies").is_empty(), "{name}");
        browser.finish().await;
        upstream.assert_counts(0, 0, 0);
    }
}

#[tokio::test]
async fn capture_validator_rejections_still_abort_before_profile_read_and_never_replay() {
    let upstream = Upstream::start().await;
    for case in 0..6 {
        let mut event = paused();
        let expected = match case {
            0 => {
                event["params"]["request"]["url"] =
                    json!(songinfo_url().replace("wwwapi.kugou.com", "synthetic@wwwapi.kugou.com"));
                WebPlaybackError::InvalidCapture
            }
            1 => {
                event["params"]["request"]["url"] =
                    json!(format!("{}#synthetic-fragment", songinfo_url()));
                WebPlaybackError::InvalidCapture
            }
            2 => {
                event["params"]["request"]["url"] =
                    json!(format!("{}&hash={HASH}", songinfo_url()));
                WebPlaybackError::InvalidCapture
            }
            3 => {
                event["params"]["request"]["url"] = json!(format!("{}&songid=9", songinfo_url()));
                WebPlaybackError::OfficialWebTrackIdentityUnproven
            }
            4 => {
                event["params"]["request"]["headers"]["Authorization"] =
                    json!("synthetic-not-allowed");
                WebPlaybackError::ProtocolUnsupported
            }
            _ => {
                event["params"]["request"]["headers"]["Referer"] =
                    json!("https://unrelated.invalid/");
                WebPlaybackError::InvalidCapture
            }
        };
        let mut browser = SyntheticBrowser::start(
            Scenario {
                events: vec![event],
                ..Default::default()
            },
            upstream.address,
        )
        .await;
        browser.attach_and_navigate().await;
        assert_eq!(
            browser.handle_next().await.unwrap_err(),
            GateFailure::Playback(expected),
            "capture case {case}"
        );
        let methods = browser.methods();
        assert_eq!(
            &methods[methods.len() - 2..],
            ["Fetch.failRequest", "Storage.getCookies"]
        );
        assert!(browser.commands("Fetch.continueRequest").is_empty());
        browser.finish().await;
    }
    upstream.assert_counts(0, 0, 0);
}

#[tokio::test]
async fn workers_are_intercepted_before_resume_but_cannot_supply_page_provenance() {
    let upstream = Upstream::start().await;
    for kind in ["worker", "service_worker", "shared_worker"] {
        let mut browser = SyntheticBrowser::start(
            Scenario {
                target_kind: kind,
                ..Default::default()
            },
            upstream.address,
        )
        .await;
        assert!(browser.handle_next().await.unwrap().is_none());
        assert_eq!(
            browser.methods(),
            [
                "Target.setAutoAttach",
                "Fetch.enable",
                "Runtime.runIfWaitingForDebugger"
            ]
        );
        assert!(browser.handle_next().await.unwrap().is_none());
        assert_eq!(
            browser.handle_next().await.unwrap_err(),
            GateFailure::Playback(WebPlaybackError::OfficialWebTrackIdentityUnproven)
        );
        assert_eq!(browser.commands("Fetch.failRequest").len(), 1);
        assert!(browser.commands("Storage.getCookies").is_empty());
        assert!(browser.commands("Fetch.continueRequest").is_empty());
        browser.finish().await;
    }
    upstream.assert_counts(0, 0, 0);
}

#[tokio::test]
async fn nonofficial_or_unproved_frames_cannot_authorize_capture() {
    let upstream = Upstream::start().await;
    for (name, root, frame_id, resource) in [
        ("http page", "http://www.kugou.com/", FRAME, "XHR"),
        (
            "lookalike page",
            "https://www.kugou.com.evil.invalid/",
            FRAME,
            "XHR",
        ),
        ("api page", "https://wwwapi.kugou.com/", FRAME, "XHR"),
        ("blank page", "about:blank", FRAME, "XHR"),
        (
            "page userinfo",
            "https://synthetic@www.kugou.com/",
            FRAME,
            "XHR",
        ),
        ("unknown frame", OFFICIAL_PAGE, "different-frame", "XHR"),
        ("document resource", OFFICIAL_PAGE, FRAME, "Document"),
    ] {
        let mut event = paused();
        event["params"]["frameId"] = json!(frame_id);
        event["params"]["resourceType"] = json!(resource);
        let mut browser = SyntheticBrowser::start(
            Scenario {
                frame: frame(root),
                events: vec![event],
                ..Default::default()
            },
            upstream.address,
        )
        .await;
        browser.attach_and_navigate().await;
        assert_eq!(
            browser.handle_next().await.unwrap_err(),
            GateFailure::Playback(WebPlaybackError::OfficialWebTrackIdentityUnproven),
            "{name}"
        );
        assert_eq!(browser.commands("Fetch.failRequest").len(), 1);
        assert!(browser.commands("Storage.getCookies").is_empty());
        assert!(browser.commands("Fetch.continueRequest").is_empty());
        browser.finish().await;
    }
    upstream.assert_counts(0, 0, 0);
}

#[tokio::test]
async fn foreign_or_detached_sessions_never_supply_capture_provenance() {
    let upstream = Upstream::start().await;
    for detached in [false, true] {
        let mut event = paused();
        let events = if detached {
            vec![
                json!({"method":"Target.detachedFromTarget", "params":{"sessionId":SESSION}}),
                event,
            ]
        } else {
            event["sessionId"] = json!("foreign-session");
            vec![event]
        };
        let mut browser = SyntheticBrowser::start(
            Scenario {
                events,
                ..Default::default()
            },
            upstream.address,
        )
        .await;
        browser.attach_and_navigate().await;
        if detached {
            assert!(browser.handle_next().await.unwrap().is_none());
        }
        assert_eq!(
            browser.handle_next().await.unwrap_err(),
            GateFailure::Browser(CaptureFailure::DevtoolsInvalid)
        );
        assert!(
            browser.commands("Fetch.failRequest").is_empty(),
            "never address a foreign session"
        );
        assert!(browser.commands("Fetch.continueRequest").is_empty());
        assert!(browser.commands("Storage.getCookies").is_empty());
        browser.finish().await;
    }
    upstream.assert_counts(0, 0, 0);
}

#[tokio::test]
async fn root_navigation_and_frame_detachment_retire_previous_official_provenance() {
    let upstream = Upstream::start().await;
    for invalidation in [
        frame("https://unrelated.invalid/"),
        json!({"method":"Page.frameDetached", "sessionId":SESSION, "params":{"frameId":FRAME}}),
    ] {
        let mut browser = SyntheticBrowser::start(
            Scenario {
                events: vec![invalidation, paused()],
                ..Default::default()
            },
            upstream.address,
        )
        .await;
        browser.attach_and_navigate().await;
        assert!(browser.handle_next().await.unwrap().is_none());
        assert_eq!(
            browser.handle_next().await.unwrap_err(),
            GateFailure::Playback(WebPlaybackError::OfficialWebTrackIdentityUnproven)
        );
        assert_eq!(browser.commands("Fetch.failRequest").len(), 1);
        assert!(browser.commands("Storage.getCookies").is_empty());
        browser.finish().await;
    }
    upstream.assert_counts(0, 0, 0);
}

#[tokio::test]
async fn unrelated_requests_continue_and_unrelated_events_are_ignored() {
    let upstream = Upstream::start().await;
    let mut event = paused();
    event["params"]["request"]["url"] = json!("https://www.kugou.com/synthetic.js");
    let noise = json!({"method":"Network.loadingFinished", "sessionId":SESSION, "params":{}});
    let mut browser = SyntheticBrowser::start(
        Scenario {
            events: vec![noise, event, paused()],
            ..Default::default()
        },
        upstream.address,
    )
    .await;
    browser.attach_and_navigate().await;
    assert!(browser.handle_next().await.unwrap().is_none());
    assert!(browser.handle_next().await.unwrap().is_none());
    assert_eq!(browser.commands("Fetch.continueRequest").len(), 1);
    assert!(browser.commands("Storage.getCookies").is_empty());
    assert!(browser.handle_next().await.unwrap().is_some());
    assert_eq!(browser.commands("Fetch.failRequest").len(), 1);
    browser.finish().await;
    upstream.assert_counts(0, 0, 0);
}

#[tokio::test]
async fn profile_cookies_are_required_and_captured_cookie_is_never_an_authority() {
    let upstream = Upstream::start().await;
    for case in 0..10 {
        let mut profile = cookies();
        let mut event = paused();
        event["params"]["request"]["headers"]["Cookie"] = json!("KugooID=42; t=synthetic-token");
        let expected = match case {
            0 => {
                profile = json!([]);
                WebPlaybackError::LoginRequired
            }
            1 => {
                profile[1]["domain"] = json!("kugou.com");
                WebPlaybackError::LoginRequired
            }
            2 => {
                profile[1]["domain"] = json!(".kugou.com.evil.invalid");
                WebPlaybackError::LoginRequired
            }
            3 => {
                profile[1]["path"] = json!("/other");
                WebPlaybackError::LoginRequired
            }
            4 => {
                profile[1]["value"] = json!("different-profile-token");
                WebPlaybackError::SessionContextRejected
            }
            5 => {
                event["params"]["request"]["headers"]["Cookie"] =
                    json!("KugooID=42; t=forged-header-token");
                WebPlaybackError::SessionContextRejected
            }
            6 => {
                event["params"]["request"]["headers"]["Cookie"] =
                    json!("KugooID=42; t=synthetic-token; analytics=analytics-sentinel");
                WebPlaybackError::ProtocolUnsupported
            }
            7 => {
                let duplicate = profile[1].clone();
                profile.as_array_mut().unwrap().push(duplicate);
                WebPlaybackError::InvalidCapture
            }
            8 => {
                profile[1]["value"] = json!("bad;value");
                WebPlaybackError::InvalidCapture
            }
            _ => {
                profile[1]["domain"] = json!("www.kugou.com");
                WebPlaybackError::LoginRequired
            }
        };
        let mut browser = SyntheticBrowser::start(
            Scenario {
                cookies: profile,
                events: vec![event],
                ..Default::default()
            },
            upstream.address,
        )
        .await;
        browser.attach_and_navigate().await;
        assert_eq!(
            browser.handle_next().await.unwrap_err(),
            GateFailure::Playback(expected),
            "cookie case {case}"
        );
        assert_eq!(browser.commands("Fetch.failRequest").len(), 1);
        assert_eq!(browser.commands("Storage.getCookies").len(), 1);
        assert!(browser.commands("Fetch.continueRequest").is_empty());
        browser.finish().await;
    }
    upstream.assert_counts(0, 0, 0);
}

#[tokio::test]
async fn no_captured_cookie_header_replays_only_minimal_profile_subset() {
    let upstream = Upstream::start().await;
    let mut profile = cookies();
    profile
        .as_array_mut()
        .unwrap()
        .push(json!({"name":"analytics", "value":"analytics-sentinel",
        "domain":".kugou.com", "path":"/", "secure":true}));
    let mut browser = SyntheticBrowser::start(
        Scenario {
            cookies: profile,
            ..Default::default()
        },
        upstream.address,
    )
    .await;
    let owner = AuthenticatedStandardCandidate::new(upstream.transport());
    let attempt = owner.begin_capture(&track_id()).unwrap();
    browser.attach_and_navigate().await;
    let capture = browser.handle_next().await.unwrap().unwrap();
    let bound = owner
        .finish_capture(attempt, capture, unix_seconds().unwrap())
        .unwrap();
    owner.resolve_captured_once(bound).await.unwrap();
    browser.finish().await;
    upstream.assert_counts(1, 1, 0);
}

#[tokio::test]
async fn replacing_generation_during_capture_or_before_replay_performs_no_upstream_io() {
    let upstream = Upstream::start().await;
    for replace_before_binding in [false, true] {
        let owner = AuthenticatedStandardCandidate::new(upstream.transport());
        let attempt = owner.begin_capture(&track_id()).unwrap();
        let mut browser = SyntheticBrowser::start(Scenario::default(), upstream.address).await;
        browser.attach_and_navigate().await;
        if replace_before_binding {
            owner.clear();
            assert!(!owner.is_capture_current(&attempt));
        }
        let capture = browser.handle_next().await.unwrap().unwrap();
        let bound = owner.finish_capture(attempt, capture, unix_seconds().unwrap());
        if replace_before_binding {
            assert_eq!(bound.unwrap_err(), WebPlaybackError::Replaced);
        } else {
            owner.clear();
            assert_eq!(
                owner
                    .resolve_captured_once(bound.unwrap())
                    .await
                    .unwrap_err(),
                WebPlaybackError::Replaced
            );
        }
        assert_eq!(
            owner.begin_capture(&track_id()).unwrap_err(),
            WebPlaybackError::AttemptConsumed
        );
        browser.finish().await;
    }
    upstream.assert_counts(0, 0, 0);
}

#[tokio::test]
async fn official_capture_for_a_different_current_track_is_never_replayed() {
    let upstream = Upstream::start().await;
    let owner = AuthenticatedStandardCandidate::new(upstream.transport());
    let other = TrackId::new(
        provider_kugou::provider_id(),
        format!("v1:9:{HASH}:8:180:8"),
    )
    .unwrap();
    let attempt = owner.begin_capture(&other).unwrap();
    let mut browser = SyntheticBrowser::start(Scenario::default(), upstream.address).await;
    browser.attach_and_navigate().await;
    let capture = browser.handle_next().await.unwrap().unwrap();
    assert_eq!(
        owner
            .finish_capture(attempt, capture, unix_seconds().unwrap())
            .unwrap_err(),
        WebPlaybackError::OfficialWebTrackIdentityUnproven
    );
    assert_eq!(
        owner.begin_capture(&other).unwrap_err(),
        WebPlaybackError::AttemptConsumed
    );
    browser.finish().await;
    upstream.assert_counts(0, 0, 0);
}

#[tokio::test]
async fn repeated_browser_candidates_are_all_aborted_and_do_not_refill_owner_admission() {
    let upstream = Upstream::start().await;
    let owner = AuthenticatedStandardCandidate::new(upstream.transport());
    let attempt = owner.begin_capture(&track_id()).unwrap();
    let mut second = paused();
    second["params"]["requestId"] = json!("second-paused-request");
    let mut browser = SyntheticBrowser::start(
        Scenario {
            events: vec![paused(), second],
            ..Default::default()
        },
        upstream.address,
    )
    .await;
    browser.attach_and_navigate().await;
    let capture = browser.handle_next().await.unwrap().unwrap();
    let bound = owner
        .finish_capture(attempt, capture, unix_seconds().unwrap())
        .unwrap();
    owner.resolve_captured_once(bound).await.unwrap();
    drop(browser.handle_next().await.unwrap().unwrap());
    assert_eq!(browser.commands("Fetch.failRequest").len(), 2);
    assert!(browser.commands("Fetch.continueRequest").is_empty());
    assert_eq!(
        owner.begin_capture(&track_id()).unwrap_err(),
        WebPlaybackError::AttemptConsumed
    );
    browser.finish().await;
    upstream.assert_counts(1, 1, 0);
}

#[tokio::test]
async fn capture_bound_debug_and_presence_diagnostics_contain_no_secret_material() {
    let upstream = Upstream::start().await;
    let owner = AuthenticatedStandardCandidate::new(upstream.transport());
    let attempt = owner.begin_capture(&track_id()).unwrap();
    assert_eq!(format!("{attempt:?}"), "CaptureAttempt([REDACTED])");
    let mut browser = SyntheticBrowser::start(Scenario::default(), upstream.address).await;
    browser.attach_and_navigate().await;
    let capture = browser.handle_next().await.unwrap().unwrap();
    assert_eq!(format!("{capture:?}"), "OfficialWebCapture([REDACTED])");
    assert_eq!(
        presence_diagnostic(capture.presence()),
        "KUGOU_CAPTURE_SOURCE=OFFICIAL_WEB\nHAS_SIGNATURE=1\nHAS_MID=1\nHAS_DFID=1\nHAS_USERID=1\nHAS_TOKEN=1"
    );
    assert_eq!(
        presence_diagnostic(CapturePresence {
            signature: false,
            mid: false,
            dfid: false,
            userid: false,
            token: false
        }),
        "KUGOU_CAPTURE_SOURCE=OFFICIAL_WEB\nHAS_SIGNATURE=0\nHAS_MID=0\nHAS_DFID=0\nHAS_USERID=0\nHAS_TOKEN=0"
    );
    let parsed = profile_cookies(cookies()).unwrap();
    assert_eq!(format!("{:?}", parsed[1]), "ProfileCookie([REDACTED])");
    let bound = owner
        .finish_capture(attempt, capture, unix_seconds().unwrap())
        .unwrap();
    assert_eq!(format!("{bound:?}"), "BoundCapture([REDACTED])");
    let source = owner.resolve_captured_once(bound).await.unwrap();
    assert_eq!(format!("{source:?}"), "StandardWebSource([REDACTED])");
    browser.finish().await;
    upstream.assert_counts(1, 1, 0);
}

#[tokio::test]
async fn authorization_and_cancelled_generation_fail_before_browser_discovery() {
    let upstream = Upstream::start().await;
    let owner = AuthenticatedStandardCandidate::new(upstream.transport());
    assert_eq!(
        run_gate(
            &owner,
            &track_id(),
            false,
            || true,
            |_| panic!("no media approval")
        )
        .await,
        Err(GateFailure::HumanAuthorizationRequired)
    );
    assert_eq!(
        run_gate(
            &owner,
            &track_id(),
            true,
            || false,
            |_| panic!("no media approval")
        )
        .await,
        Err(GateFailure::Browser(CaptureFailure::Cancelled))
    );
    assert_eq!(
        owner.begin_capture(&track_id()).unwrap_err(),
        WebPlaybackError::AttemptConsumed
    );
    upstream.assert_counts(0, 0, 0);
}

#[tokio::test]
async fn cdp_retains_fifo_events_ahead_of_response_and_resets_accounting_when_drained() {
    let (mut cdp, mut server) = cdp_peer(|mut socket| async move {
        let command = read_command(&mut socket).await;
        send_json(
            &mut socket,
            json!({"method":"Synthetic.first", "params":{}}),
        )
        .await;
        send_json(&mut socket, paused()).await;
        send_json(&mut socket, json!({"id":9999, "result":{}})).await;
        send_json(&mut socket, reply(&command, json!({"ok":true}))).await;
    })
    .await;
    cdp.retain_events = true;
    assert_eq!(
        cdp.session_command(Some(SESSION), "Synthetic.command", json!({}))
            .await
            .unwrap(),
        json!({"ok":true})
    );
    assert_eq!(cdp.events.len(), 2);
    let accounted = cdp.event_bytes;
    assert!(accounted > 0);
    assert_eq!(
        cdp.next_event().await.unwrap().unwrap()["method"],
        "Synthetic.first"
    );
    assert_eq!(
        cdp.event_bytes, accounted,
        "accounting stays conservative until drained"
    );
    assert_eq!(cdp.next_event().await.unwrap().unwrap(), paused());
    assert_eq!(cdp.event_bytes, 0);
    server.join().await;
}

#[tokio::test]
async fn cdp_default_mode_does_not_retain_events_for_the_existing_netease_path() {
    let (mut cdp, mut server) = cdp_peer(|mut socket| async move {
        let command = read_command(&mut socket).await;
        send_json(&mut socket, paused()).await;
        send_json(&mut socket, reply(&command, json!({}))).await;
    })
    .await;
    assert!(!cdp.retain_events);
    cdp.command("Storage.getCookies", json!({})).await.unwrap();
    assert!(cdp.events.is_empty());
    assert_eq!(cdp.event_bytes, 0);
    server.join().await;
}

#[tokio::test]
async fn cdp_event_count_and_aggregate_bytes_are_bounded_fail_closed() {
    for bytes_overflow in [false, true] {
        let (mut cdp, mut server) = cdp_peer(move |mut socket| async move {
            read_command(&mut socket).await;
            for index in 0..if bytes_overflow { 2 } else { 129 } {
                send_json(&mut socket, json!({"method":"Synthetic.flood", "params":{
                    "index":index, "payload":if bytes_overflow { "x".repeat(CDP_RESPONSE_LIMIT / 2) } else { String::new() }
                }})).await;
            }
        }).await;
        cdp.retain_events = true;
        assert_eq!(
            cdp.command("Synthetic.command", json!({}))
                .await
                .unwrap_err(),
            CaptureFailure::DevtoolsInvalid
        );
        assert_eq!(cdp.events.len(), if bytes_overflow { 1 } else { 128 });
        assert!(cdp.event_bytes <= CDP_RESPONSE_LIMIT);
        while !cdp.events.is_empty() {
            cdp.next_event().await.unwrap();
        }
        assert_eq!(cdp.event_bytes, 0);
        server.join().await;
    }
}

#[tokio::test]
async fn cdp_rejects_oversized_and_malformed_messages_in_command_and_event_paths() {
    for command_path in [false, true] {
        for oversized in [false, true] {
            let (mut cdp, mut server) = cdp_peer(move |mut socket| async move {
                if command_path { read_command(&mut socket).await; }
                let text = if oversized {
                    json!({"method":"Synthetic.large", "params":{"data":"x".repeat(CDP_RESPONSE_LIMIT)}}).to_string()
                } else { "not-json".to_owned() };
                socket.send(Message::Text(text.into())).await.unwrap();
            }).await;
            let failure = if command_path {
                cdp.command("Synthetic.command", json!({}))
                    .await
                    .unwrap_err()
            } else {
                cdp.next_event().await.unwrap_err()
            };
            assert_eq!(failure, CaptureFailure::DevtoolsInvalid);
            server.join().await;
        }
    }
}

#[tokio::test]
async fn cdp_rejects_foreign_session_error_missing_result_and_close_responses() {
    for case in 0..5 {
        let (mut cdp, mut server) = cdp_peer(move |mut socket| async move {
            let command = read_command(&mut socket).await;
            if case == 4 {
                socket.close(None).await.unwrap();
                return;
            }
            let mut response = reply(&command, json!({}));
            match case {
                0 => response["sessionId"] = json!("foreign-session"),
                1 => {
                    response.as_object_mut().unwrap().remove("sessionId");
                }
                2 => response["error"] = json!({"code":-1, "message":"synthetic failure"}),
                _ => {
                    response.as_object_mut().unwrap().remove("result");
                }
            }
            send_json(&mut socket, response).await;
        })
        .await;
        assert_eq!(
            cdp.session_command(Some(SESSION), "Synthetic.command", json!({}))
                .await
                .unwrap_err(),
            if case == 4 {
                CaptureFailure::BrowserClosed
            } else {
                CaptureFailure::DevtoolsInvalid
            }
        );
        server.join().await;
    }
}

#[tokio::test]
async fn cdp_event_polling_is_bounded_and_close_is_a_terminal_error() {
    let (mut cdp, mut server) = cdp_peer(|mut socket| async move {
        let command = read_command(&mut socket).await;
        send_json(&mut socket, reply(&command, json!({}))).await;
        // Wait for the explicit command so the quiet-poll assertion has no race.
        read_command(&mut socket).await;
        socket.close(None).await.unwrap();
    })
    .await;
    cdp.command("Synthetic.ready", json!({})).await.unwrap();
    assert!(cdp.next_event().await.unwrap().is_none());
    cdp.socket
        .send(Message::Text(
            json!({"id":2,"method":"Synthetic.close","params":{}})
                .to_string()
                .into(),
        ))
        .await
        .unwrap();
    assert_eq!(
        cdp.next_event().await.unwrap_err(),
        CaptureFailure::BrowserClosed
    );
    server.join().await;
}

#[tokio::test]
async fn cdp_command_id_and_queue_byte_accounting_cannot_overflow() {
    let (mut cdp, mut server) = cdp_peer(|mut socket| async move {
        assert!(matches!(
            socket.next().await.unwrap().unwrap(),
            Message::Close(_)
        ));
    })
    .await;
    cdp.next_id = u64::MAX;
    assert_eq!(
        cdp.command("Synthetic.never_sent", json!({}))
            .await
            .unwrap_err(),
        CaptureFailure::DevtoolsInvalid
    );
    assert_eq!(cdp.next_id, u64::MAX);
    cdp.event_bytes = usize::MAX;
    assert_eq!(
        cdp.queue_event(paused(), 1),
        Err(CaptureFailure::DevtoolsInvalid)
    );
    assert!(cdp.events.is_empty());
    cdp.socket.close(None).await.unwrap();
    server.join().await;
}

#[test]
fn profile_cookie_cdp_shape_and_count_bounds_fail_closed() {
    assert_eq!(
        profile_cookies(Value::Null).unwrap_err(),
        CaptureFailure::DevtoolsInvalid
    );
    for key in ["name", "value", "domain", "path", "secure"] {
        let mut profile = cookies();
        profile[0].as_object_mut().unwrap().remove(key);
        assert_eq!(
            profile_cookies(profile).unwrap_err(),
            CaptureFailure::DevtoolsInvalid
        );
    }
    let cookie = cookies()[0].clone();
    assert_eq!(
        profile_cookies(json!(vec![cookie; 2049])).unwrap_err(),
        CaptureFailure::InvalidCredential
    );
}

#[tokio::test]
async fn fresh_private_profiles_and_synthetic_child_exit_cleanup_leave_default_profile_untouched() {
    // This is a synthetic HOME for the child only. Never inspect the user's real profile.
    let home = tempfile::tempdir().unwrap();
    let default_profile = home.path().join(".config/chromium/Default");
    std::fs::create_dir_all(&default_profile).unwrap();
    let sentinel = default_profile.join("synthetic-sentinel");
    std::fs::write(&sentinel, b"default-profile-must-stay-untouched").unwrap();
    let other_profile = create_profile().unwrap();
    for already_exited in [false, true] {
        let profile = create_profile().unwrap();
        let path = profile.path().to_path_buf();
        assert_ne!(path, other_profile.path());
        assert!(!path.starts_with(home.path()));
        assert_eq!(
            std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o700
        );
        assert_eq!(std::fs::read_dir(&path).unwrap().count(), 0);
        let mut child = Command::new("/bin/sleep")
            .arg(if already_exited { "0" } else { "60" })
            .env("HOME", home.path())
            .env("XDG_CONFIG_HOME", home.path().join(".config"))
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .unwrap();
        if already_exited {
            child.wait().await.unwrap();
            assert_eq!(
                require_active(&mut child, &|| true),
                Err(CaptureFailure::BrowserClosed)
            );
        } else {
            assert_eq!(
                require_active(&mut child, &|| false),
                Err(CaptureFailure::Cancelled)
            );
            require_active(&mut child, &|| true).unwrap();
        }
        let mut running = RunningBrowser {
            child,
            profile: Some(profile),
            profile_path: path.clone(),
            port: 0,
            websocket_path: String::new(),
        };
        let child_pid = running.child.id();
        let (mut cdp, mut server) = cdp_peer(move |mut socket| async move {
            let command = read_command(&mut socket).await;
            assert_eq!(command["method"], "Browser.close");
            assert!(command.get("sessionId").is_none());
            if let Some(pid) = child_pid {
                kill(Pid::from_raw(i32::try_from(pid).unwrap()), Signal::SIGTERM).unwrap();
            }
            assert!(matches!(
                socket.next().await.unwrap().unwrap(),
                Message::Close(_)
            ));
        })
        .await;
        timeout(
            Duration::from_secs(5),
            shutdown_browser(&mut running, Some(&mut cdp)),
        )
        .await
        .unwrap()
        .unwrap();
        server.join().await;
        assert!(running.child.try_wait().unwrap().is_some());
        assert!(running.profile.is_none());
        assert!(!path.exists());
        assert!(profile_processes(&path).is_empty());
        assert!(other_profile.path().is_dir());
        assert!(std::fs::read(&sentinel).unwrap() == b"default-profile-must-stay-untouched");
    }
}

#[tokio::test]
async fn rejected_browser_close_keeps_fetch_attached_until_browser_exit() {
    let upstream = Upstream::start().await;
    let profile = create_profile().unwrap();
    let path = profile.path().to_owned();
    let child = Command::new("/bin/sleep")
        .arg("60")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .unwrap();
    let pid = Pid::from_raw(i32::try_from(child.id().unwrap()).unwrap());
    let mut running = RunningBrowser {
        child,
        profile: Some(profile),
        profile_path: path.clone(),
        port: 0,
        websocket_path: String::new(),
    };
    let address = upstream.address;
    let (mut cdp, mut server) = cdp_peer(move |mut socket| async move {
        let command = read_command(&mut socket).await;
        assert_eq!(command["method"], "Browser.close");
        send_json(
            &mut socket,
            json!({"id":command["id"], "error":{"code":-1,"message":"synthetic rejection"}}),
        )
        .await;
        // A browser with an outstanding paused request would release it on detach.
        if timeout(Duration::from_millis(100), socket.next())
            .await
            .is_ok()
        {
            let mut stream = TcpStream::connect(address).await.unwrap();
            stream
                .write_all(
                    b"GET /play/songinfo?synthetic HTTP/1.1\r\nX-Synthetic-Owner: Browser\r\n\r\n",
                )
                .await
                .unwrap();
            panic!("Fetch detached while synthetic browser remained alive");
        }
        kill(pid, Signal::SIGTERM).unwrap();
        assert!(matches!(
            socket.next().await.unwrap().unwrap(),
            Message::Close(_)
        ));
    })
    .await;
    cdp.retain_events = true;
    timeout(
        Duration::from_secs(5),
        shutdown_browser(&mut running, Some(&mut cdp)),
    )
    .await
    .unwrap()
    .unwrap();
    server.join().await;
    assert!(running.child.try_wait().unwrap().is_some());
    assert!(!path.exists());
    upstream.assert_counts(0, 0, 0);
}

#[tokio::test]
async fn forced_shutdown_reaps_owned_child_even_without_profile_in_process_arguments() {
    let upstream = Upstream::start().await;
    let profile = create_profile().unwrap();
    let path = profile.path().to_owned();
    let child = Command::new("/bin/sleep")
        .arg("60")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .unwrap();
    let pid = Pid::from_raw(i32::try_from(child.id().unwrap()).unwrap());
    let mut running = RunningBrowser {
        child,
        profile: Some(profile),
        profile_path: path.clone(),
        port: 0,
        websocket_path: String::new(),
    };
    assert!(profile_processes(&path).is_empty());
    let address = upstream.address;
    let (mut cdp, mut server) = cdp_peer(move |mut socket| async move {
        let command = read_command(&mut socket).await;
        assert_eq!(command["method"], "Browser.close");
        send_json(
            &mut socket,
            json!({"id":command["id"],"error":{"code":-1,"message":"synthetic rejection"}}),
        )
        .await;
        assert!(matches!(
            socket.next().await.unwrap().unwrap(),
            Message::Close(_)
        ));
        // The browser surrogate does not cooperate with Browser.close and has
        // no profile-bearing argv. Detachment while it lives would forward.
        if kill(pid, None).is_ok() {
            let _ = TcpStream::connect(address).await.unwrap();
            panic!("owned child was not reaped before Fetch detachment");
        }
    })
    .await;
    cdp.retain_events = true;
    timeout(
        Duration::from_secs(20),
        shutdown_browser(&mut running, Some(&mut cdp)),
    )
    .await
    .unwrap()
    .unwrap();
    server.join().await;
    assert!(running.child.try_wait().unwrap().is_some());
    assert!(!path.exists());
    upstream.assert_counts(0, 0, 0);
}

#[tokio::test]
async fn cancellation_during_range_rejects_late_success_and_failure() {
    for result in [Ok(()), Err(WebPlaybackError::RiskControl)] {
        let owner = AuthenticatedStandardCandidate::new(());
        let attempt = owner.begin_capture(&track_id()).unwrap();
        let current = owner.capture_current_check(&attempt);
        drop(attempt);
        let (release, pending) = tokio::sync::oneshot::channel();
        let range = async { pending.await.unwrap() };
        tokio::pin!(range);
        assert!(futures_util::poll!(&mut range).is_pending());
        owner.clear();
        release.send(result).unwrap();
        assert_eq!(
            accept_range_result(&owner, &current, range.await),
            Err(GateFailure::Playback(WebPlaybackError::Replaced))
        );
    }
}

#[test]
fn final_gate_diagnostics_are_fixed_categories_not_debug_or_secret_material() {
    assert_eq!(
        result_diagnostic(Err(GateFailure::Playback(
            WebPlaybackError::OfficialWebTrackIdentityUnproven
        ))),
        "KUGOU_GATE result=BLOCKED reason=OFFICIAL_WEB_TRACK_IDENTITY_UNPROVEN production_enabled=false"
    );
    assert_eq!(
        result_diagnostic(Err(GateFailure::Browser(CaptureFailure::CleanupFailed))),
        "KUGOU_GATE result=BLOCKED reason=CLEANUP_FAILED production_enabled=false"
    );
    for range in [false, true] {
        assert_eq!(
            result_diagnostic(Ok(range)),
            format!(
                "KUGOU_GATE result=STANDARD_SOURCE_ONLY range_verified={range} account_summary_verified=false production_enabled=false"
            )
        );
    }
}
