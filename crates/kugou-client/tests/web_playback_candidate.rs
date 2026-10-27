use kugou_client::{Response, web_playback_candidate::*};
use serde_json::{Value, json};

const HASH: &str = "11111111111111111111111111111111";
const NOW: u64 = 1_800_000_000;

fn cookies() -> Vec<ProfileCookie> {
    [("KugooID", "42"), ("t", "synthetic-token")]
        .into_iter()
        .map(|(name, value)| ProfileCookie {
            name: name.into(),
            value: value.into(),
            domain: ".kugou.com".into(),
            path: "/".into(),
            secure: true,
        })
        .collect()
}
fn headers() -> Vec<(String, String)> {
    [
        ("User-Agent", "SyntheticOfficialBrowser/1"),
        ("Origin", "https://www.kugou.com"),
        ("Referer", "https://www.kugou.com/song/9"),
        ("Accept", "application/json, */*"),
    ]
    .into_iter()
    .map(|(k, v)| (k.into(), v.into()))
    .collect()
}
fn official(raw: &str, now: u64) -> Result<OfficialWebCapture, WebPlaybackError> {
    OfficialWebCapture::from_cdp(raw, "GET", &headers(), &cookies(), now)
}
fn url() -> String {
    format!(
        "https://wwwapi.kugou.com/play/songinfo?srcappid=2919&clientver=20000&clienttime={NOW}&mid=synthetic-mid&uuid=synthetic-uuid&dfid=synthetic-web-dfid&appid=1014&platid=4&hash={HASH}&album_id=7&token=synthetic-token&userid=42&signature=00000000000000000000000000000000"
    )
}
fn capture(raw: &str, now: u64) -> Result<CapturedWebRequest, WebPlaybackError> {
    official(raw, now)?.bind_track(WebTrackContext::new("9", HASH, "7", 180).unwrap(), now)
}
fn success() -> Value {
    json!({"status": 1, "err_code": 0, "data": {"hash": HASH, "album_audio_id": 9, "album_id":"7",
        "privilege":0, "is_free_part":0, "play_url":"https://synthetic-media.kugou.com/synthetic.mp3?key=synthetic-secret",
        "timelength":180_000, "bitrate":128_000, "filesize":2_880_000, "extname":"mp3"}})
}
fn response(value: &Value) -> WebPlaybackResponse {
    WebPlaybackResponse {
        response: Response {
            status: 200,
            content_type: Some("application/json; charset=utf-8".into()),
            body: serde_json::to_vec(value).unwrap(),
        },
        security_challenge: false,
    }
}
fn decode(value: &Value) -> Result<StandardWebSource, WebPlaybackError> {
    decode_standard_source(&capture(&url(), NOW).unwrap(), response(value))
}

#[test]
fn cookies_are_filtered_by_exact_applicable_domain_and_path_without_profile_fallback() {
    for domain in [
        "music.163.com",
        ".qq.com",
        "www.kugou.com",
        "kugou.com",
        ".com",
        ".kugou.com.evil.com",
    ] {
        let mut jar = cookies();
        for c in &mut jar {
            c.domain = domain.into();
        }
        assert_eq!(
            OfficialWebCapture::from_cdp(&url(), "GET", &headers(), &jar, NOW).unwrap_err(),
            WebPlaybackError::LoginRequired
        );
    }
    for path in ["", "/playlist", "/play/songinfo/extra", "/play/song"] {
        let mut jar = cookies();
        for c in &mut jar {
            c.path = path.into();
        }
        assert_eq!(
            OfficialWebCapture::from_cdp(&url(), "GET", &headers(), &jar, NOW).unwrap_err(),
            WebPlaybackError::LoginRequired
        );
    }
    for domain in [".kugou.com", ".wwwapi.kugou.com", "wwwapi.kugou.com"] {
        for path in ["/", "/play", "/play/", "/play/songinfo"] {
            let mut jar = cookies();
            for c in &mut jar {
                c.domain = domain.into();
                c.path = path.into();
                c.secure = false;
            }
            assert!(OfficialWebCapture::from_cdp(&url(), "GET", &headers(), &jar, NOW).is_ok());
        }
    }
    let mut jar = cookies();
    jar.push(ProfileCookie {
        name: "t".into(),
        value: "conflict".into(),
        domain: ".kugou.com".into(),
        path: "/".into(),
        secure: true,
    });
    assert_eq!(
        OfficialWebCapture::from_cdp(&url(), "GET", &headers(), &jar, NOW).unwrap_err(),
        WebPlaybackError::InvalidCapture
    );
    for value in ["", "bad\r\nHeader", "bad;value", "bad,value"] {
        let mut jar = cookies();
        jar[1].value = value.into();
        assert_eq!(
            OfficialWebCapture::from_cdp(&url(), "GET", &headers(), &jar, NOW).unwrap_err(),
            WebPlaybackError::InvalidCapture
        );
    }
}

