use kugou_client::{Error, KuGouClient, Request, Response, Transport};
use provider_api::{MusicProvider, ProviderCapability, TrackSearchProvider};
use provider_kugou::{KuGouProvider, provider_id};
use serde_json::{Value, json};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicUsize, Ordering},
};

struct Fake {
    value: Mutex<Option<Value>>,
    calls: Arc<AtomicUsize>,
}

impl Transport for Fake {
    async fn send(&self, request: Request) -> Result<Response, Error> {
        assert!(request.url().starts_with("https://songsearch.kugou.com/"));
        self.calls.fetch_add(1, Ordering::SeqCst);
        Ok(Response {
            status: 200,
            content_type: Some("application/json".into()),
            body: serde_json::to_vec(&self.value.lock().unwrap().take().unwrap()).unwrap(),
        })
    }
}

fn provider(value: Value) -> (KuGouProvider<Fake>, Arc<AtomicUsize>) {
    let calls = Arc::new(AtomicUsize::new(0));
    (
        KuGouProvider::new(KuGouClient::new(Fake {
            value: Mutex::new(Some(value)),
            calls: calls.clone(),
        })),
        calls,
    )
}

fn result() -> Value {
    json!({
        "status": 1,
        "error_code": 0,
        "data": {
            "page": 1,
            "pagesize": 1,
            "size": 1,
            "total": 2,
            "lists": [{
                "MixSongID": "123",
                "FileHash": "0123456789ABCDEF0123456789ABCDEF",
                "Audioid": 42,
                "OriSongName": "Fixture Track",
                "Singers": [{"id": 7, "name": "Fixture Artist"}, {"id": 0, "name": "Display Only"}],
                "AlbumID": "9",
                "AlbumName": "Fixture Album",
                "Image": "https://imge.kugou.com/stdmusic/400/fixture.jpg",
                "Duration": 123
            }]
        }
    })
}

#[tokio::test]
async fn descriptor_and_search_are_truthful_and_provider_scoped() {
    let (provider, calls) = provider(result());
    assert_eq!(provider.descriptor().id, provider_id());
    assert_eq!(provider.descriptor().display_name, "KuGou Music");
    assert_eq!(
        provider.descriptor().capabilities,
        [ProviderCapability::Search]
    );

    let page = provider
        .search_tracks("fixture".into(), 1, 1)
        .await
        .unwrap();
    assert!(page.has_more());
    assert_eq!(page.total(), 2);
    let item = &page.items()[0];
    assert_eq!(item.track().id().provider(), &provider_id());
    assert_eq!(item.track().id().opaque(), "123");
    assert_eq!(item.track().title(), "Fixture Track");
    assert_eq!(
        item.track().artist_names(),
        ["Fixture Artist", "Display Only"]
    );
    assert_eq!(item.track().artists().len(), 1);
    assert_eq!(item.track().artists()[0].id().provider(), &provider_id());
    assert_eq!(item.album().unwrap().id().provider(), &provider_id());
    assert_eq!(item.track().duration_seconds(), Some(123));
    assert_eq!(calls.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn invalid_input_fails_before_transport_and_never_uses_another_provider() {
    let (provider, calls) = provider(result());
    assert!(provider.search_tracks(String::new(), 1, 1).await.is_err());
    assert!(
        provider
            .search_tracks("fixture".into(), 0, 1)
            .await
            .is_err()
    );
    assert_eq!(calls.load(Ordering::SeqCst), 0);
    assert_ne!(provider_id().as_str(), "qq-music");
    assert_ne!(provider_id().as_str(), "netease-cloud-music");
}
