use kugou_client::{Response, web_playback_candidate::*};
use serde_json::{Value, json};

const HASH: &str = "11111111111111111111111111111111";
const NOW: u64 = 1_800_000_000;

fn credential() -> OfficialWebCredential {
    OfficialWebCredential::from_cookie_header(
        "https://www.kugou.com/",
        "KugooID=42; t=synthetic-token",
    )
    .unwrap()
}
fn url() -> String {
    format!(
        "https://wwwapi.kugou.com/play/songinfo?srcappid=2919&clientver=20000&clienttime={NOW}&mid=synthetic-mid&uuid=synthetic-uuid&dfid=synthetic-web-dfid&appid=1014&platid=4&hash={HASH}&album_id=7&token=synthetic-token&userid=42&signature=00000000000000000000000000000000"
    )
}
fn capture(raw: &str, now: u64) -> Result<CapturedWebRequest, WebPlaybackError> {
    CapturedWebRequest::new(
        raw,
        &credential(),
        WebTrackContext::new("9", HASH, "7", 180).unwrap(),
        ApprovedWebMediaHost::new("synthetic-media.kugou.com").unwrap(),
        now,
    )
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
fn credential_is_pending_minimal_and_never_accepts_other_provider_or_conflicting_material() {
    for (origin, cookie, error) in [
        (
            "https://music.163.com/",
            "KugooID=42; t=secret",
            WebPlaybackError::InvalidCapture,
        ),
        (
            "https://www.kugou.com/",
            "MUSIC_U=foreign",
            WebPlaybackError::LoginRequired,
        ),
        (
            "https://www.kugou.com/",
            "qqmusic_key=foreign",
            WebPlaybackError::LoginRequired,
        ),
        (
            "https://www.kugou.com/",
            "KugooID=42; t=first; t=second",
            WebPlaybackError::InvalidCapture,
        ),
        (
            "https://www.kugou.com/",
            "KugooID=0; t=secret",
            WebPlaybackError::InvalidCapture,
        ),
        (
            "https://www.kugou.com/",
            "KugooID=42; t=secret\r\nInjected=1",
            WebPlaybackError::InvalidCapture,
        ),
        (
            "https://www.kugou.com/",
            "KugooID=42; t=",
            WebPlaybackError::InvalidCapture,
        ),
    ] {
        assert_eq!(
            OfficialWebCredential::from_cookie_header(origin, cookie).unwrap_err(),
            error
        );
    }
    let raw = format!("KugooID=42; t={}", "a".repeat(9000));
    assert_eq!(
        OfficialWebCredential::from_cookie_header(
            "https://www.kugou.com/",
            "KuGoo=synthetic-composite"
        )
        .unwrap_err(),
        WebPlaybackError::ProtocolUnsupported
    );
    assert!(OfficialWebCredential::from_cookie_header("https://www.kugou.com/", &raw).is_err());
    let credential = OfficialWebCredential::from_cookie_header(
        "https://www.kugou.com/",
        "KugooID=42; t=synthetic-token; t=synthetic-token; unrelated=ignored",
    )
    .unwrap();
    assert!(!format!("{credential:?}").contains("synthetic-token"));
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
        raw.replace("dfid=synthetic-web-dfid", "dfid="),
        raw.replace("appid=1014", "appid=3116"),
        format!("{raw}&quality=flac"),
        format!("{raw}&hash={HASH}"),
        format!("{raw}#fragment"),
        raw.replace("https://", "https://user@"),
        raw.replace("wwwapi.kugou.com", "wwwapi.kugou.com:444"),
    ] {
        assert!(capture(&raw, NOW).is_err());
    }
}

#[test]
fn standard_source_requires_exact_identity_full_duration_and_unencrypted_standard_metadata() {
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
        ("play_url", json!("https://evil.invalid/a.mp3")),
        ("play_url", json!("https://synthetic-media.kugou.com/a.kgg")),
        ("extname", json!("kge")),
        ("bitrate", json!(320_000)),
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
        "bitrate",
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
fn approved_host_is_exact_not_ip_wildcard_or_another_provider() {
    for host in [
        "kugou.com",
        "*.kugou.com",
        "127.0.0.1",
        "example.invalid",
        "a.kugou.com.evil.invalid",
        "a.kugou.com:443",
        "-a.kugou.com",
    ] {
        assert!(ApprovedWebMediaHost::new(host).is_err());
    }
    let request = capture(&url(), NOW).unwrap();
    let debug = format!("{request:?} {:?} {:?}", credential(), response(&success()));
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