#[test]
fn captured_headers_never_substitute_for_profile_cookies_and_query_session_must_match() {
    let mut h = headers();
    h.push(("Cookie".into(), "KugooID=42; t=synthetic-token".into()));
    assert_eq!(
        OfficialWebCapture::from_cdp(&url(), "GET", &h, &[], NOW).unwrap_err(),
        WebPlaybackError::LoginRequired
    );
    let composite = ProfileCookie {
        name: "KuGoo".into(),
        value: "synthetic-composite".into(),
        domain: ".kugou.com".into(),
        path: "/".into(),
        secure: true,
    };
    assert_eq!(
        OfficialWebCapture::from_cdp(&url(), "GET", &h, &[composite], NOW).unwrap_err(),
        WebPlaybackError::ProtocolUnsupported
    );
    for raw in [
        url().replace("userid=42", "userid=43"),
        url().replace("token=synthetic-token", "token=other"),
        format!("{}&UserID=43", url()),
        format!("{}&Token=other", url()),
    ] {
        assert_eq!(
            official(&raw, NOW).unwrap_err(),
            WebPlaybackError::SessionContextRejected
        );
    }
    let mut jar = cookies();
    jar[0].value = "0".into();
    assert_eq!(
        OfficialWebCapture::from_cdp(&url(), "GET", &headers(), &jar, NOW).unwrap_err(),
        WebPlaybackError::InvalidCapture
    );
}

#[test]
fn captured_cookie_semantics_must_match_the_minimal_profile_contract() {
    for cookie in [
        "KugooID=42; t=synthetic-token",
        "t=synthetic-token; KugooID=42",
    ] {
        let mut h = headers();
        h.push(("Cookie".into(), cookie.into()));
        assert!(OfficialWebCapture::from_cdp(&url(), "GET", &h, &cookies(), NOW).is_ok());
    }
    for (cookie, error) in [
        (
            "KugooID=43; t=synthetic-token",
            WebPlaybackError::SessionContextRejected,
        ),
        (
            "KugooID=42; t=other-token",
            WebPlaybackError::SessionContextRejected,
        ),
        ("KugooID=42", WebPlaybackError::SessionContextRejected),
        (
            "t=synthetic-token",
            WebPlaybackError::SessionContextRejected,
        ),
        (
            "KugooID=42; t=synthetic-token; t=synthetic-token",
            WebPlaybackError::InvalidCapture,
        ),
        (
            "KugooID=42; t=synthetic-token; mid=captured-device",
            WebPlaybackError::ProtocolUnsupported,
        ),
        (
            "KugooID=42; t=synthetic-token; KuGoo=composite",
            WebPlaybackError::ProtocolUnsupported,
        ),
        (
            "KugooID=42; t=synthetic-token; analytics=context",
            WebPlaybackError::ProtocolUnsupported,
        ),
    ] {
        let mut h = headers();
        h.push(("Cookie".into(), cookie.into()));
        assert_eq!(
            OfficialWebCapture::from_cdp(&url(), "GET", &h, &cookies(), NOW).unwrap_err(),
            error
        );
    }
    let mut h = headers();
    h.push(("Cookie".into(), "KugooID=42; t=synthetic-token".into()));
    h.push(("cookie".into(), "KugooID=42; t=synthetic-token".into()));
    assert_eq!(
        OfficialWebCapture::from_cdp(&url(), "GET", &h, &cookies(), NOW).unwrap_err(),
        WebPlaybackError::InvalidCapture
    );
}

