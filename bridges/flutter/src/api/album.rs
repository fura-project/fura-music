use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use provider_api::{AlbumTracksProvider, CatalogError};
use tokio::sync::Notify;

use super::authentication::native_qq_music_provider;
use super::library::{LibraryTrackSummary, bridge_track_summary};

#[derive(Clone, Eq, PartialEq)]
pub struct CatalogAlbumSummary {
    pub provider_id: String,
    pub opaque_id: String,
    pub title: String,
    pub artwork_uri: Option<String>,
}

impl fmt::Debug for CatalogAlbumSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CatalogAlbumSummary")
            .field("provider_id", &self.provider_id)
            .field("opaque_id", &"[REDACTED]")
            .field("title", &"[REDACTED]")
            .field("has_artwork", &self.artwork_uri.is_some())
            .finish()
    }
}

pub(super) fn bridge_album_summary(album: &music_domain::AlbumSummary) -> CatalogAlbumSummary {
    CatalogAlbumSummary {
        provider_id: album.id().provider().to_string(),
        opaque_id: album.id().opaque().to_owned(),
        title: album.title().to_owned(),
        artwork_uri: album.artwork_uri().map(str::to_owned),
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicAlbumTrackPageLoadFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicAlbumTrackPageLoad {
    pub offset: u32,
    pub total: u32,
    pub has_more: bool,
    pub tracks: Vec<LibraryTrackSummary>,
    pub failure: Option<QqMusicAlbumTrackPageLoadFailure>,
}

impl fmt::Debug for QqMusicAlbumTrackPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicAlbumTrackPageLoad")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("track_count", &self.tracks.len())
            .field("failure", &self.failure)
            .finish()
    }
}

#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicAlbumTrackPageLoadHandle {
    provider_id: String,
    opaque_album_id: String,
    offset: u32,
    size: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicAlbumTrackPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicAlbumTrackPageLoadHandle")
            .field("provider_id", &self.provider_id)
            .field("opaque_album_id", &"[REDACTED]")
            .field("offset", &self.offset)
            .field("size", &self.size)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicAlbumTrackPageLoadHandle {
    pub async fn run(&self) -> QqMusicAlbumTrackPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_load(QqMusicAlbumTrackPageLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_load(QqMusicAlbumTrackPageLoadFailure::AlreadyRunning);
        }
        let outcome = match album_id(&self.provider_id, &self.opaque_album_id) {
            Ok(album_id) => match native_qq_music_provider() {
                Ok(provider) => {
                    tokio::select! {
                        () = self.cancelled.notified() => {
                            failed_load(QqMusicAlbumTrackPageLoadFailure::Cancelled)
                        }
                        result = provider.album_tracks(album_id, self.offset, self.size) => {
                            if self.active.load(Ordering::SeqCst) {
                                map_load(result)
                            } else {
                                failed_load(QqMusicAlbumTrackPageLoadFailure::Cancelled)
                            }
                        }
                    }
                }
                Err(()) => failed_load(QqMusicAlbumTrackPageLoadFailure::CoreUnavailable),
            },
            Err(()) => failed_load(QqMusicAlbumTrackPageLoadFailure::InvalidResponse),
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
pub fn begin_qq_music_album_track_page_load(
    provider_id: String,
    opaque_album_id: String,
    offset: u32,
    size: u32,
) -> QqMusicAlbumTrackPageLoadHandle {
    QqMusicAlbumTrackPageLoadHandle {
        provider_id,
        opaque_album_id,
        offset,
        size,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn album_id(provider_id: &str, opaque_id: &str) -> Result<music_domain::AlbumId, ()> {
    let provider = music_domain::ProviderId::new(provider_id).map_err(|_| ())?;
    music_domain::AlbumId::new(provider, opaque_id).map_err(|_| ())
}

fn map_load(
    result: Result<music_domain::AlbumTracksPage, CatalogError>,
) -> QqMusicAlbumTrackPageLoad {
    match result {
        Ok(page) => QqMusicAlbumTrackPageLoad {
            offset: page.offset(),
            total: page.total(),
            has_more: page.has_more(),
            tracks: page.tracks().iter().map(bridge_track_summary).collect(),
            failure: None,
        },
        Err(error) => failed_load(map_error(error)),
    }
}

const fn failed_load(failure: QqMusicAlbumTrackPageLoadFailure) -> QqMusicAlbumTrackPageLoad {
    QqMusicAlbumTrackPageLoad {
        offset: 0,
        total: 0,
        has_more: false,
        tracks: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_error(error: CatalogError) -> QqMusicAlbumTrackPageLoadFailure {
    match error {
        CatalogError::Network => QqMusicAlbumTrackPageLoadFailure::Network,
        CatalogError::ServiceUnavailable => QqMusicAlbumTrackPageLoadFailure::ServiceUnavailable,
        CatalogError::InvalidResponse => QqMusicAlbumTrackPageLoadFailure::InvalidResponse,
    }
}

#[cfg(test)]
mod tests {
    use music_domain::{AlbumTracksPage, ProviderId, TrackId, TrackSummary};
    use provider_api::CatalogError;

    use super::{
        QqMusicAlbumTrackPageLoadFailure, begin_qq_music_album_track_page_load, map_error, map_load,
    };

    #[test]
    fn maps_album_page_without_exposing_identity_or_content() {
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
        let mapped = map_load(Ok(AlbumTracksPage::new(0, 31, true, vec![track])));

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
            QqMusicAlbumTrackPageLoadFailure::Network
        );
        assert_eq!(
            map_error(CatalogError::ServiceUnavailable),
            QqMusicAlbumTrackPageLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_error(CatalogError::InvalidResponse),
            QqMusicAlbumTrackPageLoadFailure::InvalidResponse
        );
    }

    #[tokio::test]
    async fn cancellation_is_exact_terminal_and_identity_is_redacted() {
        let handle = begin_qq_music_album_track_page_load(
            "qq-music".into(),
            "album:43001:privateAlbumMid".into(),
            0,
            30,
        );
        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let result = handle.run().await;
        assert_eq!(
            result.failure,
            Some(QqMusicAlbumTrackPageLoadFailure::Cancelled)
        );
        assert!(!format!("{handle:?}").contains("privateAlbumMid"));
    }
}
