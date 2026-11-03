use kugou_client::{
    Response,
    web_playback_candidate::{songinfo_stages::*, *},
};
use serde_json::{Value, json};
const NOW: u64 = 1_800_000_000;
const HASH: &str = "11111111111111111111111111111111";
const ENCODED: &str = "synthetic/opaque+id=Ω";

fn context() -> WebTrackContext {
    WebTrackContext::new("9", HASH, "7", 180).unwrap()
}
fn headers() -> Vec<(String, String)> {
    [
        ("User-Agent", "SyntheticOfficialBrowser/1"),
        ("Origin", "https://www.kugou.com"),
        ("Referer", "https://www.kugou.com/"),
    ]
    .into_iter()
    .map(|(k, v)| (k.into(), v.into()))
    .collect()
}
fn cookies() -> Vec<ProfileCookie> {
    [("KugooID", "42"), ("t", "synthetic-token")]
        .into_iter()
        .map(|(k, v)| ProfileCookie {
            name: k.into(),
            value: v.into(),
            domain: ".kugou.com".into(),
            path: "/".into(),
            secure: true,
        })
        .collect()
}
fn first(query: &str) -> Result<OfficialWebCapture, WebPlaybackError> {
    OfficialWebCapture::from_stage1_cdp(
        &format!("https://wwwapi.kugou.com/play/songinfo?{query}"),
        "GET",
        &headers(),
        &cookies(),
        NOW,
    )
}
fn second(encoded: &str, extra: &str) -> OfficialWebCapture {
    let mut url = url::Url::parse("https://wwwapi.kugou.com/play/songinfo").unwrap();
    url.query_pairs_mut()
        .append_pair("encode_album_audio_id", encoded);
    if !extra.is_empty() {
        url.set_query(Some(&format!("{}&{extra}", url.query().unwrap())));
    }
    OfficialWebCapture::from_stage2_cdp(url.as_str(), "GET", &headers(), &cookies(), NOW).unwrap()
}
fn request() -> CapturedWebRequest {
    first(&format!("hash={HASH}"))
        .unwrap()
        .bind_stage1(context(), NOW)
        .unwrap()
}
fn wire(data: Value) -> Stage1WireResponse {
    let mut envelope = json!({"status":1});
    envelope["data"] = data;
    let body = serde_json::to_vec(&envelope).unwrap();
    Stage1WireResponse::new(
        WebPlaybackResponse {
            response: Response {
                status: 200,
                content_type: Some("application/json".into()),
                body: body.clone(),
            },
            security_challenge: false,
        },
        vec![
            ("Content-Type".into(), "application/json".into()),
            ("Content-Length".into(), body.len().to_string()),
            (
                "Access-Control-Allow-Origin".into(),
                "https://www.kugou.com".into(),
            ),
            ("Access-Control-Allow-Credentials".into(), "true".into()),
            ("Connection".into(), "close".into()),
        ],
    )
}
fn stage1_data() -> Value {
    json!({"hash":HASH,"album_audio_id":9,"encode_album_audio_id":ENCODED})
}
fn continuation() -> ServerIssuedIdentity {
    let Stage1Decoded::Continue(chain, _) = decode_stage1(request(), wire(stage1_data())).unwrap()
    else {
        panic!("expected synthetic chain")
    };
    chain
}
fn stage2_response() -> WebPlaybackResponse {
    WebPlaybackResponse{
    response:Response{status:200,content_type:Some("application/json".into()),body:serde_json::to_vec(&json!({"status":1,"data":{
        "privilege":0,"is_free_part":0,"play_url":"https://offline-media.example.org/synthetic.mp3",
        "bitrate":128_000,"timelength":180_000,"filesize":2_880_000,"extname":"mp3","quality":"standard",
    }})).unwrap()},security_challenge:false,
}
}

#[test]
fn stage1_hash_is_required_but_album_is_optional_and_all_comparable_fields_must_match() {
    for query in [
        format!("hash={HASH}"),
        format!("hash={HASH}&album_id=7&MixSongID=9&album_audio_id=9"),
    ] {
        assert!(first(&query).unwrap().bind_stage1(context(), NOW).is_ok());
    }
    for query in [
        "hash=22222222222222222222222222222222".into(),
        format!("hash={HASH}&album_id=8"),
        format!("hash={HASH}&MixSongID=10"),
    ] {
        assert_eq!(
            first(&query)
                .unwrap()
                .bind_stage1(context(), NOW)
                .unwrap_err(),
            WebPlaybackError::OfficialWebStage1IdentityUnproven
        );
    }
    for query in ["encode_album_audio_id=synthetic", "album_id=7", "hash=bad"] {
        assert_eq!(
            first(query).unwrap_err(),
            WebPlaybackError::OfficialWebStage1IdentityUnproven
        );
    }
    assert_eq!(
        first(&format!("hash={HASH}&MixSongID=9&album_audio_id=10")).unwrap_err(),
        WebPlaybackError::OfficialWebStage1IdentityUnproven
    );
}

