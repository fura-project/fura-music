use std::fmt;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{LazyLock, Mutex as StdMutex};
use std::time::{SystemTime, UNIX_EPOCH};

use provider_api::{
    AccountSummaryError, AccountSummaryProvider, AuthenticationError, QrAuthenticationChannel,
    QrAuthenticationProgress, QrAuthenticationProvider, QrAuthenticationSession, QrImageFormat,
};
use provider_qqmusic::{
    QqMusicCredentialRestoreState as ProviderCredentialRestoreState, QqMusicProvider,
    QqMusicQrAuthenticationCancellation, QqMusicQrAuthenticationSession,
};
use qqmusic_client::{CredentialPersistenceError, QqMusicClient, ReqwestTransport};
use tokio::sync::{Mutex as AsyncMutex, Notify};

pub(crate) type NativeProvider = QqMusicProvider<ReqwestTransport>;
type NativeSession = QqMusicQrAuthenticationSession<ReqwestTransport>;

static QQ_MUSIC_PROVIDER: LazyLock<Result<NativeProvider, ()>> = LazyLock::new(|| {
    ReqwestTransport::new()
        .map(QqMusicClient::new)
        .map(QqMusicProvider::new)
        .map_err(|_| ())
});
static NEXT_START_ATTEMPT: AtomicU32 = AtomicU32::new(1);
static ACTIVE_START_ATTEMPT: StdMutex<Option<u32>> = StdMutex::new(None);

