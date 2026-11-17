use std::sync::Arc;
use std::sync::atomic::Ordering;

use base64::Engine as _;
use netease_client::{Credential, CredentialRefreshError, Error, Transport};
use serde::{Deserialize, Serialize};

use super::NeteaseProvider;

const ROTATION_VERSION: u8 = 2;
const ROTATION_PROVIDER: &str = "netease-cloud-music";
const MAX_ROTATION_BYTES: usize = 24 * 1024;

fn session_diagnostic(message: std::fmt::Arguments<'_>) {
    if cfg!(debug_assertions)
        || matches!(
            std::env::var("FURA_SESSION_DIAGNOSTIC").as_deref(),
            Ok("1" | "true")
        )
    {
        eprintln!("FURA_SESSION_DIAGNOSTIC provider=netease-cloud-music {message}");
    }
}

const fn refresh_trigger_label(trigger: NeteaseRefreshTrigger) -> &'static str {
    match trigger {
        NeteaseRefreshTrigger::AuthenticatedReadRejection => "read_rejection",
        NeteaseRefreshTrigger::Checkpoint => "checkpoint",
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NeteaseRefreshTrigger {
    AuthenticatedReadRejection,
    Checkpoint,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NeteaseRefreshFailure {
    ProductionGateDisabled,
    NoCredential,
    NotDue,
    NotRefreshable,
    Network,
    RateLimited,
    RiskControl,
    SecondaryVerificationRequired,
    ServiceUnavailable,
    InvalidResponse,
    ReauthenticationRequired,
    Replaced,
    StorageUnavailable,
}

#[derive(Clone, Eq, PartialEq)]
pub struct NeteaseRefreshPreparation {
    pub reservation_id: u32,
    pub staged_secret_bytes: Vec<u8>,
}

impl std::fmt::Debug for NeteaseRefreshPreparation {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("NeteaseRefreshPreparation")
            .field("reservation_id", &self.reservation_id)
            .field(
                "staged_secret_bytes",
                &format_args!("[{} bytes]", self.staged_secret_bytes.len()),
            )
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NeteaseRefreshPrepareState {
    Candidate,
    ReusedNewGeneration,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NeteaseRefreshPrepareResult {
    pub state: NeteaseRefreshPrepareState,
    pub preparation: Option<NeteaseRefreshPreparation>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NeteaseStagedRecoveryAction {
    VerifyCandidate,
    VerifyCommittedCurrent,
    Stale,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct NeteaseStagedRecovery {
    pub action: NeteaseStagedRecoveryAction,
    pub reservation_id: Option<u32>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NeteaseStagedRecoveryError {
    UnsupportedVersion,
    InvalidDocument,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct StoredRotationV1 {
    version: u8,
    provider: String,
    source: String,
    candidate: String,
    source_user: u64,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct StoredRotationV2 {
    version: u8,
    provider: String,
    source: String,
    candidate: String,
    source_user: u64,
    identical_candidate: bool,
}

#[derive(Deserialize)]
struct StoredRotationHeader {
    version: u8,
}

#[derive(Clone, Debug)]
pub(crate) struct RefreshReservation {
    id: u32,
    source_generation: u64,
    source: Credential,
    source_user: u64,
    candidate: Credential,
    verified: bool,
    completed: Arc<tokio::sync::Notify>,
}

#[derive(Debug, Default)]
pub(crate) enum RefreshCoordinatorState {
    #[default]
    Idle,
    Active(Box<RefreshReservation>),
    Completed {
        source_generation: u64,
        installed_generation: Option<u64>,
        result: Result<(), NeteaseRefreshFailure>,
    },
}

fn lock_refresh<T>(
    provider: &NeteaseProvider<T>,
) -> std::sync::MutexGuard<'_, RefreshCoordinatorState> {
    provider
        .refresh
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn encode_rotation(
    source: &Credential,
    candidate: &Credential,
    source_user: u64,
) -> Result<Vec<u8>, NeteaseRefreshFailure> {
    let identical_candidate = source == candidate;
    let source = source
        .export()
        .map_err(|_| NeteaseRefreshFailure::InvalidResponse)?;
    let candidate = candidate
        .export()
        .map_err(|_| NeteaseRefreshFailure::InvalidResponse)?;
    let document = StoredRotationV2 {
        version: ROTATION_VERSION,
        provider: ROTATION_PROVIDER.into(),
        source: base64::engine::general_purpose::STANDARD_NO_PAD.encode(source),
        candidate: base64::engine::general_purpose::STANDARD_NO_PAD.encode(candidate),
        source_user,
        identical_candidate,
    };
    let bytes =
        serde_json::to_vec(&document).map_err(|_| NeteaseRefreshFailure::InvalidResponse)?;
    if bytes.len() > MAX_ROTATION_BYTES {
        return Err(NeteaseRefreshFailure::InvalidResponse);
    }
    Ok(bytes)
}

fn decode_rotation(
    bytes: &[u8],
) -> Result<(Credential, Credential, u64), NeteaseStagedRecoveryError> {
    if bytes.len() > MAX_ROTATION_BYTES {
        return Err(NeteaseStagedRecoveryError::InvalidDocument);
    }
    let header: StoredRotationHeader =
        serde_json::from_slice(bytes).map_err(|_| NeteaseStagedRecoveryError::InvalidDocument)?;
    let (provider, source, candidate, source_user, identical_candidate) = match header.version {
        1 => {
            let document: StoredRotationV1 = serde_json::from_slice(bytes)
                .map_err(|_| NeteaseStagedRecoveryError::InvalidDocument)?;
            (
                document.provider,
                document.source,
                document.candidate,
                document.source_user,
                false,
            )
        }
        ROTATION_VERSION => {
            let document: StoredRotationV2 = serde_json::from_slice(bytes)
                .map_err(|_| NeteaseStagedRecoveryError::InvalidDocument)?;
            (
                document.provider,
                document.source,
                document.candidate,
                document.source_user,
                document.identical_candidate,
            )
        }
        _ => return Err(NeteaseStagedRecoveryError::UnsupportedVersion),
    };
    if provider != ROTATION_PROVIDER {
        return Err(NeteaseStagedRecoveryError::InvalidDocument);
    }
    let source = base64::engine::general_purpose::STANDARD_NO_PAD
        .decode(source)
        .map_err(|_| NeteaseStagedRecoveryError::InvalidDocument)?;
    let candidate = base64::engine::general_purpose::STANDARD_NO_PAD
        .decode(candidate)
        .map_err(|_| NeteaseStagedRecoveryError::InvalidDocument)?;
    let source =
        Credential::import(&source).map_err(|_| NeteaseStagedRecoveryError::InvalidDocument)?;
    let candidate =
        Credential::import(&candidate).map_err(|_| NeteaseStagedRecoveryError::InvalidDocument)?;
    if (source == candidate) != identical_candidate {
        return Err(NeteaseStagedRecoveryError::InvalidDocument);
    }
    Ok((source, candidate, source_user))
}

const fn map_refresh_error(error: CredentialRefreshError) -> NeteaseRefreshFailure {
    match error {
        CredentialRefreshError::NotRefreshable => NeteaseRefreshFailure::NotRefreshable,
        CredentialRefreshError::Network => NeteaseRefreshFailure::Network,
        CredentialRefreshError::RateLimited => NeteaseRefreshFailure::RateLimited,
        CredentialRefreshError::RiskControl => NeteaseRefreshFailure::RiskControl,
        CredentialRefreshError::SecondaryVerificationRequired => {
            NeteaseRefreshFailure::SecondaryVerificationRequired
        }
        CredentialRefreshError::CredentialRejected => {
            NeteaseRefreshFailure::ReauthenticationRequired
        }
        CredentialRefreshError::ProtocolUnavailable => NeteaseRefreshFailure::ServiceUnavailable,
        CredentialRefreshError::InvalidResponse
        | CredentialRefreshError::IncompleteRotation
        | CredentialRefreshError::NoRotation => NeteaseRefreshFailure::InvalidResponse,
    }
}

const fn map_verification_error(error: Error) -> NeteaseRefreshFailure {
    match error {
        Error::CredentialRejected | Error::AuthenticationRequired => {
            NeteaseRefreshFailure::ReauthenticationRequired
        }
        Error::TemporaryNetworkFailure => NeteaseRefreshFailure::Network,
        Error::RateLimited => NeteaseRefreshFailure::RateLimited,
        Error::SecurityVerificationRequired => NeteaseRefreshFailure::RiskControl,
        Error::SecondaryVerificationRequired => {
            NeteaseRefreshFailure::SecondaryVerificationRequired
        }
        Error::ResponseShapeMismatch | Error::ResponseBound | Error::InputBound => {
            NeteaseRefreshFailure::InvalidResponse
        }
        Error::VerificationRejected
        | Error::AccountRestricted
        | Error::EntitlementDenied
        | Error::CopyrightRestricted
        | Error::RegionRestricted
        | Error::TrackUnavailable
        | Error::ProtocolUnavailable
        | Error::UpstreamUnknown => NeteaseRefreshFailure::ServiceUnavailable,
    }
}

impl<T: Transport> NeteaseProvider<T> {
    /// Starts or joins the one provider-owned refresh decision for the current
    /// rejected credential generation. A candidate is never installed here.
    ///
    /// # Errors
    /// Returns a typed gate, eligibility, transport, protocol, risk-control or
    /// session-generation failure without installing a candidate.
    #[allow(clippy::too_many_lines)] // One serial owner makes every decision edge auditable.
    pub async fn prepare_credential_refresh(
        &self,
        trigger: NeteaseRefreshTrigger,
    ) -> Result<NeteaseRefreshPrepareResult, NeteaseRefreshFailure> {
        loop {
            if matches!(trigger, NeteaseRefreshTrigger::Checkpoint) {
                let mut refresh = lock_refresh(self);
                if matches!(
                    &*refresh,
                    RefreshCoordinatorState::Completed {
                        result: Err(NeteaseRefreshFailure::Network
                            | NeteaseRefreshFailure::RateLimited
                            | NeteaseRefreshFailure::RiskControl
                            | NeteaseRefreshFailure::SecondaryVerificationRequired
                            | NeteaseRefreshFailure::ServiceUnavailable
                            | NeteaseRefreshFailure::InvalidResponse
                            | NeteaseRefreshFailure::StorageUnavailable),
                        ..
                    }
                ) {
                    *refresh = RefreshCoordinatorState::Idle;
                }
            }
            if matches!(trigger, NeteaseRefreshTrigger::AuthenticatedReadRejection) {
                let completed = {
                    let refresh = lock_refresh(self);
                    match &*refresh {
                        RefreshCoordinatorState::Completed {
                            source_generation,
                            installed_generation: Some(installed_generation),
                            result: Ok(()),
                        } => Some((*source_generation, *installed_generation)),
                        _ => None,
                    }
                };
                if let Some((source_generation, installed_generation)) = completed
                    && installed_generation > source_generation
                    && self.auth.generation() == installed_generation
                    && self.auth.snapshot().is_ok()
                {
                    return Ok(NeteaseRefreshPrepareResult {
                        state: NeteaseRefreshPrepareState::ReusedNewGeneration,
                        preparation: None,
                    });
                }
            }

            let Some((source_generation, source, source_user)) = self.auth.refresh_snapshot()
            else {
                return Err(match trigger {
                    NeteaseRefreshTrigger::AuthenticatedReadRejection => {
                        NeteaseRefreshFailure::NoCredential
                    }
                    NeteaseRefreshTrigger::Checkpoint => NeteaseRefreshFailure::NotDue,
                });
            };

            session_diagnostic(format_args!(
                "phase=refresh_prepare trigger={} allowed={} refresh_material_present={}",
                refresh_trigger_label(trigger),
                self.refresh_enabled,
                source.has_refresh_material()
            ));

            if !self.refresh_enabled {
                if matches!(trigger, NeteaseRefreshTrigger::AuthenticatedReadRejection) {
                    self.auth
                        .clear_refresh_source(source_generation, &source, source_user);
                }
                session_diagnostic(format_args!(
                    "phase=refresh_prepare trigger={} outcome=production_gate_disabled action={}",
                    refresh_trigger_label(trigger),
                    if matches!(trigger, NeteaseRefreshTrigger::AuthenticatedReadRejection) {
                        "signed_out"
                    } else {
                        "retained"
                    }
                ));
                return Err(NeteaseRefreshFailure::ProductionGateDisabled);
            }

            let wait = {
                let mut refresh = lock_refresh(self);
                match &*refresh {
                    RefreshCoordinatorState::Active(active)
                        if active.source_generation == source_generation =>
                    {
                        Some((
                            source_generation,
                            Arc::clone(&active.completed).notified_owned(),
                        ))
                    }
                    RefreshCoordinatorState::Completed {
                        source_generation: completed_generation,
                        result,
                        ..
                    } if *completed_generation == source_generation => {
                        return match result {
                            Ok(()) => Ok(NeteaseRefreshPrepareResult {
                                state: NeteaseRefreshPrepareState::ReusedNewGeneration,
                                preparation: None,
                            }),
                            Err(failure) => Err(*failure),
                        };
                    }
                    _ => {
                        let reservation_id = self
                            .next_refresh_reservation
                            .try_update(Ordering::SeqCst, Ordering::SeqCst, |current| {
                                Some(if current == u32::MAX { 1 } else { current + 1 })
                            })
                            .unwrap_or_else(std::convert::identity);
                        *refresh = RefreshCoordinatorState::Active(Box::new(RefreshReservation {
                            id: reservation_id,
                            source_generation,
                            source: source.clone(),
                            source_user,
                            candidate: source.clone(),
                            verified: false,
                            completed: Arc::new(tokio::sync::Notify::new()),
                        }));
                        None
                    }
                }
            };
            if let Some((waited_generation, completed)) = wait {
                completed.await;
                let completed_result = {
                    let refresh = lock_refresh(self);
                    match &*refresh {
                        RefreshCoordinatorState::Completed {
                            source_generation,
                            result,
                            ..
                        } if *source_generation == waited_generation => Some(*result),
                        RefreshCoordinatorState::Active(active)
                            if active.source_generation != waited_generation =>
                        {
                            return Err(NeteaseRefreshFailure::Replaced);
                        }
                        _ => None,
                    }
                };
                if let Some(Err(failure)) = completed_result {
                    return Err(failure);
                }
                continue;
            }

            let (candidate, observation) =
                match self.client.refresh_credential_observed(&source).await {
                    Ok(candidate) => candidate,
                    Err(error) => {
                        let failure = map_refresh_error(error);
                        session_diagnostic(format_args!(
                            "phase=refresh_request trigger={} outcome=failure failure={failure:?}",
                            refresh_trigger_label(trigger)
                        ));
                        self.finish_refresh_failure(source_generation, failure);
                        return Err(failure);
                    }
                };
            session_diagnostic(format_args!(
                "phase=refresh_response music_u_rotation={} music_r_u_rotation={} csrf_rotation={} candidate_next_refreshable={}",
                observation.music_u.label(),
                observation.music_r_u.label(),
                observation.csrf.label(),
                observation.candidate_next_refreshable
            ));
            let staged_secret_bytes = match encode_rotation(&source, &candidate, source_user) {
                Ok(bytes) => bytes,
                Err(failure) => {
                    self.finish_refresh_failure(source_generation, failure);
                    return Err(failure);
                }
            };

            if !self
                .auth
                .refresh_source_matches(source_generation, &source, source_user)
            {
                self.finish_refresh_failure(source_generation, NeteaseRefreshFailure::Replaced);
                return Err(NeteaseRefreshFailure::Replaced);
            }
            let mut refresh = lock_refresh(self);
            let RefreshCoordinatorState::Active(active) = &mut *refresh else {
                return Err(NeteaseRefreshFailure::Replaced);
            };
            if active.source_generation != source_generation
                || active.source != source
                || active.source_user != source_user
            {
                return Err(NeteaseRefreshFailure::Replaced);
            }
            active.candidate = candidate;
            session_diagnostic(format_args!(
                "phase=refresh_request trigger={} outcome=candidate_ready",
                refresh_trigger_label(trigger)
            ));
            return Ok(NeteaseRefreshPrepareResult {
                state: NeteaseRefreshPrepareState::Candidate,
                preparation: Some(NeteaseRefreshPreparation {
                    reservation_id: active.id,
                    staged_secret_bytes,
                }),
            });
        }
    }

    /// Verifies the staged candidate against the exact source account without
    /// installing it. Returned bytes are opaque platform-vault material.
    ///
    /// # Errors
    /// Returns typed verification, risk-control, response or replacement
    /// failures; an account mismatch is never accepted.
    pub async fn verify_staged_refresh_candidate(
        &self,
        reservation_id: u32,
    ) -> Result<Vec<u8>, NeteaseRefreshFailure> {
        let (source_generation, source, source_user, candidate) = {
            let refresh = lock_refresh(self);
            let RefreshCoordinatorState::Active(active) = &*refresh else {
                return Err(NeteaseRefreshFailure::Replaced);
            };
            if active.id != reservation_id {
                return Err(NeteaseRefreshFailure::Replaced);
            }
            (
                active.source_generation,
                active.source.clone(),
                active.source_user,
                active.candidate.clone(),
            )
        };

        let verification = self.client.account(&candidate).await;
        let failure = match verification {
            Ok(account) if account.id == source_user => None,
            Ok(_) => Some(NeteaseRefreshFailure::ReauthenticationRequired),
            Err(error) => Some(map_verification_error(error)),
        };

        let source_current =
            self.auth
                .refresh_source_matches(source_generation, &source, source_user);
        let mut refresh = lock_refresh(self);
        let RefreshCoordinatorState::Active(active) = &mut *refresh else {
            return Err(NeteaseRefreshFailure::Replaced);
        };
        if active.id != reservation_id
            || active.source_generation != source_generation
            || active.source != source
            || active.source_user != source_user
        {
            return Err(NeteaseRefreshFailure::Replaced);
        }
        if !source_current {
            let completed = Arc::clone(&active.completed);
            *refresh = RefreshCoordinatorState::Completed {
                source_generation,
                installed_generation: None,
                result: Err(NeteaseRefreshFailure::Replaced),
            };
            completed.notify_waiters();
            return Err(NeteaseRefreshFailure::Replaced);
        }
        if let Some(failure) = failure {
            session_diagnostic(format_args!(
                "phase=refresh_verify outcome=failure failure={failure:?}"
            ));
            let completed = Arc::clone(&active.completed);
            if failure == NeteaseRefreshFailure::ReauthenticationRequired {
                self.auth
                    .clear_refresh_source(source_generation, &source, source_user);
            }
            *refresh = RefreshCoordinatorState::Completed {
                source_generation,
                installed_generation: None,
                result: Err(failure),
            };
            completed.notify_waiters();
            return Err(failure);
        }
        let Ok(bytes) = candidate.export() else {
            let completed = Arc::clone(&active.completed);
            *refresh = RefreshCoordinatorState::Completed {
                source_generation,
                installed_generation: None,
                result: Err(NeteaseRefreshFailure::InvalidResponse),
            };
            completed.notify_waiters();
            return Err(NeteaseRefreshFailure::InvalidResponse);
        };
        active.verified = true;
        Ok(bytes)
    }

    /// Installs a verified candidate only after durable current-slot publish.
    ///
    /// # Errors
    /// Returns `Replaced` unless the reservation is verified and still owns
    /// the exact rejected source generation.
    pub fn commit_staged_refresh_candidate(
        &self,
        reservation_id: u32,
    ) -> Result<(), NeteaseRefreshFailure> {
        let mut refresh = lock_refresh(self);
        let RefreshCoordinatorState::Active(active) = &*refresh else {
            return Err(NeteaseRefreshFailure::Replaced);
        };
        if active.id != reservation_id || !active.verified {
            return Err(NeteaseRefreshFailure::Replaced);
        }
        let source_generation = active.source_generation;
        let source = active.source.clone();
        let source_user = active.source_user;
        let candidate = active.candidate.clone();
        let completed = Arc::clone(&active.completed);
        let Ok(installed_generation) =
            self.auth
                .install_refreshed(source_generation, &source, source_user, candidate)
        else {
            *refresh = RefreshCoordinatorState::Completed {
                source_generation,
                installed_generation: None,
                result: Err(NeteaseRefreshFailure::Replaced),
            };
            completed.notify_waiters();
            return Err(NeteaseRefreshFailure::Replaced);
        };
        *refresh = RefreshCoordinatorState::Completed {
            source_generation,
            installed_generation: Some(installed_generation),
            result: Ok(()),
        };
        completed.notify_waiters();
        session_diagnostic(format_args!("phase=refresh_commit outcome=installed"));
        Ok(())
    }

    /// Ends an in-process flight after a platform storage failure. The source
    /// credential and durable stage remain available for later recovery.
    ///
    /// # Errors
    /// Returns `Replaced` when the reservation no longer owns the active
    /// refresh decision.
    pub fn abort_credential_refresh(
        &self,
        reservation_id: u32,
    ) -> Result<(), NeteaseRefreshFailure> {
        let mut refresh = lock_refresh(self);
        let RefreshCoordinatorState::Active(active) = &*refresh else {
            return Err(NeteaseRefreshFailure::Replaced);
        };
        if active.id != reservation_id {
            return Err(NeteaseRefreshFailure::Replaced);
        }
        let source_generation = active.source_generation;
        let completed = Arc::clone(&active.completed);
        *refresh = RefreshCoordinatorState::Completed {
            source_generation,
            installed_generation: None,
            result: Err(NeteaseRefreshFailure::StorageUnavailable),
        };
        completed.notify_waiters();
        Ok(())
    }

    fn finish_refresh_failure(&self, source_generation: u64, failure: NeteaseRefreshFailure) {
        let mut refresh = lock_refresh(self);
        let RefreshCoordinatorState::Active(active) = &*refresh else {
            return;
        };
        if active.source_generation != source_generation {
            return;
        }
        let completed = Arc::clone(&active.completed);
        if matches!(
            failure,
            NeteaseRefreshFailure::ReauthenticationRequired | NeteaseRefreshFailure::NotRefreshable
        ) {
            self.auth.clear_refresh_source(
                active.source_generation,
                &active.source,
                active.source_user,
            );
        }
        *refresh = RefreshCoordinatorState::Completed {
            source_generation,
            installed_generation: None,
            result: Err(failure),
        };
        completed.notify_waiters();
    }

    /// Restores a durable source/candidate transaction without sending a
    /// request. Verification remains a separate bounded step.
    ///
    /// # Errors
    /// Rejects unsupported, malformed, foreign or contradictory stage
    /// documents before mutating the provider session.
    pub fn restore_staged_credential_rotation(
        &self,
        current_secret_bytes: Option<&[u8]>,
        staged_secret_bytes: &[u8],
    ) -> Result<NeteaseStagedRecovery, NeteaseStagedRecoveryError> {
        let (source, candidate, source_user) = decode_rotation(staged_secret_bytes)?;
        let Some(current_secret_bytes) = current_secret_bytes else {
            return Ok(NeteaseStagedRecovery {
                action: NeteaseStagedRecoveryAction::Stale,
                reservation_id: None,
            });
        };
        let current = Credential::import(current_secret_bytes)
            .map_err(|_| NeteaseStagedRecoveryError::InvalidDocument)?;
        let (action, runtime_source, runtime_candidate) = if current == source {
            (
                NeteaseStagedRecoveryAction::VerifyCandidate,
                source,
                candidate,
            )
        } else if current == candidate {
            (
                NeteaseStagedRecoveryAction::VerifyCommittedCurrent,
                current.clone(),
                current,
            )
        } else {
            return Ok(NeteaseStagedRecovery {
                action: NeteaseStagedRecoveryAction::Stale,
                reservation_id: None,
            });
        };
        let source_generation = self
            .auth
            .restore_refresh_source(runtime_source.clone(), source_user);
        let reservation_id = self
            .next_refresh_reservation
            .try_update(Ordering::SeqCst, Ordering::SeqCst, |current| {
                Some(if current == u32::MAX { 1 } else { current + 1 })
            })
            .unwrap_or_else(std::convert::identity);
        let mut refresh = lock_refresh(self);
        if let RefreshCoordinatorState::Active(active) = &*refresh {
            active.completed.notify_waiters();
        }
        *refresh = RefreshCoordinatorState::Active(Box::new(RefreshReservation {
            id: reservation_id,
            source_generation,
            source: runtime_source,
            source_user,
            candidate: runtime_candidate,
            verified: false,
            completed: Arc::new(tokio::sync::Notify::new()),
        }));
        Ok(NeteaseStagedRecovery {
            action,
            reservation_id: Some(reservation_id),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn credential(music_u: &str, music_r_u: &str) -> Credential {
        Credential::import(
            serde_json::to_vec(&serde_json::json!({
                "version": 2,
                "provider": ROTATION_PROVIDER,
                "music_u": music_u,
                "music_r_u": music_r_u,
                "csrf": "csrf",
            }))
            .expect("fixture")
            .as_slice(),
        )
        .expect("credential")
    }

    #[test]
    fn stage_round_trip_is_bound_to_source_candidate_and_user() {
        let source = credential("source", "refresh-source");
        let candidate = credential("candidate", "refresh-candidate");
        let bytes = encode_rotation(&source, &candidate, 42).expect("stage");
        let decoded = decode_rotation(&bytes).expect("decode");
        assert_eq!(decoded, (source, candidate, 42));
        assert!(!String::from_utf8_lossy(&bytes).contains("refresh-source"));
    }

    #[test]
    fn stage_supports_evidenced_identical_candidate_and_rejects_contradictions() {
        let source = credential("source", "refresh-source");
        let candidate = credential("candidate", "refresh-candidate");
        let bytes = encode_rotation(&source, &candidate, 42).expect("stage");
        let mut value: serde_json::Value = serde_json::from_slice(&bytes).expect("json");
        value["provider"] = serde_json::json!("qq-music");
        assert_eq!(
            decode_rotation(&serde_json::to_vec(&value).expect("json")),
            Err(NeteaseStagedRecoveryError::InvalidDocument)
        );
        value["provider"] = serde_json::json!(ROTATION_PROVIDER);
        value["version"] = serde_json::json!(3);
        assert_eq!(
            decode_rotation(&serde_json::to_vec(&value).expect("json")),
            Err(NeteaseStagedRecoveryError::UnsupportedVersion)
        );
        assert_eq!(
            decode_rotation(&vec![0; MAX_ROTATION_BYTES + 1]),
            Err(NeteaseStagedRecoveryError::InvalidDocument)
        );

        let identical = encode_rotation(&source, &source, 42).expect("identical stage");
        assert_eq!(
            decode_rotation(&identical).expect("evidenced identical candidate"),
            (source.clone(), source.clone(), 42)
        );
        let mut contradictory: serde_json::Value =
            serde_json::from_slice(&identical).expect("json");
        contradictory["identical_candidate"] = serde_json::json!(false);
        assert_eq!(
            decode_rotation(&serde_json::to_vec(&contradictory).expect("json")),
            Err(NeteaseStagedRecoveryError::InvalidDocument)
        );

        let legacy = StoredRotationV1 {
            version: 1,
            provider: ROTATION_PROVIDER.into(),
            source: base64::engine::general_purpose::STANDARD_NO_PAD
                .encode(source.export().expect("source")),
            candidate: base64::engine::general_purpose::STANDARD_NO_PAD
                .encode(candidate.export().expect("candidate")),
            source_user: 42,
        };
        assert_eq!(
            decode_rotation(&serde_json::to_vec(&legacy).expect("legacy")).expect("legacy decode"),
            (source, candidate, 42)
        );
    }
}
