use base64::{Engine as _, engine::general_purpose::STANDARD};
use kugou_client::{Error, KuGouClient, Request, Response, Transport};
use serde_json::{Value, json};
use std::sync::{Arc, Mutex};

struct FakeTransport {
    responses: Mutex<Vec<Response>>,
    requests: Arc<Mutex<Vec<url::Url>>>,
}

impl Transport for FakeTransport {
    fn send(
        &self,
        request: Request,
    ) -> impl std::future::Future<Output = Result<Response, Error>> + Send {
        let parsed = url::Url::parse(request.url()).unwrap();
        assert_eq!(parsed.scheme(), "https");
        assert!(matches!(
            (parsed.host_str(), parsed.path()),
            (
                Some("m.kugou.com"),
                "/app/i/getSongInfo.php" | "/rank/list" | "/rank/info/"
            ) | (Some("krcs.kugou.com"), "/search")
                | (Some("lyrics.kugou.com"), "/download")
        ));
        assert_eq!(format!("{request:?}"), "KuGouRequest([REDACTED])");
        self.requests.lock().unwrap().push(parsed);
        std::future::ready(Ok(self.responses.lock().unwrap().remove(0)))
    }
}

fn response(value: &Value) -> Response {
    Response {
        status: 200,
        content_type: Some("text/html; charset=utf-8".into()),
        body: serde_json::to_vec(value).unwrap(),
    }
}

fn fixture_client(values: Vec<Value>) -> (KuGouClient<FakeTransport>, Arc<Mutex<Vec<url::Url>>>) {
    let requests = Arc::new(Mutex::new(Vec::new()));
    (
        KuGouClient::new(FakeTransport {
            responses: Mutex::new(values.into_iter().map(|value| response(&value)).collect()),
            requests: requests.clone(),
        }),
        requests,
    )
}

fn detail(status: i64) -> Value {
    json!({
        "status": status,
        "errcode": 0,
        "hash": "0123456789abcdef0123456789abcdef",
        "album_audio_id": 123,
        "audio_id": "42",
        "songName": "Fixture Track",
        "authors": [{"author_id": 7, "author_name": "Fixture Artist"}],
        "singerId": 7,
        "singerName": "Fixture Artist",
        "albumid": "9",
        "album_name": "Fixture Album",
        "album_img": "http://imge.kugou.com/stdmusic/{size}/fixture.jpg",
        "timeLength": "123000",
        "url": ""
    })
}

fn ranking(id: u64) -> Value {
    json!({
        "rankid": id,
        "rankname": "Fixture Ranking",
        "issue": "Fixture Period",
        "imgurl": "http://imge.kugou.com/v2/rank/{size}/fixture.jpg"
    })
}

fn ranking_track(id: u64) -> Value {
    json!({
        "album_audio_id": id,
        "hash": "0123456789abcdef0123456789abcdef",
        "audio_id": 42,
        "songname": "Fixture Track",
        "authors": [{"author_id": 7, "author_name": "Fixture Artist"}],
        "album_id": 9,
        "album_name": "Fixture Album",
        "album_sizable_cover": "http://imge.kugou.com/stdmusic/{size}/fixture.jpg",
        "duration": 123_000
    })
}

#[tokio::test]
async fn exact_detail_accepts_observed_status_variants_and_mixed_numeric_types() {
    for status in [0, 1] {
        let (client, requests) = fixture_client(vec![detail(status)]);
        let result = client
            .track_details("0123456789ABCDEF0123456789ABCDEF")
            .await
            .unwrap();
        assert_eq!(result.mix_song_id, "123");
        assert_eq!(result.standard_hash, "0123456789ABCDEF0123456789ABCDEF");
        assert_eq!(result.audio_id, 42);
        assert_eq!(result.album_id.as_deref(), Some("9"));
        assert_eq!(result.duration_seconds, 123);
        assert_eq!(result.artists.len(), 1);
        assert_eq!(
            result.artwork.as_deref(),
            Some("https://imge.kugou.com/stdmusic/400/fixture.jpg")
        );
        let requests = requests.lock().unwrap();
        assert_eq!(requests.len(), 1);
        assert_eq!(
            requests[0]
                .query_pairs()
                .map(|(key, _)| key.into_owned())
                .collect::<Vec<_>>(),
            ["cmd", "hash"]
        );
    }
}

#[tokio::test]
async fn detail_business_identity_and_bounds_fail_closed() {
    let mut invalid = detail(1);
    invalid["errcode"] = json!(20010);
    let (client, _) = fixture_client(vec![invalid]);
    assert_eq!(
        client
            .track_details("0123456789ABCDEF0123456789ABCDEF")
            .await
            .unwrap_err(),
        Error::UpstreamUnknown
    );

    let (client, requests) = fixture_client(vec![]);
    assert_eq!(
        client.track_details("not-a-hash").await.unwrap_err(),
        Error::InputBound
    );
    assert!(requests.lock().unwrap().is_empty());
}

