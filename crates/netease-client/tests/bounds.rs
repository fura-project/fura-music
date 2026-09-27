use netease_client::{Error, MAX_RESPONSE_BYTES, NeteaseClient, Request, Response, Transport};
use serde_json::{Value, json};
use std::sync::atomic::{AtomicUsize, Ordering};
struct Fake {
    status: u16,
    body: Vec<u8>,
    calls: AtomicUsize,
}
impl Transport for Fake {
    fn send(
        &self,
        r: Request,
    ) -> impl std::future::Future<Output = Result<Response, Error>> + Send {
        self.calls.fetch_add(1, Ordering::SeqCst);
        assert!(r.cookie().is_none());
        if r.url().starts_with("https://interface.music.163.com/eapi/") {
            assert_eq!(r.form().len(), 1);
            assert_eq!(r.form()[0].0, "params");
        } else {
            assert_eq!(r.form().len(), 2);
            assert_eq!(r.form()[0].0, "params");
            assert_eq!(r.form()[1].0, "encSecKey");
            assert_eq!(r.form()[1].1.len(), 256);
        }
        std::future::ready(Ok(Response {
            status: self.status,
            body: self.body.clone(),
            set_cookies: vec![],
        }))
    }
}
fn client(v: &Value) -> NeteaseClient<Fake> {
    NeteaseClient::new(Fake {
        status: 200,
        body: serde_json::to_vec(v).unwrap(),
        calls: AtomicUsize::new(0),
    })
}
#[tokio::test]
async fn rate_limit_non_json_and_body_bound_have_distinct_stop_results() {
    for (status, body, error) in [
        (429, b"rate".to_vec(), Error::RateLimited),
        (503, b"service".to_vec(), Error::ProtocolUnavailable),
        (
            200,
            b"<html>failure</html>".to_vec(),
            Error::ResponseShapeMismatch,
        ),
        (
            200,
            vec![b' '; MAX_RESPONSE_BYTES + 1],
            Error::ResponseBound,
        ),
    ] {
        let client = NeteaseClient::new(Fake {
            status,
            body,
            calls: AtomicUsize::new(0),
        });
        assert!(matches!(client.search_tracks("fixture",0,1).await,Err(e) if e==error));
    }
}
#[tokio::test]
async fn detail_mismatches_invalid_pagination_and_unrelated_songs_stop() {
    assert!(matches!(
        client(&json!({"code":200,"album":{"id":8,"name":"Other"},"songs":[]}))
            .album(3)
            .await,
        Err(Error::ResponseShapeMismatch)
    ));
    assert!(matches!(
        client(&json!({"code":200,"playlist":{"id":8,"trackCount":0,"trackIds":[]}}))
            .playlist_page(3, 0, 1)
            .await,
        Err(Error::ResponseShapeMismatch)
    ));
    assert!(matches!(
        client(&json!({"code":200,"songs":[],"total":4,"more":true}))
            .artist_tracks(2, 0, 1)
            .await,
        Err(Error::ResponseShapeMismatch)
    ));
    let s = json!({"id":8,"name":"Unrelated","dt":1000,"ar":[],"al":{"id":3,"name":"Album"}});
    assert!(matches!(
        client(&json!({"code":200,"songs":[s]})).songs(&[1]).await,
        Err(Error::ResponseShapeMismatch)
    ));
    assert!(matches!(
        client(&json!({})).songs(&[1, 1]).await,
        Err(Error::InputBound)
    ));
}
#[tokio::test]
async fn empty_catalog_and_missing_content_are_distinct_from_malformed() {
    assert!(
        client(&json!({"code":200,"songs":[]}))
            .songs(&[1])
            .await
            .unwrap()
            .is_empty()
    );
    assert!(
        client(&json!({"code":200,"album":{"id":3,"name":"Empty"},"songs":[]}))
            .album(3)
            .await
            .unwrap()
            .songs
            .is_empty()
    );
    assert!(
        client(&json!({"code":200,"list":[]}))
            .rankings()
            .await
            .unwrap()
            .is_empty()
    );
    assert!(
        client(&json!({"code":200,"result":[]}))
            .recommendations(3)
            .await
            .unwrap()
            .is_empty()
    );
    assert!(matches!(
        client(&json!({"code":200,"nolyric":true})).lyrics(1).await,
        Err(Error::TrackUnavailable)
    ));
    assert!(matches!(
        client(&json!({"code":200})).rankings().await,
        Err(Error::ResponseShapeMismatch)
    ));
}

