use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use provider_api::{UserLibraryError, UserPlaylistsProvider};
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

#[cfg(test)]
mod tests {
    use music_domain::{PlaylistId, PlaylistSummary, ProviderId};
    use provider_api::UserLibraryError;

    use super::{
        QqMusicUserPlaylistLoadFailure, begin_qq_music_user_playlist_load, map_error, map_load,
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
}