#[test]
fn all_recognized_recording_id_aliases_must_bind_the_exact_current_track() {
    for key in [
        "MixSongID",
        "mixsongid",
        "mix_song_id",
        "Mix-Song-Id",
        "album_audio_id",
        "AlbumAudioID",
    ] {
        let raw = format!("{}&{key}=9", url());
        assert_eq!(capture(&raw, NOW).unwrap().url(), raw);
        for value in ["10", "0", "09", "opaque", ""] {
            assert_eq!(
                capture(&format!("{}&{key}={value}", url()), NOW).unwrap_err(),
                WebPlaybackError::OfficialWebTrackIdentityUnproven
            );
        }
    }
    for extra in [
        "MixSongID=9&mix_song_id=10",
        "MixSongID=9&album_audio_id=10",
        "Hash=22222222222222222222222222222222",
        "AlbumID=8",
        "audio_id=8",
        "songid=9",
        "encode_album_audio_id=opaque",
    ] {
        assert_eq!(
            capture(&format!("{}&{extra}", url()), NOW).unwrap_err(),
            WebPlaybackError::OfficialWebTrackIdentityUnproven
        );
    }
    let raw = format!("{}&MixSongID=9&album_audio_id=9", url());
    assert_eq!(capture(&raw, NOW).unwrap().url(), raw);
}

#[test]
fn request_preserves_exact_signed_envelope_without_generating_context_or_signature() {
    let raw = url();
    let request = capture(&raw, NOW).unwrap();
    assert_eq!(request.url(), raw);
    assert_eq!(request.cookie_header(), "KugooID=42; t=synthetic-token");
    assert!(request.validate_time(NOW + 300).is_ok());
    assert_eq!(
        request.validate_time(NOW + 301),
        Err(WebPlaybackError::InvalidCapture)
    );
    assert!(capture(&raw, NOW - 6).is_err());
    assert!(
        capture(
            &raw.replace(
                &format!("clienttime={NOW}"),
                &format!("clienttime={NOW}000")
            ),
            NOW
        )
        .is_ok()
    );
    for raw in [
        raw.replace("https:", "http:"),
        raw.replace("wwwapi.kugou.com", "wwwapi.kugou.com.evil.invalid"),
        raw.replace("/play/songinfo?", "/play/songinfo/extra?"),
        raw.replace("userid=42", "userid=43"),
        raw.replace("synthetic-token", "other-token"),
        raw.replace("album_id=7", "album_id=8"),
        raw.replace(HASH, "22222222222222222222222222222222"),
        format!("{raw}&hash={HASH}"),
        format!("{raw}#fragment"),
        raw.replace("https://", "https://user@"),
        raw.replace("wwwapi.kugou.com", "wwwapi.kugou.com:444"),
    ] {
        assert!(capture(&raw, NOW).is_err());
    }
}

#[test]
fn capture_expiry_never_extends_an_older_captured_clienttime() {
    let older = url().replace(
        &format!("clienttime={NOW}"),
        &format!("clienttime={}", NOW - 299),
    );
    let request = capture(&older, NOW).unwrap();
    assert!(request.validate_time(NOW + 1).is_ok());
    assert_eq!(
        request.validate_time(NOW + 2),
        Err(WebPlaybackError::InvalidCapture)
    );
    let raw = format!("https://wwwapi.kugou.com/play/songinfo?hash={HASH}&album_id=7");
    let request = capture(&raw, NOW).unwrap();
    assert_eq!(request.url(), raw);
    assert!(request.validate_time(NOW + 300).is_ok());
    assert_eq!(
        request.validate_time(NOW + 301),
        Err(WebPlaybackError::InvalidCapture)
    );
    for raw in [
        url().replace("album_id=7", "album_id=8"),
        url().replace(HASH, "22222222222222222222222222222222"),
    ] {
        assert_eq!(
            capture(&raw, NOW).unwrap_err(),
            WebPlaybackError::OfficialWebTrackIdentityUnproven
        );
    }
}

