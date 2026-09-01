use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use provider_api::{ArtistAlbumsProvider, ArtistTracksProvider, CatalogError};
use tokio::sync::Notify;

use super::album::{CatalogAlbumSummary, bridge_album_summary};
use super::authentication::native_qq_music_provider;
use super::library::{LibraryTrackSummary, bridge_track_summary};

#[derive(Clone, Eq, PartialEq)]
pub struct CatalogArtistSummary {
    pub provider_id: String,
    pub opaque_id: String,
    pub name: String,
    pub artwork_uri: Option<String>,
}

impl fmt::Debug for CatalogArtistSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CatalogArtistSummary")
            .field("provider_id", &self.provider_id)
            .field("opaque_id", &"[REDACTED]")
            .field("name", &"[REDACTED]")
            .field("has_artwork", &self.artwork_uri.is_some())
            .finish()
    }
}

pub(super) fn bridge_artist_summary(artist: &music_domain::ArtistSummary) -> CatalogArtistSummary {
    CatalogArtistSummary {
        provider_id: artist.id().provider().to_string(),
        opaque_id: artist.id().opaque().to_owned(),
        name: artist.name().to_owned(),
        artwork_uri: artist.artwork_uri().map(str::to_owned),
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicArtistTrackPageLoadFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicArtistTrackPageLoad {
    pub offset: u32,
    pub total: u32,
    pub has_more: bool,
    pub tracks: Vec<LibraryTrackSummary>,
    pub failure: Option<QqMusicArtistTrackPageLoadFailure>,
}

impl fmt::Debug for QqMusicArtistTrackPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicArtistTrackPageLoad")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("track_count", &self.tracks.len())
            .field("failure", &self.failure)
            .finish()
    }
}