pub(crate) fn native_qq_music_provider() -> Result<&'static NativeProvider, ()> {
    QQ_MUSIC_PROVIDER.as_ref().map_err(|_| ())
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicQrImageFormat {
    Png,
    Jpeg,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicQrLoginChannel {
    Qq,
    Wechat,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicQrChallenge {
    pub image_format: QqMusicQrImageFormat,
    pub image_bytes: Vec<u8>,
}

impl fmt::Debug for QqMusicQrChallenge {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicQrChallenge")
            .field("image_format", &self.image_format)
            .field(
                "image_bytes",
                &format_args!("[{} bytes]", self.image_bytes.len()),
            )
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicQrLoginState {
    WaitingForScan,
    ScannedAwaitingConfirmation,
    Authenticated,
    Expired,
    Refused,
    TimedOut,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicQrLoginFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Rejected,
    Cancelled,
    Replaced,
    SessionClosed,
    SessionFinished,
    TimedOut,
    TooManyNetworkFailures,
    AdvanceAlreadyInProgress,
}

pub struct QqMusicQrLoginStart {
    pub session: Option<QqMusicQrLoginSessionHandle>,
    pub challenge: Option<QqMusicQrChallenge>,
    pub failure: Option<QqMusicQrLoginFailure>,
}

impl fmt::Debug for QqMusicQrLoginStart {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicQrLoginStart")
            .field("has_session", &self.session.is_some())
            .field("challenge", &self.challenge)
            .field("failure", &self.failure)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct QqMusicQrLoginUpdate {
    pub state: Option<QqMusicQrLoginState>,
    pub failure: Option<QqMusicQrLoginFailure>,
    pub session_active: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicCredentialExportFailure {
    NoAuthenticatedCredential,
    SerializationFailed,
}

pub struct QqMusicCredentialExport {
    pub secret_bytes: Option<Vec<u8>>,
    pub failure: Option<QqMusicCredentialExportFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicCredentialRestoreState {
    SignedOut,
    VerificationRequired,
    LocallyExpired,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicCredentialRestoreFailure {
    CoreUnavailable,
    InvalidDocument,
    UnsupportedVersion,
    InvalidCredential,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct QqMusicCredentialRestore {
    pub state: Option<QqMusicCredentialRestoreState>,
    pub failure: Option<QqMusicCredentialRestoreFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicCredentialVerificationState {
    Authenticated,
    Rejected,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicCredentialVerificationFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    NoRestoredCredential,
    Replaced,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct QqMusicCredentialVerification {
    pub state: Option<QqMusicCredentialVerificationState>,
    pub failure: Option<QqMusicCredentialVerificationFailure>,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicAccountSummary {
    pub display_name: String,
    pub avatar_uri: Option<String>,
}

impl fmt::Debug for QqMusicAccountSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicAccountSummary")
            .field("display_name", &"[REDACTED]")
            .field("has_avatar", &self.avatar_uri.is_some())
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicAccountSummaryFailure {
    CoreUnavailable,
    AuthenticationRequired,
    CredentialRejected,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Replaced,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct QqMusicAccountSummaryLoad {
    pub summary: Option<QqMusicAccountSummary>,
    pub failure: Option<QqMusicAccountSummaryFailure>,
}

impl fmt::Debug for QqMusicCredentialExport {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicCredentialExport")
            .field(
                "secret_bytes_length",
                &self.secret_bytes.as_ref().map(Vec::len),
            )
            .field("failure", &self.failure)
            .finish()
    }
}

/// Rust-owned login attempt. Flutter can advance or cancel it but cannot read
/// its UUID, OAuth code, credential, refresh material, or protocol client.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicQrLoginSessionHandle {
    session: AsyncMutex<NativeSession>,
    cancellation: QqMusicQrAuthenticationCancellation,
}

impl QqMusicQrLoginSessionHandle {
    pub async fn advance(&self) -> QqMusicQrLoginUpdate {
        let Ok(mut session) = self.session.try_lock() else {
            return QqMusicQrLoginUpdate {
                state: None,
                failure: Some(QqMusicQrLoginFailure::AdvanceAlreadyInProgress),
                session_active: self.cancellation.is_active(),
            };
        };

        match session.advance().await {
            Ok(progress) => QqMusicQrLoginUpdate {
                state: Some(map_progress(progress)),
                failure: None,
                session_active: session.is_active(),
            },
            Err(error) => QqMusicQrLoginUpdate {
                state: None,
                failure: Some(map_error(error)),
                session_active: session.is_active(),
            },
        }
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) -> bool {
        self.cancellation.cancel()
    }

    #[flutter_rust_bridge::frb(sync, getter)]
    pub fn is_active(&self) -> bool {
        self.cancellation.is_active()
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn reserve_qq_music_wechat_qr_login_start() -> u32 {
    NEXT_START_ATTEMPT
        .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |current| {
            Some(if current == u32::MAX { 1 } else { current + 1 })
        })
        .expect("start-attempt update closure always returns Some")
}

#[flutter_rust_bridge::frb(sync)]
pub fn reserve_qq_music_qr_login_start() -> u32 {
    reserve_qq_music_wechat_qr_login_start()
}

pub async fn start_qq_music_wechat_qr_login(attempt_id: u32) -> QqMusicQrLoginStart {
    start_qq_music_qr_login(attempt_id, QqMusicQrLoginChannel::Wechat).await
}

pub async fn start_qq_music_qr_login(
    attempt_id: u32,
    channel: QqMusicQrLoginChannel,
) -> QqMusicQrLoginStart {
    let Ok(provider) = QQ_MUSIC_PROVIDER.as_ref() else {
        return failed_start(QqMusicQrLoginFailure::CoreUnavailable);
    };
    *start_attempt_guard() = Some(attempt_id);
    let session = match provider
        .begin_qr_authentication(match channel {
            QqMusicQrLoginChannel::Qq => QrAuthenticationChannel::Qq,
            QqMusicQrLoginChannel::Wechat => QrAuthenticationChannel::Wechat,
        })
        .await
    {
        Ok(session) => session,
        Err(error) => {
            clear_start_attempt(attempt_id);
            return failed_start(map_error(error));
        }
    };
    clear_start_attempt(attempt_id);
    let challenge = session.challenge();
    let cancellation = session.cancellation_handle();

    QqMusicQrLoginStart {
        session: Some(QqMusicQrLoginSessionHandle {
            session: AsyncMutex::new(session),
            cancellation,
        }),
        challenge: Some(QqMusicQrChallenge {
            image_format: match challenge.image_format() {
                QrImageFormat::Png => QqMusicQrImageFormat::Png,
                QrImageFormat::Jpeg => QqMusicQrImageFormat::Jpeg,
            },
            image_bytes: challenge.image_bytes().to_vec(),
        }),
        failure: None,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn cancel_qq_music_wechat_qr_login_start(attempt_id: u32) -> bool {
    let mut active = start_attempt_guard();
    if *active != Some(attempt_id) {
        return false;
    }
    *active = None;
    QQ_MUSIC_PROVIDER
        .as_ref()
        .is_ok_and(QqMusicProvider::cancel_active_authentication)
}

#[flutter_rust_bridge::frb(sync)]
pub fn cancel_qq_music_qr_login_start(attempt_id: u32) -> bool {
    cancel_qq_music_wechat_qr_login_start(attempt_id)
}

#[flutter_rust_bridge::frb(sync)]
pub fn qq_music_has_authenticated_credential() -> bool {
    QQ_MUSIC_PROVIDER
        .as_ref()
        .is_ok_and(QrAuthenticationProvider::has_authenticated_credential)
}

/// One cancellable, single-use account-summary read. It owns no credential or
/// account identifier and returns only presentation-safe identity fields.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicAccountSummaryLoadHandle {
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl QqMusicAccountSummaryLoadHandle {
    pub async fn run(&self) -> QqMusicAccountSummaryLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_account_summary(QqMusicAccountSummaryFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_account_summary(QqMusicAccountSummaryFailure::AlreadyRunning);
        }
        let outcome = match native_qq_music_provider() {
            Ok(provider) => {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_account_summary(QqMusicAccountSummaryFailure::Cancelled)
                    }
                    result = provider.account_summary() => {
                        if self.active.load(Ordering::SeqCst) {
                            map_account_summary_load(result)
                        } else {
                            failed_account_summary(QqMusicAccountSummaryFailure::Cancelled)
                        }
                    }
                }
            }
            Err(()) => failed_account_summary(QqMusicAccountSummaryFailure::CoreUnavailable),
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
pub fn begin_qq_music_account_summary_load() -> QqMusicAccountSummaryLoadHandle {
    QqMusicAccountSummaryLoadHandle {
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_account_summary_load(
    result: Result<music_domain::AccountSummary, AccountSummaryError>,
) -> QqMusicAccountSummaryLoad {
    match result {
        Ok(summary) => QqMusicAccountSummaryLoad {
            summary: Some(QqMusicAccountSummary {
                display_name: summary.display_name().to_owned(),
                avatar_uri: summary.avatar_uri().map(str::to_owned),
            }),
            failure: None,
        },
        Err(error) => failed_account_summary(map_account_summary_failure(error)),
    }
}

/// Clears the process-local QQ Music credential and cancels authentication
/// work. The Flutter platform edge deletes the separately stored vault entry
/// only after this succeeds.
#[flutter_rust_bridge::frb(sync)]
pub fn sign_out_qq_music() -> bool {
    let Ok(provider) = QQ_MUSIC_PROVIDER.as_ref() else {
        return false;
    };
    *start_attempt_guard() = None;
    QrAuthenticationProvider::sign_out(provider);
    true
}

/// Produces a short-lived secret payload for immediate handoff to the platform
/// secure-storage plugin. Do not log, cache, or retain the returned bytes.
#[flutter_rust_bridge::frb(sync)]
pub fn export_qq_music_credential_for_secure_storage() -> QqMusicCredentialExport {
    let Ok(provider) = QQ_MUSIC_PROVIDER.as_ref() else {
        return QqMusicCredentialExport {
            secret_bytes: None,
            failure: Some(QqMusicCredentialExportFailure::NoAuthenticatedCredential),
        };
    };
    match provider.encode_authenticated_credential() {
        Ok(Some(secret_bytes)) => QqMusicCredentialExport {
            secret_bytes: Some(secret_bytes),
            failure: None,
        },
        Ok(None) => QqMusicCredentialExport {
            secret_bytes: None,
            failure: Some(QqMusicCredentialExportFailure::NoAuthenticatedCredential),
        },
        Err(_) => QqMusicCredentialExport {
            secret_bytes: None,
            failure: Some(QqMusicCredentialExportFailure::SerializationFailed),
        },
    }
}

/// Imports an optional platform-vault document into Rust and returns only the
/// safe next action. A present document is never considered authenticated
/// until a later QQ Music server-verification step succeeds.
#[flutter_rust_bridge::frb(sync)]
pub fn restore_qq_music_credential_from_secure_storage(
    secret_bytes: Option<Vec<u8>>,
) -> QqMusicCredentialRestore {
    let Ok(provider) = QQ_MUSIC_PROVIDER.as_ref() else {
        return failed_restore(QqMusicCredentialRestoreFailure::CoreUnavailable);
    };
    let Ok(now_unix_seconds) = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
    else {
        return failed_restore(QqMusicCredentialRestoreFailure::CoreUnavailable);
    };

    match provider.restore_credential_from_secure_storage(secret_bytes.as_deref(), now_unix_seconds)
    {
        Ok(state) => QqMusicCredentialRestore {
            state: Some(map_restore_state(state)),
            failure: None,
        },
        Err(error) => failed_restore(map_persistence_error(error)),
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn reserve_qq_music_credential_verification() -> Option<u32> {
    QQ_MUSIC_PROVIDER
        .as_ref()
        .ok()
        .and_then(QqMusicProvider::reserve_restored_credential_verification)
}

pub async fn verify_restored_qq_music_credential(attempt_id: u32) -> QqMusicCredentialVerification {
    let Ok(provider) = QQ_MUSIC_PROVIDER.as_ref() else {
        return failed_verification(QqMusicCredentialVerificationFailure::CoreUnavailable);
    };
    match provider.verify_restored_credential(attempt_id).await {
        Ok(()) => QqMusicCredentialVerification {
            state: Some(QqMusicCredentialVerificationState::Authenticated),
            failure: None,
        },
        Err(AuthenticationError::Rejected) => QqMusicCredentialVerification {
            state: Some(QqMusicCredentialVerificationState::Rejected),
            failure: None,
        },
        Err(error) => failed_verification(map_verification_failure(error)),
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn cancel_qq_music_credential_verification(attempt_id: u32) -> bool {
    QQ_MUSIC_PROVIDER
        .as_ref()
        .is_ok_and(|provider| provider.cancel_restored_credential_verification(attempt_id))
}

const fn failed_verification(
    failure: QqMusicCredentialVerificationFailure,
) -> QqMusicCredentialVerification {
    QqMusicCredentialVerification {
        state: None,
        failure: Some(failure),
    }
}

const fn failed_account_summary(
    failure: QqMusicAccountSummaryFailure,
) -> QqMusicAccountSummaryLoad {
    QqMusicAccountSummaryLoad {
        summary: None,
        failure: Some(failure),
    }
}

const fn failed_restore(failure: QqMusicCredentialRestoreFailure) -> QqMusicCredentialRestore {
    QqMusicCredentialRestore {
        state: None,
        failure: Some(failure),
    }
}

fn failed_start(failure: QqMusicQrLoginFailure) -> QqMusicQrLoginStart {
    QqMusicQrLoginStart {
        session: None,
        challenge: None,
        failure: Some(failure),
    }
}

fn start_attempt_guard() -> std::sync::MutexGuard<'static, Option<u32>> {
    ACTIVE_START_ATTEMPT
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn clear_start_attempt(attempt_id: u32) {
    let mut active = start_attempt_guard();
    if *active == Some(attempt_id) {
        *active = None;
    }
}

const fn map_progress(progress: QrAuthenticationProgress) -> QqMusicQrLoginState {
    match progress {
        QrAuthenticationProgress::WaitingForScan => QqMusicQrLoginState::WaitingForScan,
        QrAuthenticationProgress::ScannedAwaitingConfirmation => {
            QqMusicQrLoginState::ScannedAwaitingConfirmation
        }
        QrAuthenticationProgress::Authenticated => QqMusicQrLoginState::Authenticated,
        QrAuthenticationProgress::Expired => QqMusicQrLoginState::Expired,
        QrAuthenticationProgress::Refused => QqMusicQrLoginState::Refused,
        QrAuthenticationProgress::TimedOut => QqMusicQrLoginState::TimedOut,
    }
}

const fn map_error(error: AuthenticationError) -> QqMusicQrLoginFailure {
    match error {
        AuthenticationError::Network => QqMusicQrLoginFailure::Network,
        AuthenticationError::ServiceUnavailable => QqMusicQrLoginFailure::ServiceUnavailable,
        AuthenticationError::InvalidResponse => QqMusicQrLoginFailure::InvalidResponse,
        AuthenticationError::Rejected => QqMusicQrLoginFailure::Rejected,
        AuthenticationError::Cancelled => QqMusicQrLoginFailure::Cancelled,
        AuthenticationError::Replaced => QqMusicQrLoginFailure::Replaced,
        AuthenticationError::SessionClosed => QqMusicQrLoginFailure::SessionClosed,
        AuthenticationError::SessionFinished => QqMusicQrLoginFailure::SessionFinished,
        AuthenticationError::TimedOut => QqMusicQrLoginFailure::TimedOut,
        AuthenticationError::TooManyNetworkFailures => {
            QqMusicQrLoginFailure::TooManyNetworkFailures
        }
    }
}

const fn map_account_summary_failure(error: AccountSummaryError) -> QqMusicAccountSummaryFailure {
    match error {
        AccountSummaryError::AuthenticationRequired => {
            QqMusicAccountSummaryFailure::AuthenticationRequired
        }
        AccountSummaryError::CredentialRejected => QqMusicAccountSummaryFailure::CredentialRejected,
        AccountSummaryError::Network => QqMusicAccountSummaryFailure::Network,
        AccountSummaryError::ServiceUnavailable => QqMusicAccountSummaryFailure::ServiceUnavailable,
        AccountSummaryError::InvalidResponse => QqMusicAccountSummaryFailure::InvalidResponse,
        AccountSummaryError::Replaced => QqMusicAccountSummaryFailure::Replaced,
    }
}

const fn map_restore_state(state: ProviderCredentialRestoreState) -> QqMusicCredentialRestoreState {
    match state {
        ProviderCredentialRestoreState::SignedOut => QqMusicCredentialRestoreState::SignedOut,
        ProviderCredentialRestoreState::VerificationRequired => {
            QqMusicCredentialRestoreState::VerificationRequired
        }
        ProviderCredentialRestoreState::LocallyExpired => {
            QqMusicCredentialRestoreState::LocallyExpired
        }
    }
}

const fn map_persistence_error(
    error: CredentialPersistenceError,
) -> QqMusicCredentialRestoreFailure {
    match error {
        CredentialPersistenceError::Serialize => QqMusicCredentialRestoreFailure::CoreUnavailable,
        CredentialPersistenceError::InvalidDocument => {
            QqMusicCredentialRestoreFailure::InvalidDocument
        }
        CredentialPersistenceError::UnsupportedVersion(_) => {
            QqMusicCredentialRestoreFailure::UnsupportedVersion
        }
        CredentialPersistenceError::InvalidLoginType(_)
        | CredentialPersistenceError::InvalidCredential(_)
        | CredentialPersistenceError::InvalidExpiry(_) => {
            QqMusicCredentialRestoreFailure::InvalidCredential
        }
    }
}

const fn map_verification_failure(
    error: AuthenticationError,
) -> QqMusicCredentialVerificationFailure {
    match error {
        AuthenticationError::Network => QqMusicCredentialVerificationFailure::Network,
        AuthenticationError::ServiceUnavailable => {
            QqMusicCredentialVerificationFailure::ServiceUnavailable
        }
        AuthenticationError::InvalidResponse => {
            QqMusicCredentialVerificationFailure::InvalidResponse
        }
        AuthenticationError::SessionFinished => {
            QqMusicCredentialVerificationFailure::NoRestoredCredential
        }
        AuthenticationError::Replaced | AuthenticationError::Cancelled => {
            QqMusicCredentialVerificationFailure::Replaced
        }
        AuthenticationError::Rejected
        | AuthenticationError::SessionClosed
        | AuthenticationError::TimedOut
        | AuthenticationError::TooManyNetworkFailures => {
            QqMusicCredentialVerificationFailure::CoreUnavailable
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        QqMusicAccountSummary, QqMusicAccountSummaryFailure, QqMusicCredentialExport,
        QqMusicCredentialRestoreFailure, QqMusicCredentialVerificationFailure, QqMusicQrChallenge,
        QqMusicQrImageFormat, QqMusicQrLoginFailure, begin_qq_music_account_summary_load,
        clear_start_attempt, failed_start, map_account_summary_failure, map_error,
        map_persistence_error, map_verification_failure, reserve_qq_music_wechat_qr_login_start,
        start_attempt_guard,
    };
    use provider_api::{AccountSummaryError, AuthenticationError};
    use qqmusic_client::{CredentialPersistenceError, InvalidCredential};

    #[test]
    fn bridge_failure_mapping_is_typed_and_complete() {
        assert_eq!(
            map_error(AuthenticationError::Network),
            QqMusicQrLoginFailure::Network
        );
        assert_eq!(
            map_error(AuthenticationError::TooManyNetworkFailures),
            QqMusicQrLoginFailure::TooManyNetworkFailures
        );
        let outcome = failed_start(QqMusicQrLoginFailure::InvalidResponse);
        assert!(outcome.session.is_none());
        assert!(outcome.challenge.is_none());
        assert_eq!(
            outcome.failure,
            Some(QqMusicQrLoginFailure::InvalidResponse)
        );
    }

    #[test]
    fn bridge_challenge_debug_output_does_not_dump_image_bytes() {
        let challenge = QqMusicQrChallenge {
            image_format: QqMusicQrImageFormat::Png,
            image_bytes: b"private-qr-bytes".to_vec(),
        };

        let debug = format!("{challenge:?}");
        assert!(debug.contains("16 bytes"));
        assert!(!debug.contains("private"));
    }

    #[test]
    fn credential_export_debug_output_redacts_secret_bytes() {
        let export = QqMusicCredentialExport {
            secret_bytes: Some(b"private-music-key".to_vec()),
            failure: None,
        };

        let debug = format!("{export:?}");
        assert!(debug.contains("17"));
        assert!(!debug.contains("private"));
    }

    #[test]
    fn account_summary_bridge_is_typed_and_redacts_debug_output() {
        let summary = QqMusicAccountSummary {
            display_name: "Synthetic listener".into(),
            avatar_uri: Some("https://example.invalid/avatar.jpg".into()),
        };
        let debug = format!("{summary:?}");
        assert!(!debug.contains("Synthetic listener"));
        assert!(!debug.contains("avatar.jpg"));
        assert_eq!(
            map_account_summary_failure(AccountSummaryError::CredentialRejected),
            QqMusicAccountSummaryFailure::CredentialRejected
        );
        assert_eq!(
            map_account_summary_failure(AccountSummaryError::Replaced),
            QqMusicAccountSummaryFailure::Replaced
        );
    }

    #[tokio::test]
    async fn account_summary_load_cancellation_is_exact_and_terminal() {
        let handle = begin_qq_music_account_summary_load();
        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let result = handle.run().await;
        assert!(result.summary.is_none());
        assert_eq!(
            result.failure,
            Some(QqMusicAccountSummaryFailure::Cancelled)
        );
    }

    #[test]
    fn credential_restore_failure_mapping_is_typed_and_secret_free() {
        assert_eq!(
            map_persistence_error(CredentialPersistenceError::InvalidDocument),
            QqMusicCredentialRestoreFailure::InvalidDocument,
        );
        assert_eq!(
            map_persistence_error(CredentialPersistenceError::UnsupportedVersion(99)),
            QqMusicCredentialRestoreFailure::UnsupportedVersion,
        );
        assert_eq!(
            map_persistence_error(CredentialPersistenceError::InvalidCredential(
                InvalidCredential::MissingMusicKey,
            )),
            QqMusicCredentialRestoreFailure::InvalidCredential,
        );
    }

    #[test]
    fn credential_verification_failure_mapping_is_precise() {
        assert_eq!(
            map_verification_failure(AuthenticationError::Network),
            QqMusicCredentialVerificationFailure::Network,
        );
        assert_eq!(
            map_verification_failure(AuthenticationError::ServiceUnavailable),
            QqMusicCredentialVerificationFailure::ServiceUnavailable,
        );
        assert_eq!(
            map_verification_failure(AuthenticationError::SessionFinished),
            QqMusicCredentialVerificationFailure::NoRestoredCredential,
        );
        assert_eq!(
            map_verification_failure(AuthenticationError::Replaced),
            QqMusicCredentialVerificationFailure::Replaced,
        );
    }

    #[test]
    fn stale_start_attempt_cannot_clear_its_replacement() {
        let first = reserve_qq_music_wechat_qr_login_start();
        let second = reserve_qq_music_wechat_qr_login_start();
        assert_ne!(first, second);
        *start_attempt_guard() = Some(second);

        clear_start_attempt(first);
        assert_eq!(*start_attempt_guard(), Some(second));

        clear_start_attempt(second);
        assert_eq!(*start_attempt_guard(), None);
    }
}
