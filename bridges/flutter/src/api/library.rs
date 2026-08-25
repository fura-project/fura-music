use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use provider_api::{PlaylistDetailsProvider, UserLibraryError, UserPlaylistsProvider};
use tokio::sync::Notify;

use super::authentication::native_qq_music_provider;

#[derive(Clone, Eq, PartialEq)]
pub struct LibraryPlaylistSummary {
    pub provider_id: String,
    pub opaque_id: String,
    pub title: String,
    pub artwork_uri: Option<String>,
    pub track_count: Option<u32>,
}

impl fmt::Debug for LibraryPlaylistSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("LibraryPlaylistSummary")
            .field("provider_id", &self.provider_id)
            .field("opaque_id", &"[REDACTED]")
            .field("title", &"[REDACTED]")
            .field("has_artwork", &self.artwork_uri.is_some())
            .field("track_count", &self.track_count)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicUserPlaylistLoadFailure {
    CoreUnavailable,
    AuthenticationRequired,
    CredentialRejected,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Replaced,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicUserPlaylistLoad {
    pub playlists: Vec<LibraryPlaylistSummary>,
    pub failure: Option<QqMusicUserPlaylistLoadFailure>,
}

impl fmt::Debug for QqMusicUserPlaylistLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicUserPlaylistLoad")
            .field("playlist_count", &self.playlists.len())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use user-library load. The handle contains no
/// credential or QQ Music protocol identifier.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicUserPlaylistLoadHandle {
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicUserPlaylistLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicUserPlaylistLoadHandle")
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicUserPlaylistLoadHandle {
    pub async fn run(&self) -> QqMusicUserPlaylistLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_load(QqMusicUserPlaylistLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_load(QqMusicUserPlaylistLoadFailure::AlreadyRunning);
        }

        let outcome = match native_qq_music_provider() {
            Ok(provider) => {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_load(QqMusicUserPlaylistLoadFailure::Cancelled)
                    }
                    result = provider.user_playlists() => {
                        if self.active.load(Ordering::SeqCst) {
                            map_load(result)
                        } else {
                            failed_load(QqMusicUserPlaylistLoadFailure::Cancelled)
                        }
                    }
                }
            }
            Err(()) => failed_load(QqMusicUserPlaylistLoadFailure::CoreUnavailable),
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
pub fn begin_qq_music_user_playlist_load() -> QqMusicUserPlaylistLoadHandle {
    QqMusicUserPlaylistLoadHandle {
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_load(
    result: Result<Vec<music_domain::PlaylistSummary>, UserLibraryError>,
) -> QqMusicUserPlaylistLoad {
    match result {
        Ok(playlists) => QqMusicUserPlaylistLoad {
            playlists: playlists
                .into_iter()
                .map(|playlist| LibraryPlaylistSummary {
                    provider_id: playlist.id().provider().to_string(),
                    opaque_id: playlist.id().opaque().to_owned(),
                    title: playlist.title().to_owned(),
                    artwork_uri: playlist.artwork_uri().map(str::to_owned),
                    track_count: playlist.track_count(),
                })
                .collect(),
            failure: None,
        },
        Err(error) => failed_load(map_error(error)),
    }
}

const fn failed_load(failure: QqMusicUserPlaylistLoadFailure) -> QqMusicUserPlaylistLoad {
    QqMusicUserPlaylistLoad {
        playlists: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_error(error: UserLibraryError) -> QqMusicUserPlaylistLoadFailure {
    match error {
        UserLibraryError::AuthenticationRequired => {
            QqMusicUserPlaylistLoadFailure::AuthenticationRequired
        }
        UserLibraryError::CredentialRejected => QqMusicUserPlaylistLoadFailure::CredentialRejected,
        UserLibraryError::Network => QqMusicUserPlaylistLoadFailure::Network,
        UserLibraryError::ServiceUnavailable => QqMusicUserPlaylistLoadFailure::ServiceUnavailable,
        UserLibraryError::InvalidResponse => QqMusicUserPlaylistLoadFailure::InvalidResponse,
        UserLibraryError::Replaced => QqMusicUserPlaylistLoadFailure::Replaced,
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct LibraryTrackSummary {
    pub provider_id: String,
    pub opaque_id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub artist_names: Vec<String>,
    pub album_title: Option<String>,
    pub artwork_uri: Option<String>,
    pub duration_seconds: Option<u32>,
}

impl fmt::Debug for LibraryTrackSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("LibraryTrackSummary")
            .field("provider_id", &self.provider_id)
            .field("opaque_id", &"[REDACTED]")
            .field("title", &"[REDACTED]")
            .field("has_subtitle", &self.subtitle.is_some())
            .field("artist_count", &self.artist_names.len())
            .field("has_album_title", &self.album_title.is_some())
            .field("has_artwork", &self.artwork_uri.is_some())
            .field("duration_seconds", &self.duration_seconds)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicPlaylistTrackPageLoadFailure {
    CoreUnavailable,
    AuthenticationRequired,
    CredentialRejected,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Replaced,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicPlaylistTrackPageLoad {
    pub offset: u32,
    pub total: u32,
    pub has_more: bool,
    pub tracks: Vec<LibraryTrackSummary>,
    pub failure: Option<QqMusicPlaylistTrackPageLoadFailure>,
}

impl fmt::Debug for QqMusicPlaylistTrackPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicPlaylistTrackPageLoad")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("track_count", &self.tracks.len())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use playlist-track page load. Provider identity is
/// carried for routing but remains opaque to this Bridge lifecycle.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicPlaylistTrackPageLoadHandle {
    provider_id: String,
    opaque_playlist_id: String,
    offset: u32,
    size: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicPlaylistTrackPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicPlaylistTrackPageLoadHandle")
            .field("provider_id", &self.provider_id)
            .field("opaque_playlist_id", &"[REDACTED]")
            .field("offset", &self.offset)
            .field("size", &self.size)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicPlaylistTrackPageLoadHandle {
    pub async fn run(&self) -> QqMusicPlaylistTrackPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_track_page(QqMusicPlaylistTrackPageLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_track_page(QqMusicPlaylistTrackPageLoadFailure::AlreadyRunning);
        }

        let outcome = match domain_playlist_id(&self.provider_id, &self.opaque_playlist_id) {
            Ok(playlist_id) => match native_qq_music_provider() {
                Ok(provider) => {
                    tokio::select! {
                        () = self.cancelled.notified() => {
                            failed_track_page(QqMusicPlaylistTrackPageLoadFailure::Cancelled)
                        }
                        result = provider.playlist_tracks_page(playlist_id, self.offset, self.size) => {
                            if self.active.load(Ordering::SeqCst) {
                                map_track_page_load(result)
                            } else {
                                failed_track_page(QqMusicPlaylistTrackPageLoadFailure::Cancelled)
                            }
                        }
                    }
                }
                Err(()) => failed_track_page(QqMusicPlaylistTrackPageLoadFailure::CoreUnavailable),
            },
            Err(()) => failed_track_page(QqMusicPlaylistTrackPageLoadFailure::InvalidResponse),
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
pub fn begin_qq_music_playlist_track_page_load(
    provider_id: String,
    opaque_playlist_id: String,
    offset: u32,
    size: u32,
) -> QqMusicPlaylistTrackPageLoadHandle {
    QqMusicPlaylistTrackPageLoadHandle {
        provider_id,
        opaque_playlist_id,
        offset,
        size,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn domain_playlist_id(
    provider_id: &str,
    opaque_playlist_id: &str,
) -> Result<music_domain::PlaylistId, ()> {
    let provider = music_domain::ProviderId::new(provider_id).map_err(|_| ())?;
    music_domain::PlaylistId::new(provider, opaque_playlist_id).map_err(|_| ())
}

fn map_track_page_load(
    result: Result<music_domain::PlaylistTracksPage, UserLibraryError>,
) -> QqMusicPlaylistTrackPageLoad {
    match result {
        Ok(page) => QqMusicPlaylistTrackPageLoad {
            offset: page.offset(),
            total: page.total(),
            has_more: page.has_more(),
            tracks: page
                .tracks()
                .iter()
                .map(|track| LibraryTrackSummary {
                    provider_id: track.id().provider().to_string(),
                    opaque_id: track.id().opaque().to_owned(),
                    title: track.title().to_owned(),
                    subtitle: track.subtitle().map(str::to_owned),
                    artist_names: track.artist_names().to_vec(),
                    album_title: track.album_title().map(str::to_owned),
                    artwork_uri: track.artwork_uri().map(str::to_owned),
                    duration_seconds: track.duration_seconds(),
                })
                .collect(),
            failure: None,
        },
        Err(error) => failed_track_page(map_track_page_error(error)),
    }
}

const fn failed_track_page(
    failure: QqMusicPlaylistTrackPageLoadFailure,
) -> QqMusicPlaylistTrackPageLoad {
    QqMusicPlaylistTrackPageLoad {
        offset: 0,
        total: 0,
        has_more: false,
        tracks: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_track_page_error(error: UserLibraryError) -> QqMusicPlaylistTrackPageLoadFailure {
    match error {
        UserLibraryError::AuthenticationRequired => {
            QqMusicPlaylistTrackPageLoadFailure::AuthenticationRequired
        }
        UserLibraryError::CredentialRejected => {
            QqMusicPlaylistTrackPageLoadFailure::CredentialRejected
        }
        UserLibraryError::Network => QqMusicPlaylistTrackPageLoadFailure::Network,
        UserLibraryError::ServiceUnavailable => {
            QqMusicPlaylistTrackPageLoadFailure::ServiceUnavailable
        }
        UserLibraryError::InvalidResponse => QqMusicPlaylistTrackPageLoadFailure::InvalidResponse,
        UserLibraryError::Replaced => QqMusicPlaylistTrackPageLoadFailure::Replaced,
    }
}

#[cfg(test)]
mod tests {
    use music_domain::{
        PlaylistId, PlaylistSummary, PlaylistTracksPage, ProviderId, TrackId, TrackSummary,
    };
    use provider_api::UserLibraryError;

    use super::{
        QqMusicPlaylistTrackPageLoadFailure, QqMusicUserPlaylistLoadFailure,
        begin_qq_music_playlist_track_page_load, begin_qq_music_user_playlist_load, map_error,
        map_load, map_track_page_error, map_track_page_load,
    };

    #[test]
    fn maps_domain_summaries_without_exposing_them_in_diagnostics() {
        let id = PlaylistId::new(
            ProviderId::new("qq-music").expect("provider"),
            "owned:7001:201",
        )
        .expect("playlist ID");
        let summary = PlaylistSummary::new(id, "must-not-leak")
            .expect("summary")
            .with_track_count(Some(42));
        let favorite_id = PlaylistId::new(
            ProviderId::new("qq-music").expect("provider"),
            "favorite:8001",
        )
        .expect("favorite playlist ID");
        let favorite =
            PlaylistSummary::new(favorite_id, "favorite-must-not-leak").expect("favorite summary");

        let mapped = map_load(Ok(vec![summary, favorite]));

        assert_eq!(mapped.playlists.len(), 2);
        assert_eq!(mapped.playlists[0].provider_id, "qq-music");
        assert_eq!(mapped.playlists[0].opaque_id, "owned:7001:201");
        assert_eq!(mapped.playlists[0].title, "must-not-leak");
        assert_eq!(mapped.playlists[1].opaque_id, "favorite:8001");
        assert_eq!(mapped.playlists[1].title, "favorite-must-not-leak");
        assert!(!format!("{mapped:?}").contains("must-not-leak"));
        assert!(!format!("{:?}", mapped.playlists[0]).contains("7001"));
        assert!(!format!("{:?}", mapped.playlists[1]).contains("8001"));
    }

    #[test]
    fn maps_each_provider_failure_precisely() {
        assert_eq!(
            map_error(UserLibraryError::CredentialRejected),
            QqMusicUserPlaylistLoadFailure::CredentialRejected
        );
        assert_eq!(
            map_error(UserLibraryError::ServiceUnavailable),
            QqMusicUserPlaylistLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_error(UserLibraryError::Replaced),
            QqMusicUserPlaylistLoadFailure::Replaced
        );
    }

    #[tokio::test]
    async fn cancellation_is_exact_and_terminal() {
        let handle = begin_qq_music_user_playlist_load();

        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let outcome = handle.run().await;
        assert_eq!(
            outcome.failure,
            Some(QqMusicUserPlaylistLoadFailure::Cancelled)
        );
    }

    #[test]
    fn maps_track_pages_without_parsing_opaque_identity_or_logging_content() {
        let track_id = TrackId::new(
            ProviderId::new("qq-music").expect("provider"),
            "track:41001:0:1:opaque-mid",
        )
        .expect("track ID");
        let track = TrackSummary::new(track_id, "must-not-leak", vec!["private-artist".into()])
            .expect("track summary")
            .with_album_title(Some("private-album".into()))
            .with_duration_seconds(Some(245));

        let mapped = map_track_page_load(Ok(PlaylistTracksPage::new(100, 101, true, vec![track])));

        assert_eq!(mapped.offset, 100);
        assert_eq!(mapped.total, 101);
        assert!(mapped.has_more);
        assert_eq!(mapped.tracks.len(), 1);
        assert_eq!(mapped.tracks[0].provider_id, "qq-music");
        assert_eq!(mapped.tracks[0].opaque_id, "track:41001:0:1:opaque-mid");
        assert_eq!(mapped.tracks[0].title, "must-not-leak");
        assert_eq!(mapped.tracks[0].artist_names, ["private-artist"]);
        let debug = format!("{mapped:?} {:?}", mapped.tracks[0]);
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("41001"));
        assert!(!debug.contains("private-artist"));
    }

    #[test]
    fn maps_track_page_failures_precisely() {
        assert_eq!(
            map_track_page_error(UserLibraryError::CredentialRejected),
            QqMusicPlaylistTrackPageLoadFailure::CredentialRejected
        );
        assert_eq!(
            map_track_page_error(UserLibraryError::ServiceUnavailable),
            QqMusicPlaylistTrackPageLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_track_page_error(UserLibraryError::Replaced),
            QqMusicPlaylistTrackPageLoadFailure::Replaced
        );
    }

    #[tokio::test]
    async fn track_page_cancellation_is_exact_and_terminal() {
        let handle = begin_qq_music_playlist_track_page_load(
            "qq-music".into(),
            "favorite:8001".into(),
            0,
            100,
        );

        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let outcome = handle.run().await;
        assert_eq!(
            outcome.failure,
            Some(QqMusicPlaylistTrackPageLoadFailure::Cancelled)
        );
        assert!(!format!("{handle:?}").contains("8001"));
    }
}
