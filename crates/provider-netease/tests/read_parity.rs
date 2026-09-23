use music_domain::*;
use netease_client::{Error, NeteaseClient, Request, Response, Transport};
use provider_api::*;
use provider_netease::{NeteaseProvider, provider_id};
use serde_json::{Value, json};
use std::sync::{Arc, Mutex};

struct Fake {
    values: Mutex<std::collections::VecDeque<Value>>,
    urls: Arc<Mutex<Vec<String>>>,
}

impl Transport for Fake {
    fn send(
        &self,
        request: Request,
    ) -> impl std::future::Future<Output = Result<Response, Error>> + Send {
        assert!(request.cookie().is_none());
        self.urls.lock().unwrap().push(request.url().to_owned());
        std::future::ready(Ok(Response {
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
        }))
    }
}

fn provider(values: Vec<Value>) -> (NeteaseProvider<Fake>, Arc<Mutex<Vec<String>>>) {
    let urls = Arc::new(Mutex::new(Vec::new()));
    (
        NeteaseProvider::new(NeteaseClient::new(Fake {
            values: Mutex::new(values.into()),
            urls: urls.clone(),
        })),
        urls,
    )
}

fn album() -> Value {
    json!({
        "id":3,
        "name":"Album",
        "picUrl":"http://p1.music.126.net/fixture",
        "artists":[{"id":2,"name":"Artist"}]
    })
}

fn song(id: u64, mv: u64) -> Value {
    json!({
        "id":id,
        "name":"Track",
        "ar":[{"id":2,"name":"Artist"}],
        "al":album(),
        "dt":123_456,
        "mv":mv
    })
}

fn comment(id: u64) -> Value {
    json!({
        "commentId":id,
        "content":"Comment",
        "time":1_700_000_000_000_u64 + id,
        "likedCount":3,
        "user":{
            "nickname":"Listener",
            "avatarUrl":"http://p1.music.126.net/avatar.jpg"
        }
    })
}

fn track() -> TrackId {
    TrackId::new(provider_id(), "1").unwrap()
}

#[test]
fn descriptor_advertises_only_completed_read_capabilities() {
    let (provider, _) = provider(vec![]);
    let descriptor = provider.descriptor();
    assert!(
        descriptor
            .capabilities
            .contains(&ProviderCapability::Comments)
    );
    assert!(
        descriptor
            .capabilities
            .contains(&ProviderCapability::MusicVideo)
    );
    assert!(
        descriptor
            .capabilities
            .contains(&ProviderCapability::RecentHistoryRead)
    );
    assert!(
        descriptor
            .capabilities
            .contains(&ProviderCapability::TrackLikeMutation)
    );
    assert!(
        descriptor
            .capabilities
            .contains(&ProviderCapability::PlaylistTrackMutation)
    );
    assert!(
        descriptor
            .capabilities
            .contains(&ProviderCapability::PlaylistCreation)
    );
    assert!(
        !descriptor
            .capabilities
            .contains(&ProviderCapability::AlbumFavoriteMutation)
    );
    assert!(
        !descriptor
            .capabilities
            .contains(&ProviderCapability::PlaylistDeletion)
    );
}

#[tokio::test]
async fn comments_keep_true_hot_and_latest_paging_without_identity_leakage() {
    let (provider, urls) = provider(vec![
        json!({"code":200,"total":2,"more":true,"hotComments":[comment(9)],"comments":[comment(1)]}),
        json!({"code":200,"total":2,"more":false,"hotComments":[comment(9)],"comments":[comment(2)]}),
    ]);
    let first = provider.track_comments(track(), 0, 1).await.unwrap();
    assert_eq!(first.hot_comments().len(), 1);
    assert_eq!(first.latest_comments().len(), 1);
    assert_eq!(first.latest_comments()[0].id().opaque(), "1");
    assert_eq!(
        first.latest_comments()[0].published_at_unix_seconds(),
        1_700_000_000
    );
    assert_eq!(
        first.latest_comments()[0].author_avatar_uri(),
        Some("https://p1.music.126.net/avatar.jpg")
    );
    assert!(first.has_more());
    assert!(!format!("{first:?}").contains("Listener"));
    let second = provider.track_comments(track(), 1, 1).await.unwrap();
    assert!(second.hot_comments().is_empty());
    assert!(!second.has_more());
    assert!(urls.lock().unwrap()[0].ends_with("v1/resource/comments/R_SO_4_1"));
}

