use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use provider_api::{LibraryMutationError, PlaylistTrackMutationProvider};
use tokio::sync::Notify;

use super::authentication::native_qq_music_provider;
use super::{domain_playlist_id, domain_track_id};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicPlaylistTrackState {
    Present,
    Absent,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicPlaylistTrackMutationFailure {
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
pub struct QqMusicPlaylistTrackMutationResult {
    pub confirmed_state: Option<QqMusicPlaylistTrackState>,
    pub failure: Option<QqMusicPlaylistTrackMutationFailure>,
}

/// One cancellable, single-use desired Track membership mutation. Playlist
/// and Track identities are retained only for Provider routing and redacted
/// from diagnostics.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicPlaylistTrackMutationHandle {
    provider_id: String,
    opaque_playlist_id: String,
    opaque_track_id: String,
    desired_state: QqMusicPlaylistTrackState,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicPlaylistTrackMutationHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicPlaylistTrackMutationHandle")
            .field("provider_id", &self.provider_id)
            .field("opaque_playlist_id", &"[REDACTED]")
            .field("opaque_track_id", &"[REDACTED]")
            .field("desired_state", &self.desired_state)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicPlaylistTrackMutationHandle {
    pub async fn run(&self) -> QqMusicPlaylistTrackMutationResult {
        if !self.active.load(Ordering::SeqCst) {
            return failed_mutation(QqMusicPlaylistTrackMutationFailure::CancelledOutcomeUnknown);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_mutation(QqMusicPlaylistTrackMutationFailure::AlreadyRunning);
        }
        let outcome = match (
            domain_playlist_id(&self.provider_id, &self.opaque_playlist_id),
            domain_track_id(&self.provider_id, &self.opaque_track_id),
        ) {
            (Ok(playlist_id), Ok(track_id)) => match native_qq_music_provider() {
                Ok(provider) => {
                    let present = self.desired_state == QqMusicPlaylistTrackState::Present;
                    tokio::select! {
                        () = self.cancelled.notified() => {
                            failed_mutation(
                                QqMusicPlaylistTrackMutationFailure::CancelledOutcomeUnknown,
                            )
                        }
                        result = provider.set_playlist_track_membership(
                            playlist_id,
                            track_id,
                            present,
                        ) => {
                            if self.active.load(Ordering::SeqCst) {
                                map_mutation(result, self.desired_state)
                            } else {
                                failed_mutation(
                                    QqMusicPlaylistTrackMutationFailure::CancelledOutcomeUnknown,
                                )
                            }
                        }
                    }
                }
                Err(()) => failed_mutation(QqMusicPlaylistTrackMutationFailure::CoreUnavailable),
            },
            _ => failed_mutation(QqMusicPlaylistTrackMutationFailure::InvalidRequest),
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
pub fn begin_qq_music_playlist_track_mutation(
    provider_id: String,
    opaque_playlist_id: String,
    opaque_track_id: String,
    desired_state: QqMusicPlaylistTrackState,
) -> QqMusicPlaylistTrackMutationHandle {
    QqMusicPlaylistTrackMutationHandle {
        provider_id,
        opaque_playlist_id,
        opaque_track_id,
        desired_state,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_mutation(
    result: Result<(), LibraryMutationError>,
    desired_state: QqMusicPlaylistTrackState,
) -> QqMusicPlaylistTrackMutationResult {
    match result {
        Ok(()) => QqMusicPlaylistTrackMutationResult {
            confirmed_state: Some(desired_state),
            failure: None,
        },
        Err(error) => failed_mutation(map_error(error)),
    }
}

const fn failed_mutation(
    failure: QqMusicPlaylistTrackMutationFailure,
) -> QqMusicPlaylistTrackMutationResult {
    QqMusicPlaylistTrackMutationResult {
        confirmed_state: None,
        failure: Some(failure),
    }
}

const fn map_error(error: LibraryMutationError) -> QqMusicPlaylistTrackMutationFailure {
    match error {
        LibraryMutationError::AuthenticationRequired => {
            QqMusicPlaylistTrackMutationFailure::AuthenticationRequired
        }
        LibraryMutationError::CredentialRejected => {
            QqMusicPlaylistTrackMutationFailure::CredentialRejected
        }
        LibraryMutationError::NetworkOutcomeUnknown => {
            QqMusicPlaylistTrackMutationFailure::NetworkOutcomeUnknown
        }
        LibraryMutationError::ServiceUnavailable => {
            QqMusicPlaylistTrackMutationFailure::ServiceUnavailable
        }
        LibraryMutationError::InvalidRequest => QqMusicPlaylistTrackMutationFailure::InvalidRequest,
        LibraryMutationError::InvalidResponseOutcomeUnknown => {
            QqMusicPlaylistTrackMutationFailure::InvalidResponseOutcomeUnknown
        }
        LibraryMutationError::Replaced => {
            QqMusicPlaylistTrackMutationFailure::ReplacedOutcomeUnknown
        }
    }
}

#[cfg(test)]
mod tests {
    use provider_api::LibraryMutationError;

    use super::{
        QqMusicPlaylistTrackMutationFailure, QqMusicPlaylistTrackState,
        begin_qq_music_playlist_track_mutation, map_error, map_mutation,
    };

    #[test]
    fn maps_confirmed_state_and_all_failures() {
        let success = map_mutation(Ok(()), QqMusicPlaylistTrackState::Present);
        assert_eq!(
            success.confirmed_state,
            Some(QqMusicPlaylistTrackState::Present)
        );
        assert_eq!(success.failure, None);

        let cases = [
            (
                LibraryMutationError::AuthenticationRequired,
                QqMusicPlaylistTrackMutationFailure::AuthenticationRequired,
            ),
            (
                LibraryMutationError::CredentialRejected,
                QqMusicPlaylistTrackMutationFailure::CredentialRejected,
            ),
            (
                LibraryMutationError::NetworkOutcomeUnknown,
                QqMusicPlaylistTrackMutationFailure::NetworkOutcomeUnknown,
            ),
            (
                LibraryMutationError::ServiceUnavailable,
                QqMusicPlaylistTrackMutationFailure::ServiceUnavailable,
            ),
            (
                LibraryMutationError::InvalidRequest,
                QqMusicPlaylistTrackMutationFailure::InvalidRequest,
            ),
            (
                LibraryMutationError::InvalidResponseOutcomeUnknown,
                QqMusicPlaylistTrackMutationFailure::InvalidResponseOutcomeUnknown,
            ),
            (
                LibraryMutationError::Replaced,
                QqMusicPlaylistTrackMutationFailure::ReplacedOutcomeUnknown,
            ),
        ];
        for (input, expected) in cases {
            assert_eq!(map_error(input), expected);
        }
    }

    #[tokio::test]
    async fn cancellation_is_terminal_and_identities_are_redacted() {
        let handle = begin_qq_music_playlist_track_mutation(
            "qq-music".into(),
            "owned:7002:902".into(),
            "track:41001:0:privateTrackMid:privateFileMid".into(),
            QqMusicPlaylistTrackState::Absent,
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
            Some(QqMusicPlaylistTrackMutationFailure::CancelledOutcomeUnknown)
        );
    }
}
