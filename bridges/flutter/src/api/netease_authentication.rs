use std::fmt;
use std::sync::Mutex as StdMutex;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};

use netease_client::HttpsTransport;
use provider_api::{
    AccountSummaryError, AuthenticationError, QrAuthenticationChannel, QrAuthenticationProgress,
    QrAuthenticationProvider, QrAuthenticationSession, QrImageFormat, SmsAuthenticationError,
    SmsAuthenticationProvider,
};
use provider_netease::{NeteaseQrCancellation, NeteaseQrSession};
use tokio::sync::Mutex as AsyncMutex;

use super::authentication::{
    QqMusicCredentialExport, QqMusicCredentialExportFailure, QqMusicCredentialRestore,
    QqMusicCredentialRestoreFailure, QqMusicCredentialRestoreState, QqMusicCredentialVerification,
    QqMusicCredentialVerificationFailure, QqMusicCredentialVerificationState, QqMusicQrChallenge,
    QqMusicQrImageFormat, QqMusicQrLoginFailure, QqMusicQrLoginState, QqMusicQrLoginUpdate,
};

type NativeSession = NeteaseQrSession<HttpsTransport>;

static NEXT_ATTEMPT: AtomicU32 = AtomicU32::new(1);
static ACTIVE_START: StdMutex<Option<u32>> = StdMutex::new(None);
static ACTIVE_VERIFICATION: StdMutex<Option<u32>> = StdMutex::new(None);
static ACTIVE_SMS_SEND: StdMutex<Option<u32>> = StdMutex::new(None);
static ACTIVE_SMS_LOGIN: StdMutex<Option<u32>> = StdMutex::new(None);
static ACTIVE_SYSTEM_BROWSER: StdMutex<Option<u32>> = StdMutex::new(None);
static SYSTEM_BROWSER_GATE: AsyncMutex<()> = AsyncMutex::const_new(());

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NeteaseSmsAuthenticationFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    InvalidInput,
    CodeRejected,
    RateLimited,
    SecurityVerificationRequired,
    SecondaryVerificationRequired,
    Replaced,
    AlreadyRunning,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct NeteaseSmsAuthenticationOutcome {
    pub success: bool,
    pub failure: Option<NeteaseSmsAuthenticationFailure>,
}

pub struct NeteaseQrLoginStart {
    pub session: Option<NeteaseQrLoginSessionHandle>,
    pub challenge: Option<QqMusicQrChallenge>,
    pub external_confirmation_url: Option<String>,
    pub failure: Option<QqMusicQrLoginFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NeteaseSystemBrowserAuthenticationFailure {
    UnsupportedPlatform,
    BrowserUnavailable,
    BrowserLaunchFailed,
    ProfileSetupFailed,
    DevtoolsUnavailable,
    DevtoolsInvalid,
    OfficialTargetUnavailable,
    BrowserClosed,
    InvalidCredential,
    TimedOut,
    Cancelled,
    CleanupFailed,
    Rejected,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Replaced,
    CoreUnavailable,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct NeteaseSystemBrowserAuthenticationOutcome {
    pub authenticated: bool,
    pub failure: Option<NeteaseSystemBrowserAuthenticationFailure>,
}

impl fmt::Debug for NeteaseQrLoginStart {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("NeteaseQrLoginStart")
            .field("has_session", &self.session.is_some())
            .field("challenge", &self.challenge)
            .field(
                "has_external_confirmation_url",
                &self.external_confirmation_url.is_some(),
            )
            .field("failure", &self.failure)
            .finish()
    }
}

#[flutter_rust_bridge::frb(opaque)]
pub struct NeteaseQrLoginSessionHandle {
    session: AsyncMutex<NativeSession>,
    cancellation: NeteaseQrCancellation,
    active: AtomicBool,
}

impl NeteaseQrLoginSessionHandle {
    pub async fn advance(&self) -> QqMusicQrLoginUpdate {
        let Ok(mut session) = self.session.try_lock() else {
            return QqMusicQrLoginUpdate {
                state: None,
                failure: Some(QqMusicQrLoginFailure::AdvanceAlreadyInProgress),
                session_active: self.active.load(Ordering::SeqCst),
            };
        };
        let update = match session.advance().await {
            Ok(progress) => QqMusicQrLoginUpdate {
                state: Some(map_progress(progress)),
                failure: None,
                session_active: session.is_active(),
            },
            Err(error) => QqMusicQrLoginUpdate {
                state: None,
                failure: Some(map_auth_error(error)),
                session_active: session.is_active(),
            },
        };
        self.active.store(update.session_active, Ordering::SeqCst);
        update
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) -> bool {
        let was_active = self.active.swap(false, Ordering::SeqCst);
        was_active && self.cancellation.cancel()
    }

