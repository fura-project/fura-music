use std::fmt;

use provider_api::{AlbumFavoriteMutationProvider, LibraryMutationError};

use super::domain_album_id;
use super::remote_mutation::{RemoteMutationLifecycle, RemoteMutationStart};
use super::{authentication::native_qq_music_provider, built_in_provider};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AlbumFavoriteState {
    Favorite,
    NotFavorite,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AlbumFavoriteMutationFailure {
    CoreUnavailable,
    AuthenticationRequired,
    CredentialRejected,
    NetworkOutcomeUnknown,
    ServiceUnavailable,
    InvalidRequest,
    InvalidResponseOutcomeUnknown,
    ReplacedOutcomeUnknown,
    /// Cancelling the local wait cannot recall a write already sent to the
    /// Provider, so presentation must refresh instead of assuming failure.
    CancelledOutcomeUnknown,
    AlreadyRunning,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AlbumFavoriteMutationResult {
    pub confirmed_state: Option<AlbumFavoriteState>,
    pub failure: Option<AlbumFavoriteMutationFailure>,
}

/// One cancellable, single-use desired Album-favorite mutation. Album identity
/// is retained only for Provider routing and redacted from diagnostics.
#[flutter_rust_bridge::frb(opaque)]
pub struct AlbumFavoriteMutationHandle {
    provider_id: String,
    opaque_album_id: String,
    desired_state: AlbumFavoriteState,
    lifecycle: RemoteMutationLifecycle,
}

impl fmt::Debug for AlbumFavoriteMutationHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AlbumFavoriteMutationHandle")
            .field("provider_id", &self.provider_id)
            .field("opaque_album_id", &"[REDACTED]")
            .field("desired_state", &self.desired_state)
            .field("active", &self.is_active())
            .field("running", &self.lifecycle.is_running())
            .finish()
    }
}

