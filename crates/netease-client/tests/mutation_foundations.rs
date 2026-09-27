use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

use netease_client::{Credential, Error, NeteaseClient, Request, Response, Transport};
use serde_json::{Value, json};

struct RecordingTransport {
    responses: Mutex<VecDeque<Result<Value, Error>>>,
    urls: Arc<Mutex<Vec<String>>>,
}

impl Transport for RecordingTransport {
    fn send(
        &self,
        request: Request,
    ) -> impl std::future::Future<Output = Result<Response, Error>> + Send {
        assert!(request.cookie().is_some());
        assert_eq!(request.form().len(), 2);
        self.urls.lock().unwrap().push(request.url().to_owned());
        let response = self
            .responses
            .lock()
            .unwrap()
            .pop_front()
            .expect("unexpected mutation request");
        std::future::ready(response.map(|value| Response {
            status: 200,
            body: serde_json::to_vec(&value).unwrap(),
            set_cookies: Vec::new(),
        }))
    }
}

fn credential() -> Credential {
    Credential::import(
        br#"{"version":1,"provider":"netease-cloud-music","music_u":"fixture","csrf":"fixture"}"#,
    )
    .expect("fixture credential")
}

fn client(
    responses: impl IntoIterator<Item = Value>,
) -> (NeteaseClient<RecordingTransport>, Arc<Mutex<Vec<String>>>) {
    let urls = Arc::new(Mutex::new(Vec::new()));
    (
        NeteaseClient::new(RecordingTransport {
            responses: Mutex::new(responses.into_iter().map(Ok).collect()),
            urls: Arc::clone(&urls),
        }),
        urls,
    )
}

fn client_results(
    responses: impl IntoIterator<Item = Result<Value, Error>>,
) -> (NeteaseClient<RecordingTransport>, Arc<Mutex<Vec<String>>>) {
    let urls = Arc::new(Mutex::new(Vec::new()));
    (
        NeteaseClient::new(RecordingTransport {
            responses: Mutex::new(responses.into_iter().collect()),
            urls: Arc::clone(&urls),
        }),
        urls,
    )
}

#[tokio::test]
async fn album_artist_and_owned_playlist_foundations_are_single_request_routes() {
    let (client, urls) = client(std::iter::repeat_n(json!({"code": 200}), 5));
    let credential = credential();

    client
        .set_album_favorite(&credential, 11, true)
        .await
        .expect("album subscribe");
    client
        .set_album_favorite(&credential, 11, false)
        .await
        .expect("album unsubscribe");
    client
        .set_artist_followed(&credential, 12, true)
        .await
        .expect("artist subscribe");
    client
        .set_artist_followed(&credential, 12, false)
        .await
        .expect("artist unsubscribe");
    client
        .delete_owned_playlist(&credential, 13)
        .await
        .expect("playlist removal");

    assert_eq!(
        urls.lock().unwrap().as_slice(),
        [
            "https://music.163.com/weapi/album/sub",
            "https://music.163.com/weapi/album/unsub",
            "https://music.163.com/weapi/artist/sub",
            "https://music.163.com/weapi/artist/unsub",
            "https://music.163.com/weapi/playlist/remove",
        ]
    );
}

#[tokio::test]
async fn mutation_foundations_stop_invalid_input_and_preserve_unknown_outcomes() {
    let (client, urls) = client([json!({"code": 500})]);
    let credential = credential();

    assert_eq!(
        client.set_album_favorite(&credential, 0, true).await,
        Err(Error::InputBound)
    );
    assert_eq!(
        client.set_artist_followed(&credential, 0, true).await,
        Err(Error::InputBound)
    );
    assert_eq!(
        client.delete_owned_playlist(&credential, 0).await,
        Err(Error::InputBound)
    );
    assert!(urls.lock().unwrap().is_empty());

    assert_eq!(
        client.set_album_favorite(&credential, 11, true).await,
        Err(Error::UpstreamUnknown)
    );
    assert_eq!(urls.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn mutation_foundations_keep_typed_failures_and_never_retry() {
    for (response, expected) in [
        (Ok(json!({"code":301})), Error::CredentialRejected),
        (Ok(json!({"code":500})), Error::UpstreamUnknown),
        (Ok(json!({})), Error::ResponseShapeMismatch),
        (
            Err(Error::TemporaryNetworkFailure),
            Error::TemporaryNetworkFailure,
        ),
    ] {
        let (client, urls) = client_results([response]);
        let error = client
            .set_artist_followed(&credential(), 12, true)
            .await
            .expect_err("fixture failure");

        assert_eq!(error, expected);
        assert_eq!(urls.lock().unwrap().len(), 1, "writes are single attempt");
        let debug = format!("{error:?}");
        assert!(!debug.contains("fixture"));
        assert!(!debug.contains("artistId"));
    }
}