#[test]
fn optional_profile_fields_are_not_required_synthesized_or_repaired() {
    let raw = format!(
        "https://wwwapi.kugou.com/play/songinfo?album_id=7&hash={HASH}&unknown_profile=a%2Fb%20c&appid=other"
    );
    let captured = official(&raw, NOW).unwrap();
    assert_eq!(captured.source(), CaptureSource::OfficialWebGenerated);
    assert_eq!(
        captured.presence(),
        CapturePresence {
            signature: false,
            mid: false,
            dfid: false,
            userid: false,
            token: false
        }
    );
    let request = captured
        .bind_track(WebTrackContext::new("9", HASH, "7", 180).unwrap(), NOW)
        .unwrap();
    assert_eq!(request.url(), raw);
    assert_eq!(request.cookie_header(), "KugooID=42; t=synthetic-token");
    assert!(capture(&url().replace("appid=1014", "appid=3116"), NOW).is_ok());
    assert!(
        official(
            "https://wwwapi.kugou.com/play/songinfo?hash=unknown&album_id=7",
            NOW
        )
        .is_err()
    );
    let missing = "https://wwwapi.kugou.com/play/songinfo?mix_song_id=9";
    assert_eq!(
        OfficialWebCapture::from_cdp(missing, "GET", &headers(), &cookies(), NOW).unwrap_err(),
        WebPlaybackError::OfficialWebTrackIdentityUnproven
    );
    assert_eq!(
        WebPlaybackError::OfficialWebTrackIdentityUnproven.to_string(),
        "OFFICIAL_WEB_TRACK_IDENTITY_UNPROVEN"
    );
}

#[test]
fn replay_headers_preserve_official_ua_and_reject_unsupported_semantics() {
    let mut h = headers();
    for (k, v) in [
        ("Accept-Language", "zh-CN"),
        ("Sec-Fetch-Site", "same-site"),
        ("sec-ch-ua", "synthetic-hint"),
        ("Cookie", "KugooID=42; t=synthetic-token"),
    ] {
        h.push((k.into(), v.into()));
    }
    let mut jar = cookies();
    jar.push(ProfileCookie {
        name: "unrelated".into(),
        value: "not-forwarded".into(),
        domain: ".kugou.com".into(),
        path: "/".into(),
        secure: true,
    });
    let request = OfficialWebCapture::from_cdp(&url(), "GET", &h, &jar, NOW)
        .unwrap()
        .bind_track(WebTrackContext::new("9", HASH, "7", 180).unwrap(), NOW)
        .unwrap();
    assert_eq!(request.replay_headers().len(), 4);
    assert!(
        request
            .replay_headers()
            .contains(&("user-agent".into(), "SyntheticOfficialBrowser/1".into()))
    );
    assert_eq!(request.cookie_header(), "KugooID=42; t=synthetic-token");
    for name in [
        "Authorization",
        "X-Signature",
        "X-Custom",
        "Range",
        "Content-Type",
    ] {
        let mut h = headers();
        h.push((name.into(), "synthetic".into()));
        assert_eq!(
            OfficialWebCapture::from_cdp(&url(), "GET", &h, &cookies(), NOW).unwrap_err(),
            WebPlaybackError::ProtocolUnsupported
        );
    }
    for (name, value) in [
        ("Origin", "https://www.kugou.com.evil.com"),
        ("Referer", "https://music.163.com/"),
        ("User-Agent", "bad\r\nInjected"),
        ("Origin", "https://www.kugou.com:443"),
    ] {
        let mut h = headers();
        h.iter_mut().find(|(k, _)| k == name).unwrap().1 = value.into();
        assert!(OfficialWebCapture::from_cdp(&url(), "GET", &h, &cookies(), NOW).is_err());
    }
    for method in ["POST", "get", "HEAD"] {
        assert!(OfficialWebCapture::from_cdp(&url(), method, &headers(), &cookies(), NOW).is_err());
    }
    for missing in ["User-Agent", "Origin", "Referer"] {
        let mut h = headers();
        h.retain(|(name, _)| name != missing);
        assert_eq!(
            OfficialWebCapture::from_cdp(&url(), "GET", &h, &cookies(), NOW).unwrap_err(),
            WebPlaybackError::InvalidCapture
        );
    }
    let mut h = headers();
    h.retain(|(name, _)| name != "Accept");
    assert!(OfficialWebCapture::from_cdp(&url(), "GET", &h, &cookies(), NOW).is_ok());
    h.push(("Host".into(), "foreign.example.com".into()));
    assert_eq!(
        OfficialWebCapture::from_cdp(&url(), "GET", &h, &cookies(), NOW).unwrap_err(),
        WebPlaybackError::InvalidCapture
    );
}

