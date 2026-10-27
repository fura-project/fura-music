use kugou_client::{Response, web_playback_candidate::*};
use music_domain::{ProviderId, TrackId};
use provider_kugou::{provider_id, web_playback_candidate::*};
use serde_json::json;
use std::{
    future::{Future, poll_fn},
    pin::pin,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
    task::Poll,
};

const NOW: u64 = 1_800_000_000;
const HASH: &str = "11111111111111111111111111111111";
fn id() -> TrackId {
    TrackId::new(provider_id(), format!("v1:9:{HASH}:8:180:7")).unwrap()
}
fn captured() -> String {
    format!(
        "https://wwwapi.kugou.com/play/songinfo?srcappid=2919&clientver=20000&clienttime={NOW}&mid=synthetic-mid&uuid=synthetic-uuid&dfid=synthetic-web-dfid&appid=1014&platid=4&hash={HASH}&album_id=7&token=synthetic-token&userid=42&signature=00000000000000000000000000000000"
    )
}
#[derive(Default)]
struct Gate {
    ready: AtomicBool,
    calls: AtomicUsize,
    outcome: AtomicUsize,
    format: AtomicUsize,
    non_standard: AtomicBool,
}
struct Mock(Arc<Gate>);
impl WebPlaybackTransport for Mock {
    async fn send_web(
        &self,
        request: &CapturedWebRequest,
    ) -> Result<WebPlaybackResponse, WebPlaybackError> {
        self.0.calls.fetch_add(1, Ordering::SeqCst);
        assert_eq!(request.url(), captured());
        assert_eq!(request.cookie_header(), "KugooID=42; t=synthetic-token");
        poll_fn(|_| {
            if self.0.ready.load(Ordering::SeqCst) {
                Poll::Ready(())
            } else {
                Poll::Pending
            }
        })
        .await;
        let (ext, bitrate, size) = match self.0.format.load(Ordering::SeqCst) {
            1 => ("ogg", 64_000, 1_440_000),
            2 => ("m4a", 96_000, 2_160_000),
            _ => ("mp3", 128_000, 2_880_000),
        };
        let quality = if self.0.non_standard.load(Ordering::SeqCst) {
            "high"
        } else {
            "standard"
        };
        match self.0.outcome.load(Ordering::SeqCst) {
            1 => Err(WebPlaybackError::Network),
            2 => Err(WebPlaybackError::RiskControl),
            3 => Err(WebPlaybackError::RateLimited),
            _ => Ok(WebPlaybackResponse {
                security_challenge: false,
                response: Response {
                    status: 200,
                    content_type: Some("application/json".into()),
                    body: serde_json::to_vec(&json!({"status":1,"data":{
                    "hash":HASH,"album_audio_id":9,"album_id":7,"privilege":0,"is_free_part":0,
                    "play_url":"https://synthetic-media.kugou.com/a.mp3", "bitrate":bitrate,
                    "timelength":180_000,"filesize":size,"extname":ext,"quality":quality}}))
                    .unwrap(),
                },
            }),
        }
    }
}
fn capture() -> OfficialWebCapture {
    let cookies: Vec<_> = [("KugooID", "42"), ("t", "synthetic-token")]
        .into_iter()
        .map(|(name, value)| ProfileCookie {
            name: name.into(),
            value: value.into(),
            domain: ".kugou.com".into(),
            path: "/".into(),
            secure: true,
        })
        .collect();
    let headers: Vec<_> = [
        ("User-Agent", "SyntheticOfficialBrowser/1"),
        ("Origin", "https://www.kugou.com"),
        ("Referer", "https://www.kugou.com/"),
    ]
    .into_iter()
    .map(|(k, v)| (k.into(), v.into()))
    .collect();
    OfficialWebCapture::from_cdp(&captured(), "GET", &headers, &cookies, NOW).unwrap()
}

fn bound(owner: &AuthenticatedStandardCandidate<Mock>) -> BoundCapture {
    let attempt = owner.begin_capture(&id()).unwrap();
    owner.finish_capture(attempt, capture(), NOW).unwrap()
}