#[tokio::test]
async fn lyrics_accept_netease_negative_line_markers_without_relaxing_timing() {
    let lyrics = client(&json!({
        "code": 200,
        "lrc": {
            "lyric": "[00:00.00-1] 作词 : Aljosha Frederick Konstanty/Liam Morgan Thomas\n[00:00.00-1] 作曲 : Aljosha Frederick Konstanty/Liam Morgan Thomas\n"
        }
    }))
    .lyrics(1)
    .await
    .unwrap();

    assert_eq!(lyrics.lines.len(), 2);
    assert_eq!(lyrics.lines[0].start_ms, 0);
    assert!(lyrics.lines[0].text.contains("作词"));
    assert_eq!(lyrics.lines[1].start_ms, 0);
    assert!(lyrics.lines[1].text.contains("作曲"));
}

#[tokio::test]
async fn malformed_optional_lyric_tracks_do_not_discard_valid_original() {
    let oversized_translation = "[00:01]Translation fixture\n".repeat(20_000);
    let lyrics = client(&json!({
        "code": 200,
        "lrc": {"lyric": "[00:01.00]Original A\n[00:02.00]Original B"},
        "tlyric": {"lyric": oversized_translation},
        "romalrc": {"lyric": "[00:01.00]Roma A\n[00:61.00]bad\n[00:02.00]Roma B"}
    }))
    .lyrics(1)
    .await
    .expect("valid original survives malformed optional tracks");

    assert_eq!(lyrics.lines.len(), 2);
    assert!(lyrics.translation.is_empty());
    assert_eq!(lyrics.romanization.len(), 2);
    assert_eq!(lyrics.omitted_line_count, 2);
}

#[tokio::test]
async fn lyric_v1_prefers_complete_yrc_and_falls_back_atomically_when_malformed() {
    let lyrics = client(&json!({
        "code": 200,
        "lrc": {"lyric": "[00:01.00]Line only"},
        "yrc": {"lyric": "[1000,900](1000,400,0)Word (1400,500,0)timing"},
        "ytlrc": {"lyric": "[00:01.00]Translation"},
        "yromalrc": {"lyric": "[00:01.00]Romanization"}
    }))
    .lyrics(1)
    .await
    .expect("complete YRC");
    assert_eq!(lyrics.lines[0].text, "Word timing");
    assert_eq!(lyrics.lines[0].duration_ms, 900);
    assert_eq!(lyrics.lines[0].segments.len(), 2);
    assert_eq!(lyrics.translation[0].text, "Translation");
    assert_eq!(lyrics.romanization[0].text, "Romanization");

    let fallback = client(&json!({
        "code": 200,
        "lrc": {"lyric": "[00:01.00]Canonical A\n[00:02.00]Canonical B"},
        "yrc": {"lyric": "[1000,900](1000,900,0)Valid\n[2000,900](0,900,0)Malformed"}
    }))
    .lyrics(1)
    .await
    .expect("canonical LRC survives malformed YRC");
    assert_eq!(fallback.lines.len(), 2);
    assert_eq!(fallback.lines[0].text, "Canonical A");
    assert!(fallback.lines.iter().all(|line| line.segments.is_empty()));
    assert_eq!(fallback.omitted_line_count, 1);
}

#[tokio::test]
async fn lyric_v1_keeps_word_track_resource_bounds_fail_closed() {
    let error = client(&json!({
        "code": 200,
        "lrc": {"lyric": "[00:01.00]Canonical"},
        "yrc": {"lyric": "x".repeat(512 * 1024 + 1)}
    }))
    .lyrics(1)
    .await
    .expect_err("oversized YRC must not be hidden by canonical fallback");
    assert_eq!(error, netease_client::Error::ResponseBound);
}