#[tokio::test]
async fn valid_empty_and_partial_duplicate_comments_are_distinct() {
    let (provider, _) = provider(vec![
        json!({"code":200,"total":0,"more":false,"hotComments":[],"comments":[]}),
        json!({"code":200,"total":2,"more":false,"hotComments":[],"comments":[comment(1),comment(1)]}),
    ]);
    let empty = provider.track_comments(track(), 0, 10).await.unwrap();
    assert!(empty.latest_comments().is_empty());
    let partial = provider.track_comments(track(), 0, 2).await.unwrap();
    assert_eq!(partial.latest_comments().len(), 1);
    assert_eq!(partial.next_offset(), 2);
    assert_eq!(partial.omitted_latest_comment_count(), 1);
}

#[tokio::test]
async fn related_tracks_are_exact_bounded_and_reject_seed_or_duplicates() {
    let (provider, urls) = provider(vec![
        json!({"code":200,"songs":[song(2,0)]}),
        json!({"code":200,"songs":[song(1,0)]}),
        json!({"code":200,"songs":[song(2,0),song(2,0)]}),
    ]);
    let rows = provider.related_tracks(track()).await.unwrap();
    assert_eq!(rows[0].id().opaque(), "2");
    assert_eq!(
        provider.related_tracks(track()).await,
        Err(RelatedTracksError::InvalidResponse)
    );
    assert_eq!(
        provider.related_tracks(track()).await,
        Err(RelatedTracksError::InvalidResponse)
    );
    assert!(urls.lock().unwrap()[0].ends_with("v1/discovery/simiSong"));
}

#[tokio::test]
async fn new_song_categories_map_only_exact_netease_semantics() {
    let (provider, urls) = provider(vec![json!({"code":200,"data":[song(1,0)]})]);
    assert_eq!(
        provider.new_songs(NewSongCategory::MainlandChina).await,
        Err(CatalogError::InvalidResponse)
    );
    let latest = provider.new_songs(NewSongCategory::Latest).await.unwrap();
    assert_eq!(latest.category(), NewSongCategory::Latest);
    assert_eq!(latest.tracks()[0].id().opaque(), "1");
    assert_eq!(urls.lock().unwrap().len(), 1);
    assert!(urls.lock().unwrap()[0].ends_with("v1/discovery/new/songs"));
}

#[tokio::test]
async fn new_albums_use_true_pages_and_do_not_fabricate_release_dates() {
    let mut release = album();
    release["publishTime"] = json!(1_700_000_000_000_u64);
    let (provider, urls) = provider(vec![json!({"code":200,"total":2,"albums":[release]})]);
    assert_eq!(
        provider
            .new_album_releases(NewAlbumRegion::MainlandChina, 0, 1)
            .await,
        Err(CatalogError::InvalidResponse)
    );
    let page = provider
        .new_album_releases(NewAlbumRegion::Japan, 0, 1)
        .await
        .unwrap();
    assert_eq!(page.region(), NewAlbumRegion::Japan);
    assert!(page.has_more());
    assert_eq!(page.releases()[0].album().id().opaque(), "3");
    assert_eq!(page.releases()[0].release_date(), None);
    assert_eq!(urls.lock().unwrap().len(), 1);
    assert!(urls.lock().unwrap()[0].ends_with("album/new"));
}

#[tokio::test]
async fn track_mv_follows_exact_association_and_returns_redacted_https_source() {
    let (provider, urls) = provider(vec![
        json!({"code":200,"songs":[song(1,9)]}),
        json!({"code":200,"data":{"id":9,"name":"Video","artistName":"Artist","artists":[{"id":2,"name":"Artist"}],"cover":"http://p1.music.126.net/mv","duration":180_000}}),
        json!({"code":200,"data":{"id":9,"code":200,"url":"http://vod.example.126.net/source","r":720}}),
    ]);
    let video = provider.track_music_video(track()).await.unwrap().unwrap();
    assert_eq!(video.id().opaque(), "9");
    assert_eq!(video.source().quality(), MusicVideoQuality::Hd);
    assert!(video.source().uri().starts_with("https://"));
    assert!(!format!("{video:?}").contains("example.126.net"));
    let urls = urls.lock().unwrap();
    assert_eq!(urls.len(), 3);
    assert!(urls[0].ends_with("v3/song/detail"));
    assert!(urls[1].ends_with("v1/mv/detail"));
    assert!(urls[2].ends_with("song/enhance/play/mv/url"));
}

#[tokio::test]
async fn track_without_mv_is_valid_none_and_never_requests_video_endpoints() {
    let (provider, urls) = provider(vec![json!({"code":200,"songs":[song(1,0)]})]);
    assert!(provider.track_music_video(track()).await.unwrap().is_none());
    assert_eq!(urls.lock().unwrap().len(), 1);
}
