use kugou_client::{Error, KuGouClient, Request, Response, Transport};
use serde_json::{Value, json};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicUsize, Ordering},
};

struct FakeTransport {
    responses: Mutex<Vec<Result<Response, Error>>>,
    calls: Arc<AtomicUsize>,
}

impl Transport for FakeTransport {
    fn send(
        &self,
        request: Request,
    ) -> impl std::future::Future<Output = Result<Response, Error>> + Send {
        let uri = url::Url::parse(request.url()).unwrap();
        assert_eq!(uri.scheme(), "https");
        assert_eq!(uri.host_str(), Some("songsearch.kugou.com"));
        assert_eq!(uri.path(), "/song_search_v2");
        let names = uri
            .query_pairs()
            .map(|(name, _)| name.into_owned())
            .collect::<Vec<_>>();
        assert_eq!(
            names,
            ["platform", "iscorrection", "keyword", "page", "pagesize"]
        );
        assert!(!names.iter().any(|name| matches!(
            name.as_str(),
            "signature" | "dfid" | "mid" | "uuid" | "token" | "userid"
        )));
        assert_eq!(format!("{request:?}"), "KuGouRequest([REDACTED])");
        self.calls.fetch_add(1, Ordering::SeqCst);
        std::future::ready(self.responses.lock().unwrap().remove(0))
    }
}

fn response(value: &Value) -> Response {
    Response {
        status: 200,
        content_type: Some("text/plain; charset=utf-8".into()),
        body: serde_json::to_vec(&value).unwrap(),
    }
}

fn fixture_client(
    values: Vec<Result<Response, Error>>,
) -> (KuGouClient<FakeTransport>, Arc<AtomicUsize>) {
    let calls = Arc::new(AtomicUsize::new(0));
    (
        KuGouClient::new(FakeTransport {
            responses: Mutex::new(values),
            calls: calls.clone(),
        }),
        calls,
    )
}

fn track(id: &str) -> Value {
    json!({
        "MixSongID": id,
        "FileHash": "0123456789ABCDEF0123456789ABCDEF",
        "Audioid": 42,
        "OriSongName": "Fixture Track",
        "SongName": "Fixture Track",
        "Suffix": "(Live)",
        "Singers": [{"id": 7, "name": "Fixture Artist"}, {"id": 0, "name": "Display Only"}],
        "SingerName": "Fixture Artist",
        "AlbumID": "9",
        "AlbumName": "Fixture Album",
        "Image": "http://imge.kugou.com/stdmusic/{size}/fixture.jpg",
        "Duration": 123,
        "Grp": []
    })
}

fn page(rows: &[Value], total: u32, page: u32, page_size: u32) -> Value {
    json!({
        "status": 1,
        "error_code": 0,
        "data": {
            "page": page,
            "pagesize": page_size,
            "size": rows.len(),
            "total": total,
            "lists": rows
        }
    })
}

#[tokio::test]
async fn search_is_unsigned_bounded_and_preserves_exact_context() {
    let (client, calls) = fixture_client(vec![Ok(response(&page(&[track("123")], 3, 1, 1)))]);
    let result = client.search_tracks("fixture", 1, 1).await.unwrap();
    assert_eq!(result.page, 1);
    assert_eq!(result.total, 3);
    assert!(result.more);
    assert_eq!(result.items.len(), 1);
    let item = &result.items[0];
    assert_eq!(item.mix_song_id, "123");
    assert_eq!(item.standard_hash, "0123456789ABCDEF0123456789ABCDEF");
    assert_eq!(item.audio_id, 42);
    assert_eq!(item.title, "Fixture Track (Live)");
    assert_eq!(item.artists.len(), 2);
    assert_eq!(item.album.as_ref().unwrap().id, "9");
    assert_eq!(item.duration_seconds, 123);
    assert_eq!(
        item.artwork.as_deref(),
        Some("https://imge.kugou.com/stdmusic/400/fixture.jpg")
    );
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    assert!(!format!("{item:?}").contains("Fixture"));
}

#[tokio::test]
async fn valid_empty_is_distinct_from_missing_shape_and_unknown_code() {
    let (client, _) = fixture_client(vec![Ok(response(&page(&[], 0, 1, 5)))]);
    assert!(
        client
            .search_tracks("fixture", 1, 5)
            .await
            .unwrap()
            .items
            .is_empty()
    );

    for value in [
        json!({"status":1,"error_code":0}),
        json!({"status":1,"error_code":0,"data":{"page":1,"pagesize":5,"size":1,"total":1,"lists":[]}}),
        json!({"status":0,"error_code":20006,"data":{"page":1,"pagesize":5,"size":0,"total":0,"lists":[]}}),
    ] {
        let (client, _) = fixture_client(vec![Ok(response(&value))]);
        assert!(matches!(
            client.search_tracks("fixture", 1, 5).await,
            Err(Error::ResponseShapeMismatch | Error::UpstreamUnknown)
        ));
    }
}