#[test]
fn encoded_capture_never_weakens_the_old_direct_identity_contract() {
    assert_eq!(
        OfficialWebCapture::from_cdp(
            "https://wwwapi.kugou.com/play/songinfo?encode_album_audio_id=synthetic",
            "GET",
            &headers(),
            &cookies(),
            NOW
        )
        .unwrap_err(),
        WebPlaybackError::OfficialWebTrackIdentityUnproven
    );
    assert_eq!(
        first(&format!("hash={HASH}"))
            .unwrap()
            .bind_track(context(), NOW)
            .unwrap_err(),
        WebPlaybackError::InvalidCapture
    );
}

#[test]
fn stage1_response_requires_exact_hash_and_every_numeric_relation() {
    for (key, value) in [
        ("hash", json!("22222222222222222222222222222222")),
        ("album_audio_id", json!(10)),
        ("MixSongID", json!(10)),
        ("album_id", json!(8)),
        ("AlbumID", json!(8)),
        ("MixSongId", json!(10)),
    ] {
        let mut data = stage1_data();
        data[key] = value;
        assert_eq!(
            decode_stage1(request(), wire(data)).unwrap_err(),
            WebPlaybackError::Stage1ResponseIdentityMismatch
        );
    }
    let mut data = stage1_data();
    data.as_object_mut().unwrap().remove("hash");
    assert_eq!(
        decode_stage1(request(), wire(data)).unwrap_err(),
        WebPlaybackError::Stage1ResponseIdentityMismatch
    );
}

#[test]
fn stage1_missing_empty_or_invalid_encoded_identity_does_not_construct_stage2() {
    for value in [
        Value::Null,
        json!(""),
        json!("synthetic\nencoded"),
        json!("a".repeat(4097)),
    ] {
        let mut data = stage1_data();
        data["encode_album_audio_id"] = value;
        assert_eq!(
            decode_stage1(request(), wire(data)).unwrap_err(),
            WebPlaybackError::Stage1EncodedIdMissing
        );
    }
}

#[test]
fn fulfillment_keeps_original_bytes_and_cors_without_inventing_headers() {
    // Deliberately non-canonical JSON order and whitespace. Re-serialization
    // would change these bytes and must not substitute for the server body.
    let expected=format!("{{\n \"data\": {{\"encode_album_audio_id\":{}, \"album_audio_id\":9, \"hash\":\"{HASH}\"}}, \"status\":1 }}\n",serde_json::to_string(ENCODED).unwrap()).into_bytes();
    let response = Stage1WireResponse::new(
        WebPlaybackResponse {
            response: Response {
                status: 200,
                content_type: Some("application/json".into()),
                body: expected.clone(),
            },
            security_challenge: false,
        },
        vec![
            ("Content-Type".into(), "application/json".into()),
            ("Content-Length".into(), expected.len().to_string()),
            (
                "Access-Control-Allow-Origin".into(),
                "https://www.kugou.com".into(),
            ),
            ("Access-Control-Allow-Credentials".into(), "true".into()),
            ("Connection".into(), "close".into()),
        ],
    );
    let Stage1Decoded::Continue(_, fulfillment) = decode_stage1(request(), response).unwrap()
    else {
        panic!("expected synthetic chain")
    };
    assert_eq!(fulfillment.body(), expected);
    assert!(fulfillment.headers().contains(&(
        "Access-Control-Allow-Origin".into(),
        "https://www.kugou.com".into()
    )));
    assert!(
        fulfillment
            .headers()
            .contains(&("Access-Control-Allow-Credentials".into(), "true".into()))
    );
    assert!(
        !fulfillment
            .headers()
            .iter()
            .any(|(k, _)| k.eq_ignore_ascii_case("connection"))
    );
}

