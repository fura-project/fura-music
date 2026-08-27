use std::fmt;

use provider_api::{LibraryMutationError, PlaylistCreationProvider};

use super::authentication::native_qq_music_provider;
use super::library::{LibraryPlaylistSummary, bridge_playlist_summary};
use super::remote_mutation::{RemoteMutationLifecycle, RemoteMutationStart};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicPlaylistCreationFailure {
    CoreUnavailable,
    AuthenticationRequired,
    CredentialRejected,
    NetworkOutcomeUnknown,
    ServiceUnavailable,
    InvalidRequest,
    InvalidResponseOutcomeUnknown,
    ReplacedOutcomeUnknown,
    /// Cancelling the local wait cannot recall a create request already sent
    /// to QQ Music, so presentation must refresh instead of assuming failure.
    CancelledOutcomeUnknown,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicPlaylistCreationResult {
    pub created_playlist: Option<LibraryPlaylistSummary>,
    pub failure: Option<QqMusicPlaylistCreationFailure>,
}

impl fmt::Debug for QqMusicPlaylistCreationResult {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicPlaylistCreationResult")
            .field("has_created_playlist", &self.created_playlist.is_some())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use playlist creation. The requested name is
/// redacted from diagnostics and remains inside the Provider call boundary.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicPlaylistCreationHandle {
    name: String,
    lifecycle: RemoteMutationLifecycle,
}

impl fmt::Debug for QqMusicPlaylistCreationHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicPlaylistCreationHandle")
            .field("name", &"[REDACTED]")
            .field("active", &self.is_active())
            .field("running", &self.lifecycle.is_running())
            .finish()
    }
}

impl QqMusicPlaylistCreationHandle {
    pub async fn run(&self) -> QqMusicPlaylistCreationResult {
        match self.lifecycle.try_start() {
            RemoteMutationStart::Started => {}
            RemoteMutationStart::Cancelled => {
                return failed_creation(QqMusicPlaylistCreationFailure::CancelledOutcomeUnknown);
            }
            RemoteMutationStart::AlreadyRunning => {
                return failed_creation(QqMusicPlaylistCreationFailure::AlreadyRunning);
            }
        }
        let outcome = match native_qq_music_provider() {
            Ok(provider) => {
                tokio::select! {
                    () = self.lifecycle.cancelled() => {
                        failed_creation(
                            QqMusicPlaylistCreationFailure::CancelledOutcomeUnknown,
                        )
                    }
                    result = provider.create_playlist(self.name.clone()) => {
                        if self.lifecycle.is_active() {
                            map_creation(result)
                        } else {
                            failed_creation(
                                QqMusicPlaylistCreationFailure::CancelledOutcomeUnknown,
                            )
                        }
                    }
                }
            }
            Err(()) => failed_creation(QqMusicPlaylistCreationFailure::CoreUnavailable),
        };
        self.lifecycle.finish();
        outcome
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) -> bool {
        self.lifecycle.cancel()
    }

    #[flutter_rust_bridge::frb(sync, getter)]
    pub fn is_active(&self) -> bool {
        self.lifecycle.is_active()
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn begin_qq_music_playlist_creation(name: String) -> QqMusicPlaylistCreationHandle {
    QqMusicPlaylistCreationHandle {
        name,
        lifecycle: RemoteMutationLifecycle::new(),
    }
}

fn map_creation(
    result: Result<music_domain::PlaylistSummary, LibraryMutationError>,
) -> QqMusicPlaylistCreationResult {
    match result {
        Ok(playlist) => QqMusicPlaylistCreationResult {
            created_playlist: Some(bridge_playlist_summary(&playlist)),
            failure: None,
        },
        Err(error) => failed_creation(map_error(error)),
    }
}

const fn failed_creation(failure: QqMusicPlaylistCreationFailure) -> QqMusicPlaylistCreationResult {
    QqMusicPlaylistCreationResult {
        created_playlist: None,
        failure: Some(failure),
    }
}

const fn map_error(error: LibraryMutationError) -> QqMusicPlaylistCreationFailure {
    match error {
        LibraryMutationError::AuthenticationRequired => {
            QqMusicPlaylistCreationFailure::AuthenticationRequired
        }
        LibraryMutationError::CredentialRejected => {
            QqMusicPlaylistCreationFailure::CredentialRejected
        }
        LibraryMutationError::NetworkOutcomeUnknown => {
            QqMusicPlaylistCreationFailure::NetworkOutcomeUnknown
        }
        LibraryMutationError::ServiceUnavailable => {
            QqMusicPlaylistCreationFailure::ServiceUnavailable
        }
        LibraryMutationError::InvalidRequest => QqMusicPlaylistCreationFailure::InvalidRequest,
        LibraryMutationError::InvalidResponseOutcomeUnknown => {
            QqMusicPlaylistCreationFailure::InvalidResponseOutcomeUnknown
        }
        LibraryMutationError::Replaced => QqMusicPlaylistCreationFailure::ReplacedOutcomeUnknown,
    }
}

#[cfg(test)]
mod tests {
    use music_domain::{PlaylistId, PlaylistSummary, ProviderId};
    use provider_api::LibraryMutationError;

    use super::{
        QqMusicPlaylistCreationFailure, begin_qq_music_playlist_creation, map_creation, map_error,
    };

    #[test]
    fn maps_created_playlist_and_all_failures() {
        let playlist = PlaylistSummary::new(
            PlaylistId::new(
                ProviderId::new("qq-music").expect("provider"),
                "owned:7002:902",
            )
            .expect("playlist ID"),
            "Fixture playlist",
        )
        .expect("playlist");
        let success = map_creation(Ok(playlist));
        let created = success.created_playlist.expect("created playlist");
        assert_eq!(created.provider_id, "qq-music");
        assert_eq!(created.opaque_id, "owned:7002:902");
        assert_eq!(created.title, "Fixture playlist");
        assert_eq!(success.failure, None);

        let cases = [
            (
                LibraryMutationError::AuthenticationRequired,
                QqMusicPlaylistCreationFailure::AuthenticationRequired,
            ),
            (
                LibraryMutationError::CredentialRejected,
                QqMusicPlaylistCreationFailure::CredentialRejected,
            ),
            (
                LibraryMutationError::NetworkOutcomeUnknown,
                QqMusicPlaylistCreationFailure::NetworkOutcomeUnknown,
            ),
            (
                LibraryMutationError::ServiceUnavailable,
                QqMusicPlaylistCreationFailure::ServiceUnavailable,
            ),
            (
                LibraryMutationError::InvalidRequest,
                QqMusicPlaylistCreationFailure::InvalidRequest,
            ),
            (
                LibraryMutationError::InvalidResponseOutcomeUnknown,
                QqMusicPlaylistCreationFailure::InvalidResponseOutcomeUnknown,
            ),
            (
                LibraryMutationError::Replaced,
                QqMusicPlaylistCreationFailure::ReplacedOutcomeUnknown,
            ),
        ];
        for (input, expected) in cases {
            assert_eq!(map_error(input), expected);
        }
    }

    #[tokio::test]
    async fn cancellation_is_terminal_and_name_is_redacted() {
        let handle = begin_qq_music_playlist_creation("Private playlist".into());
        let debug = format!("{handle:?}");
        assert!(!debug.contains("Private playlist"));
        assert!(handle.cancel());
        assert!(!handle.cancel());

        let result = handle.run().await;
        assert_eq!(result.created_playlist, None);
        assert_eq!(
            result.failure,
            Some(QqMusicPlaylistCreationFailure::CancelledOutcomeUnknown)
        );
    }
}
