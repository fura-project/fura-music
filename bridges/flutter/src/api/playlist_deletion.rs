use std::fmt;

use provider_api::{LibraryMutationError, PlaylistDeletionProvider};

use super::authentication::native_qq_music_provider;
use super::built_in_provider;
use super::domain_playlist_id;
use super::remote_mutation::{RemoteMutationLifecycle, RemoteMutationStart};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PlaylistDeletionFailure {
    CoreUnavailable,
    AuthenticationRequired,
    CredentialRejected,
    NetworkOutcomeUnknown,
    ServiceUnavailable,
    InvalidRequest,
    InvalidResponseOutcomeUnknown,
    ReplacedOutcomeUnknown,
    /// Cancelling the local wait cannot recall a delete request already sent
    /// to the Provider, so presentation must refresh instead of assuming failure.
    CancelledOutcomeUnknown,
    AlreadyRunning,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PlaylistDeletionResult {
    pub deleted: bool,
    pub failure: Option<PlaylistDeletionFailure>,
}

/// One cancellable, single-use owned-playlist deletion. Opaque identity stays
/// redacted and source-specific parsing remains inside the Provider.
#[flutter_rust_bridge::frb(opaque)]
pub struct PlaylistDeletionHandle {
    provider_id: String,
    opaque_playlist_id: String,
    lifecycle: RemoteMutationLifecycle,
}

impl fmt::Debug for PlaylistDeletionHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PlaylistDeletionHandle")
            .field("provider_id", &"[REDACTED]")
            .field("opaque_playlist_id", &"[REDACTED]")
            .field("active", &self.is_active())
            .field("running", &self.lifecycle.is_running())
            .finish()
    }
}

impl PlaylistDeletionHandle {
    pub async fn run(&self) -> PlaylistDeletionResult {
        match self.lifecycle.try_start() {
            RemoteMutationStart::Started => {}
            RemoteMutationStart::Cancelled => {
                return failed_deletion(PlaylistDeletionFailure::CancelledOutcomeUnknown);
            }
            RemoteMutationStart::AlreadyRunning => {
                return failed_deletion(PlaylistDeletionFailure::AlreadyRunning);
            }
        }
        let target = domain_playlist_id(&self.provider_id, &self.opaque_playlist_id);
        let outcome = match (built_in_provider(&self.provider_id), target) {
            (Ok(provider_api::BuiltInProvider::QQMusic), Ok(playlist_id)) => {
                let Ok(provider) = native_qq_music_provider() else {
                    self.lifecycle.finish();
                    return failed_deletion(PlaylistDeletionFailure::CoreUnavailable);
                };
                tokio::select! {
                    () = self.lifecycle.cancelled() => {
                        failed_deletion(
                            PlaylistDeletionFailure::CancelledOutcomeUnknown,
                        )
                    }
                    result = provider.delete_playlist(playlist_id) => {
                        if self.lifecycle.is_active() {
                            map_deletion(result)
                        } else {
                            failed_deletion(
                                PlaylistDeletionFailure::CancelledOutcomeUnknown,
                            )
                        }
                    }
                }
            }
            (Ok(provider_api::BuiltInProvider::NetEaseCloudMusic), _) | (Err(()), _) => {
                failed_deletion(PlaylistDeletionFailure::InvalidRequest)
            }
            (_, Err(())) => failed_deletion(PlaylistDeletionFailure::InvalidRequest),
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
pub fn begin_playlist_deletion(
    provider_id: String,
    opaque_playlist_id: String,
) -> PlaylistDeletionHandle {
    PlaylistDeletionHandle {
        provider_id,
        opaque_playlist_id,
        lifecycle: RemoteMutationLifecycle::new(),
    }
}

fn map_deletion(result: Result<(), LibraryMutationError>) -> PlaylistDeletionResult {
    match result {
        Ok(()) => PlaylistDeletionResult {
            deleted: true,
            failure: None,
        },
        Err(error) => failed_deletion(map_error(error)),
    }
}

const fn failed_deletion(failure: PlaylistDeletionFailure) -> PlaylistDeletionResult {
    PlaylistDeletionResult {
        deleted: false,
        failure: Some(failure),
    }
}

const fn map_error(error: LibraryMutationError) -> PlaylistDeletionFailure {
    match error {
        LibraryMutationError::AuthenticationRequired => {
            PlaylistDeletionFailure::AuthenticationRequired
        }
        LibraryMutationError::CredentialRejected => PlaylistDeletionFailure::CredentialRejected,
        LibraryMutationError::NetworkOutcomeUnknown => {
            PlaylistDeletionFailure::NetworkOutcomeUnknown
        }
        LibraryMutationError::ServiceUnavailable => PlaylistDeletionFailure::ServiceUnavailable,
        LibraryMutationError::InvalidRequest => PlaylistDeletionFailure::InvalidRequest,
        LibraryMutationError::InvalidResponseOutcomeUnknown => {
            PlaylistDeletionFailure::InvalidResponseOutcomeUnknown
        }
        LibraryMutationError::Replaced => PlaylistDeletionFailure::ReplacedOutcomeUnknown,
    }
}

#[cfg(test)]
mod tests {
    use provider_api::LibraryMutationError;

    use super::{PlaylistDeletionFailure, begin_playlist_deletion, map_deletion, map_error};

    #[test]
    fn maps_confirmed_deletion_and_all_failures() {
        let success = map_deletion(Ok(()));
        assert!(success.deleted);
        assert_eq!(success.failure, None);

        let cases = [
            (
                LibraryMutationError::AuthenticationRequired,
                PlaylistDeletionFailure::AuthenticationRequired,
            ),
            (
                LibraryMutationError::CredentialRejected,
                PlaylistDeletionFailure::CredentialRejected,
            ),
            (
                LibraryMutationError::NetworkOutcomeUnknown,
                PlaylistDeletionFailure::NetworkOutcomeUnknown,
            ),
            (
                LibraryMutationError::ServiceUnavailable,
                PlaylistDeletionFailure::ServiceUnavailable,
            ),
            (
                LibraryMutationError::InvalidRequest,
                PlaylistDeletionFailure::InvalidRequest,
            ),
            (
                LibraryMutationError::InvalidResponseOutcomeUnknown,
                PlaylistDeletionFailure::InvalidResponseOutcomeUnknown,
            ),
            (
                LibraryMutationError::Replaced,
                PlaylistDeletionFailure::ReplacedOutcomeUnknown,
            ),
        ];
        for (input, expected) in cases {
            assert_eq!(map_error(input), expected);
        }
    }

    #[tokio::test]
    async fn cancellation_is_terminal_and_identity_is_redacted() {
        let handle =
            begin_playlist_deletion("qq-music".into(), "owned:7002:private-directory".into());
        let debug = format!("{handle:?}");
        assert!(!debug.contains("qq-music"));
        assert!(!debug.contains("private-directory"));
        assert!(handle.cancel());
        assert!(!handle.cancel());

        let result = handle.run().await;
        assert!(!result.deleted);
        assert_eq!(
            result.failure,
            Some(PlaylistDeletionFailure::CancelledOutcomeUnknown)
        );
    }
}