#[tokio::test]
async fn malformed_rows_are_omitted_but_duplicates_and_windows_stay_strict() {
    for field in ["MixSongID", "FileHash", "Audioid", "Duration"] {
        let mut row = track("123");
        row.as_object_mut().unwrap().remove(field);
        let (client, _) = fixture_client(vec![Ok(response(&page(&[row], 1, 1, 1)))]);
        let result = client.search_tracks("fixture", 1, 1).await.unwrap();
        assert!(result.items.is_empty());
        assert_eq!(result.omitted_item_count, 1);
    }
    let (client, _) = fixture_client(vec![Ok(response(&page(
        &[track("123"), track("123")],
        2,
        1,
        2,
    )))]);
    assert_eq!(
        client.search_tracks("fixture", 1, 2).await.unwrap_err(),
        Error::ResponseShapeMismatch
    );
    let (client, _) = fixture_client(vec![Ok(response(&page(&[track("123")], 1, 2, 1)))]);
    assert_eq!(
        client.search_tracks("fixture", 2, 1).await.unwrap_err(),
        Error::ResponseShapeMismatch
    );
}

#[tokio::test]
async fn input_content_type_status_and_artwork_are_strict() {
    let (client, calls) = fixture_client(vec![]);
    for (query, page, size) in [
        ("", 1, 1),
        ("fixture", 0, 1),
        ("fixture", 1, 0),
        ("fixture", 1, 31),
    ] {
        assert_eq!(
            client.search_tracks(query, page, size).await.unwrap_err(),
            Error::InputBound
        );
    }
    assert_eq!(calls.load(Ordering::SeqCst), 0);

    let (client, _) = fixture_client(vec![Ok(Response {
        status: 429,
        content_type: None,
        body: vec![],
    })]);
    assert_eq!(
        client.search_tracks("fixture", 1, 1).await.unwrap_err(),
        Error::RateLimited
    );
    let (client, _) = fixture_client(vec![Ok(Response {
        status: 200,
        content_type: Some("text/html".into()),
        body: b"{}".to_vec(),
    })]);
    assert_eq!(
        client.search_tracks("fixture", 1, 1).await.unwrap_err(),
        Error::ResponseShapeMismatch
    );

    let mut row = track("123");
    row["Image"] = json!("http://example.invalid/art.jpg");
    let (client, _) = fixture_client(vec![Ok(response(&page(&[row], 1, 1, 1)))]);
    let result = client.search_tracks("fixture", 1, 1).await.unwrap();
    assert_eq!(result.items.len(), 1);
    assert_eq!(result.items[0].artwork, None);
    assert_eq!(result.omitted_item_count, 0);
}

#[tokio::test]
async fn good_bad_good_rows_preserve_order_and_report_omission() {
    let mut malformed = track("124");
    malformed.as_object_mut().unwrap().remove("FileHash");
    let (client, _) = fixture_client(vec![Ok(response(&page(
        &[track("123"), malformed, track("125")],
        3,
        1,
        3,
    )))]);

    let result = client.search_tracks("fixture", 1, 3).await.unwrap();
    assert_eq!(result.items.len(), 2);
    assert_eq!(result.items[0].mix_song_id, "123");
    assert_eq!(result.items[1].mix_song_id, "125");
    assert_eq!(result.omitted_item_count, 1);
}

#[tokio::test]
async fn missing_catalog_identity_stays_absent_and_artist_name_is_not_split() {
    let mut row = track("123");
    row["AlbumID"] = json!("0");
    row["AlbumName"] = json!("");
    row["Singers"] = json!([]);
    row["SingerName"] = json!("Artist A、Artist B");
    let (client, _) = fixture_client(vec![Ok(response(&page(&[row], 1, 1, 1)))]);
    let result = client.search_tracks("fixture", 1, 1).await.unwrap();
    assert!(result.items[0].album.is_none());
    assert_eq!(result.items[0].artists.len(), 1);
    assert_eq!(result.items[0].artists[0].id, 0);
    assert_eq!(result.items[0].artists[0].name, "Artist A、Artist B");
}