#[test]
fn source_requires_exact_identity_full_duration_and_supported_format_metadata() {
    let source = decode(&success()).unwrap();
    assert!(
        source
            .url()
            .starts_with("https://synthetic-media.kugou.com/")
    );
    assert!(!format!("{source:?}").contains("synthetic-secret"));
    for (field, value) in [
        ("hash", json!("22222222222222222222222222222222")),
        ("album_audio_id", json!(10)),
        ("album_id", json!(8)),
        ("play_url", json!("")),
        ("play_url", json!("http://synthetic-media.kugou.com/a.mp3")),
        ("play_url", json!("https://127.0.0.1/a.mp3")),
        ("extname", json!("kge")),
        ("filesize", json!(0)),
    ] {
        let mut v = success();
        v["data"][field] = value;
        assert!(decode(&v).is_err(), "field={field}");
    }
    for field in [
        "hash",
        "privilege",
        "is_free_part",
        "play_url",
        "filesize",
        "extname",
        "timelength",
    ] {
        let mut v = success();
        v["data"].as_object_mut().unwrap().remove(field);
        assert!(decode(&v).is_err(), "missing={field}");
    }
}

#[test]
fn permissions_previews_and_unknown_authorization_are_not_generic_service_failures() {
    let mut preview = success();
    preview["data"]["is_free_part"] = json!(1);
    assert_eq!(decode(&preview).unwrap_err(), WebPlaybackError::PreviewOnly);
    let mut short = success();
    short["data"]["timelength"] = json!(60_000);
    assert_eq!(decode(&short).unwrap_err(), WebPlaybackError::PreviewOnly);
    let mut tiny = success();
    tiny["data"]["filesize"] = json!(4096);
    assert_eq!(decode(&tiny).unwrap_err(), WebPlaybackError::PreviewOnly);
    let mut vip = success();
    vip["data"]["privilege"] = json!(10);
    vip["data"]["pay_type"] = json!(1);
    assert_eq!(
        decode(&vip).unwrap_err(),
        WebPlaybackError::MembershipOrPurchaseRequired
    );
    vip["data"]["privilege"] = json!(0); // Contradictory metadata never grants entitlement.
    assert_eq!(
        decode(&vip).unwrap_err(),
        WebPlaybackError::MembershipOrPurchaseRequired
    );
    let mut rights = success();
    rights["data"]["privilege"] = json!(8);
    assert_eq!(
        decode(&rights).unwrap_err(),
        WebPlaybackError::RightsUnavailable
    );
    for (code, expected) in [
        (30020, WebPlaybackError::LoginRequired),
        (20018, WebPlaybackError::SessionContextRejected),
        (20017, WebPlaybackError::RiskControl),
        (20028, WebPlaybackError::RiskControl),
        (1002, WebPlaybackError::RateLimited),
        (999_999, WebPlaybackError::UpstreamRejected),
    ] {
        assert_eq!(
            decode(&json!({"status":0,"error_code":code,"data":"malformed-on-purpose"}))
                .unwrap_err(),
            expected
        );
    }
}

