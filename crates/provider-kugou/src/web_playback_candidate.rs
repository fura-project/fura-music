//! One-shot experimental owner, disconnected from production resolution/authentication.
//! Capture admission is consumed synchronously BEFORE the caller opens CDP. Replay
//! is separately consumed before transport await. Neither budget is replenished.

use crate::decode_track_context;
use kugou_client::web_playback_candidate::songinfo_stages::{
    ServerIssuedIdentity, Stage1Decoded, Stage1Fulfillment, decode_stage1,
};
use kugou_client::web_playback_candidate::{
    CapturedWebRequest, OfficialWebCapture, StandardWebSource, WebPlaybackError,
    WebPlaybackTransport, WebTrackContext, decode_standard_source,
};
use music_domain::TrackId;
use std::{
    fmt,
    sync::{Arc, Mutex, MutexGuard},
};

/// Separate one-shot Stage 1 and Stage 2 admissions; never a retry allowance.
pub const MAX_SONGINFO_REQUESTS: usize = 2;
const STAGE1: usize = 0;
const STAGE2: usize = 1;

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
    songinfo_consumed: [bool; MAX_SONGINFO_REQUESTS],
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

/// One Stage 1 upstream reservation. It cannot be cloned or reused as Stage 2.
pub struct BoundStage1 {
    generation: Arc<()>,
    id: TrackId,
    request: CapturedWebRequest,
}

/// Server-issued identity and original representation, bound to this session owner.
pub struct Stage1Continuation {
    generation: Arc<()>,
    id: TrackId,
    identity: ServerIssuedIdentity,
    fulfillment: Stage1Fulfillment,
}

pub enum Stage1Progress {
    Direct(StandardWebSource),
    Continue(Box<Stage1Continuation>),
}

macro_rules! opaque_debug {
    ($($name:ty),+ $(,)?)=>{$(impl fmt::Debug for $name {fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result {f.write_str(concat!(stringify!($name),"([REDACTED])"))}})+};
}
opaque_debug!(BoundStage1, Stage1Continuation, Stage1Progress);

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
                songinfo_consumed: [false; MAX_SONGINFO_REQUESTS],
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

    /// # Errors
    /// Bind the paused hash request before the first upstream await. Album is
    /// optional on the wire, but supplied comparable identity must match exactly.
    pub fn bind_stage1(
        &self,
        attempt: CaptureAttempt,
        capture: OfficialWebCapture,
        now: u64,
    ) -> Result<BoundStage1, WebPlaybackError> {
        self.require_current(&attempt.generation, &attempt.id)?;
        let request = capture.bind_stage1(attempt.track, now)?;
        Ok(BoundStage1 {
            generation: attempt.generation,
            id: attempt.id,
            request,
        })
    }

    fn require_current(&self, generation: &Arc<()>, id: &TrackId) -> Result<(), WebPlaybackError> {
        let session = self.lock();
        if !Arc::ptr_eq(&session.generation, generation)
            || session.current_track.as_ref() != Some(id)
        {
            return Err(WebPlaybackError::Replaced);
        }
        if session.halted {
            return Err(WebPlaybackError::RiskControl);
        }
        Ok(())
    }

    /// # Errors
    /// Never deliver a stale first response back into an already-retired browser.
    pub fn stage1_fulfillment<'a>(
        &self,
        continuation: &'a Stage1Continuation,
    ) -> Result<&'a Stage1Fulfillment, WebPlaybackError> {
        self.require_current(&continuation.generation, &continuation.id)?;
        Ok(&continuation.fulfillment)
    }

    /// # Errors
    /// The second capture must equal this owner's server-issued identity and session.
    pub fn bind_stage2(
        &self,
        continuation: Box<Stage1Continuation>,
        capture: OfficialWebCapture,
        now: u64,
    ) -> Result<BoundCapture, WebPlaybackError> {
        let continuation = *continuation;
        self.require_current(&continuation.generation, &continuation.id)?;
        let request = continuation.identity.bind_second(capture, now)?;
        Ok(BoundCapture {
            generation: continuation.generation,
            id: continuation.id,
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
        } else if session.songinfo_consumed[STAGE2] {
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
    /// # Errors
    /// Consume Stage 1 before await. Failure/cancellation never refunds it. The
    /// one full-response direct branch never falls back to an encoded attempt.
    pub async fn resolve_stage1_once(
        &self,
        bound: BoundStage1,
    ) -> Result<Stage1Progress, WebPlaybackError> {
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
            if session.songinfo_consumed.iter().any(|spent| *spent) {
                return Err(WebPlaybackError::AttemptConsumed);
            }
            session.songinfo_consumed[STAGE1] = true;
        }
        let response = self.transport.send_stage1(&bound.request).await;
        let mut session = self.lock();
        if !Arc::ptr_eq(&session.generation, &bound.generation)
            || session.current_track.as_ref() != Some(&bound.id)
        {
            return Err(WebPlaybackError::Replaced);
        }
        if let Ok(response) = &response {
            report_stage1_response(response.identity_presence());
        }
        let result = response.and_then(|wire| decode_stage1(bound.request, wire));
        if matches!(
            result,
            Err(WebPlaybackError::RiskControl | WebPlaybackError::RateLimited)
        ) {
            session.halted = true;
        }
        match result? {
            Stage1Decoded::Direct(source) => {
                session.songinfo_consumed[STAGE2] = true;
                Ok(Stage1Progress::Direct(source))
            }
            Stage1Decoded::Continue(identity, fulfillment) => {
                Ok(Stage1Progress::Continue(Box::new(Stage1Continuation {
                    generation: bound.generation,
                    id: bound.id,
                    identity,
                    fulfillment,
                })))
            }
        }
    }

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
            if session.songinfo_consumed[STAGE2] {
                return Err(WebPlaybackError::AttemptConsumed);
            }
            session.songinfo_consumed[STAGE2] = true;
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

fn report_stage1_response(
    presence: kugou_client::web_playback_candidate::songinfo_stages::IdentityPresence,
) {
    // A fixed shape observation only. No account, track, encoded ID or response is logged.
    use std::io::Write as _;
    let _ =
        writeln!(std::io::stdout().lock(),
        "{}",
        presence.diagnostic(
            kugou_client::web_playback_candidate::songinfo_stages::IdentityStage::Stage1Response
        )
    );
}