#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicArtistTrackPageLoadHandle {
    provider_id: String,
    opaque_artist_id: String,
    offset: u32,
    size: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicArtistTrackPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicArtistTrackPageLoadHandle")
            .field("provider_id", &self.provider_id)
            .field("opaque_artist_id", &"[REDACTED]")
            .field("offset", &self.offset)
            .field("size", &self.size)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicArtistTrackPageLoadHandle {
    pub async fn run(&self) -> QqMusicArtistTrackPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_load(QqMusicArtistTrackPageLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_load(QqMusicArtistTrackPageLoadFailure::AlreadyRunning);
        }
        let outcome = match artist_id(&self.provider_id, &self.opaque_artist_id) {
            Ok(artist_id) => match native_qq_music_provider() {
                Ok(provider) => {
                    tokio::select! {
                        () = self.cancelled.notified() => {
                            failed_load(QqMusicArtistTrackPageLoadFailure::Cancelled)
                        }
                        result = provider.artist_tracks(artist_id, self.offset, self.size) => {
                            if self.active.load(Ordering::SeqCst) {
                                map_load(result)
                            } else {
                                failed_load(QqMusicArtistTrackPageLoadFailure::Cancelled)
                            }
                        }
                    }
                }
                Err(()) => failed_load(QqMusicArtistTrackPageLoadFailure::CoreUnavailable),
            },
            Err(()) => failed_load(QqMusicArtistTrackPageLoadFailure::InvalidResponse),
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
pub fn begin_qq_music_artist_track_page_load(
    provider_id: String,
    opaque_artist_id: String,
    offset: u32,
    size: u32,
) -> QqMusicArtistTrackPageLoadHandle {
    QqMusicArtistTrackPageLoadHandle {
        provider_id,
        opaque_artist_id,
        offset,
        size,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn artist_id(provider_id: &str, opaque_id: &str) -> Result<music_domain::ArtistId, ()> {
    let provider = music_domain::ProviderId::new(provider_id).map_err(|_| ())?;
    music_domain::ArtistId::new(provider, opaque_id).map_err(|_| ())
}

fn map_load(
    result: Result<music_domain::ArtistTracksPage, CatalogError>,
) -> QqMusicArtistTrackPageLoad {
    match result {
        Ok(page) => QqMusicArtistTrackPageLoad {
            offset: page.offset(),
            total: page.total(),
            has_more: page.has_more(),
            tracks: page.tracks().iter().map(bridge_track_summary).collect(),
            failure: None,
        },
        Err(error) => failed_load(map_error(error)),
    }
}

const fn failed_load(failure: QqMusicArtistTrackPageLoadFailure) -> QqMusicArtistTrackPageLoad {
    QqMusicArtistTrackPageLoad {
        offset: 0,
        total: 0,
        has_more: false,
        tracks: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_error(error: CatalogError) -> QqMusicArtistTrackPageLoadFailure {
    match error {
        CatalogError::Network => QqMusicArtistTrackPageLoadFailure::Network,
        CatalogError::ServiceUnavailable => QqMusicArtistTrackPageLoadFailure::ServiceUnavailable,
        CatalogError::InvalidResponse => QqMusicArtistTrackPageLoadFailure::InvalidResponse,
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicArtistAlbumPageLoadFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicArtistAlbumPageLoad {
    pub offset: u32,
    pub total: u32,
    pub has_more: bool,
    pub albums: Vec<CatalogAlbumSummary>,
    pub failure: Option<QqMusicArtistAlbumPageLoadFailure>,
}

impl fmt::Debug for QqMusicArtistAlbumPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicArtistAlbumPageLoad")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("album_count", &self.albums.len())
            .field("failure", &self.failure)
            .finish()
    }
}

#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicArtistAlbumPageLoadHandle {
    provider_id: String,
    opaque_artist_id: String,
    offset: u32,
    size: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicArtistAlbumPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicArtistAlbumPageLoadHandle")
            .field("provider_id", &self.provider_id)
            .field("opaque_artist_id", &"[REDACTED]")
            .field("offset", &self.offset)
            .field("size", &self.size)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicArtistAlbumPageLoadHandle {
    pub async fn run(&self) -> QqMusicArtistAlbumPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_album_load(QqMusicArtistAlbumPageLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_album_load(QqMusicArtistAlbumPageLoadFailure::AlreadyRunning);
        }
        let outcome = match artist_id(&self.provider_id, &self.opaque_artist_id) {
            Ok(artist_id) => match native_qq_music_provider() {
                Ok(provider) => {
                    tokio::select! {
                        () = self.cancelled.notified() => {
                            failed_album_load(QqMusicArtistAlbumPageLoadFailure::Cancelled)
                        }
                        result = provider.artist_albums(artist_id, self.offset, self.size) => {
                            if self.active.load(Ordering::SeqCst) {
                                map_album_load(result)
                            } else {
                                failed_album_load(QqMusicArtistAlbumPageLoadFailure::Cancelled)
                            }
                        }
                    }
                }
                Err(()) => failed_album_load(QqMusicArtistAlbumPageLoadFailure::CoreUnavailable),
            },
            Err(()) => failed_album_load(QqMusicArtistAlbumPageLoadFailure::InvalidResponse),
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
pub fn begin_qq_music_artist_album_page_load(
    provider_id: String,
    opaque_artist_id: String,
    offset: u32,
    size: u32,
) -> QqMusicArtistAlbumPageLoadHandle {
    QqMusicArtistAlbumPageLoadHandle {
        provider_id,
        opaque_artist_id,
        offset,
        size,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_album_load(
    result: Result<music_domain::ArtistAlbumsPage, CatalogError>,
) -> QqMusicArtistAlbumPageLoad {
    match result {
        Ok(page) => QqMusicArtistAlbumPageLoad {
            offset: page.offset(),
            total: page.total(),
            has_more: page.has_more(),
            albums: page.albums().iter().map(bridge_album_summary).collect(),
            failure: None,
        },
        Err(error) => failed_album_load(map_album_error(error)),
    }
}

const fn failed_album_load(
    failure: QqMusicArtistAlbumPageLoadFailure,
) -> QqMusicArtistAlbumPageLoad {
    QqMusicArtistAlbumPageLoad {
        offset: 0,
        total: 0,
        has_more: false,
        albums: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_album_error(error: CatalogError) -> QqMusicArtistAlbumPageLoadFailure {
    match error {
        CatalogError::Network => QqMusicArtistAlbumPageLoadFailure::Network,
        CatalogError::ServiceUnavailable => QqMusicArtistAlbumPageLoadFailure::ServiceUnavailable,
        CatalogError::InvalidResponse => QqMusicArtistAlbumPageLoadFailure::InvalidResponse,
    }
}

#[cfg(test)]
mod tests {
    use music_domain::{
        AlbumId, AlbumSummary, ArtistAlbumsPage, ArtistTracksPage, ProviderId, TrackId,
        TrackSummary,
    };
    use provider_api::CatalogError;

    use super::{
        QqMusicArtistAlbumPageLoadFailure, QqMusicArtistTrackPageLoadFailure,
        begin_qq_music_artist_album_page_load, begin_qq_music_artist_track_page_load,
        map_album_error, map_album_load, map_error, map_load,
    };

    #[test]
    fn maps_artist_page_without_exposing_identity_or_content() {
        let track = TrackSummary::new(
            TrackId::new(
                ProviderId::new("qq-music").expect("provider"),
                "track:41001:0:fixtureMid:-",
            )
            .expect("Track ID"),
            "must-not-leak",
            vec!["private-artist".into()],
        )
        .expect("Track summary");
        let mapped = map_load(Ok(ArtistTracksPage::new(0, 31, true, vec![track])));

        assert_eq!(mapped.offset, 0);
        assert_eq!(mapped.total, 31);
        assert!(mapped.has_more);
        assert_eq!(mapped.tracks.len(), 1);
        let debug = format!("{mapped:?} {:?}", mapped.tracks[0]);
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("private-artist"));
        assert!(!debug.contains("41001"));
    }

    #[test]
    fn maps_catalog_failures_precisely() {
        assert_eq!(
            map_error(CatalogError::Network),
            QqMusicArtistTrackPageLoadFailure::Network
        );
        assert_eq!(
            map_error(CatalogError::ServiceUnavailable),
            QqMusicArtistTrackPageLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_error(CatalogError::InvalidResponse),
            QqMusicArtistTrackPageLoadFailure::InvalidResponse
        );
        assert_eq!(
            map_album_error(CatalogError::Network),
            QqMusicArtistAlbumPageLoadFailure::Network
        );
        assert_eq!(
            map_album_error(CatalogError::ServiceUnavailable),
            QqMusicArtistAlbumPageLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_album_error(CatalogError::InvalidResponse),
            QqMusicArtistAlbumPageLoadFailure::InvalidResponse
        );
    }

    #[test]
    fn maps_artist_album_page_without_exposing_identity_or_content() {
        let album = AlbumSummary::new(
            AlbumId::new(
                ProviderId::new("qq-music").expect("provider"),
                "album:43001:privateAlbumMid",
            )
            .expect("Album ID"),
            "must-not-leak",
        )
        .expect("Album summary");
        let mapped = map_album_load(Ok(ArtistAlbumsPage::new(0, 31, true, vec![album])));

        assert_eq!(mapped.offset, 0);
        assert_eq!(mapped.total, 31);
        assert!(mapped.has_more);
        assert_eq!(mapped.albums.len(), 1);
        let debug = format!("{mapped:?} {:?}", mapped.albums[0]);
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("privateAlbumMid"));
        assert!(!debug.contains("43001"));
    }

    #[tokio::test]
    async fn cancellation_is_exact_terminal_and_identity_is_redacted() {
        let handle = begin_qq_music_artist_track_page_load(
            "qq-music".into(),
            "artist:42001:privateArtistMid".into(),
            0,
            30,
        );
        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let result = handle.run().await;
        assert_eq!(
            result.failure,
            Some(QqMusicArtistTrackPageLoadFailure::Cancelled)
        );
        assert!(!format!("{handle:?}").contains("privateArtistMid"));

        let album_handle = begin_qq_music_artist_album_page_load(
            "qq-music".into(),
            "artist:42001:privateArtistMid".into(),
            0,
            30,
        );
        assert!(album_handle.is_active());
        assert!(album_handle.cancel());
        assert!(!album_handle.cancel());
        let album_result = album_handle.run().await;
        assert_eq!(
            album_result.failure,
            Some(QqMusicArtistAlbumPageLoadFailure::Cancelled)
        );
        assert!(!format!("{album_handle:?}").contains("privateArtistMid"));
    }
}
