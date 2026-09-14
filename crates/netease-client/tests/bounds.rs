use netease_client::{Error, MAX_RESPONSE_BYTES, NeteaseClient, Request, Response, Transport};
use serde_json::{Value, json};
use std::sync::atomic::{AtomicUsize, Ordering};
struct Fake {
    status: u16,
    body: Vec<u8>,
    calls: AtomicUsize,
}
impl Transport for Fake {
    async fn send(&self, r: Request) -> Result<Response, Error> {
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
        Ok(Response {
            status: self.status,
            body: self.body.clone(),
            set_cookies: vec![],
        })
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