    #[flutter_rust_bridge::frb(sync, getter)]
    pub fn is_active(&self) -> bool {
        self.active.load(Ordering::SeqCst)
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn reserve_netease_qr_login_start() -> u32 {
    let attempt = next_attempt();
    *lock_attempt(&ACTIVE_START) = Some(attempt);
    attempt
}

pub async fn start_netease_qr_login(attempt_id: u32) -> NeteaseQrLoginStart {
    if *lock_attempt(&ACTIVE_START) != Some(attempt_id) {
        return failed_start(QqMusicQrLoginFailure::Replaced);
    }
    let Ok(provider) = crate::native_netease::native_netease_provider() else {
        clear_attempt(&ACTIVE_START, attempt_id);
        return failed_start(QqMusicQrLoginFailure::CoreUnavailable);
    };
    let session = match provider
        .begin_qr_authentication(QrAuthenticationChannel::ProviderDefault)
        .await
    {
        Ok(session) => session,
        Err(error) => {
            clear_attempt(&ACTIVE_START, attempt_id);
            return failed_start(map_auth_error(error));
        }
    };
    if *lock_attempt(&ACTIVE_START) != Some(attempt_id) {
        session.cancel();
        return failed_start(QqMusicQrLoginFailure::Replaced);
    }
    clear_attempt(&ACTIVE_START, attempt_id);
    let external_confirmation_url = session.external_confirmation_url().to_owned();
    let challenge = session.challenge();
    let cancellation = session.cancellation_handle();
    NeteaseQrLoginStart {
        session: Some(NeteaseQrLoginSessionHandle {
            session: AsyncMutex::new(session),
            cancellation,
            active: AtomicBool::new(true),
        }),
        challenge: Some(QqMusicQrChallenge {
            image_format: match challenge.image_format() {
                QrImageFormat::Png => QqMusicQrImageFormat::Png,
                QrImageFormat::Jpeg => QqMusicQrImageFormat::Jpeg,
            },
            image_bytes: challenge.image_bytes().to_vec(),
        }),
        external_confirmation_url: Some(external_confirmation_url),
        failure: None,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn cancel_netease_qr_login_start(attempt_id: u32) -> bool {
    let mut active = lock_attempt(&ACTIVE_START);
    if *active != Some(attempt_id) {
        return false;
    }
    *active = None;
    true
}

#[flutter_rust_bridge::frb(sync)]
pub fn netease_has_authenticated_credential() -> bool {
    crate::native_netease::native_netease_provider()
        .is_ok_and(QrAuthenticationProvider::has_authenticated_credential)
}

/// Whether a supported, root-owned Chromium-family binary is available on
/// Linux. This never starts the browser or inspects any browser profile.
#[flutter_rust_bridge::frb(sync)]
pub fn netease_system_browser_login_supported() -> bool {
    #[cfg(target_os = "linux")]
    {
        crate::linux_system_chromium::is_supported()
    }
    #[cfg(not(target_os = "linux"))]
    {
        false
    }
}

/// Reserves a single serialized system-browser attempt. A newer reservation
/// replaces an older attempt, whose owner will close its browser and profile.
#[flutter_rust_bridge::frb(sync)]
pub fn reserve_netease_system_browser_login() -> u32 {
    let attempt = next_attempt();
    *lock_attempt(&ACTIVE_SYSTEM_BROWSER) = Some(attempt);
    attempt
}

/// Runs the complete Linux official-browser path. Raw browser Cookie values
/// stay in Rust: they are staged, zeroed, and verified before this function
/// returns a coarse result to Dart.
pub async fn authenticate_netease_with_system_browser(
    attempt_id: u32,
) -> NeteaseSystemBrowserAuthenticationOutcome {
    if *lock_attempt(&ACTIVE_SYSTEM_BROWSER) != Some(attempt_id) {
        return failed_system_browser(NeteaseSystemBrowserAuthenticationFailure::Replaced);
    }
    let _gate = SYSTEM_BROWSER_GATE.lock().await;
    if *lock_attempt(&ACTIVE_SYSTEM_BROWSER) != Some(attempt_id) {
        return failed_system_browser(classify_system_browser_cancellation(attempt_id));
    }

    #[cfg(not(target_os = "linux"))]
    let capture: Result<Vec<u8>, NeteaseSystemBrowserAuthenticationFailure> =
        Err(NeteaseSystemBrowserAuthenticationFailure::UnsupportedPlatform);
    #[cfg(target_os = "linux")]
    let capture = crate::linux_system_chromium::capture_netease_credential(|| {
        *lock_attempt(&ACTIVE_SYSTEM_BROWSER) == Some(attempt_id)
    })
    .await
    .map_err(map_system_browser_capture_failure);

    let mut secret_bytes = match capture {
        Ok(secret_bytes) => secret_bytes,
        Err(failure) => {
            let failure = if failure == NeteaseSystemBrowserAuthenticationFailure::Cancelled {
                classify_system_browser_cancellation(attempt_id)
            } else {
                failure
            };
            clear_attempt(&ACTIVE_SYSTEM_BROWSER, attempt_id);
            return failed_system_browser(failure);
        }
    };
    if *lock_attempt(&ACTIVE_SYSTEM_BROWSER) != Some(attempt_id) {
        secret_bytes.fill(0);
        return failed_system_browser(classify_system_browser_cancellation(attempt_id));
    }
    let Ok(provider) = crate::native_netease::native_netease_provider() else {
        secret_bytes.fill(0);
        clear_attempt(&ACTIVE_SYSTEM_BROWSER, attempt_id);
        return failed_system_browser(NeteaseSystemBrowserAuthenticationFailure::CoreUnavailable);
    };
    let staged = provider.import_browser_credential(&secret_bytes);
    secret_bytes.fill(0);
    if let Err(error) = staged {
        clear_attempt(&ACTIVE_SYSTEM_BROWSER, attempt_id);
        return failed_system_browser(match error {
            AccountSummaryError::InvalidResponse => {
                NeteaseSystemBrowserAuthenticationFailure::InvalidCredential
            }
            AccountSummaryError::Replaced => NeteaseSystemBrowserAuthenticationFailure::Replaced,
            _ => NeteaseSystemBrowserAuthenticationFailure::InvalidCredential,
        });
    }

    let verification = provider.verify_pending_credential().await;
    let still_current = *lock_attempt(&ACTIVE_SYSTEM_BROWSER) == Some(attempt_id);
    if !still_current {
        let failure = classify_system_browser_cancellation(attempt_id);
        clear_attempt(&ACTIVE_SYSTEM_BROWSER, attempt_id);
        return failed_system_browser(failure);
    }
    clear_attempt(&ACTIVE_SYSTEM_BROWSER, attempt_id);
    match verification {
        Ok(()) => NeteaseSystemBrowserAuthenticationOutcome {
            authenticated: true,
            failure: None,
        },
        Err(AccountSummaryError::CredentialRejected) => {
            failed_system_browser(NeteaseSystemBrowserAuthenticationFailure::Rejected)
        }
        Err(AccountSummaryError::Network) => {
            failed_system_browser(NeteaseSystemBrowserAuthenticationFailure::Network)
        }
        Err(AccountSummaryError::ServiceUnavailable) => {
            failed_system_browser(NeteaseSystemBrowserAuthenticationFailure::ServiceUnavailable)
        }
        Err(AccountSummaryError::InvalidResponse) => {
            failed_system_browser(NeteaseSystemBrowserAuthenticationFailure::InvalidResponse)
        }
        Err(AccountSummaryError::Replaced) => {
            failed_system_browser(NeteaseSystemBrowserAuthenticationFailure::Replaced)
        }
        Err(AccountSummaryError::AuthenticationRequired) => {
            failed_system_browser(NeteaseSystemBrowserAuthenticationFailure::CoreUnavailable)
        }
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn cancel_netease_system_browser_login(attempt_id: u32) -> bool {
    let mut active = lock_attempt(&ACTIVE_SYSTEM_BROWSER);
    if *active != Some(attempt_id) {
        return false;
    }
    *active = None;
    drop(active);
    let _ = crate::native_netease::native_netease_provider()
        .is_ok_and(provider_netease::NeteaseProvider::cancel_pending_credential_verification);
    true
}

/// Cancels any attempt and waits until its browser/profile owner has completed
/// cleanup. Used by sign-out and provider replacement boundaries.
pub async fn cancel_active_netease_system_browser_login_and_wait() -> bool {
    let was_active = lock_attempt(&ACTIVE_SYSTEM_BROWSER).take().is_some();
    let _ = crate::native_netease::native_netease_provider()
        .is_ok_and(provider_netease::NeteaseProvider::cancel_pending_credential_verification);
    let _gate = SYSTEM_BROWSER_GATE.lock().await;
    was_active
}

#[flutter_rust_bridge::frb(sync)]
pub fn reserve_netease_sms_code_request() -> u32 {
    if let Ok(provider) = crate::native_netease::native_netease_provider() {
        let _ = provider.cancel_sms_authentication();
    }
    *lock_attempt(&ACTIVE_SMS_LOGIN) = None;
    let attempt = next_attempt();
    *lock_attempt(&ACTIVE_SMS_SEND) = Some(attempt);
    attempt
}

pub async fn request_netease_sms_code(
    attempt_id: u32,
    country_code: String,
    phone: String,
) -> NeteaseSmsAuthenticationOutcome {
    if *lock_attempt(&ACTIVE_SMS_SEND) != Some(attempt_id) {
        return failed_sms(NeteaseSmsAuthenticationFailure::Replaced);
    }
    let Ok(provider) = crate::native_netease::native_netease_provider() else {
        clear_attempt(&ACTIVE_SMS_SEND, attempt_id);
        return failed_sms(NeteaseSmsAuthenticationFailure::CoreUnavailable);
    };
    let result = provider.request_sms_code(country_code, phone).await;
    if *lock_attempt(&ACTIVE_SMS_SEND) != Some(attempt_id) {
        return failed_sms(NeteaseSmsAuthenticationFailure::Replaced);
    }
    clear_attempt(&ACTIVE_SMS_SEND, attempt_id);
    match result {
        Ok(()) => successful_sms(),
        Err(error) => failed_sms(map_sms_error(error)),
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn cancel_netease_sms_code_request(attempt_id: u32) -> bool {
    let mut active = lock_attempt(&ACTIVE_SMS_SEND);
    if *active != Some(attempt_id) {
        return false;
    }
    *active = None;
    drop(active);
    crate::native_netease::native_netease_provider()
        .is_ok_and(SmsAuthenticationProvider::cancel_sms_authentication)
}

#[flutter_rust_bridge::frb(sync)]
pub fn reserve_netease_sms_login() -> Option<u32> {
    let mut active = lock_attempt(&ACTIVE_SMS_LOGIN);
    if active.is_some() {
        return None;
    }
    let attempt = next_attempt();
    *active = Some(attempt);
    Some(attempt)
}

pub async fn authenticate_netease_sms_code(
    attempt_id: u32,
    code: String,
) -> NeteaseSmsAuthenticationOutcome {
    if *lock_attempt(&ACTIVE_SMS_LOGIN) != Some(attempt_id) {
        return failed_sms(NeteaseSmsAuthenticationFailure::Replaced);
    }
    let Ok(provider) = crate::native_netease::native_netease_provider() else {
        clear_attempt(&ACTIVE_SMS_LOGIN, attempt_id);
        return failed_sms(NeteaseSmsAuthenticationFailure::CoreUnavailable);
    };
    let result = provider.authenticate_sms_code(code).await;
    if *lock_attempt(&ACTIVE_SMS_LOGIN) != Some(attempt_id) {
        return failed_sms(NeteaseSmsAuthenticationFailure::Replaced);
    }
    clear_attempt(&ACTIVE_SMS_LOGIN, attempt_id);
    match result {
        Ok(()) => successful_sms(),
        Err(error) => failed_sms(map_sms_error(error)),
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn cancel_netease_sms_login(attempt_id: u32) -> bool {
    let mut active = lock_attempt(&ACTIVE_SMS_LOGIN);
    if *active != Some(attempt_id) {
        return false;
    }
    *active = None;
    drop(active);
    crate::native_netease::native_netease_provider()
        .is_ok_and(SmsAuthenticationProvider::cancel_sms_authentication)
}

/// Cancels the provider-owned phone-code session after a completed code
/// request. At that point no bridge attempt remains active, but the provider
/// still retains the short-lived challenge needed to authenticate the code.
#[flutter_rust_bridge::frb(sync)]
pub fn cancel_netease_sms_authentication() -> bool {
    *lock_attempt(&ACTIVE_SMS_SEND) = None;
    *lock_attempt(&ACTIVE_SMS_LOGIN) = None;
    crate::native_netease::native_netease_provider()
        .is_ok_and(SmsAuthenticationProvider::cancel_sms_authentication)
}

#[flutter_rust_bridge::frb(sync)]
pub fn export_netease_credential_for_secure_storage() -> QqMusicCredentialExport {
    let Ok(provider) = crate::native_netease::native_netease_provider() else {
        return failed_export(QqMusicCredentialExportFailure::NoAuthenticatedCredential);
    };
    match provider.export_credential() {
        Ok(Some(secret_bytes)) => QqMusicCredentialExport {
            secret_bytes: Some(secret_bytes),
            failure: None,
        },
        Ok(None) => failed_export(QqMusicCredentialExportFailure::NoAuthenticatedCredential),
        Err(_) => failed_export(QqMusicCredentialExportFailure::SerializationFailed),
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn restore_netease_credential_from_secure_storage(
    secret_bytes: Option<Vec<u8>>,
) -> QqMusicCredentialRestore {
    let Some(secret_bytes) = secret_bytes else {
        return QqMusicCredentialRestore {
            state: Some(QqMusicCredentialRestoreState::SignedOut),
            failure: None,
        };
    };
    let Ok(provider) = crate::native_netease::native_netease_provider() else {
        return failed_restore(QqMusicCredentialRestoreFailure::CoreUnavailable);
    };
    match provider.import_credential(&secret_bytes) {
        Ok(()) => QqMusicCredentialRestore {
            state: Some(QqMusicCredentialRestoreState::VerificationRequired),
            failure: None,
        },
        Err(AccountSummaryError::InvalidResponse) => {
            failed_restore(QqMusicCredentialRestoreFailure::InvalidDocument)
        }
        Err(_) => failed_restore(QqMusicCredentialRestoreFailure::InvalidCredential),
    }
}

/// Stages the minimal Cookie header returned by an official `NetEase` web login.
/// The caller must run the normal credential verification before treating the
/// account as authenticated. Secret bytes are overwritten before returning.
#[flutter_rust_bridge::frb(sync)]
pub fn stage_netease_official_web_credential(
    mut secret_bytes: Vec<u8>,
) -> QqMusicCredentialRestore {
    *lock_attempt(&ACTIVE_START) = None;
    *lock_attempt(&ACTIVE_VERIFICATION) = None;
    *lock_attempt(&ACTIVE_SMS_SEND) = None;
    *lock_attempt(&ACTIVE_SMS_LOGIN) = None;

    let result = match crate::native_netease::native_netease_provider() {
        Ok(provider) => match provider.import_browser_credential(&secret_bytes) {
            Ok(()) => QqMusicCredentialRestore {
                state: Some(QqMusicCredentialRestoreState::VerificationRequired),
                failure: None,
            },
            Err(AccountSummaryError::InvalidResponse) => {
                failed_restore(QqMusicCredentialRestoreFailure::InvalidDocument)
            }
            Err(_) => failed_restore(QqMusicCredentialRestoreFailure::InvalidCredential),
        },
        Err(_) => failed_restore(QqMusicCredentialRestoreFailure::CoreUnavailable),
    };
    secret_bytes.fill(0);
    result
}

#[flutter_rust_bridge::frb(sync)]
pub fn reserve_netease_credential_verification() -> Option<u32> {
    let attempt = next_attempt();
    *lock_attempt(&ACTIVE_VERIFICATION) = Some(attempt);
    Some(attempt)
}

pub async fn verify_restored_netease_credential(attempt_id: u32) -> QqMusicCredentialVerification {
    if *lock_attempt(&ACTIVE_VERIFICATION) != Some(attempt_id) {
        return failed_verification(QqMusicCredentialVerificationFailure::Replaced);
    }
    let Ok(provider) = crate::native_netease::native_netease_provider() else {
        clear_attempt(&ACTIVE_VERIFICATION, attempt_id);
        return failed_verification(QqMusicCredentialVerificationFailure::CoreUnavailable);
    };
    let result = provider.verify_restored_credential().await;
    if *lock_attempt(&ACTIVE_VERIFICATION) != Some(attempt_id) {
        return failed_verification(QqMusicCredentialVerificationFailure::Replaced);
    }
    clear_attempt(&ACTIVE_VERIFICATION, attempt_id);
    match result {
        Ok(()) => QqMusicCredentialVerification {
            state: Some(QqMusicCredentialVerificationState::Authenticated),
            failure: None,
        },
        Err(AccountSummaryError::CredentialRejected) => QqMusicCredentialVerification {
            state: Some(QqMusicCredentialVerificationState::Rejected),
            failure: None,
        },
        Err(AccountSummaryError::AuthenticationRequired) => {
            failed_verification(QqMusicCredentialVerificationFailure::NoRestoredCredential)
        }
        Err(AccountSummaryError::Network) => {
            failed_verification(QqMusicCredentialVerificationFailure::Network)
        }
        Err(AccountSummaryError::ServiceUnavailable) => {
            failed_verification(QqMusicCredentialVerificationFailure::ServiceUnavailable)
        }
        Err(AccountSummaryError::InvalidResponse) => {
            failed_verification(QqMusicCredentialVerificationFailure::InvalidResponse)
        }
        Err(AccountSummaryError::Replaced) => {
            failed_verification(QqMusicCredentialVerificationFailure::Replaced)
        }
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn cancel_netease_credential_verification(attempt_id: u32) -> bool {
    let mut active = lock_attempt(&ACTIVE_VERIFICATION);
    if *active != Some(attempt_id) {
        return false;
    }
    *active = None;
    let _ = crate::native_netease::native_netease_provider()
        .is_ok_and(provider_netease::NeteaseProvider::cancel_pending_credential_verification);
    true
}

#[flutter_rust_bridge::frb(sync)]
pub fn sign_out_netease() -> bool {
    let Ok(provider) = crate::native_netease::native_netease_provider() else {
        return false;
    };
    *lock_attempt(&ACTIVE_START) = None;
    *lock_attempt(&ACTIVE_VERIFICATION) = None;
    *lock_attempt(&ACTIVE_SMS_SEND) = None;
    *lock_attempt(&ACTIVE_SMS_LOGIN) = None;
    *lock_attempt(&ACTIVE_SYSTEM_BROWSER) = None;
    QrAuthenticationProvider::sign_out(provider);
    true
}

fn next_attempt() -> u32 {
    NEXT_ATTEMPT
        .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |current| {
            Some(if current == u32::MAX { 1 } else { current + 1 })
        })
        .expect("attempt update closure always returns Some")
}

fn lock_attempt(lock: &StdMutex<Option<u32>>) -> std::sync::MutexGuard<'_, Option<u32>> {
    lock.lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn clear_attempt(lock: &StdMutex<Option<u32>>, attempt: u32) {
    let mut active = lock_attempt(lock);
    if *active == Some(attempt) {
        *active = None;
    }
}

const fn failed_start(failure: QqMusicQrLoginFailure) -> NeteaseQrLoginStart {
    NeteaseQrLoginStart {
        session: None,
        challenge: None,
        external_confirmation_url: None,
        failure: Some(failure),
    }
}

const fn failed_export(failure: QqMusicCredentialExportFailure) -> QqMusicCredentialExport {
    QqMusicCredentialExport {
        secret_bytes: None,
        failure: Some(failure),
    }
}

const fn failed_restore(failure: QqMusicCredentialRestoreFailure) -> QqMusicCredentialRestore {
    QqMusicCredentialRestore {
        state: None,
        failure: Some(failure),
    }
}

const fn failed_verification(
    failure: QqMusicCredentialVerificationFailure,
) -> QqMusicCredentialVerification {
    QqMusicCredentialVerification {
        state: None,
        failure: Some(failure),
    }
}

const fn successful_sms() -> NeteaseSmsAuthenticationOutcome {
    NeteaseSmsAuthenticationOutcome {
        success: true,
        failure: None,
    }
}

const fn failed_sms(failure: NeteaseSmsAuthenticationFailure) -> NeteaseSmsAuthenticationOutcome {
    NeteaseSmsAuthenticationOutcome {
        success: false,
        failure: Some(failure),
    }
}

const fn failed_system_browser(
    failure: NeteaseSystemBrowserAuthenticationFailure,
) -> NeteaseSystemBrowserAuthenticationOutcome {
    NeteaseSystemBrowserAuthenticationOutcome {
        authenticated: false,
        failure: Some(failure),
    }
}

fn classify_system_browser_cancellation(
    attempt_id: u32,
) -> NeteaseSystemBrowserAuthenticationFailure {
    match *lock_attempt(&ACTIVE_SYSTEM_BROWSER) {
        None => NeteaseSystemBrowserAuthenticationFailure::Cancelled,
        Some(active) if active != attempt_id => NeteaseSystemBrowserAuthenticationFailure::Replaced,
        Some(_) => NeteaseSystemBrowserAuthenticationFailure::Cancelled,
    }
}

#[cfg(target_os = "linux")]
const fn map_system_browser_capture_failure(
    failure: crate::linux_system_chromium::CaptureFailure,
) -> NeteaseSystemBrowserAuthenticationFailure {
    use crate::linux_system_chromium::CaptureFailure;
    match failure {
        CaptureFailure::BrowserUnavailable => {
            NeteaseSystemBrowserAuthenticationFailure::BrowserUnavailable
        }
        CaptureFailure::BrowserLaunchFailed => {
            NeteaseSystemBrowserAuthenticationFailure::BrowserLaunchFailed
        }
        CaptureFailure::ProfileSetupFailed => {
            NeteaseSystemBrowserAuthenticationFailure::ProfileSetupFailed
        }
        CaptureFailure::DevtoolsUnavailable => {
            NeteaseSystemBrowserAuthenticationFailure::DevtoolsUnavailable
        }
        CaptureFailure::DevtoolsInvalid => {
            NeteaseSystemBrowserAuthenticationFailure::DevtoolsInvalid
        }
        CaptureFailure::OfficialTargetUnavailable => {
            NeteaseSystemBrowserAuthenticationFailure::OfficialTargetUnavailable
        }
        CaptureFailure::BrowserClosed => NeteaseSystemBrowserAuthenticationFailure::BrowserClosed,
        CaptureFailure::InvalidCredential => {
            NeteaseSystemBrowserAuthenticationFailure::InvalidCredential
        }
        CaptureFailure::TimedOut => NeteaseSystemBrowserAuthenticationFailure::TimedOut,
        CaptureFailure::Cancelled => NeteaseSystemBrowserAuthenticationFailure::Cancelled,
        CaptureFailure::CleanupFailed => NeteaseSystemBrowserAuthenticationFailure::CleanupFailed,
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

const fn map_auth_error(error: AuthenticationError) -> QqMusicQrLoginFailure {
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
        AuthenticationError::SecurityVerificationRequired => {
            QqMusicQrLoginFailure::SecurityVerificationRequired
        }
        AuthenticationError::SecondaryVerificationRequired => {
            QqMusicQrLoginFailure::SecondaryVerificationRequired
        }
    }
}

const fn map_sms_error(error: SmsAuthenticationError) -> NeteaseSmsAuthenticationFailure {
    match error {
        SmsAuthenticationError::Network => NeteaseSmsAuthenticationFailure::Network,
        SmsAuthenticationError::ServiceUnavailable => {
            NeteaseSmsAuthenticationFailure::ServiceUnavailable
        }
        SmsAuthenticationError::InvalidResponse => NeteaseSmsAuthenticationFailure::InvalidResponse,
        SmsAuthenticationError::InvalidInput => NeteaseSmsAuthenticationFailure::InvalidInput,
        SmsAuthenticationError::CodeRejected => NeteaseSmsAuthenticationFailure::CodeRejected,
        SmsAuthenticationError::RateLimited => NeteaseSmsAuthenticationFailure::RateLimited,
        SmsAuthenticationError::SecurityVerificationRequired => {
            NeteaseSmsAuthenticationFailure::SecurityVerificationRequired
        }
        SmsAuthenticationError::SecondaryVerificationRequired => {
            NeteaseSmsAuthenticationFailure::SecondaryVerificationRequired
        }
        SmsAuthenticationError::Replaced => NeteaseSmsAuthenticationFailure::Replaced,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn absent_vault_document_is_signed_out_without_touching_qq() {
        let result = restore_netease_credential_from_secure_storage(None);
        assert_eq!(result.state, Some(QqMusicCredentialRestoreState::SignedOut));
        assert_eq!(result.failure, None);
    }

    #[test]
    fn stale_start_attempt_is_rejected_before_transport() {
        let attempt = reserve_netease_qr_login_start();
        assert!(cancel_netease_qr_login_start(attempt));
        assert!(!cancel_netease_qr_login_start(attempt));
    }

    #[test]
    fn qr_start_debug_never_exposes_the_external_confirmation_secret() {
        let start = NeteaseQrLoginStart {
            session: None,
            challenge: None,
            external_confirmation_url: Some(
                "https://music.163.com/st/platform/scanlogin?codekey=synthetic-secret".to_owned(),
            ),
            failure: None,
        };
        let debug = format!("{start:?}");
        assert!(debug.contains("has_external_confirmation_url: true"));
        assert!(!debug.contains("synthetic-secret"));
        assert!(!debug.contains("codekey"));
    }

    #[test]
    fn security_verification_remains_an_explicit_bridge_failure() {
        assert_eq!(
            map_auth_error(AuthenticationError::SecurityVerificationRequired),
            QqMusicQrLoginFailure::SecurityVerificationRequired
        );
        assert_eq!(
            map_auth_error(AuthenticationError::SecondaryVerificationRequired),
            QqMusicQrLoginFailure::SecondaryVerificationRequired
        );
    }

    #[test]
    fn sms_failures_remain_typed_and_secret_free() {
        assert_eq!(
            map_sms_error(SmsAuthenticationError::SecurityVerificationRequired),
            NeteaseSmsAuthenticationFailure::SecurityVerificationRequired
        );
        assert_eq!(
            map_sms_error(SmsAuthenticationError::SecondaryVerificationRequired),
            NeteaseSmsAuthenticationFailure::SecondaryVerificationRequired
        );
        assert_eq!(
            map_sms_error(SmsAuthenticationError::CodeRejected),
            NeteaseSmsAuthenticationFailure::CodeRejected
        );
        assert_eq!(
            failed_sms(NeteaseSmsAuthenticationFailure::RateLimited),
            NeteaseSmsAuthenticationOutcome {
                success: false,
                failure: Some(NeteaseSmsAuthenticationFailure::RateLimited),
            }
        );
    }
}
