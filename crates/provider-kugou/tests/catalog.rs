use base64::{Engine as _, engine::general_purpose::STANDARD};
use kugou_client::{Error, KuGouClient, Request, Response, Transport};
use music_domain::{RankingId, TrackId};
use provider_api::{LyricsProvider, RankingsProvider, TrackDetailsProvider};
use provider_kugou::{KuGouProvider, provider_id};
use serde_json::{Value, json};
use std::sync::Mutex;

struct Fake {
    values: Mutex<Vec<Value>>,
}

impl Transport for Fake {
    fn send(
        &self,
        _request: Request,
    ) -> impl std::future::Future<Output = Result<Response, Error>> + Send {
        let value = self.values.lock().unwrap().remove(0);
        std::future::ready(Ok(Response {
            status: 200,
            content_type: Some("text/html".into()),
            body: serde_json::to_vec(&value).unwrap(),
        }))
    }
}

fn fixture_provider(values: Vec<Value>) -> KuGouProvider<Fake> {
    KuGouProvider::new(KuGouClient::new(Fake {
        values: Mutex::new(values),
    }))
}

fn track_id() -> TrackId {
    TrackId::new(
        provider_id(),
        "v1:123:0123456789ABCDEF0123456789ABCDEF:42:123:9",
    )
    .unwrap()
}

fn detail() -> Value {
    json!({
        "status": 0,
        "errcode": 0,
        "hash": "0123456789ABCDEF0123456789ABCDEF",
        "album_audio_id": 123,
        "audio_id": 42,
        "songName": "Fixture Track",
        "authors": [{"author_id": 7, "author_name": "Fixture Artist"}],
        "albumid": 9,
        "album_name": "Fixture Album",
        "album_img": "https://imge.kugou.com/stdmusic/400/fixture.jpg",
        "timeLength": 123_000,
        "url": ""
    })
}

fn ranking(id: u64) -> Value {
    json!({
        "rankid": id,
        "rankname": "Fixture Ranking",
        "issue": "Fixture Period",
        "imgurl": "https://imge.kugou.com/v2/rank/400/fixture.jpg"
    })
}

fn ranking_track() -> Value {
    json!({
        "album_audio_id": 123,
        "hash": "0123456789ABCDEF0123456789ABCDEF",
        "audio_id": 42,
        "songname": "Fixture Track",
        "authors": [{"author_id": 7, "author_name": "Fixture Artist"}],
        "album_id": 9,
        "album_name": "Fixture Album",
        "duration": 123
    })
}

#[tokio::test]
async fn exact_detail_requires_all_provider_private_identity_fields() {
    let provider = fixture_provider(vec![detail()]);
    let track = provider.track_details(track_id()).await.unwrap().unwrap();
    assert_eq!(track.id().provider(), &provider_id());
    assert_eq!(track.membership_opaque_id(), "123");
    assert_eq!(track.title(), "Fixture Track");
    assert_eq!(track.artist_names(), ["Fixture Artist"]);
    assert_eq!(track.album().unwrap().id().opaque(), "9");

    let mut mismatch = detail();
    mismatch["album_audio_id"] = json!(124);
    let provider = fixture_provider(vec![mismatch]);
    assert!(provider.track_details(track_id()).await.is_err());

    let foreign = TrackId::new(
        music_domain::ProviderId::new("qq-music").unwrap(),
        track_id().opaque(),
    )
    .unwrap();
    let provider = fixture_provider(Vec::new());
    assert!(provider.track_details(foreign).await.is_err());
}

#[tokio::test]
async fn rankings_map_to_provider_owned_tracks_with_native_cursor() {
    let list = json!({"rank":{"total":1,"list":[ranking(1)]}});
    let page = json!({
        "info": ranking(1),
        "songs":{"page":1,"pagesize":30,"total":1,"list":[ranking_track()]}
    });
    let provider = fixture_provider(vec![list, page]);
    let groups = provider.ranking_groups().await.unwrap();
    assert_eq!(groups.groups().len(), 1);
    assert_eq!(groups.groups()[0].title(), "KuGou Music");
    assert_eq!(groups.groups()[0].rankings().len(), 1);
    let ranking_id = groups.groups()[0].rankings()[0].id().clone();
    let page = provider.ranking_tracks(ranking_id, 0, 30).await.unwrap();
    assert_eq!(page.offset(), 0);
    assert_eq!(page.total(), 1);
    assert!(!page.has_more());
    assert_eq!(page.next_offset(), 1);
    assert_eq!(page.tracks().len(), 1);
    assert_eq!(page.tracks()[0].id().provider(), &provider_id());
    assert_eq!(page.tracks()[0].membership_opaque_id(), "123");

    let provider = fixture_provider(Vec::new());
    let id = RankingId::new(provider_id(), "1").unwrap();
    assert!(provider.ranking_tracks(id.clone(), 0, 20).await.is_err());
    assert!(provider.ranking_tracks(id, 1, 30).await.is_err());
}

#[tokio::test]
async fn lyrics_are_provider_scoped_and_do_not_claim_word_or_auxiliary_timing() {
    let search = json!({
        "status":200,"error_code":200,
        "candidates":[{"id":"55","accesskey":"abc_DEF-123"}]
    });
    let download = json!({
        "status":200,"errcode":0,"fmt":"lrc",
        "content":STANDARD.encode("[00:01.20]Fixture line")
    });
    let provider = fixture_provider(vec![search, download]);
    let lyrics = provider.lyrics(track_id()).await.unwrap();
    assert_eq!(lyrics.track_id().provider(), &provider_id());
    assert_eq!(lyrics.lines().len(), 1);
    assert_eq!(lyrics.lines()[0].start_ms(), 1_200);
    assert_eq!(lyrics.lines()[0].duration_ms(), 0);
    assert!(lyrics.lines()[0].segments().is_empty());
    assert_eq!(lyrics.lines()[0].translation(), None);
    assert_eq!(lyrics.lines()[0].romanization(), None);
}