#[test]
fn http_challenges_bounds_content_types_and_duplicate_authorization_fields_fail_closed() {
    let request = capture(&url(), NOW).unwrap();
    for (status, expected) in [
        (401, WebPlaybackError::SessionContextRejected),
        (403, WebPlaybackError::RiskControl),
        (429, WebPlaybackError::RateLimited),
        (302, WebPlaybackError::ProtocolUnsupported),
        (503, WebPlaybackError::ServiceUnavailable),
        (206, WebPlaybackError::ProtocolUnsupported),
    ] {
        let mut r = response(&success());
        r.response.status = status;
        assert_eq!(decode_standard_source(&request, r).unwrap_err(), expected);
    }
    let mut r = response(&success());
    r.security_challenge = true;
    r.response.body = b"not-json".to_vec();
    assert_eq!(
        decode_standard_source(&request, r).unwrap_err(),
        WebPlaybackError::RiskControl
    );
    let mut r = response(&success());
    r.response.content_type = Some("text/html".into());
    assert_eq!(
        decode_standard_source(&request, r).unwrap_err(),
        WebPlaybackError::ProtocolUnsupported
    );
    let mut r = response(&success());
    r.response.body = vec![b' '; 256 * 1024 + 1];
    assert_eq!(
        decode_standard_source(&request, r).unwrap_err(),
        WebPlaybackError::ResponseBound
    );
    for body in [
        b"{\"status\":1,\"status\":0}".as_slice(),
        b"{\"status\":1,\"data\":{\"privilege\":0,\"privilege\":10}}",
        b"{\"status\":1,\"data\":{\"quality\":\"standard\",\"quality\":\"high\"}}",
    ] {
        let mut r = response(&success());
        r.response.body = body.to_vec();
        assert_eq!(
            decode_standard_source(&request, r).unwrap_err(),
            WebPlaybackError::InvalidResponse
        );
    }
}

#[test]
fn a_second_error_field_cannot_hide_a_hard_stop_behind_an_ordinary_error() {
    for first in [0, 30020, 999_999] {
        for (second, expected) in [
            (20028, WebPlaybackError::RiskControl),
            (1002, WebPlaybackError::RateLimited),
        ] {
            assert_eq!(
                decode(&json!({"status":0,"err_code":first,"error_code":second,"data":false}))
                    .unwrap_err(),
                expected
            );
        }
    }
}

#[test]
fn media_hosts_are_ephemeral_public_dns_and_debug_never_exposes_secrets() {
    for host in [
        "localhost",
        "*.kugou.com",
        "127.0.0.1",
        "[::1]",
        "example.invalid",
        "a.local",
        "a.internal",
        "a.kugou.com:443",
        "-a.kugou.com",
        "a.kugou.com.",
    ] {
        let mut v = success();
        v["data"]["play_url"] = json!(format!("https://{host}/media"));
        assert!(decode(&v).is_err());
    }
    let mut v = success();
    v["data"]["play_url"] =
        json!("https://cdn.example.com/opaque-no-extension?key=synthetic-secret");
    let source = decode(&v).unwrap();
    assert_eq!(source.media_host(), "cdn.example.com");
    v["data"]["play_url"] = json!("https://CDN.Example.COM/opaque?key=synthetic-secret");
    assert_eq!(decode(&v).unwrap().media_host(), "cdn.example.com");
    let request = capture(&url(), NOW).unwrap();
    let debug = format!(
        "{request:?} {:?} {:?} {:?} {:?} {:?}",
        cookies(),
        official(&url(), NOW).unwrap(),
        response(&success()),
        source,
        source.approve_media_host()
    );
    for secret in [
        "synthetic-token",
        HASH,
        "synthetic-web-dfid",
        "userid=",
        "play_url",
        "https://",
    ] {
        assert!(!debug.contains(secret));
    }
}

#[test]
fn format_and_quality_are_independent_and_file_extensions_do_not_define_quality() {
    for (ext, format, bitrate, size) in [
        ("mp3", MediaFormat::Mp3, 128_000, 2_880_000),
        ("mp3", MediaFormat::Mp3, 64_000, 1_440_000),
        ("ogg", MediaFormat::Ogg, 64_000, 1_440_000),
        ("m4a", MediaFormat::Mp4Aac, 96_000, 2_160_000),
        ("mp4", MediaFormat::Mp4Aac, 128_000, 2_880_000),
    ] {
        let mut v = success();
        v["data"]["extname"] = json!(ext);
        v["data"]["quality"] = json!("standard"); // Synthetic contract, not a live field assertion.
        v["data"]["bitrate"] = json!(bitrate);
        v["data"]["filesize"] = json!(size);
        v["data"]["play_url"] = json!("https://cdn.example.com/opaque");
        let source = decode(&v).unwrap();
        assert_eq!(source.media_format(), format);
        assert_eq!(source.quality(), Some(WebQuality::Standard));
    }
    for ext in ["flac", "kgg", "kge", "aac", "wav", "html"] {
        let mut v = success();
        v["data"]["extname"] = json!(ext);
        v["data"]["quality"] = json!("standard");
        assert_eq!(
            decode(&v).unwrap_err(),
            WebPlaybackError::ProtocolUnsupported
        );
    }
    let mut v = success();
    v["data"].as_object_mut().unwrap().remove("bitrate");
    assert_eq!(
        decode(&v).unwrap_err(),
        WebPlaybackError::ProtocolUnsupported
    );
    v["data"]["quality"] = json!("standard");
    assert_eq!(decode(&v).unwrap().quality(), Some(WebQuality::Standard));
}

