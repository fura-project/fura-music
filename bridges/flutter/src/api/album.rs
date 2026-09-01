use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use provider_api::{AlbumDetailsProvider, AlbumTracksProvider, CatalogError};
use tokio::sync::Notify;

use super::artist::{CatalogArtistSummary, bridge_artist_summary};
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

#[derive(Clone, Eq, PartialEq)]
pub struct CatalogAlbumDetails {
    pub album: CatalogAlbumSummary,
    pub artists: Vec<CatalogArtistSummary>,
    pub subtitle: Option<String>,
    pub release_date: Option<String>,
    pub description: Option<String>,
    pub language: Option<String>,
    pub album_type: Option<String>,
    pub genre: Option<String>,
    pub company: Option<String>,
}

impl fmt::Debug for CatalogAlbumDetails {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CatalogAlbumDetails")
            .field("album", &self.album)
            .field("artist_count", &self.artists.len())
            .field("has_subtitle", &self.subtitle.is_some())
            .field("has_release_date", &self.release_date.is_some())
            .field("has_description", &self.description.is_some())
            .field("has_language", &self.language.is_some())
            .field("has_album_type", &self.album_type.is_some())
            .field("has_genre", &self.genre.is_some())
            .field("has_company", &self.company.is_some())
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicAlbumDetailsLoadFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicAlbumDetailsLoad {
    pub details: Option<CatalogAlbumDetails>,
    pub failure: Option<QqMusicAlbumDetailsLoadFailure>,
}

impl fmt::Debug for QqMusicAlbumDetailsLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicAlbumDetailsLoad")
            .field("has_details", &self.details.is_some())
            .field("failure", &self.failure)
            .finish()
    }
}

