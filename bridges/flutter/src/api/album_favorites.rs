use std::fmt;

use provider_api::{AlbumFavoriteMutationProvider, LibraryMutationError};

use super::authentication::native_qq_music_provider;
use super::domain_album_id;
use super::remote_mutation::{RemoteMutationLifecycle, RemoteMutationStart};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicAlbumFavoriteState {
    Favorite,
    NotFavorite,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicAlbumFavoriteMutationFailure {
    CoreUnavailable,
    AuthenticationRequired,
    CredentialRejected,
    NetworkOutcomeUnknown,
    ServiceUnavailable,
    InvalidRequest,
    InvalidResponseOutcomeUnknown,
    ReplacedOutcomeUnknown,
    /// Cancelling the local wait cannot recall a write already sent to QQ
    /// Music, so presentation must refresh instead of assuming failure.
    CancelledOutcomeUnknown,
    AlreadyRunning,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct QqMusicAlbumFavoriteMutationResult {
    pub confirmed_state: Option<QqMusicAlbumFavoriteState>,
    pub failure: Option<QqMusicAlbumFavoriteMutationFailure>,
}

/// One cancellable, single-use desired Album-favorite mutation. Album identity
/// is retained only for Provider routing and redacted from diagnostics.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicAlbumFavoriteMutationHandle {
    provider_id: String,
    opaque_album_id: String,
    desired_state: QqMusicAlbumFavoriteState,
    lifecycle: RemoteMutationLifecycle,
}

impl fmt::Debug for QqMusicAlbumFavoriteMutationHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicAlbumFavoriteMutationHandle")
            .field("provider_id", &self.provider_id)
            .field("opaque_album_id", &"[REDACTED]")
            .field("desired_state", &self.desired_state)
            .field("active", &self.is_active())
            .field("running", &self.lifecycle.is_running())
            .finish()
    }
}