#[test]
fn encoded_id_is_opaque_and_compared_byte_for_byte_with_session_and_optional_context() {
    let request = continuation()
        .bind_second(second(ENCODED, ""), NOW)
        .unwrap();
    assert!(request.url().contains("encode_album_audio_id="));
    assert!(!request.url().contains("hash="));
    let source = decode_standard_source(&request, stage2_response()).unwrap();
    assert_eq!(source.media_format(), MediaFormat::Mp3);
    for encoded in [
        "synthetic/opaque+id=ω",
        "synthetic/opaque+id=Ω ",
        "synthetic-replacement",
    ] {
        assert_eq!(
            continuation()
                .bind_second(second(encoded, ""), NOW)
                .unwrap_err(),
            WebPlaybackError::OfficialWebEncodedIdentityMismatch
        );
    }
    for extra in [
        "hash=22222222222222222222222222222222",
        "album_id=8",
        "MixSongID=10",
    ] {
        assert_eq!(
            continuation()
                .bind_second(second(ENCODED, extra), NOW)
                .unwrap_err(),
            WebPlaybackError::OfficialWebEncodedIdentityMismatch
        );
    }
    assert_eq!(
        continuation()
            .bind_second(second(ENCODED, ""), NOW + 301)
            .unwrap_err(),
        WebPlaybackError::InvalidCapture
    );
}

#[test]
fn stage2_response_rejects_any_contradictory_identity_without_requiring_repeated_hash() {
    for (key, value) in [
        ("hash", json!("22222222222222222222222222222222")),
        ("album_audio_id", json!(10)),
        ("MixSongID", json!(10)),
        ("album_id", json!(8)),
        ("AlbumID", json!(8)),
        ("MixSongId", json!(10)),
        ("encode_album_audio_id", json!("synthetic-replacement")),
    ] {
        let request = continuation()
            .bind_second(second(ENCODED, ""), NOW)
            .unwrap();
        let mut response = stage2_response();
        let mut body: Value = serde_json::from_slice(&response.response.body).unwrap();
        body["data"][key] = value;
        response.response.body = serde_json::to_vec(&body).unwrap();
        assert_eq!(
            decode_standard_source(&request, response).unwrap_err(),
            WebPlaybackError::Stage2ResponseIdentityMismatch
        );
    }
}

#[test]
fn unsupported_fulfillment_semantics_fail_instead_of_repairing_response() {
    for (name, value, error) in [
        (
            "Set-Cookie",
            "t=synthetic-replacement",
            WebPlaybackError::Stage1ResponseCookieMutationUnsupported,
        ),
        (
            "Content-Encoding",
            "gzip",
            WebPlaybackError::Stage1ResponseEncodingUnsupported,
        ),
        (
            "Content-Length",
            "0",
            WebPlaybackError::Stage1ResponseReplayUnsupported,
        ),
        (
            "Connection",
            "custom-header",
            WebPlaybackError::Stage1ResponseReplayUnsupported,
        ),
        (
            "Refresh",
            "0;url=synthetic",
            WebPlaybackError::Stage1ResponseReplayUnsupported,
        ),
        (
            "Transfer-Encoding",
            "gzip",
            WebPlaybackError::Stage1ResponseReplayUnsupported,
        ),
    ] {
        let response = WebPlaybackResponse {
            response: Response {
                status: 200,
                content_type: Some("application/json".into()),
                body: serde_json::to_vec(&json!({"status":1,"data":stage1_data()})).unwrap(),
            },
            security_challenge: false,
        };
        let wire = Stage1WireResponse::new(
            response,
            vec![
                ("Content-Type".into(), "application/json".into()),
                (name.into(), value.into()),
            ],
        );
        assert_eq!(decode_stage1(request(), wire).unwrap_err(), error);
    }
}

#[test]
fn dechunked_representation_preserves_body_and_removes_only_transport_framing() {
    let body = serde_json::to_vec(&json!({"status":1,"data":stage1_data()})).unwrap();
    let response = Stage1WireResponse::new(
        WebPlaybackResponse {
            response: Response {
                status: 200,
                content_type: Some("application/json".into()),
                body: body.clone(),
            },
            security_challenge: false,
        },
        vec![
            ("Content-Type".into(), "application/json".into()),
            ("Transfer-Encoding".into(), "chunked".into()),
            ("Connection".into(), "close".into()),
        ],
    );
    let Stage1Decoded::Continue(_, fulfillment) = decode_stage1(request(), response).unwrap()
    else {
        panic!("expected synthetic chain")
    };
    assert_eq!(fulfillment.body(), body);
    assert_eq!(
        fulfillment.headers(),
        [("Content-Type".into(), "application/json".into())]
    );
}

