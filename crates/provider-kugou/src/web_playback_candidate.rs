//! One-shot experimental owner. Not wired to `MediaResolver`, Authentication,
//! `BuiltInProvider`, Bridge or UI. Pending material is never called Authenticated.

use crate::decode_track_context;
use kugou_client::web_playback_candidate::{
    ApprovedWebMediaHost, CapturedWebRequest, OfficialWebCredential, StandardWebSource,
    WebPlaybackError, WebPlaybackTransport, WebTrackContext, decode_standard_source,
};
use music_domain::TrackId;
use std::sync::{Arc, Mutex, MutexGuard};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CandidateSessionState {
    Missing,
    Pending,
    AttemptConsumed,
    Halted,
}

struct Session {
    generation: Arc<()>,
    pending: Option<OfficialWebCredential>,
    consumed: bool,
    halted: bool,
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
                pending: None,
                consumed: false,
                halted: false,
            }),
        }
    }

    /// Stage only. No login, account read, vault access or verification is performed.
    /// # Errors
    /// Invalid input preserves the previous candidate.
    pub fn stage_official_web_session(
        &self,
        origin: &str,
        cookie_header: &str,
    ) -> Result<(), WebPlaybackError> {
        let credential = OfficialWebCredential::from_cookie_header(origin, cookie_header)?;
        let mut session = self.lock();
        session.generation = Arc::new(());
        session.pending = Some(credential);
        // A risk-control stop is sticky for this experiment owner, even across
        // account replacement. Create no replacement owner to bypass a challenge.
        Ok(())
    }

    /// Logout, provider replacement and cancellation retire pending async work.
    pub fn clear(&self) {
        let mut session = self.lock();
        session.generation = Arc::new(());
        session.pending = None;
    }

    #[must_use]
    pub fn state(&self) -> CandidateSessionState {
        let session = self.lock();
        if session.halted {
            CandidateSessionState::Halted
        } else if session.pending.is_none() {
            CandidateSessionState::Missing
        } else if session.consumed {
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
    /// Exactly one attempt per experiment owner, including transport failures
    /// and dropped futures. No fallback, retry, automatic login or persistence.
    /// # Errors
    /// Rejects foreign IDs before IO and suppresses every old-session completion.
    pub async fn resolve_once(
        &self,
        id: &TrackId,
        captured_url: &str,
        approved_media_host: &str,
        now_seconds: u64,
    ) -> Result<StandardWebSource, WebPlaybackError> {
        let context = decode_track_context(id).map_err(|_| WebPlaybackError::InvalidCapture)?;
        let track = WebTrackContext::new(
            &context.mix_song_id,
            &context.standard_hash,
            context
                .album_id
                .as_deref()
                .ok_or(WebPlaybackError::ProtocolUnsupported)?,
            context.duration_seconds,
        )?;
        let (generation, request) = {
            let mut session = self.lock();
            if session.halted {
                return Err(WebPlaybackError::RiskControl);
            }
            let credential = session
                .pending
                .as_ref()
                .ok_or(WebPlaybackError::LoginRequired)?;
            if session.consumed {
                return Err(WebPlaybackError::AttemptConsumed);
            }
            let request = CapturedWebRequest::new(
                captured_url,
                credential,
                track,
                ApprovedWebMediaHost::new(approved_media_host)?,
                now_seconds,
            )?;
            session.consumed = true;
            (Arc::clone(&session.generation), request)
        };
        let response = self.transport.send_web(&request).await;
        let mut session = self.lock();
        if !Arc::ptr_eq(&session.generation, &generation) {
            return Err(WebPlaybackError::Replaced);
        }
        let result = response.and_then(|response| decode_standard_source(&request, response));
        if matches!(
            result,
            Err(WebPlaybackError::RiskControl | WebPlaybackError::RateLimited)
        ) {
            session.halted = true;
        }
        result
    }
}
