use music_domain::*;
use netease_client::{Error, NeteaseClient, Request, Response, Transport};
use provider_api::*;
use provider_netease::{NeteaseProvider, provider_id};
use serde_json::{Value, json};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicUsize, Ordering},
};
struct Fake {
    values: Mutex<std::collections::VecDeque<Value>>,
    calls: Arc<AtomicUsize>,
}
impl Transport for Fake {
    async fn send(&self, r: Request) -> Result<Response, Error> {
        assert!(r.url().starts_with("https://"));
        assert!(r.cookie().is_none());
        assert!(!format!("{r:?}").contains("params"));
        self.calls.fetch_add(1, Ordering::SeqCst);
        Ok(Response {
            status: 200,
            body: serde_json::to_vec(
                &self
                    .values
                    .lock()
                    .unwrap()
                    .pop_front()
                    .expect("unexpected hidden request"),
            )
            .unwrap(),
            set_cookies: vec![],
        })
    }
}
fn provider(values: Vec<Value>) -> (NeteaseProvider<Fake>, Arc<AtomicUsize>) {
    let calls = Arc::new(AtomicUsize::new(0));
    (
        NeteaseProvider::new(NeteaseClient::new(Fake {
            values: Mutex::new(values.into()),
            calls: calls.clone(),
        })),
        calls,
    )
}
fn a() -> Value {
    json!({"id":3,"name":"Album","picUrl":"http://p1.music.126.net/fixture","artists":[{"id":2,"name":"Artist"}]})
}
fn s(id: u64) -> Value {
    json!({"id":id,"name":"Track","ar":[{"id":2,"name":"Artist"},{"id":0,"name":"Display only"}],"al":a(),"dt":123_456})
}
fn p() -> Value {
    json!({"id":4,"name":"Playlist","trackCount":3,"trackIds":[{"id":1},{"id":5},{"id":6}]})
}
fn track() -> TrackId {
    TrackId::new(provider_id(), "1").unwrap()
}
#[tokio::test]
async fn search_details_and_all_context_are_provider_scoped() {
    let (p, calls) = provider(vec![
        json!({"code":200,"result":{"songCount":1,"songs":[s(1)]}}),
        json!({"code":200,"songs":[s(1)]}),
    ]);
    let page = p.search_tracks("fixture".into(), 1, 1).await.unwrap();
    let t = page.items()[0].track();
    assert_eq!(t.id(), &track());
    assert_eq!(t.album().unwrap().id().provider(), &provider_id());
    assert_eq!(t.artists().len(), 1);
    assert_eq!(t.artist_names().len(), 2);
    assert_eq!(t.duration_seconds(), Some(123));
    assert!(t.artwork_uri().unwrap().starts_with("https://"));
    assert_eq!(
        p.track_details(track()).await.unwrap().unwrap().id(),
        &track()
    );
    assert_eq!(calls.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn track_search_keeps_a_song_when_netease_has_no_album_identity() {
    let row = json!({
        "id": 3_422_334_311_u64,
        "name": "神曼波 (Cover 陈阳)",
        "ar": [{"id": 0, "name": "艺术嘉"}],
        "al": {
            "id": 0,
            "name": "",
            "picUrl": "https://p1.music.126.net/placeholder.jpg"
        },
        "dt": 151_000
    });
    let (provider, calls) = provider(vec![
        json!({"code":200,"result":{"songCount":1,"songs":[row]}}),
    ]);

    let page = provider.search_tracks("神曼波".into(), 1, 1).await.unwrap();
    let item = &page.items()[0];
    assert_eq!(item.track().id().opaque(), "3422334311");
    assert_eq!(item.track().artist_names(), &["艺术嘉"]);
    assert!(item.album().is_none());
    assert!(item.track().album().is_none());
    assert!(item.track().album_title().is_none());
    assert!(item.track().artwork_uri().is_none());
    assert!(item.artists().is_empty());
    assert_eq!(calls.load(Ordering::SeqCst), 1);
}
#[tokio::test]
async fn all_search_types_map_and_page_numbers_are_one_based() {
    let (p, c) = provider(vec![
        json!({"code":200,"result":{"artistCount":1,"artists":[{"id":2,"name":"Artist"}]}}),
        json!({"code":200,"result":{"albumCount":1,"albums":[a()]}}),
        json!({"code":200,"result":{"playlistCount":1,"playlists":[p()]}}),
    ]);
    assert_eq!(
        p.search_artists("fixture".into(), 1, 1)
            .await
            .unwrap()
            .artists()[0]
            .id()
            .opaque(),
        "2"
    );
    assert_eq!(
        p.search_albums("fixture".into(), 1, 1)
            .await
            .unwrap()
            .albums()[0]
            .id()
            .opaque(),
        "3"
    );
    assert_eq!(
        p.search_playlists("fixture".into(), 1, 1)
            .await
            .unwrap()
            .playlists()[0]
            .id()
            .opaque(),
        "4"
    );
    assert!(p.search_tracks("fixture".into(), 0, 1).await.is_err());
    assert_eq!(c.load(Ordering::SeqCst), 3);
}
#[tokio::test]
async fn playlist_consumes_raw_cursor_for_unavailable_details_and_restores_order() {
    let (p, c) = provider(vec![
        json!({"code":200,"playlist":p()}),
        json!({"code":200,"songs":[s(5),s(1)]}),
    ]);
    let page = p
        .playlist_tracks_page(PlaylistId::new(provider_id(), "4").unwrap(), 0, 3)
        .await
        .unwrap();
    assert_eq!(page.next_offset(), 3);
    assert_eq!(page.omitted_track_count(), 1);
    assert!(!page.has_more());
    assert_eq!(page.tracks()[0].id().opaque(), "1");
    assert_eq!(page.tracks()[1].id().opaque(), "5");
    assert_eq!(c.load(Ordering::SeqCst), 2);
}
#[tokio::test]
async fn empty_playlist_never_requests_song_details() {
    let (p, c) = provider(vec![
        json!({"code":200,"playlist":{"id":4,"name":"Empty","trackCount":0,"trackIds":[]}}),
    ]);
    assert!(
        p.playlist_tracks_page(PlaylistId::new(provider_id(), "4").unwrap(), 0, 3)
            .await
            .unwrap()
            .tracks()
            .is_empty()
    );
    assert_eq!(c.load(Ordering::SeqCst), 1);
}
#[tokio::test]
async fn playlist_above_the_old_ceiling_pages_without_silent_truncation() {
    let ids: Vec<_> = (1..=1001).map(|id| json!({"id":id})).collect();
    let (p, c) = provider(vec![
        json!({"code":200,"playlist":{"id":4,"name":"Large","trackCount":1001,"trackIds":ids}}),
        json!({"code":200,"songs":[s(1001)]}),
    ]);
    let page = p
        .playlist_tracks_page(PlaylistId::new(provider_id(), "4").unwrap(), 1000, 1)
        .await
        .unwrap();
    assert_eq!(page.tracks()[0].id().opaque(), "1001");
    assert_eq!(page.next_offset(), 1001);
    assert!(!page.has_more());
    assert_eq!(c.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn playlist_identity_table_still_has_a_derived_memory_ceiling() {
    let count = netease_client::MAX_COLLECTION_IDENTITIES + 1;
    let ids: Vec<_> = (1..=count).map(|id| json!({"id":id})).collect();
    let (p, c) = provider(vec![
        json!({"code":200,"playlist":{"id":4,"name":"Too large","trackCount":count,"trackIds":ids}}),
    ]);
    assert!(
        p.playlist_tracks_page(PlaylistId::new(provider_id(), "4").unwrap(), 0, 1)
            .await
            .is_err()
    );
    assert_eq!(c.load(Ordering::SeqCst), 1);
}
#[tokio::test]
async fn album_tracks_metadata_and_artist_pages_are_bounded() {
    let content = json!({"code":200,"album":a(),"songs":[s(1),s(5)]});
    let (p, c) = provider(vec![
        content.clone(),
        content,
        json!({"code":200,"songs":[s(1)],"total":2,"more":true}),
        json!({"code":200,"artist":{"id":2,"albumSize":1},"hotAlbums":[a()],"more":false}),
    ]);
    let id = AlbumId::new(provider_id(), "3").unwrap();
    assert_eq!(p.album_details(id.clone()).await.unwrap().album().id(), &id);
    let page = p.album_tracks(id, 1, 1).await.unwrap();
    assert_eq!(page.tracks()[0].id().opaque(), "5");
    assert!(!page.has_more());
    let id = ArtistId::new(provider_id(), "2").unwrap();
    assert!(p.artist_tracks(id.clone(), 0, 1).await.unwrap().has_more());
    assert!(!p.artist_albums(id, 0, 1).await.unwrap().has_more());
    assert_eq!(c.load(Ordering::SeqCst), 4);
}

#[tokio::test]
async fn album_above_the_old_ceiling_remains_windowed_and_bounded() {
    let songs: Vec<_> = (1..=1001).map(s).collect();
    let (p, c) = provider(vec![json!({"code":200,"album":a(),"songs":songs})]);
    let page = p
        .album_tracks(AlbumId::new(provider_id(), "3").unwrap(), 1000, 1)
        .await
        .unwrap();
    assert_eq!(page.tracks()[0].id().opaque(), "1001");
    assert_eq!(page.total(), 1001);
    assert!(!page.has_more());
    assert_eq!(c.load(Ordering::SeqCst), 1);

    let count = netease_client::MAX_ALBUM_TRACKS + 1;
    let songs: Vec<_> = (1..=count).map(|id| s(id as u64)).collect();
    let (p, c) = provider(vec![json!({"code":200,"album":a(),"songs":songs})]);
    assert!(
        p.album_tracks(AlbumId::new(provider_id(), "3").unwrap(), 0, 1)
            .await
            .is_err()
    );
    assert_eq!(c.load(Ordering::SeqCst), 1);
}
#[tokio::test]
async fn lyrics_keep_only_exact_translation_alignment_and_no_invented_words() {
    let (p, _) = provider(vec![
        json!({"code":200,"lrc":{"lyric":"[00:01]Fixture\n[00:02]End"},"tlyric":{"lyric":"[00:01]Translation\n[00:03]Unmatched"}}),
    ]);
    let l = p.lyrics(track()).await.unwrap();
    assert_eq!(l.lines().len(), 2);
    assert_eq!(l.lines()[0].translation(), Some("Translation"));
    assert_eq!(l.lines()[1].translation(), None);
    assert!(l.lines()[0].segments().is_empty());
    assert_eq!(l.lines()[0].duration_ms(), 0);
}
#[tokio::test]
async fn foreign_ids_never_send_or_attempt_fuzzy_matching() {
    let (p, c) = provider(vec![]);
    let foreign = TrackId::new(BuiltInProvider::QQMusic.id(), "1").unwrap();
    assert!(p.track_details(foreign.clone()).await.is_err());
    assert!(!p.media_source_resolver().supports(&foreign));
    assert!(
        p.media_source_resolver()
            .resolve_media(foreign, AudioQuality::High)
            .await
            .is_err()
    );
    assert_eq!(c.load(Ordering::SeqCst), 0);
}
#[tokio::test]
async fn recommendations_rankings_and_standard_media_map_without_raw_fields() {
    let media = json!({"code":200,"data":[{"id":1,"code":200,"url":"https://fixture.invalid/source","type":"mp3","expi":600,"freeTrialInfo":null,"level":"standard"}]});
    let (p, _) = provider(vec![
        json!({"code":200,"result":[p()]}),
        json!({"code":200,"list":[p()]}),
        media,
    ]);
    assert!(!p.recommended_playlists(0, 1).await.unwrap().has_more());
    assert_eq!(p.ranking_groups().await.unwrap().len(), 1);
    let source = p
        .media_source_resolver()
        .resolve_media(track(), AudioQuality::Lossless)
        .await
        .unwrap();
    assert_eq!(source.quality(), AudioQuality::Standard);
    assert!(!format!("{source:?}").contains("fixture.invalid"));
}

#[tokio::test]
async fn selected_media_quality_maps_requested_and_actual_netease_levels() {
    let high = json!({"code":200,"data":[{"id":1,"code":200,"url":"https://fixture.invalid/high","type":"mp3","expi":600,"freeTrialInfo":null,"level":"exhigh"}]});
    let lossless = json!({"code":200,"data":[{"id":1,"code":200,"url":"https://fixture.invalid/lossless","type":"flac","expi":600,"freeTrialInfo":null,"level":"lossless"}]});
    let (provider, calls) = provider(vec![high, lossless]);

    let high_source = provider
        .media_source_resolver()
        .resolve_media(track(), AudioQuality::High)
        .await
        .unwrap();
    assert_eq!(high_source.format(), AudioFormat::Mp3);
    assert_eq!(high_source.quality(), AudioQuality::High);

    let lossless_source = provider
        .media_source_resolver()
        .resolve_media(track(), AudioQuality::Lossless)
        .await
        .unwrap();
    assert_eq!(lossless_source.format(), AudioFormat::Flac);
    assert_eq!(lossless_source.quality(), AudioQuality::Lossless);
    assert_eq!(calls.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn ranking_omissions_preserve_cursor_even_when_entire_window_is_unavailable() {
    let detail = json!({"code":200,"playlist":{"id":4,"name":"Ranking","trackCount":3,"trackIds":[{"id":1},{"id":5},{"id":7}]}});
    let (p, calls) = provider(vec![
        detail.clone(),
        json!({"code":200,"songs":[]}),
        detail,
        json!({"code":200,"songs":[s(7)]}),
    ]);
    let id = RankingId::new(provider_id(), "4").unwrap();
    let first = p.ranking_tracks(id.clone(), 0, 2).await.unwrap();
    assert!(first.tracks().is_empty());
    assert_eq!(first.omitted_track_count(), 2);
    assert_eq!(first.next_offset(), 2);
    assert!(first.has_more());
    let second = p.ranking_tracks(id, first.next_offset(), 2).await.unwrap();
    assert_eq!(second.tracks()[0].id().opaque(), "7");
    assert_eq!(second.omitted_track_count(), 0);
    assert_eq!(second.next_offset(), 3);
    assert!(!second.has_more());
    assert_eq!(calls.load(Ordering::SeqCst), 4);
}
