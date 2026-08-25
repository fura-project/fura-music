use std::fmt;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{LazyLock, Mutex as StdMutex};

use provider_api::{
    AuthenticationError, QrAuthenticationProgress, QrAuthenticationProvider,
    QrAuthenticationSession, QrImageFormat,
};
use provider_qqmusic::{
    QqMusicProvider, QqMusicQrAuthenticationCancellation, QqMusicQrAuthenticationSession,
};
use qqmusic_client::{QqMusicClient, ReqwestTransport};
use tokio::sync::Mutex as AsyncMutex;

type NativeProvider = QqMusicProvider<ReqwestTransport>;
type NativeSession = QqMusicQrAuthenticationSession<ReqwestTransport>;

static QQ_MUSIC_PROVIDER: LazyLock<Result<NativeProvider, ()>> = LazyLock::new(|| {
    ReqwestTransport::new()
        .map(QqMusicClient::new)
        .map(QqMusicProvider::new)
        .map_err(|_| ())
});
static NEXT_START_ATTEMPT: AtomicU32 = AtomicU32::new(1);
static ACTIVE_START_ATTEMPT: StdMutex<Option<u32>> = StdMutex::new(None);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicQrImageFormat {
    Png,
    Jpeg,
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

pub async fn start_qq_music_wechat_qr_login(attempt_id: u32) -> QqMusicQrLoginStart {
    let Ok(provider) = QQ_MUSIC_PROVIDER.as_ref() else {
        return failed_start(QqMusicQrLoginFailure::CoreUnavailable);
    };
    *start_attempt_guard() = Some(attempt_id);
    let session = match provider.begin_qr_authentication().await {
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
pub fn qq_music_has_authenticated_credential() -> bool {
    QQ_MUSIC_PROVIDER
        .as_ref()
        .is_ok_and(QrAuthenticationProvider::has_authenticated_credential)
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

#[cfg(test)]
mod tests {
    use super::{
        QqMusicQrChallenge, QqMusicQrImageFormat, QqMusicQrLoginFailure, clear_start_attempt,
        failed_start, map_error, reserve_qq_music_wechat_qr_login_start, start_attempt_guard,
    };
    use provider_api::AuthenticationError;

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