#[tokio::test]
async fn foreign_invalid_context_expired_and_wrong_identity_captures_make_zero_requests() {
    let gate = Arc::new(Gate::default());
    let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
    assert_eq!(owner.state(), CandidateSessionState::Missing);
    for provider in ["qq-music", "netease-cloud-music"] {
        let foreign = TrackId::new(ProviderId::new(provider).unwrap(), id().opaque()).unwrap();
        assert_eq!(
            owner.begin_capture(&foreign).unwrap_err(),
            WebPlaybackError::InvalidCapture
        );
    }
    let missing_album = TrackId::new(provider_id(), format!("v1:9:{HASH}:8:180:-")).unwrap();
    assert_eq!(
        owner.begin_capture(&missing_album).unwrap_err(),
        WebPlaybackError::OfficialWebTrackIdentityUnproven
    );
    let attempt = owner.begin_capture(&id()).unwrap();
    assert_eq!(
        owner
            .finish_capture(attempt, capture(), NOW + 301)
            .unwrap_err(),
        WebPlaybackError::InvalidCapture
    );
    assert_eq!(gate.calls.load(Ordering::SeqCst), 0);
    assert_eq!(owner.state(), CandidateSessionState::Pending);
    assert_eq!(
        owner.begin_capture(&id()).unwrap_err(),
        WebPlaybackError::AttemptConsumed
    );
    let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
    let other = TrackId::new(provider_id(), format!("v1:9:{HASH}:8:180:8")).unwrap();
    let attempt = owner.begin_capture(&other).unwrap();
    assert_eq!(
        owner.finish_capture(attempt, capture(), NOW).unwrap_err(),
        WebPlaybackError::OfficialWebTrackIdentityUnproven
    );
    assert_eq!(gate.calls.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn current_exact_source_is_one_shot_and_never_advertises_authenticated() {
    let gate = Arc::new(Gate::default());
    gate.ready.store(true, Ordering::SeqCst);
    let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
    let bound = bound(&owner);
    let source = owner.resolve_captured_once(bound).await.unwrap();
    assert_eq!(source.url(), "https://synthetic-media.kugou.com/a.mp3");
    assert_eq!(owner.state(), CandidateSessionState::AttemptConsumed);
    owner.clear(); // Even same-account relogin must not refill admission.
    assert_eq!(
        owner.begin_capture(&id()).unwrap_err(),
        WebPlaybackError::AttemptConsumed
    );
    assert_eq!(gate.calls.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn standard_is_independent_of_container_and_non_standard_never_reopens_admission() {
    for (index, format) in [MediaFormat::Mp3, MediaFormat::Ogg, MediaFormat::Mp4Aac]
        .into_iter()
        .enumerate()
    {
        for non_standard in [false, true] {
            let gate = Arc::new(Gate::default());
            gate.ready.store(true, Ordering::SeqCst);
            gate.format.store(index, Ordering::SeqCst);
            gate.non_standard.store(non_standard, Ordering::SeqCst);
            let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
            let result = owner.resolve_captured_once(bound(&owner)).await;
            if non_standard {
                assert_eq!(result.unwrap_err(), WebPlaybackError::ProtocolUnsupported);
            } else {
                let source = result.unwrap();
                assert_eq!(source.media_format(), format);
                assert_eq!(source.quality(), Some(WebQuality::Standard));
            }
            assert_eq!(owner.state(), CandidateSessionState::AttemptConsumed);
            assert_eq!(
                owner.begin_capture(&id()).unwrap_err(),
                WebPlaybackError::AttemptConsumed
            );
            assert_eq!(gate.calls.load(Ordering::SeqCst), 1);
        }
    }
}

#[tokio::test]
async fn logout_provider_switch_account_replacement_and_relogin_dominate_late_results() {
    for _event in [
        "logout",
        "provider-switch",
        "account-replacement",
        "same-account-relogin",
    ] {
        for outcome in 0..4 {
            let gate = Arc::new(Gate::default());
            gate.outcome.store(outcome, Ordering::SeqCst);
            let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
            let bound = bound(&owner);
            let mut pending = pin!(owner.resolve_captured_once(bound));
            assert!(
                poll_fn(|cx| Poll::Ready(pending.as_mut().poll(cx)))
                    .await
                    .is_pending()
            );
            owner.clear();
            gate.ready.store(true, Ordering::SeqCst);
            assert_eq!(pending.await.unwrap_err(), WebPlaybackError::Replaced);
            assert_eq!(gate.calls.load(Ordering::SeqCst), 1);
        }
    }
}

#[tokio::test]
async fn concurrent_dropped_and_failed_attempts_do_not_retry_or_reopen_budget() {
    for outcome in 0..4 {
        let gate = Arc::new(Gate::default());
        gate.outcome.store(outcome, Ordering::SeqCst);
        let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
        let bound = bound(&owner);
        {
            let mut pending = pin!(owner.resolve_captured_once(bound));
            assert!(
                poll_fn(|cx| Poll::Ready(pending.as_mut().poll(cx)))
                    .await
                    .is_pending()
            );
            assert_eq!(
                owner.begin_capture(&id()).unwrap_err(),
                WebPlaybackError::AttemptConsumed
            );
            // Drop/cancel while transport is pending. No spawned task survives.
        }
        owner.clear();
        assert_eq!(
            owner.begin_capture(&id()).unwrap_err(),
            WebPlaybackError::AttemptConsumed
        );
        assert_eq!(gate.calls.load(Ordering::SeqCst), 1);
    }
}

#[tokio::test]
async fn risk_and_rate_limit_are_sticky_and_network_failure_is_not_logout() {
    for (outcome, expected) in [
        (1, WebPlaybackError::Network),
        (2, WebPlaybackError::RiskControl),
        (3, WebPlaybackError::RateLimited),
    ] {
        let gate = Arc::new(Gate::default());
        gate.ready.store(true, Ordering::SeqCst);
        gate.outcome.store(outcome, Ordering::SeqCst);
        let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
        let bound = bound(&owner);
        assert_eq!(
            owner.resolve_captured_once(bound).await.unwrap_err(),
            expected
        );
        let state = if outcome == 1 {
            CandidateSessionState::AttemptConsumed
        } else {
            CandidateSessionState::Halted
        };
        assert_eq!(owner.state(), state);
        owner.clear();
        assert_eq!(
            owner.state(),
            if outcome == 1 {
                CandidateSessionState::Missing
            } else {
                state
            }
        );
        assert_eq!(
            owner.begin_capture(&id()).unwrap_err(),
            if outcome == 1 {
                WebPlaybackError::AttemptConsumed
            } else {
                WebPlaybackError::RiskControl
            }
        );
        assert_eq!(gate.calls.load(Ordering::SeqCst), 1);
    }
}

#[test]
fn capture_admission_is_consumed_before_browser_await_and_not_cloneable_or_transferable() {
    let gate = Arc::new(Gate::default());
    let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
    let attempt = owner.begin_capture(&id()).unwrap();
    assert_eq!(format!("{attempt:?}"), "CaptureAttempt([REDACTED])");
    assert_eq!(
        owner.begin_capture(&id()).unwrap_err(),
        WebPlaybackError::AttemptConsumed
    );
    let other = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
    assert_eq!(
        other.finish_capture(attempt, capture(), NOW).unwrap_err(),
        WebPlaybackError::Replaced
    );
    owner.clear();
    assert_eq!(
        owner.begin_capture(&id()).unwrap_err(),
        WebPlaybackError::AttemptConsumed
    );
    assert_eq!(gate.calls.load(Ordering::SeqCst), 0);
    let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
    drop(owner.begin_capture(&id()).unwrap());
    assert_eq!(
        owner.begin_capture(&id()).unwrap_err(),
        WebPlaybackError::AttemptConsumed
    );
    let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
    drop(bound(&owner));
    assert_eq!(
        owner.begin_capture(&id()).unwrap_err(),
        WebPlaybackError::AttemptConsumed
    );
    assert_eq!(gate.calls.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn lifecycle_changes_during_capture_and_between_binding_and_replay_reject_before_io() {
    let gate = Arc::new(Gate::default());
    for _event in [
        "logout",
        "provider-switch",
        "different-account",
        "same-account-relogin",
        "cancel",
    ] {
        let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
        let attempt = owner.begin_capture(&id()).unwrap();
        owner.clear();
        assert_eq!(
            owner.finish_capture(attempt, capture(), NOW).unwrap_err(),
            WebPlaybackError::Replaced
        );
        let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
        let bound = bound(&owner);
        assert_eq!(format!("{bound:?}"), "BoundCapture([REDACTED])");
        owner.clear();
        assert_eq!(
            owner.resolve_captured_once(bound).await.unwrap_err(),
            WebPlaybackError::Replaced
        );
    }
    let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
    let bound = bound(&owner);
    let other = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
    assert_eq!(
        other.resolve_captured_once(bound).await.unwrap_err(),
        WebPlaybackError::Replaced
    );
    assert_eq!(gate.calls.load(Ordering::SeqCst), 0);
}
