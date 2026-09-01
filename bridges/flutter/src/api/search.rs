use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use provider_api::{
    AlbumSearchProvider, ArtistSearchProvider, PlaylistSearchProvider, SearchError,
    TrackSearchProvider,
};
use tokio::sync::Notify;

use super::album::{CatalogAlbumSummary, bridge_album_summary};
use super::artist::{CatalogArtistSummary, bridge_artist_summary};
use super::authentication::native_qq_music_provider;
use super::library::{
    LibraryPlaylistSummary, LibraryTrackSummary, bridge_playlist_summary, bridge_track_summary,
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicTrackSearchPageLoadFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicTrackSearchItem {
    pub track: LibraryTrackSummary,
    pub album: Option<CatalogAlbumSummary>,
    pub artists: Vec<CatalogArtistSummary>,
}

impl fmt::Debug for QqMusicTrackSearchItem {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicTrackSearchItem")
            .field("track", &self.track)
            .field("album", &self.album)
            .field("artists", &self.artists)
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicTrackSearchPageLoad {
    pub page: u32,
    pub total: u32,
    pub has_more: bool,
    pub items: Vec<QqMusicTrackSearchItem>,
    pub failure: Option<QqMusicTrackSearchPageLoadFailure>,
}

impl fmt::Debug for QqMusicTrackSearchPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicTrackSearchPageLoad")
            .field("page", &self.page)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("item_count", &self.items.len())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use Track search page. The query remains inside
/// this opaque handle and is always redacted from diagnostics.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicTrackSearchPageLoadHandle {
    query: String,
    page: u32,
    size: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicTrackSearchPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicTrackSearchPageLoadHandle")
            .field("query", &"[REDACTED]")
            .field("page", &self.page)
            .field("size", &self.size)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicTrackSearchPageLoadHandle {
    pub async fn run(&self) -> QqMusicTrackSearchPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_load(QqMusicTrackSearchPageLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_load(QqMusicTrackSearchPageLoadFailure::AlreadyRunning);
        }

        let outcome = match native_qq_music_provider() {
            Ok(provider) => {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_load(QqMusicTrackSearchPageLoadFailure::Cancelled)
                    }
                    result = provider.search_tracks(self.query.clone(), self.page, self.size) => {
                        if self.active.load(Ordering::SeqCst) {
                            map_load(result)
                        } else {
                            failed_load(QqMusicTrackSearchPageLoadFailure::Cancelled)
                        }
                    }
                }
            }
            Err(()) => failed_load(QqMusicTrackSearchPageLoadFailure::CoreUnavailable),
        };
        self.running.store(false, Ordering::SeqCst);
        self.active.store(false, Ordering::SeqCst);
        outcome
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) -> bool {
        let was_active = self.active.swap(false, Ordering::SeqCst);
        if was_active {
            self.cancelled.notify_one();
        }
        was_active
    }

    #[flutter_rust_bridge::frb(sync, getter)]
    pub fn is_active(&self) -> bool {
        self.active.load(Ordering::SeqCst)
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn begin_qq_music_track_search_page_load(
    query: String,
    page: u32,
    size: u32,
) -> QqMusicTrackSearchPageLoadHandle {
    QqMusicTrackSearchPageLoadHandle {
        query,
        page,
        size,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_load(
    result: Result<music_domain::TrackSearchPage, SearchError>,
) -> QqMusicTrackSearchPageLoad {
    match result {
        Ok(page) => QqMusicTrackSearchPageLoad {
            page: page.page(),
            total: page.total(),
            has_more: page.has_more(),
            items: page
                .items()
                .iter()
                .map(|item| QqMusicTrackSearchItem {
                    track: bridge_track_summary(item.track()),
                    album: item.album().map(bridge_album_summary),
                    artists: item.artists().iter().map(bridge_artist_summary).collect(),
                })
                .collect(),
            failure: None,
        },
        Err(error) => failed_load(map_error(error)),
    }
}

const fn failed_load(failure: QqMusicTrackSearchPageLoadFailure) -> QqMusicTrackSearchPageLoad {
    QqMusicTrackSearchPageLoad {
        page: 0,
        total: 0,
        has_more: false,
        items: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_error(error: SearchError) -> QqMusicTrackSearchPageLoadFailure {
    match error {
        SearchError::Network => QqMusicTrackSearchPageLoadFailure::Network,
        SearchError::ServiceUnavailable => QqMusicTrackSearchPageLoadFailure::ServiceUnavailable,
        SearchError::InvalidResponse => QqMusicTrackSearchPageLoadFailure::InvalidResponse,
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicArtistSearchPageLoadFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicArtistSearchPageLoad {
    pub page: u32,
    pub total: u32,
    pub has_more: bool,
    pub artists: Vec<CatalogArtistSummary>,
    pub failure: Option<QqMusicArtistSearchPageLoadFailure>,
}

impl fmt::Debug for QqMusicArtistSearchPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicArtistSearchPageLoad")
            .field("page", &self.page)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("artist_count", &self.artists.len())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use Artist search page. The query remains inside
/// this opaque handle and is always redacted from diagnostics.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicArtistSearchPageLoadHandle {
    query: String,
    page: u32,
    size: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicArtistSearchPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicArtistSearchPageLoadHandle")
            .field("query", &"[REDACTED]")
            .field("page", &self.page)
            .field("size", &self.size)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicArtistSearchPageLoadHandle {
    pub async fn run(&self) -> QqMusicArtistSearchPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_artist_load(QqMusicArtistSearchPageLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_artist_load(QqMusicArtistSearchPageLoadFailure::AlreadyRunning);
        }

        let outcome = match native_qq_music_provider() {
            Ok(provider) => {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_artist_load(QqMusicArtistSearchPageLoadFailure::Cancelled)
                    }
                    result = provider.search_artists(self.query.clone(), self.page, self.size) => {
                        if self.active.load(Ordering::SeqCst) {
                            map_artist_load(result)
                        } else {
                            failed_artist_load(QqMusicArtistSearchPageLoadFailure::Cancelled)
                        }
                    }
                }
            }
            Err(()) => failed_artist_load(QqMusicArtistSearchPageLoadFailure::CoreUnavailable),
        };
        self.running.store(false, Ordering::SeqCst);
        self.active.store(false, Ordering::SeqCst);
        outcome
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) -> bool {
        let was_active = self.active.swap(false, Ordering::SeqCst);
        if was_active {
            self.cancelled.notify_one();
        }
        was_active
    }

    #[flutter_rust_bridge::frb(sync, getter)]
    pub fn is_active(&self) -> bool {
        self.active.load(Ordering::SeqCst)
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn begin_qq_music_artist_search_page_load(
    query: String,
    page: u32,
    size: u32,
) -> QqMusicArtistSearchPageLoadHandle {
    QqMusicArtistSearchPageLoadHandle {
        query,
        page,
        size,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_artist_load(
    result: Result<music_domain::ArtistSearchPage, SearchError>,
) -> QqMusicArtistSearchPageLoad {
    match result {
        Ok(page) => QqMusicArtistSearchPageLoad {
            page: page.page(),
            total: page.total(),
            has_more: page.has_more(),
            artists: page.artists().iter().map(bridge_artist_summary).collect(),
            failure: None,
        },
        Err(error) => failed_artist_load(map_artist_error(error)),
    }
}

const fn failed_artist_load(
    failure: QqMusicArtistSearchPageLoadFailure,
) -> QqMusicArtistSearchPageLoad {
    QqMusicArtistSearchPageLoad {
        page: 0,
        total: 0,
        has_more: false,
        artists: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_artist_error(error: SearchError) -> QqMusicArtistSearchPageLoadFailure {
    match error {
        SearchError::Network => QqMusicArtistSearchPageLoadFailure::Network,
        SearchError::ServiceUnavailable => QqMusicArtistSearchPageLoadFailure::ServiceUnavailable,
        SearchError::InvalidResponse => QqMusicArtistSearchPageLoadFailure::InvalidResponse,
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicAlbumSearchPageLoadFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicAlbumSearchPageLoad {
    pub page: u32,
    pub total: u32,
    pub has_more: bool,
    pub albums: Vec<CatalogAlbumSummary>,
    pub failure: Option<QqMusicAlbumSearchPageLoadFailure>,
}

impl fmt::Debug for QqMusicAlbumSearchPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicAlbumSearchPageLoad")
            .field("page", &self.page)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("album_count", &self.albums.len())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use Album search page. The query remains inside
/// this opaque handle and is always redacted from diagnostics.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicAlbumSearchPageLoadHandle {
    query: String,
    page: u32,
    size: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicAlbumSearchPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicAlbumSearchPageLoadHandle")
            .field("query", &"[REDACTED]")
            .field("page", &self.page)
            .field("size", &self.size)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicAlbumSearchPageLoadHandle {
    pub async fn run(&self) -> QqMusicAlbumSearchPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_album_load(QqMusicAlbumSearchPageLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_album_load(QqMusicAlbumSearchPageLoadFailure::AlreadyRunning);
        }

        let outcome = match native_qq_music_provider() {
            Ok(provider) => {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_album_load(QqMusicAlbumSearchPageLoadFailure::Cancelled)
                    }
                    result = provider.search_albums(self.query.clone(), self.page, self.size) => {
                        if self.active.load(Ordering::SeqCst) {
                            map_album_load(result)
                        } else {
                            failed_album_load(QqMusicAlbumSearchPageLoadFailure::Cancelled)
                        }
                    }
                }
            }
            Err(()) => failed_album_load(QqMusicAlbumSearchPageLoadFailure::CoreUnavailable),
        };
        self.running.store(false, Ordering::SeqCst);
        self.active.store(false, Ordering::SeqCst);
        outcome
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) -> bool {
        let was_active = self.active.swap(false, Ordering::SeqCst);
        if was_active {
            self.cancelled.notify_one();
        }
        was_active
    }

    #[flutter_rust_bridge::frb(sync, getter)]
    pub fn is_active(&self) -> bool {
        self.active.load(Ordering::SeqCst)
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn begin_qq_music_album_search_page_load(
    query: String,
    page: u32,
    size: u32,
) -> QqMusicAlbumSearchPageLoadHandle {
    QqMusicAlbumSearchPageLoadHandle {
        query,
        page,
        size,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_album_load(
    result: Result<music_domain::AlbumSearchPage, SearchError>,
) -> QqMusicAlbumSearchPageLoad {
    match result {
        Ok(page) => QqMusicAlbumSearchPageLoad {
            page: page.page(),
            total: page.total(),
            has_more: page.has_more(),
            albums: page.albums().iter().map(bridge_album_summary).collect(),
            failure: None,
        },
        Err(error) => failed_album_load(map_album_error(error)),
    }
}

const fn failed_album_load(
    failure: QqMusicAlbumSearchPageLoadFailure,
) -> QqMusicAlbumSearchPageLoad {
    QqMusicAlbumSearchPageLoad {
        page: 0,
        total: 0,
        has_more: false,
        albums: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_album_error(error: SearchError) -> QqMusicAlbumSearchPageLoadFailure {
    match error {
        SearchError::Network => QqMusicAlbumSearchPageLoadFailure::Network,
        SearchError::ServiceUnavailable => QqMusicAlbumSearchPageLoadFailure::ServiceUnavailable,
        SearchError::InvalidResponse => QqMusicAlbumSearchPageLoadFailure::InvalidResponse,
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicPlaylistSearchPageLoadFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicPlaylistSearchPageLoad {
    pub page: u32,
    pub total: u32,
    pub has_more: bool,
    pub playlists: Vec<LibraryPlaylistSummary>,
    pub failure: Option<QqMusicPlaylistSearchPageLoadFailure>,
}

impl fmt::Debug for QqMusicPlaylistSearchPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicPlaylistSearchPageLoad")
            .field("page", &self.page)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("playlist_count", &self.playlists.len())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use Playlist search page. The query remains inside
/// this opaque handle and is always redacted from diagnostics.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicPlaylistSearchPageLoadHandle {
    query: String,
    page: u32,
    size: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicPlaylistSearchPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicPlaylistSearchPageLoadHandle")
            .field("query", &"[REDACTED]")
            .field("page", &self.page)
            .field("size", &self.size)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicPlaylistSearchPageLoadHandle {
    pub async fn run(&self) -> QqMusicPlaylistSearchPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_playlist_load(QqMusicPlaylistSearchPageLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_playlist_load(QqMusicPlaylistSearchPageLoadFailure::AlreadyRunning);
        }

        let outcome = match native_qq_music_provider() {
            Ok(provider) => {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_playlist_load(QqMusicPlaylistSearchPageLoadFailure::Cancelled)
                    }
                    result = provider.search_playlists(self.query.clone(), self.page, self.size) => {
                        if self.active.load(Ordering::SeqCst) {
                            map_playlist_load(result)
                        } else {
                            failed_playlist_load(QqMusicPlaylistSearchPageLoadFailure::Cancelled)
                        }
                    }
                }
            }
            Err(()) => failed_playlist_load(QqMusicPlaylistSearchPageLoadFailure::CoreUnavailable),
        };
        self.running.store(false, Ordering::SeqCst);
        self.active.store(false, Ordering::SeqCst);
        outcome
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) -> bool {
        let was_active = self.active.swap(false, Ordering::SeqCst);
        if was_active {
            self.cancelled.notify_one();
        }
        was_active
    }

    #[flutter_rust_bridge::frb(sync, getter)]
    pub fn is_active(&self) -> bool {
        self.active.load(Ordering::SeqCst)
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn begin_qq_music_playlist_search_page_load(
    query: String,
    page: u32,
    size: u32,
) -> QqMusicPlaylistSearchPageLoadHandle {
    QqMusicPlaylistSearchPageLoadHandle {
        query,
        page,
        size,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_playlist_load(
    result: Result<music_domain::PlaylistSearchPage, SearchError>,
) -> QqMusicPlaylistSearchPageLoad {
    match result {
        Ok(page) => QqMusicPlaylistSearchPageLoad {
            page: page.page(),
            total: page.total(),
            has_more: page.has_more(),
            playlists: page
                .playlists()
                .iter()
                .map(bridge_playlist_summary)
                .collect(),
            failure: None,
        },
        Err(error) => failed_playlist_load(map_playlist_error(error)),
    }
}

const fn failed_playlist_load(
    failure: QqMusicPlaylistSearchPageLoadFailure,
) -> QqMusicPlaylistSearchPageLoad {
    QqMusicPlaylistSearchPageLoad {
        page: 0,
        total: 0,
        has_more: false,
        playlists: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_playlist_error(error: SearchError) -> QqMusicPlaylistSearchPageLoadFailure {
    match error {
        SearchError::Network => QqMusicPlaylistSearchPageLoadFailure::Network,
        SearchError::ServiceUnavailable => QqMusicPlaylistSearchPageLoadFailure::ServiceUnavailable,
        SearchError::InvalidResponse => QqMusicPlaylistSearchPageLoadFailure::InvalidResponse,
    }
}

#[cfg(test)]
mod tests {
    use music_domain::{
        AlbumId, AlbumSearchPage, AlbumSummary, ArtistId, ArtistSearchPage, ArtistSummary,
        PlaylistId, PlaylistSearchPage, PlaylistSummary, ProviderId, TrackId, TrackSearchItem,
        TrackSearchPage, TrackSummary,
    };
    use provider_api::SearchError;

    use super::{
        QqMusicAlbumSearchPageLoadFailure, QqMusicArtistSearchPageLoadFailure,
        QqMusicPlaylistSearchPageLoadFailure, QqMusicTrackSearchPageLoadFailure,
        begin_qq_music_album_search_page_load, begin_qq_music_artist_search_page_load,
        begin_qq_music_playlist_search_page_load, begin_qq_music_track_search_page_load,
        map_album_error, map_album_load, map_artist_error, map_artist_load, map_error, map_load,
        map_playlist_error, map_playlist_load,
    };

    #[test]
    fn maps_search_page_without_exposing_query_or_content() {
        let track = TrackSummary::new(
            TrackId::new(
                ProviderId::new("qq-music").expect("provider"),
                "track:41001:0:fixtureMid:-",
            )
            .expect("track ID"),
            "must-not-leak",
            vec!["private-artist".into()],
        )
        .expect("track summary");
        let album = AlbumSummary::new(
            AlbumId::new(
                ProviderId::new("qq-music").expect("provider"),
                "album:43001:fixtureAlbumMid",
            )
            .expect("Album ID"),
            "private-album",
        )
        .expect("Album summary");
        let artist = ArtistSummary::new(
            ArtistId::new(
                ProviderId::new("qq-music").expect("provider"),
                "artist:42001:fixtureArtistMid",
            )
            .expect("Artist ID"),
            "private-artist",
        )
        .expect("Artist summary")
        .with_artwork_uri(Some("https://example.invalid/artist.jpg".into()));
        let mapped = map_load(Ok(TrackSearchPage::new(
            1,
            31,
            true,
            vec![TrackSearchItem::new(track, Some(album), vec![artist])],
        )));

        assert_eq!(mapped.page, 1);
        assert_eq!(mapped.total, 31);
        assert!(mapped.has_more);
        assert_eq!(mapped.items.len(), 1);
        assert_eq!(mapped.items[0].track.provider_id, "qq-music");
        assert_eq!(mapped.items[0].track.title, "must-not-leak");
        assert!(mapped.items[0].album.is_some());
        assert_eq!(mapped.items[0].artists.len(), 1);
        let debug = format!("{mapped:?} {:?}", mapped.items[0]);
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("private-artist"));
        assert!(!debug.contains("41001"));
        assert!(!debug.contains("private-album"));
        assert!(!debug.contains("43001"));
    }

    #[test]
    fn maps_provider_failures_precisely() {
        assert_eq!(
            map_error(SearchError::Network),
            QqMusicTrackSearchPageLoadFailure::Network
        );
        assert_eq!(
            map_error(SearchError::ServiceUnavailable),
            QqMusicTrackSearchPageLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_error(SearchError::InvalidResponse),
            QqMusicTrackSearchPageLoadFailure::InvalidResponse
        );
        assert_eq!(
            map_artist_error(SearchError::Network),
            QqMusicArtistSearchPageLoadFailure::Network
        );
        assert_eq!(
            map_artist_error(SearchError::ServiceUnavailable),
            QqMusicArtistSearchPageLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_artist_error(SearchError::InvalidResponse),
            QqMusicArtistSearchPageLoadFailure::InvalidResponse
        );
        assert_eq!(
            map_album_error(SearchError::Network),
            QqMusicAlbumSearchPageLoadFailure::Network
        );
        assert_eq!(
            map_album_error(SearchError::ServiceUnavailable),
            QqMusicAlbumSearchPageLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_album_error(SearchError::InvalidResponse),
            QqMusicAlbumSearchPageLoadFailure::InvalidResponse
        );
        assert_eq!(
            map_playlist_error(SearchError::Network),
            QqMusicPlaylistSearchPageLoadFailure::Network
        );
        assert_eq!(
            map_playlist_error(SearchError::ServiceUnavailable),
            QqMusicPlaylistSearchPageLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_playlist_error(SearchError::InvalidResponse),
            QqMusicPlaylistSearchPageLoadFailure::InvalidResponse
        );
    }

    #[test]
    fn maps_artist_search_page_without_exposing_content() {
        let artist = ArtistSummary::new(
            ArtistId::new(
                ProviderId::new("qq-music").expect("provider"),
                "artist:42001:fixtureArtistMid",
            )
            .expect("Artist ID"),
            "must-not-leak",
        )
        .expect("Artist summary")
        .with_artwork_uri(Some("https://example.invalid/artist.jpg".into()));
        let mapped = map_artist_load(Ok(ArtistSearchPage::new(1, 8, true, vec![artist])));

        assert_eq!(mapped.page, 1);
        assert_eq!(mapped.total, 8);
        assert!(mapped.has_more);
        assert_eq!(mapped.artists.len(), 1);
        assert_eq!(mapped.artists[0].provider_id, "qq-music");
        assert_eq!(mapped.artists[0].name, "must-not-leak");
        assert_eq!(
            mapped.artists[0].artwork_uri.as_deref(),
            Some("https://example.invalid/artist.jpg")
        );
        let debug = format!("{mapped:?} {:?}", mapped.artists[0]);
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("42001"));
        assert!(!debug.contains("example.invalid"));
    }

    #[test]
    fn maps_album_search_page_without_exposing_content() {
        let album = AlbumSummary::new(
            AlbumId::new(
                ProviderId::new("qq-music").expect("provider"),
                "album:43001:fixtureAlbumMid",
            )
            .expect("Album ID"),
            "must-not-leak",
        )
        .expect("Album summary");
        let mapped = map_album_load(Ok(AlbumSearchPage::new(1, 25, true, vec![album])));

        assert_eq!(mapped.page, 1);
        assert_eq!(mapped.total, 25);
        assert!(mapped.has_more);
        assert_eq!(mapped.albums.len(), 1);
        assert_eq!(mapped.albums[0].provider_id, "qq-music");
        assert_eq!(mapped.albums[0].title, "must-not-leak");
        let debug = format!("{mapped:?} {:?}", mapped.albums[0]);
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("43001"));
    }

    #[test]
    fn maps_playlist_search_page_without_exposing_content() {
        let playlist = PlaylistSummary::new(
            PlaylistId::new(
                ProviderId::new("qq-music").expect("provider"),
                "catalog:44001",
            )
            .expect("Playlist ID"),
            "must-not-leak",
        )
        .expect("Playlist summary")
        .with_track_count(Some(42));
        let mapped = map_playlist_load(Ok(PlaylistSearchPage::new(1, 25, true, vec![playlist])));

        assert_eq!(mapped.page, 1);
        assert_eq!(mapped.total, 25);
        assert!(mapped.has_more);
        assert_eq!(mapped.playlists.len(), 1);
        assert_eq!(mapped.playlists[0].provider_id, "qq-music");
        assert_eq!(mapped.playlists[0].title, "must-not-leak");
        let debug = format!("{mapped:?} {:?}", mapped.playlists[0]);
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("44001"));
    }

    #[tokio::test]
    async fn cancellation_is_exact_terminal_and_query_is_redacted() {
        let handle = begin_qq_music_track_search_page_load("private search query".into(), 1, 30);

        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let result = handle.run().await;
        assert_eq!(
            result.failure,
            Some(QqMusicTrackSearchPageLoadFailure::Cancelled)
        );
        assert!(!format!("{handle:?}").contains("private search query"));
    }

    #[tokio::test]
    async fn artist_cancellation_is_exact_terminal_and_query_is_redacted() {
        let handle = begin_qq_music_artist_search_page_load("private search query".into(), 1, 30);

        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let result = handle.run().await;
        assert_eq!(
            result.failure,
            Some(QqMusicArtistSearchPageLoadFailure::Cancelled)
        );
        assert!(!format!("{handle:?}").contains("private search query"));
    }

    #[tokio::test]
    async fn album_cancellation_is_exact_terminal_and_query_is_redacted() {
        let handle = begin_qq_music_album_search_page_load("private search query".into(), 1, 30);

        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let result = handle.run().await;
        assert_eq!(
            result.failure,
            Some(QqMusicAlbumSearchPageLoadFailure::Cancelled)
        );
        assert!(!format!("{handle:?}").contains("private search query"));
    }

    #[tokio::test]
    async fn playlist_cancellation_is_exact_terminal_and_query_is_redacted() {
        let handle = begin_qq_music_playlist_search_page_load("private search query".into(), 1, 30);

        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let result = handle.run().await;
        assert_eq!(
            result.failure,
            Some(QqMusicPlaylistSearchPageLoadFailure::Cancelled)
        );
        assert!(!format!("{handle:?}").contains("private search query"));
    }
}