impl QqMusicAlbumFavoriteMutationHandle {
    pub async fn run(&self) -> QqMusicAlbumFavoriteMutationResult {
        match self.lifecycle.try_start() {
            RemoteMutationStart::Started => {}
            RemoteMutationStart::Cancelled => {
                return failed_mutation(
                    QqMusicAlbumFavoriteMutationFailure::CancelledOutcomeUnknown,
                );
            }
            RemoteMutationStart::AlreadyRunning => {
                return failed_mutation(QqMusicAlbumFavoriteMutationFailure::AlreadyRunning);
            }
        }
        let outcome = match domain_album_id(&self.provider_id, &self.opaque_album_id) {
            Ok(album_id) => match native_qq_music_provider() {
                Ok(provider) => {
                    let favorite = self.desired_state == QqMusicAlbumFavoriteState::Favorite;
                    tokio::select! {
                        () = self.lifecycle.cancelled() => {
                            failed_mutation(
                                QqMusicAlbumFavoriteMutationFailure::CancelledOutcomeUnknown,
                            )
                        }
                        result = provider.set_album_favorite(album_id, favorite) => {
                            if self.lifecycle.is_active() {
                                map_mutation(result, self.desired_state)
                            } else {
                                failed_mutation(
                                    QqMusicAlbumFavoriteMutationFailure::CancelledOutcomeUnknown,
                                )
                            }
                        }
                    }
                }
                Err(()) => failed_mutation(QqMusicAlbumFavoriteMutationFailure::CoreUnavailable),
            },
            Err(()) => failed_mutation(QqMusicAlbumFavoriteMutationFailure::InvalidRequest),
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
pub fn begin_qq_music_album_favorite_mutation(
    provider_id: String,
    opaque_album_id: String,
    desired_state: QqMusicAlbumFavoriteState,
) -> QqMusicAlbumFavoriteMutationHandle {
    QqMusicAlbumFavoriteMutationHandle {
        provider_id,
        opaque_album_id,
        desired_state,
        lifecycle: RemoteMutationLifecycle::new(),
    }
}

fn map_mutation(
    result: Result<(), LibraryMutationError>,
    desired_state: QqMusicAlbumFavoriteState,
) -> QqMusicAlbumFavoriteMutationResult {
    match result {
        Ok(()) => QqMusicAlbumFavoriteMutationResult {
            confirmed_state: Some(desired_state),
            failure: None,
        },
        Err(error) => failed_mutation(map_error(error)),
    }
}

const fn failed_mutation(
    failure: QqMusicAlbumFavoriteMutationFailure,
) -> QqMusicAlbumFavoriteMutationResult {
    QqMusicAlbumFavoriteMutationResult {
        confirmed_state: None,
        failure: Some(failure),
    }
}

const fn map_error(error: LibraryMutationError) -> QqMusicAlbumFavoriteMutationFailure {
    match error {
        LibraryMutationError::AuthenticationRequired => {
            QqMusicAlbumFavoriteMutationFailure::AuthenticationRequired
        }
        LibraryMutationError::CredentialRejected => {
            QqMusicAlbumFavoriteMutationFailure::CredentialRejected
        }
        LibraryMutationError::NetworkOutcomeUnknown => {
            QqMusicAlbumFavoriteMutationFailure::NetworkOutcomeUnknown
        }
        LibraryMutationError::ServiceUnavailable => {
            QqMusicAlbumFavoriteMutationFailure::ServiceUnavailable
        }
        LibraryMutationError::InvalidRequest => QqMusicAlbumFavoriteMutationFailure::InvalidRequest,
        LibraryMutationError::InvalidResponseOutcomeUnknown => {
            QqMusicAlbumFavoriteMutationFailure::InvalidResponseOutcomeUnknown
        }
        LibraryMutationError::Replaced => {
            QqMusicAlbumFavoriteMutationFailure::ReplacedOutcomeUnknown
        }
    }
}

#[cfg(test)]
mod tests {
    use provider_api::LibraryMutationError;

    use super::{
        QqMusicAlbumFavoriteMutationFailure, QqMusicAlbumFavoriteState,
        begin_qq_music_album_favorite_mutation, map_error, map_mutation,
    };

    #[test]
    fn maps_confirmed_state_and_all_failures() {
        let success = map_mutation(Ok(()), QqMusicAlbumFavoriteState::Favorite);
        assert_eq!(
            success.confirmed_state,
            Some(QqMusicAlbumFavoriteState::Favorite)
        );
        assert_eq!(success.failure, None);

        let cases = [
            (
                LibraryMutationError::AuthenticationRequired,
                QqMusicAlbumFavoriteMutationFailure::AuthenticationRequired,
            ),
            (
                LibraryMutationError::CredentialRejected,
                QqMusicAlbumFavoriteMutationFailure::CredentialRejected,
            ),
            (
                LibraryMutationError::NetworkOutcomeUnknown,
                QqMusicAlbumFavoriteMutationFailure::NetworkOutcomeUnknown,
            ),
            (
                LibraryMutationError::ServiceUnavailable,
                QqMusicAlbumFavoriteMutationFailure::ServiceUnavailable,
            ),
            (
                LibraryMutationError::InvalidRequest,
                QqMusicAlbumFavoriteMutationFailure::InvalidRequest,
            ),
            (
                LibraryMutationError::InvalidResponseOutcomeUnknown,
                QqMusicAlbumFavoriteMutationFailure::InvalidResponseOutcomeUnknown,
            ),
            (
                LibraryMutationError::Replaced,
                QqMusicAlbumFavoriteMutationFailure::ReplacedOutcomeUnknown,
            ),
        ];
        for (input, expected) in cases {
            assert_eq!(map_error(input), expected);
        }
    }

    #[tokio::test]
    async fn cancellation_is_terminal_and_identity_is_redacted() {
        let handle = begin_qq_music_album_favorite_mutation(
            "qq-music".into(),
            "album:43001:privateAlbumMid".into(),
            QqMusicAlbumFavoriteState::NotFavorite,
        );
        let debug = format!("{handle:?}");
        assert!(!debug.contains("43001"));
        assert!(!debug.contains("privateAlbumMid"));
        assert!(handle.cancel());
        assert!(!handle.cancel());

        let result = handle.run().await;
        assert_eq!(result.confirmed_state, None);
        assert_eq!(
            result.failure,
            Some(QqMusicAlbumFavoriteMutationFailure::CancelledOutcomeUnknown)
        );
    }
}