#[test]
fn direct_profile_is_decided_by_response_shape_with_no_encoded_fallback() {
    let response = stage2_response();
    let mut value: Value = serde_json::from_slice(&response.response.body).unwrap();
    value["data"]["hash"] = json!(HASH);
    value["data"]["encode_album_audio_id"] = json!(ENCODED);
    assert!(matches!(
        decode_stage1(request(), wire(value["data"].clone())).unwrap(),
        Stage1Decoded::Direct(_)
    ));
    value["data"]["quality"] = json!("lossless");
    assert_eq!(
        decode_stage1(request(), wire(value["data"].clone())).unwrap_err(),
        WebPlaybackError::ProtocolUnsupported
    );
    value["data"]["play_url"] = json!("");
    value["data"]["play_backup_url"] = json!("https://offline-media.example.org/backup.mp3");
    assert_eq!(
        decode_stage1(request(), wire(value["data"].clone())).unwrap_err(),
        WebPlaybackError::Stage1ResponseReplayUnsupported
    );
}

#[test]
fn stage_shape_and_new_debug_never_expose_raw_identity_or_response() {
    let response = wire(stage1_data());
    assert_eq!(
        response.identity_presence(),
        IdentityPresence {
            hash: true,
            album_id: false,
            album_audio_id: true,
            encoded_id: true
        }
    );
    let Stage1Decoded::Continue(chain, fulfillment) = decode_stage1(request(), response).unwrap()
    else {
        panic!("expected synthetic chain")
    };
    let debug = format!("{chain:?}{fulfillment:?}");
    for forbidden in [HASH, ENCODED, "synthetic-token", "https://", "play_url"] {
        assert!(!debug.contains(forbidden));
    }
    for stage in [
        IdentityStage::Stage1Request,
        IdentityStage::Stage1Response,
        IdentityStage::Stage2Request,
    ] {
        let text = IdentityPresence {
            hash: true,
            album_id: false,
            album_audio_id: true,
            encoded_id: true,
        }
        .diagnostic(stage);
        for forbidden in [HASH, ENCODED, "synthetic-token", "https://", "data"] {
            assert!(!text.contains(forbidden));
        }
    }
    assert_eq!(
        IdentityPresence::request(
            "https://synthetic.invalid/?hash=redacted&encode_album_audio_id=redacted"
        ),
        IdentityPresence {
            hash: true,
            album_id: false,
            album_audio_id: false,
            encoded_id: true
        }
    );
}

#[test]
fn second_stage_cannot_import_another_cookie_session_or_ambiguous_encoded_context() {
    let mut other = cookies();
    other[1].value = "synthetic-other-token".into();
    let capture=OfficialWebCapture::from_stage2_cdp("https://wwwapi.kugou.com/play/songinfo?encode_album_audio_id=synthetic%2Fopaque%2Bid%3D%CE%A9","GET",&headers(),&other,NOW).unwrap();
    assert_eq!(
        continuation().bind_second(capture, NOW).unwrap_err(),
        WebPlaybackError::SessionContextRejected
    );
    for query in [
        "encode_album_audio_id=synthetic&EncodeAlbumAudioId=other",
        "encode_album_audio_id=%FF",
    ] {
        assert!(
            OfficialWebCapture::from_stage2_cdp(
                &format!("https://wwwapi.kugou.com/play/songinfo?{query}"),
                "GET",
                &headers(),
                &cookies(),
                NOW
            )
            .is_err()
        );
    }
}

#[test]
fn first_stage_security_dominates_missing_identity_and_does_not_fulfill() {
    for (status, body, challenge, expected) in [
        (
            200,
            br#"{"status":0,"error_code":20017,"data":null}"#.to_vec(),
            false,
            WebPlaybackError::RiskControl,
        ),
        (
            429,
            b"malformed".to_vec(),
            false,
            WebPlaybackError::RateLimited,
        ),
        (
            200,
            b"malformed".to_vec(),
            true,
            WebPlaybackError::RiskControl,
        ),
    ] {
        let response = Stage1WireResponse::new(
            WebPlaybackResponse {
                response: Response {
                    status,
                    content_type: Some("application/json".into()),
                    body,
                },
                security_challenge: challenge,
            },
            vec![],
        );
        assert_eq!(decode_stage1(request(), response).unwrap_err(), expected);
    }
}