#[tokio::test]
async fn rankings_preserve_native_page_and_omit_only_independent_bad_rows() {
    let mut bad = ranking(2);
    bad["rankname"] = json!("");
    let ranking_list = json!({
        "rank": {"total": 2, "list": [ranking(1), bad]}
    });
    let ranking_page = json!({
        "info": ranking(1),
        "songs": {
            "page": 2,
            "pagesize": 30,
            "total": 31,
            "list": [ranking_track(123)]
        }
    });
    let (client, requests) = fixture_client(vec![ranking_list, ranking_page]);
    let rankings = client.rankings().await.unwrap();
    assert_eq!(rankings.items.len(), 1);
    assert_eq!(rankings.omitted_item_count, 1);
    assert_eq!(rankings.items[0].id, "1");
    assert_eq!(
        rankings.items[0].artwork.as_deref(),
        Some("https://imge.kugou.com/v2/rank/400/fixture.jpg")
    );
    let page = client.ranking_tracks("1", 2).await.unwrap();
    assert_eq!(page.page, 2);
    assert_eq!(page.total, 31);
    assert!(!page.more);
    assert_eq!(page.items.len(), 1);
    assert_eq!(page.items[0].mix_song_id, "123");
    assert_eq!(page.items[0].duration_seconds, 123);
    assert_eq!(page.omitted_item_count, 0);
    let requests = requests.lock().unwrap();
    assert_eq!(requests.len(), 2);
    assert_eq!(requests[0].path(), "/rank/list");
    assert_eq!(requests[1].path(), "/rank/info/");
    assert_eq!(
        requests[1]
            .query_pairs()
            .map(|(key, _)| key.into_owned())
            .collect::<Vec<_>>(),
        ["rankid", "page", "json"]
    );
}

#[tokio::test]
async fn ranking_duplicates_and_window_contradictions_fail_closed() {
    let duplicate = json!({"rank":{"total":2,"list":[ranking(1),ranking(1)]}});
    let (client, _) = fixture_client(vec![duplicate]);
    assert_eq!(
        client.rankings().await.unwrap_err(),
        Error::ResponseShapeMismatch
    );

    let bad_page = json!({
        "info": ranking(1),
        "songs":{"page":1,"pagesize":20,"total":1,"list":[ranking_track(123)]}
    });
    let (client, _) = fixture_client(vec![bad_page]);
    assert_eq!(
        client.ranking_tracks("1", 1).await.unwrap_err(),
        Error::ResponseShapeMismatch
    );
}

#[tokio::test]
async fn lyrics_use_exact_hash_two_step_contract_and_decode_only_timed_lrc() {
    let lyric = "[ar:Fixture]\n[00:01.20]First\n[00:02.034]Second";
    let search = json!({
        "status": 200,
        "error_code": 200,
        "candidates": [{"id": 55, "accesskey": "abc_DEF-123"}]
    });
    let download = json!({
        "status": 200,
        "errcode": 0,
        "fmt": "lrc",
        "content": STANDARD.encode(lyric)
    });
    let (client, requests) = fixture_client(vec![search, download]);
    let result = client
        .lyrics("0123456789ABCDEF0123456789ABCDEF", 123)
        .await
        .unwrap();
    assert_eq!(result.lines.len(), 2);
    assert_eq!(result.lines[0].start_ms, 1_200);
    assert_eq!(result.lines[1].start_ms, 2_034);
    assert_eq!(result.omitted_line_count, 0);
    assert!(!format!("{result:?}").contains("First"));
    let requests = requests.lock().unwrap();
    assert_eq!(requests.len(), 2);
    assert_eq!(requests[0].host_str(), Some("krcs.kugou.com"));
    assert_eq!(requests[1].host_str(), Some("lyrics.kugou.com"));
    assert_eq!(
        requests[0]
            .query_pairs()
            .map(|(key, _)| key.into_owned())
            .collect::<Vec<_>>(),
        ["ver", "man", "client", "hash", "duration"]
    );
}

#[tokio::test]
async fn lyrics_missing_candidate_and_malformed_base64_are_not_success() {
    let no_candidate = json!({"status":200,"error_code":200,"candidates":[]});
    let (client, _) = fixture_client(vec![no_candidate]);
    assert_eq!(
        client
            .lyrics("0123456789ABCDEF0123456789ABCDEF", 123)
            .await
            .unwrap_err(),
        Error::ContentUnavailable
    );

    let search = json!({
        "status":200,"error_code":200,
        "candidates":[{"id":"55","accesskey":"abc_DEF-123"}]
    });
    let download = json!({"status":200,"errcode":0,"fmt":"lrc","content":"%%%"});
    let (client, _) = fixture_client(vec![search, download]);
    assert_eq!(
        client
            .lyrics("0123456789ABCDEF0123456789ABCDEF", 123)
            .await
            .unwrap_err(),
        Error::ResponseShapeMismatch
    );
}
