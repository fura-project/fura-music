use std::fmt;

use provider_api::{LibraryMutationError, TrackLikeMutationProvider};

use super::authentication::native_qq_music_provider;
use super::domain_track_id;
use super::remote_mutation::{RemoteMutationLifecycle, RemoteMutationStart};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicTrackLikeState {
    Liked,
    NotLiked,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicTrackLikeMutationFailure {
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
pub struct QqMusicTrackLikeMutationResult {
    pub confirmed_state: Option<QqMusicTrackLikeState>,
    pub failure: Option<QqMusicTrackLikeMutationFailure>,
}

/// One cancellable, single-use desired liked-Track mutation. Track identity is
/// retained only for Provider routing and redacted from diagnostics.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicTrackLikeMutationHandle {
    provider_id: String,
    opaque_track_id: String,
    desired_state: QqMusicTrackLikeState,
    lifecycle: RemoteMutationLifecycle,
}

impl fmt::Debug for QqMusicTrackLikeMutationHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicTrackLikeMutationHandle")
            .field("provider_id", &self.provider_id)
            .field("opaque_track_id", &"[REDACTED]")
            .field("desired_state", &self.desired_state)
            .field("active", &self.is_active())
            .field("running", &self.lifecycle.is_running())
            .finish()
    }
}

impl QqMusicTrackLikeMutationHandle {
    pub async fn run(&self) -> QqMusicTrackLikeMutationResult {
        match self.lifecycle.try_start() {
            RemoteMutationStart::Started => {}
            RemoteMutationStart::Cancelled => {
                return failed_mutation(QqMusicTrackLikeMutationFailure::CancelledOutcomeUnknown);
            }
            RemoteMutationStart::AlreadyRunning => {
                return failed_mutation(QqMusicTrackLikeMutationFailure::AlreadyRunning);
            }
        }
        let outcome = match domain_track_id(&self.provider_id, &self.opaque_track_id) {
            Ok(track_id) => match native_qq_music_provider() {
                Ok(provider) => {
                    let liked = self.desired_state == QqMusicTrackLikeState::Liked;
                    tokio::select! {
                        () = self.lifecycle.cancelled() => {
                            failed_mutation(
                                QqMusicTrackLikeMutationFailure::CancelledOutcomeUnknown,
                            )
                        }
                        result = provider.set_track_liked(track_id, liked) => {
                            if self.lifecycle.is_active() {
                                map_mutation(result, self.desired_state)
                            } else {
                                failed_mutation(
                                    QqMusicTrackLikeMutationFailure::CancelledOutcomeUnknown,
                                )
                            }
                        }
                    }
                }
                Err(()) => failed_mutation(QqMusicTrackLikeMutationFailure::CoreUnavailable),
            },
            Err(()) => failed_mutation(QqMusicTrackLikeMutationFailure::InvalidRequest),
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
pub fn begin_qq_music_track_like_mutation(
    provider_id: String,
    opaque_track_id: String,
    desired_state: QqMusicTrackLikeState,
) -> QqMusicTrackLikeMutationHandle {
    QqMusicTrackLikeMutationHandle {
        provider_id,
        opaque_track_id,
        desired_state,
        lifecycle: RemoteMutationLifecycle::new(),
    }
}

fn map_mutation(
    result: Result<(), LibraryMutationError>,
    desired_state: QqMusicTrackLikeState,
) -> QqMusicTrackLikeMutationResult {
    match result {
        Ok(()) => QqMusicTrackLikeMutationResult {
            confirmed_state: Some(desired_state),
            failure: None,
        },
        Err(error) => failed_mutation(map_error(error)),
    }
}

const fn failed_mutation(
    failure: QqMusicTrackLikeMutationFailure,
) -> QqMusicTrackLikeMutationResult {
    QqMusicTrackLikeMutationResult {
        confirmed_state: None,
        failure: Some(failure),
    }
}

const fn map_error(error: LibraryMutationError) -> QqMusicTrackLikeMutationFailure {
    match error {
        LibraryMutationError::AuthenticationRequired => {
            QqMusicTrackLikeMutationFailure::AuthenticationRequired
        }
        LibraryMutationError::CredentialRejected => {
            QqMusicTrackLikeMutationFailure::CredentialRejected
        }
        LibraryMutationError::NetworkOutcomeUnknown => {
            QqMusicTrackLikeMutationFailure::NetworkOutcomeUnknown
        }
        LibraryMutationError::ServiceUnavailable => {
            QqMusicTrackLikeMutationFailure::ServiceUnavailable
        }
        LibraryMutationError::InvalidRequest => QqMusicTrackLikeMutationFailure::InvalidRequest,
        LibraryMutationError::InvalidResponseOutcomeUnknown => {
            QqMusicTrackLikeMutationFailure::InvalidResponseOutcomeUnknown
        }
        LibraryMutationError::Replaced => QqMusicTrackLikeMutationFailure::ReplacedOutcomeUnknown,
    }
}

#[cfg(test)]
mod tests {
    use provider_api::LibraryMutationError;

    use super::{
        QqMusicTrackLikeMutationFailure, QqMusicTrackLikeState, begin_qq_music_track_like_mutation,
        map_error, map_mutation,
    };

    #[test]
    fn maps_confirmed_state_and_all_failures() {
        let success = map_mutation(Ok(()), QqMusicTrackLikeState::Liked);
        assert_eq!(success.confirmed_state, Some(QqMusicTrackLikeState::Liked));
        assert_eq!(success.failure, None);

        let cases = [
            (
                LibraryMutationError::AuthenticationRequired,
                QqMusicTrackLikeMutationFailure::AuthenticationRequired,
            ),
            (
                LibraryMutationError::CredentialRejected,
                QqMusicTrackLikeMutationFailure::CredentialRejected,
            ),
            (
                LibraryMutationError::NetworkOutcomeUnknown,
                QqMusicTrackLikeMutationFailure::NetworkOutcomeUnknown,
            ),
            (
                LibraryMutationError::ServiceUnavailable,
                QqMusicTrackLikeMutationFailure::ServiceUnavailable,
            ),
            (
                LibraryMutationError::InvalidRequest,
                QqMusicTrackLikeMutationFailure::InvalidRequest,
            ),
            (
                LibraryMutationError::InvalidResponseOutcomeUnknown,
                QqMusicTrackLikeMutationFailure::InvalidResponseOutcomeUnknown,
            ),
            (
                LibraryMutationError::Replaced,
                QqMusicTrackLikeMutationFailure::ReplacedOutcomeUnknown,
            ),
        ];
        for (input, expected) in cases {
            assert_eq!(map_error(input), expected);
        }
    }

    #[tokio::test]
    async fn cancellation_is_terminal_and_identity_is_redacted() {
        let handle = begin_qq_music_track_like_mutation(
            "qq-music".into(),
            "track:41001:0:privateTrackMid:privateFileMid".into(),
            QqMusicTrackLikeState::NotLiked,
        );
        let debug = format!("{handle:?}");
        assert!(!debug.contains("41001"));
        assert!(!debug.contains("privateTrackMid"));
        assert!(handle.cancel());
        assert!(!handle.cancel());

        let result = handle.run().await;
        assert_eq!(result.confirmed_state, None);
        assert_eq!(
            result.failure,
            Some(QqMusicTrackLikeMutationFailure::CancelledOutcomeUnknown)
        );
    }
}