#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicAlbumDetailsLoadHandle {
    provider_id: String,
    opaque_album_id: String,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicAlbumDetailsLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicAlbumDetailsLoadHandle")
            .field("provider_id", &self.provider_id)
            .field("opaque_album_id", &"[REDACTED]")
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicAlbumDetailsLoadHandle {
    pub async fn run(&self) -> QqMusicAlbumDetailsLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_details_load(QqMusicAlbumDetailsLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_details_load(QqMusicAlbumDetailsLoadFailure::AlreadyRunning);
        }
        let outcome = match album_id(&self.provider_id, &self.opaque_album_id) {
            Ok(album_id) => match native_qq_music_provider() {
                Ok(provider) => {
                    tokio::select! {
                        () = self.cancelled.notified() => {
                            failed_details_load(QqMusicAlbumDetailsLoadFailure::Cancelled)
                        }
                        result = provider.album_details(album_id) => {
                            if self.active.load(Ordering::SeqCst) {
                                map_details_load(result)
                            } else {
                                failed_details_load(QqMusicAlbumDetailsLoadFailure::Cancelled)
                            }
                        }
                    }
                }
                Err(()) => failed_details_load(QqMusicAlbumDetailsLoadFailure::CoreUnavailable),
            },
            Err(()) => failed_details_load(QqMusicAlbumDetailsLoadFailure::InvalidResponse),
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
pub fn begin_qq_music_album_details_load(
    provider_id: String,
    opaque_album_id: String,
) -> QqMusicAlbumDetailsLoadHandle {
    QqMusicAlbumDetailsLoadHandle {
        provider_id,
        opaque_album_id,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
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

fn map_details_load(
    result: Result<music_domain::AlbumDetails, CatalogError>,
) -> QqMusicAlbumDetailsLoad {
    match result {
        Ok(details) => QqMusicAlbumDetailsLoad {
            details: Some(CatalogAlbumDetails {
                album: bridge_album_summary(details.album()),
                artists: details
                    .artists()
                    .iter()
                    .map(bridge_artist_summary)
                    .collect(),
                subtitle: details.subtitle().map(str::to_owned),
                release_date: details.release_date().map(str::to_owned),
                description: details.description().map(str::to_owned),
                language: details.language().map(str::to_owned),
                album_type: details.album_type().map(str::to_owned),
                genre: details.genre().map(str::to_owned),
                company: details.company().map(str::to_owned),
            }),
            failure: None,
        },
        Err(error) => failed_details_load(map_details_error(error)),
    }
}

const fn failed_details_load(failure: QqMusicAlbumDetailsLoadFailure) -> QqMusicAlbumDetailsLoad {
    QqMusicAlbumDetailsLoad {
        details: None,
        failure: Some(failure),
    }
}

const fn map_details_error(error: CatalogError) -> QqMusicAlbumDetailsLoadFailure {
    match error {
        CatalogError::Network => QqMusicAlbumDetailsLoadFailure::Network,
        CatalogError::ServiceUnavailable => QqMusicAlbumDetailsLoadFailure::ServiceUnavailable,
        CatalogError::InvalidResponse => QqMusicAlbumDetailsLoadFailure::InvalidResponse,
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
    use music_domain::{
        AlbumDetails, AlbumId, AlbumSummary, AlbumTracksPage, ArtistId, ArtistSummary, ProviderId,
        TrackId, TrackSummary,
    };
    use provider_api::CatalogError;

    use super::{
        QqMusicAlbumDetailsLoadFailure, QqMusicAlbumTrackPageLoadFailure,
        begin_qq_music_album_details_load, begin_qq_music_album_track_page_load, map_details_error,
        map_details_load, map_error, map_load,
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
        assert_eq!(
            map_details_error(CatalogError::Network),
            QqMusicAlbumDetailsLoadFailure::Network
        );
        assert_eq!(
            map_details_error(CatalogError::ServiceUnavailable),
            QqMusicAlbumDetailsLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_details_error(CatalogError::InvalidResponse),
            QqMusicAlbumDetailsLoadFailure::InvalidResponse
        );
    }

    #[test]
    fn maps_album_details_without_exposing_identity_or_content() {
        let provider = ProviderId::new("qq-music").expect("provider");
        let album = AlbumSummary::new(
            AlbumId::new(provider.clone(), "album:43001:privateAlbumMid").expect("Album ID"),
            "must-not-leak-album",
        )
        .expect("Album");
        let artist = ArtistSummary::new(
            ArtistId::new(provider, "artist:42001:privateArtistMid").expect("Artist ID"),
            "must-not-leak-artist",
        )
        .expect("Artist")
        .with_artwork_uri(Some("https://example.invalid/artist.jpg".into()));
        let mapped = map_details_load(Ok(AlbumDetails::new(album, vec![artist])
            .with_subtitle(Some("private-subtitle".into()))
            .with_release_date(Some("2026-08-26".into()))
            .with_description(Some("private-description".into()))
            .with_company(Some("private-company".into()))));

        assert!(mapped.failure.is_none());
        let details = mapped.details.as_ref().expect("details");
        assert_eq!(details.artists.len(), 1);
        assert_eq!(
            details.artists[0].artwork_uri.as_deref(),
            Some("https://example.invalid/artist.jpg")
        );
        assert_eq!(details.subtitle.as_deref(), Some("private-subtitle"));
        assert_eq!(details.description.as_deref(), Some("private-description"));
        let debug = format!("{mapped:?} {details:?}");
        for private in [
            "must-not-leak",
            "private-",
            "privateAlbumMid",
            "2026-08-26",
            "43001",
            "42001",
            "example.invalid",
        ] {
            assert!(!debug.contains(private));
        }
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

        let details_handle = begin_qq_music_album_details_load(
            "qq-music".into(),
            "album:43001:privateAlbumMid".into(),
        );
        assert!(details_handle.cancel());
        let result = details_handle.run().await;
        assert_eq!(
            result.failure,
            Some(QqMusicAlbumDetailsLoadFailure::Cancelled)
        );
        assert!(!format!("{details_handle:?}").contains("privateAlbumMid"));
    }
}
