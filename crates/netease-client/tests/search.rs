use netease_client::{Error, NeteaseClient, Request, Response, Transport};
use serde_json::{Value, json};
use std::sync::Mutex;
struct FakeTransport {
    responses: Mutex<Vec<Value>>,
    requests: Mutex<Vec<Request>>,
}
impl Transport for FakeTransport {
    async fn send(&self, request: Request) -> Result<Response, Error> {
        self.requests.lock().unwrap().push(request);
        Ok(Response {
            status: 200,
            body: serde_json::to_vec(&self.responses.lock().unwrap().remove(0)).unwrap(),
            set_cookies: vec![],
        })
    }
}
fn client(value: Value) -> NeteaseClient<FakeTransport> {
    NeteaseClient::new(FakeTransport {
        responses: Mutex::new(vec![value]),
        requests: Mutex::new(vec![]),
    })
}
fn song() -> Value {
    json!({"id":123,"name":"Fixture track","duration":234_000,"artists":[{"id":45,"name":"Fixture artist"}],"album":{"id":67,"name":"Fixture album","picUrl":"http://p1.music.126.net/fixture.jpg"}})
}
#[tokio::test]
async fn search_preserves_exact_identity_context_duration_and_pagination() {
    let p = client(json!({"code":200,"result":{"songCount":3,"songs":[song()]}}))
        .search_tracks("fixture", 0, 1)
        .await
        .unwrap();
    assert_eq!(
        (p.items[0].id, p.items[0].album.id, p.items[0].artists[0].id),
        (123, 67, 45)
    );
    assert_eq!(p.items[0].duration, 234_000);
    assert!(p.more);
    assert_eq!(p.total, 3);
    let p = client(json!({"code":200,"result":{"songCount":3,"songs":[song()]}}))
        .search_tracks("fixture", 2, 1)
        .await
        .unwrap();
    assert!(!p.more);
}
#[tokio::test]
async fn valid_empty_is_distinct_from_missing_shape_and_unknown_codes() {
    assert!(
        client(json!({"code":200,"result":{"songCount":0}}))
            .search_tracks("fixture", 0, 5)
            .await
            .unwrap()
            .items
            .is_empty()
    );
    for v in [
        json!({"code":200}),
        json!({"code":200,"result":{}}),
        json!({"code":200,"result":{"songCount":4,"songs":[]}}),
    ] {
        assert!(matches!(
            client(v).search_tracks("fixture", 0, 5).await,
            Err(Error::ResponseShapeMismatch)
        ));
    }
    assert!(matches!(
        client(json!({"code":7654}))
            .search_tracks("fixture", 0, 5)
            .await,
        Err(Error::UpstreamUnknown)
    ));
    assert!(matches!(
        client(json!({"code":301}))
            .search_tracks("fixture", 0, 5)
            .await,
        Err(Error::AuthenticationRequired)
    ));
}
#[tokio::test]
async fn malformed_rows_and_over_limit_pages_stop() {
    for field in ["id", "name", "duration", "artists", "album"] {
        let mut s = song();
        s.as_object_mut().unwrap().remove(field);
        assert!(matches!(
            client(json!({"code":200,"result":{"songCount":1,"songs":[s]}}))
                .search_tracks("fixture", 0, 1)
                .await,
            Err(Error::ResponseShapeMismatch)
        ));
    }
    assert!(matches!(
        client(json!({"code":200,"result":{"songCount":2,"songs":[song(),song()]}}))
            .search_tracks("fixture", 0, 1)
            .await,
        Err(Error::ResponseShapeMismatch)
    ));
    assert!(matches!(
        client(json!({})).search_tracks("fixture", 0, 101).await,
        Err(Error::InputBound)
    ));
}
#[test]
fn unsafe_artwork_is_rejected() {
    for uri in [
        "http://example.test/art",
        "https://user:password@example.test/art",
        "javascript:x",
        "https://example.test/art#secret",
    ] {
        assert_eq!(
            netease_client::artwork(Some(uri.into())),
            Err(Error::ResponseShapeMismatch)
        );
    }
    assert_eq!(
        netease_client::artwork(Some("http://p1.music.126.net/test".into())).unwrap(),
        Some("https://p1.music.126.net/test".into())
    );
}
#[tokio::test]
async fn display_only_zero_artist_identity_is_not_fabricated() {
    let mut s = song();
    s["artists"][0]["id"] = json!(0);
    let page = client(json!({"code":200,"result":{"songCount":1,"songs":[s]}}))
        .search_tracks("fixture", 0, 1)
        .await
        .unwrap();
    assert_eq!(page.items[0].artists[0].id, 0);
    assert_eq!(page.items[0].artists[0].name, "Fixture artist");
}