impl AlbumFavoriteMutationHandle {
    pub async fn run(&self) -> AlbumFavoriteMutationResult {
        match self.lifecycle.try_start() {
            RemoteMutationStart::Started => {}
            RemoteMutationStart::Cancelled => {
                return failed_mutation(AlbumFavoriteMutationFailure::CancelledOutcomeUnknown);
            }
            RemoteMutationStart::AlreadyRunning => {
                return failed_mutation(AlbumFavoriteMutationFailure::AlreadyRunning);
            }
        }
        let outcome = match domain_album_id(&self.provider_id, &self.opaque_album_id) {
            Ok(album_id) => match built_in_provider(&self.provider_id) {
                Ok(provider_api::BuiltInProvider::QQMusic) => match native_qq_music_provider() {
                    Ok(provider) => {
                        let favorite = self.desired_state == AlbumFavoriteState::Favorite;
                        tokio::select! {
                            () = self.lifecycle.cancelled() => {
                                failed_mutation(
                                    AlbumFavoriteMutationFailure::CancelledOutcomeUnknown,
                                )
                            }
                            result = provider.set_album_favorite(album_id, favorite) => {
                                if self.lifecycle.is_active() {
                                    map_mutation(result, self.desired_state)
                                } else {
                                    failed_mutation(
                                        AlbumFavoriteMutationFailure::CancelledOutcomeUnknown,
                                    )
                                }
                            }
                        }
                    }
                    Err(()) => failed_mutation(AlbumFavoriteMutationFailure::CoreUnavailable),
                },
                Ok(provider_api::BuiltInProvider::NetEaseCloudMusic) | Err(()) => {
                    failed_mutation(AlbumFavoriteMutationFailure::InvalidRequest)
                }
            },
            Err(()) => failed_mutation(AlbumFavoriteMutationFailure::InvalidRequest),
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
pub fn begin_album_favorite_mutation(
    provider_id: String,
    opaque_album_id: String,
    desired_state: AlbumFavoriteState,
) -> AlbumFavoriteMutationHandle {
    AlbumFavoriteMutationHandle {
        provider_id,
        opaque_album_id,
        desired_state,
        lifecycle: RemoteMutationLifecycle::new(),
    }
}

fn map_mutation(
    result: Result<(), LibraryMutationError>,
    desired_state: AlbumFavoriteState,
) -> AlbumFavoriteMutationResult {
    match result {
        Ok(()) => AlbumFavoriteMutationResult {
            confirmed_state: Some(desired_state),
            failure: None,
        },
        Err(error) => failed_mutation(map_error(error)),
    }
}

const fn failed_mutation(failure: AlbumFavoriteMutationFailure) -> AlbumFavoriteMutationResult {
    AlbumFavoriteMutationResult {
        confirmed_state: None,
        failure: Some(failure),
    }
}

const fn map_error(error: LibraryMutationError) -> AlbumFavoriteMutationFailure {
    match error {
        LibraryMutationError::AuthenticationRequired => {
            AlbumFavoriteMutationFailure::AuthenticationRequired
        }
        LibraryMutationError::CredentialRejected => {
            AlbumFavoriteMutationFailure::CredentialRejected
        }
        LibraryMutationError::NetworkOutcomeUnknown => {
            AlbumFavoriteMutationFailure::NetworkOutcomeUnknown
        }
        LibraryMutationError::ServiceUnavailable => {
            AlbumFavoriteMutationFailure::ServiceUnavailable
        }
        LibraryMutationError::InvalidRequest => AlbumFavoriteMutationFailure::InvalidRequest,
        LibraryMutationError::InvalidResponseOutcomeUnknown => {
            AlbumFavoriteMutationFailure::InvalidResponseOutcomeUnknown
        }
        LibraryMutationError::Replaced => AlbumFavoriteMutationFailure::ReplacedOutcomeUnknown,
    }
}

#[cfg(test)]
mod tests {
    use provider_api::LibraryMutationError;

    use super::{
        AlbumFavoriteMutationFailure, AlbumFavoriteState, begin_album_favorite_mutation, map_error,
        map_mutation,
    };

    #[test]
    fn maps_confirmed_state_and_all_failures() {
        let success = map_mutation(Ok(()), AlbumFavoriteState::Favorite);
        assert_eq!(success.confirmed_state, Some(AlbumFavoriteState::Favorite));
        assert_eq!(success.failure, None);

        let cases = [
            (
                LibraryMutationError::AuthenticationRequired,
                AlbumFavoriteMutationFailure::AuthenticationRequired,
            ),
            (
                LibraryMutationError::CredentialRejected,
                AlbumFavoriteMutationFailure::CredentialRejected,
            ),
            (
                LibraryMutationError::NetworkOutcomeUnknown,
                AlbumFavoriteMutationFailure::NetworkOutcomeUnknown,
            ),
            (
                LibraryMutationError::ServiceUnavailable,
                AlbumFavoriteMutationFailure::ServiceUnavailable,
            ),
            (
                LibraryMutationError::InvalidRequest,
                AlbumFavoriteMutationFailure::InvalidRequest,
            ),
            (
                LibraryMutationError::InvalidResponseOutcomeUnknown,
                AlbumFavoriteMutationFailure::InvalidResponseOutcomeUnknown,
            ),
            (
                LibraryMutationError::Replaced,
                AlbumFavoriteMutationFailure::ReplacedOutcomeUnknown,
            ),
        ];
        for (input, expected) in cases {
            assert_eq!(map_error(input), expected);
        }
    }

    #[tokio::test]
    async fn cancellation_is_terminal_and_identity_is_redacted() {
        let handle = begin_album_favorite_mutation(
            "qq-music".into(),
            "album:43001:privateAlbumMid".into(),
            AlbumFavoriteState::NotFavorite,
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
            Some(AlbumFavoriteMutationFailure::CancelledOutcomeUnknown)
        );
    }
}
