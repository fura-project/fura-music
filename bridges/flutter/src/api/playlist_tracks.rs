use std::fmt;

use provider_api::{LibraryMutationError, PlaylistTrackMutationProvider};

use super::remote_mutation::{RemoteMutationLifecycle, RemoteMutationStart};
use super::{domain_playlist_id, domain_track_id, with_native_provider};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PlaylistTrackState {
    Present,
    Absent,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PlaylistTrackMutationFailure {
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
pub struct PlaylistTrackMutationResult {
    pub confirmed_state: Option<PlaylistTrackState>,
    pub failure: Option<PlaylistTrackMutationFailure>,
}

/// One cancellable, single-use desired Track membership mutation. Playlist
/// and Track identities are retained only for Provider routing and redacted
/// from diagnostics.
#[flutter_rust_bridge::frb(opaque)]
pub struct PlaylistTrackMutationHandle {
    provider_id: String,
    opaque_playlist_id: String,
    opaque_track_id: String,
    desired_state: PlaylistTrackState,
    lifecycle: RemoteMutationLifecycle,
}

impl fmt::Debug for PlaylistTrackMutationHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PlaylistTrackMutationHandle")
            .field("provider_id", &self.provider_id)
            .field("opaque_playlist_id", &"[REDACTED]")
            .field("opaque_track_id", &"[REDACTED]")
            .field("desired_state", &self.desired_state)
            .field("active", &self.is_active())
            .field("running", &self.lifecycle.is_running())
            .finish()
    }
}

impl PlaylistTrackMutationHandle {
    pub async fn run(&self) -> PlaylistTrackMutationResult {
        match self.lifecycle.try_start() {
            RemoteMutationStart::Started => {}
            RemoteMutationStart::Cancelled => {
                return failed_mutation(PlaylistTrackMutationFailure::CancelledOutcomeUnknown);
            }
            RemoteMutationStart::AlreadyRunning => {
                return failed_mutation(PlaylistTrackMutationFailure::AlreadyRunning);
            }
        }
        let outcome = match (
            domain_playlist_id(&self.provider_id, &self.opaque_playlist_id),
            domain_track_id(&self.provider_id, &self.opaque_track_id),
        ) {
            (Ok(playlist_id), Ok(track_id)) => with_native_provider!(
                &self.provider_id,
                |provider| {
                    let present = self.desired_state == PlaylistTrackState::Present;
                    tokio::select! {
                        () = self.lifecycle.cancelled() => {
                            failed_mutation(
                                PlaylistTrackMutationFailure::CancelledOutcomeUnknown,
                            )
                        }
                        result = provider.set_playlist_track_membership(
                            playlist_id,
                            track_id,
                            present,
                        ) => {
                            if self.lifecycle.is_active() {
                                map_mutation(result, self.desired_state)
                            } else {
                                failed_mutation(
                                    PlaylistTrackMutationFailure::CancelledOutcomeUnknown,
                                )
                            }
                        }
                    }
                },
                failed_mutation(PlaylistTrackMutationFailure::CoreUnavailable)
            ),
            _ => failed_mutation(PlaylistTrackMutationFailure::InvalidRequest),
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
pub fn begin_playlist_track_mutation(
    provider_id: String,
    opaque_playlist_id: String,
    opaque_track_id: String,
    desired_state: PlaylistTrackState,
) -> PlaylistTrackMutationHandle {
    PlaylistTrackMutationHandle {
        provider_id,
        opaque_playlist_id,
        opaque_track_id,
        desired_state,
        lifecycle: RemoteMutationLifecycle::new(),
    }
}

fn map_mutation(
    result: Result<(), LibraryMutationError>,
    desired_state: PlaylistTrackState,
) -> PlaylistTrackMutationResult {
    match result {
        Ok(()) => PlaylistTrackMutationResult {
            confirmed_state: Some(desired_state),
            failure: None,
        },
        Err(error) => failed_mutation(map_error(error)),
    }
}

const fn failed_mutation(failure: PlaylistTrackMutationFailure) -> PlaylistTrackMutationResult {
    PlaylistTrackMutationResult {
        confirmed_state: None,
        failure: Some(failure),
    }
}

const fn map_error(error: LibraryMutationError) -> PlaylistTrackMutationFailure {
    match error {
        LibraryMutationError::AuthenticationRequired => {
            PlaylistTrackMutationFailure::AuthenticationRequired
        }
        LibraryMutationError::CredentialRejected => {
            PlaylistTrackMutationFailure::CredentialRejected
        }
        LibraryMutationError::NetworkOutcomeUnknown => {
            PlaylistTrackMutationFailure::NetworkOutcomeUnknown
        }
        LibraryMutationError::ServiceUnavailable => {
            PlaylistTrackMutationFailure::ServiceUnavailable
        }
        LibraryMutationError::InvalidRequest => PlaylistTrackMutationFailure::InvalidRequest,
        LibraryMutationError::InvalidResponseOutcomeUnknown => {
            PlaylistTrackMutationFailure::InvalidResponseOutcomeUnknown
        }
        LibraryMutationError::Replaced => PlaylistTrackMutationFailure::ReplacedOutcomeUnknown,
    }
}

#[cfg(test)]
mod tests {
    use provider_api::LibraryMutationError;

    use super::{
        PlaylistTrackMutationFailure, PlaylistTrackState, begin_playlist_track_mutation, map_error,
        map_mutation,
    };

    #[test]
    fn maps_confirmed_state_and_all_failures() {
        let success = map_mutation(Ok(()), PlaylistTrackState::Present);
        assert_eq!(success.confirmed_state, Some(PlaylistTrackState::Present));
        assert_eq!(success.failure, None);

        let cases = [
            (
                LibraryMutationError::AuthenticationRequired,
                PlaylistTrackMutationFailure::AuthenticationRequired,
            ),
            (
                LibraryMutationError::CredentialRejected,
                PlaylistTrackMutationFailure::CredentialRejected,
            ),
            (
                LibraryMutationError::NetworkOutcomeUnknown,
                PlaylistTrackMutationFailure::NetworkOutcomeUnknown,
            ),
            (
                LibraryMutationError::ServiceUnavailable,
                PlaylistTrackMutationFailure::ServiceUnavailable,
            ),
            (
                LibraryMutationError::InvalidRequest,
                PlaylistTrackMutationFailure::InvalidRequest,
            ),
            (
                LibraryMutationError::InvalidResponseOutcomeUnknown,
                PlaylistTrackMutationFailure::InvalidResponseOutcomeUnknown,
            ),
            (
                LibraryMutationError::Replaced,
                PlaylistTrackMutationFailure::ReplacedOutcomeUnknown,
            ),
        ];
        for (input, expected) in cases {
            assert_eq!(map_error(input), expected);
        }
    }

    #[tokio::test]
    async fn cancellation_is_terminal_and_identities_are_redacted() {
        let handle = begin_playlist_track_mutation(
            "qq-music".into(),
            "owned:7002:902".into(),
            "track:41001:0:privateTrackMid:privateFileMid".into(),
            PlaylistTrackState::Absent,
        );
        let debug = format!("{handle:?}");
        assert!(!debug.contains("7002"));
        assert!(!debug.contains("41001"));
        assert!(!debug.contains("privateTrackMid"));
        assert!(handle.cancel());
        assert!(!handle.cancel());

        let result = handle.run().await;
        assert_eq!(result.confirmed_state, None);
        assert_eq!(
            result.failure,
            Some(PlaylistTrackMutationFailure::CancelledOutcomeUnknown)
        );
    }
}
