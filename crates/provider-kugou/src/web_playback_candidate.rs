//! One-shot experimental owner, disconnected from production resolution/authentication.
//! Capture admission is consumed synchronously BEFORE the caller opens CDP. Replay
//! is separately consumed before transport await. Neither budget is replenished.

use crate::decode_track_context;
use kugou_client::web_playback_candidate::{
    CapturedWebRequest, OfficialWebCapture, StandardWebSource, WebPlaybackError,
    WebPlaybackTransport, WebTrackContext, decode_standard_source,
};
use music_domain::TrackId;
use std::{
    fmt,
    sync::{Arc, Mutex, MutexGuard},
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CandidateSessionState {
    Missing,
    Pending,
    AttemptConsumed,
    Halted,
}

struct Session {
    generation: Arc<()>,
    current_track: Option<TrackId>,
    capture_consumed: bool,
    replay_consumed: bool,
    halted: bool,
}

/// Non-clone, owner/generation/exact-TrackId-bound capture admission.
pub struct CaptureAttempt {
    generation: Arc<()>,
    id: TrackId,
    track: WebTrackContext,
}

/// Non-clone replay admission. No caller-supplied `TrackId` can replace its identity.
pub struct BoundCapture {
    generation: Arc<()>,
    id: TrackId,
    request: CapturedWebRequest,
}

impl fmt::Debug for CaptureAttempt {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("CaptureAttempt([REDACTED])")
    }
}
impl fmt::Debug for BoundCapture {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("BoundCapture([REDACTED])")
    }
}

pub struct AuthenticatedStandardCandidate<T> {
    transport: T,
    session: Mutex<Session>,
}

impl<T> AuthenticatedStandardCandidate<T> {
    #[must_use]
    pub fn new(transport: T) -> Self {
        Self {
            transport,
            session: Mutex::new(Session {
                generation: Arc::new(()),
                current_track: None,
                capture_consumed: false,
                replay_consumed: false,
                halted: false,
            }),
        }
    }

    /// Logout, provider switch, account replacement, SAME-account relogin and
    /// cancellation must call this. No cookies or account assertion are accepted.
    /// Retires outstanding tokens/results without resetting either attempt budget
    /// or the sticky risk/rate stop. Do not replace owners to bypass a challenge.
    pub fn clear(&self) {
        let mut session = self.lock();
        session.generation = Arc::new(());
        session.current_track = None;
    }

    /// Call before the first browser await. Even a dropped/failed capture consumes
    /// admission. Foreign/unsupported IDs are rejected before browser startup.
    /// # Errors
    /// Requires a current `KuGou` catalog `TrackId` with provable hash+Album context.
    pub fn begin_capture(&self, id: &TrackId) -> Result<CaptureAttempt, WebPlaybackError> {
        let context = decode_track_context(id).map_err(|_| WebPlaybackError::InvalidCapture)?;
        let track = WebTrackContext::new(
            &context.mix_song_id,
            &context.standard_hash,
            context
                .album_id
                .as_deref()
                .ok_or(WebPlaybackError::OfficialWebTrackIdentityUnproven)?,
            context.duration_seconds,
        )
        .map_err(|_| WebPlaybackError::OfficialWebTrackIdentityUnproven)?;
        let mut session = self.lock();
        if session.halted {
            return Err(WebPlaybackError::RiskControl);
        }
        if session.capture_consumed {
            return Err(WebPlaybackError::AttemptConsumed);
        }
        session.capture_consumed = true;
        session.current_track = Some(id.clone());
        Ok(CaptureAttempt {
            generation: Arc::clone(&session.generation),
            id: id.clone(),
            track,
        })
    }

    /// Admit only the capture belonging to the still-current pre-browser token.
    /// # Errors
    /// Stale/cross-owner tokens, expired captures and unproved exact identity fail closed.
    pub fn finish_capture(
        &self,
        attempt: CaptureAttempt,
        capture: OfficialWebCapture,
        now: u64,
    ) -> Result<BoundCapture, WebPlaybackError> {
        let session = self.lock();
        if !Arc::ptr_eq(&session.generation, &attempt.generation)
            || session.current_track.as_ref() != Some(&attempt.id)
        {
            return Err(WebPlaybackError::Replaced);
        }
        if session.halted {
            return Err(WebPlaybackError::RiskControl);
        }
        let request = capture.bind_track(attempt.track, now)?;
        Ok(BoundCapture {
            generation: attempt.generation,
            id: attempt.id,
            request,
        })
    }

    /// Cooperative CDP cancellation uses the same exact owner/generation/TrackId
    /// reservation that will later admit the captured request.
    #[must_use]
    pub fn is_capture_current(&self, attempt: &CaptureAttempt) -> bool {
        let session = self.lock();
        Arc::ptr_eq(&session.generation, &attempt.generation)
            && session.current_track.as_ref() == Some(&attempt.id)
            && !session.halted
    }

    /// Retains only the reservation identity across token consumption, so a
    /// later optional media completion cannot outlive provider replacement.
    pub fn capture_current_check<'a>(
        &'a self,
        attempt: &CaptureAttempt,
    ) -> impl Fn() -> bool + use<'a, T> {
        let generation = Arc::clone(&attempt.generation);
        let id = attempt.id.clone();
        move || {
            let session = self.lock();
            Arc::ptr_eq(&session.generation, &generation)
                && session.current_track.as_ref() == Some(&id)
                && !session.halted
        }
    }

    #[must_use]
    pub fn state(&self) -> CandidateSessionState {
        let session = self.lock();
        if session.halted {
            CandidateSessionState::Halted
        } else if session.current_track.is_none() {
            CandidateSessionState::Missing
        } else if session.replay_consumed {
            CandidateSessionState::AttemptConsumed
        } else {
            CandidateSessionState::Pending
        }
    }

    fn lock(&self) -> MutexGuard<'_, Session> {
        self.session
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }
}

impl<T: WebPlaybackTransport> AuthenticatedStandardCandidate<T> {
    /// No retry, redirect fallback, automatic login or persistence. Dropping the
    /// future after polling cannot refill the replay or capture budget.
    /// # Errors
    /// Revalidates owner generation before await and suppresses stale completion.
    pub async fn resolve_captured_once(
        &self,
        bound: BoundCapture,
    ) -> Result<StandardWebSource, WebPlaybackError> {
        {
            let mut session = self.lock();
            if !Arc::ptr_eq(&session.generation, &bound.generation)
                || session.current_track.as_ref() != Some(&bound.id)
            {
                return Err(WebPlaybackError::Replaced);
            }
            if session.halted {
                return Err(WebPlaybackError::RiskControl);
            }
            if session.replay_consumed {
                return Err(WebPlaybackError::AttemptConsumed);
            }
            session.replay_consumed = true;
        }
        let response = self.transport.send_web(&bound.request).await;
        let mut session = self.lock();
        if !Arc::ptr_eq(&session.generation, &bound.generation)
            || session.current_track.as_ref() != Some(&bound.id)
        {
            return Err(WebPlaybackError::Replaced);
        }
        let result = response.and_then(|response| decode_standard_source(&bound.request, response));
        if matches!(
            result,
            Err(WebPlaybackError::RiskControl | WebPlaybackError::RateLimited)
        ) {
            session.halted = true;
        }
        result
    }
}