#[test]
fn unknown_and_higher_quality_cannot_bypass_the_standard_only_gate_or_use_legacy_fallback() {
    for ext in ["mp3", "ogg", "m4a"] {
        for quality in [
            json!("high"),
            json!("lossless"),
            json!("hires"),
            json!("vip"),
            json!("Standard"),
            json!(""),
            Value::Null,
        ] {
            let mut v = success();
            v["data"]["extname"] = json!(ext);
            v["data"]["quality"] = quality;
            assert_eq!(
                decode(&v).unwrap_err(),
                WebPlaybackError::ProtocolUnsupported
            );
        }
        for quality in [json!(320), json!(["standard"]), json!({"tier":"standard"})] {
            let mut v = success();
            v["data"]["extname"] = json!(ext);
            v["data"]["quality"] = quality;
            assert_eq!(decode(&v).unwrap_err(), WebPlaybackError::InvalidResponse);
        }
    }
    let mut high = success();
    high["data"]["quality"] = json!("high");
    high["data"]["bitrate"] = json!(320_000);
    high["data"]["filesize"] = json!(7_200_000);
    assert_eq!(
        decode(&high).unwrap_err(),
        WebPlaybackError::ProtocolUnsupported
    );
    high["data"].as_object_mut().unwrap().remove("quality");
    assert_eq!(
        decode(&high).unwrap_err(),
        WebPlaybackError::ProtocolUnsupported
    );
    assert_eq!(
        decode(&success()).unwrap().quality(),
        Some(WebQuality::Standard)
    );
    for ext in ["ogg", "m4a"] {
        let mut v = success();
        v["data"]["extname"] = json!(ext);
        assert_eq!(
            decode(&v).unwrap_err(),
            WebPlaybackError::ProtocolUnsupported
        );
        v["data"]["audio_name"] = json!("standard"); // No unproved alias or guessed title/tier semantics.
        assert_eq!(
            decode(&v).unwrap_err(),
            WebPlaybackError::ProtocolUnsupported
        );
        v["data"]["quality"] = json!("standard");
        v["data"]["audio_name"] = json!("synthetic song title");
        assert_eq!(decode(&v).unwrap().quality(), Some(WebQuality::Standard));
    }
}

#[test]
fn explicit_standard_quality_never_grants_entitlement_or_full_track_evidence() {
    for ext in ["mp3", "ogg", "m4a"] {
        for (field, value, expected) in [
            ("privilege", json!(8), WebPlaybackError::RightsUnavailable),
            (
                "pay_type",
                json!(1),
                WebPlaybackError::MembershipOrPurchaseRequired,
            ),
            ("is_free_part", json!(1), WebPlaybackError::PreviewOnly),
            ("timelength", json!(60_000), WebPlaybackError::PreviewOnly),
            ("filesize", json!(4096), WebPlaybackError::PreviewOnly),
        ] {
            let mut v = success();
            v["data"]["extname"] = json!(ext);
            v["data"]["quality"] = json!("standard");
            v["data"][field] = value;
            assert_eq!(decode(&v).unwrap_err(), expected);
        }
        let mut v = success();
        v["data"]["extname"] = json!(ext);
        v["data"]["quality"] = json!("standard");
        v["error_code"] = json!(20028);
        assert_eq!(decode(&v).unwrap_err(), WebPlaybackError::RiskControl);
    }
}
