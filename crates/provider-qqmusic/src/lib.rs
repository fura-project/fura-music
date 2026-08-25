//! QQ Music provider mapping layer.

use std::sync::{Arc, Mutex};

use music_domain::ProviderId;
use provider_api::{
    AuthenticationError, MusicProvider, ProviderCapability, ProviderDescriptor,
    QrAuthenticationChallenge, QrAuthenticationProgress, QrAuthenticationProvider,
    QrAuthenticationSession, QrImageFormat,
};
use qqmusic_client::{
    Credential, CredentialPersistenceError, CredentialRestorePlan, HttpTransport, QqMusicClient,
    QrImageMediaType, WechatCredentialExchangeError, WechatQrError, WechatQrLoginCancellation,
    WechatQrLoginCoordinator, WechatQrLoginError, WechatQrLoginProgress, WechatQrLoginSession,
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicCredentialRestoreState {
    SignedOut,
    VerificationRequired,
    LocallyExpired,
}

#[derive(Debug, Default)]
enum QqMusicCredentialState {
    #[default]
    SignedOut,
    PendingVerification(Credential),
    LocallyExpired(Credential),
    Authenticated(Credential),
}

#[derive(Debug)]
pub struct QqMusicProvider<T> {
    login: WechatQrLoginCoordinator<T>,
    credential: Arc<Mutex<QqMusicCredentialState>>,
}

impl<T> QqMusicProvider<T> {
    #[must_use]
    pub fn new(client: QqMusicClient<T>) -> Self {
        Self {
            login: WechatQrLoginCoordinator::new(client),
            credential: Arc::new(Mutex::new(QqMusicCredentialState::SignedOut)),
        }
    }

    #[must_use]
    pub fn client(&self) -> &QqMusicClient<T> {
        self.login.client()
    }

    #[must_use]
    pub fn has_authenticated_credential(&self) -> bool {
        matches!(
            *credential_guard(&self.credential),
            QqMusicCredentialState::Authenticated(_)
        )
    }

    /// Returns a cloned startup candidate for server verification or a future
    /// refresh decision. Authenticated QR credentials are intentionally not
    /// exposed through this restore-only accessor.
    #[must_use]
    pub fn restored_credential(&self) -> Option<(QqMusicCredentialRestoreState, Credential)> {
        match &*credential_guard(&self.credential) {
            QqMusicCredentialState::PendingVerification(credential) => Some((
                QqMusicCredentialRestoreState::VerificationRequired,
                credential.clone(),
            )),
            QqMusicCredentialState::LocallyExpired(credential) => Some((
                QqMusicCredentialRestoreState::LocallyExpired,
                credential.clone(),
            )),
            QqMusicCredentialState::SignedOut | QqMusicCredentialState::Authenticated(_) => None,
        }
    }

    /// Cancels the currently creating or active QR generation.
    ///
    /// Higher layers should prefer a generation-specific session cancellation
    /// handle after QR creation completes.
    #[must_use]
    pub fn cancel_active_authentication(&self) -> bool {
        self.login.cancel_active()
    }

    /// Exports the current credential as a short-lived, versioned secret
    /// document for the platform secure-storage adapter.
    ///
    /// # Errors
    ///
    /// Returns a serialization error without exposing credential content.
    pub fn encode_authenticated_credential(
        &self,
    ) -> Result<Option<Vec<u8>>, CredentialPersistenceError> {
        let credential = credential_guard(&self.credential);
        match &*credential {
            QqMusicCredentialState::Authenticated(credential) => {
                credential.encode_for_secure_storage().map(Some)
            }
            QqMusicCredentialState::SignedOut
            | QqMusicCredentialState::PendingVerification(_)
            | QqMusicCredentialState::LocallyExpired(_) => Ok(None),
        }
    }

    /// Loads an optional versioned credential document and classifies the next
    /// action without treating the credential as authenticated.
    ///
    /// # Errors
    ///
    /// Returns a diagnostics-safe persistence error and leaves the previous
    /// in-memory state unchanged when the document is malformed or invalid.
    pub fn restore_credential_from_secure_storage(
        &self,
        secret_bytes: Option<&[u8]>,
        now_unix_seconds: u64,
    ) -> Result<QqMusicCredentialRestoreState, CredentialPersistenceError> {
        let credential = secret_bytes
            .map(Credential::decode_from_secure_storage)
            .transpose()?;
        let plan = CredentialRestorePlan::from_loaded(credential, now_unix_seconds);
        let (state, result) = match plan {
            CredentialRestorePlan::SignedOut => (
                QqMusicCredentialState::SignedOut,
                QqMusicCredentialRestoreState::SignedOut,
            ),
            CredentialRestorePlan::VerifyWithServer(credential) => (
                QqMusicCredentialState::PendingVerification(credential),
                QqMusicCredentialRestoreState::VerificationRequired,
            ),
            CredentialRestorePlan::LocallyExpired(credential) => (
                QqMusicCredentialState::LocallyExpired(credential),
                QqMusicCredentialRestoreState::LocallyExpired,
            ),
        };
        *credential_guard(&self.credential) = state;
        Ok(result)
    }
}

impl<T> MusicProvider for QqMusicProvider<T> {
    fn descriptor(&self) -> ProviderDescriptor {
        ProviderDescriptor {
            id: ProviderId::new("qq-music").expect("static provider id is valid"),
            display_name: "QQ Music".into(),
            capabilities: vec![ProviderCapability::Authentication],
        }
    }
}

impl<T> QrAuthenticationProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = AuthenticationError;
    type Session = QqMusicQrAuthenticationSession<T>;

    async fn begin_qr_authentication(&self) -> Result<Self::Session, Self::Error> {
        let session = self.login.begin().await.map_err(map_login_error)?;
        Ok(QqMusicQrAuthenticationSession {
            cancellation: QqMusicQrAuthenticationCancellation {
                inner: session.cancellation_handle(),
            },
            session,
            credential: Arc::clone(&self.credential),
        })
    }

    fn has_authenticated_credential(&self) -> bool {
        QqMusicProvider::has_authenticated_credential(self)
    }
}

#[derive(Clone, Debug)]
pub struct QqMusicQrAuthenticationCancellation {
    inner: WechatQrLoginCancellation,
}

impl QqMusicQrAuthenticationCancellation {
    #[must_use]
    pub fn is_active(&self) -> bool {
        self.inner.is_active()
    }

    #[must_use]
    pub fn cancel(&self) -> bool {
        self.inner.cancel()
    }
}

pub struct QqMusicQrAuthenticationSession<T> {
    session: WechatQrLoginSession<T>,
    cancellation: QqMusicQrAuthenticationCancellation,
    credential: Arc<Mutex<QqMusicCredentialState>>,
}

impl<T> std::fmt::Debug for QqMusicQrAuthenticationSession<T> {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("QqMusicQrAuthenticationSession")
            .field("active", &self.cancellation.is_active())
            .finish_non_exhaustive()
    }
}

impl<T> QqMusicQrAuthenticationSession<T> {
    #[must_use]
    pub fn cancellation_handle(&self) -> QqMusicQrAuthenticationCancellation {
        self.cancellation.clone()
    }
}

impl<T> QrAuthenticationSession for QqMusicQrAuthenticationSession<T>
where
    T: HttpTransport + 'static,
{
    type Error = AuthenticationError;

    fn challenge(&self) -> QrAuthenticationChallenge {
        let image = self.session.qr().image();
        let format = match image.media_type() {
            QrImageMediaType::Png => QrImageFormat::Png,
            QrImageMediaType::Jpeg => QrImageFormat::Jpeg,
        };
        QrAuthenticationChallenge::new(format, image.bytes().to_vec())
    }

    fn is_active(&self) -> bool {
        self.cancellation.is_active()
    }

    fn cancel(&self) -> bool {
        self.cancellation.cancel()
    }

    async fn advance(&mut self) -> Result<QrAuthenticationProgress, Self::Error> {
        match self.session.advance().await.map_err(map_login_error)? {
            WechatQrLoginProgress::WaitingForScan => Ok(QrAuthenticationProgress::WaitingForScan),
            WechatQrLoginProgress::ScannedAwaitingConfirmation => {
                Ok(QrAuthenticationProgress::ScannedAwaitingConfirmation)
            }
            WechatQrLoginProgress::Authenticated(credential) => {
                *credential_guard(&self.credential) =
                    QqMusicCredentialState::Authenticated(*credential);
                Ok(QrAuthenticationProgress::Authenticated)
            }
            WechatQrLoginProgress::Expired => Ok(QrAuthenticationProgress::Expired),
            WechatQrLoginProgress::Refused => Ok(QrAuthenticationProgress::Refused),
            WechatQrLoginProgress::TimedOut => Ok(QrAuthenticationProgress::TimedOut),
        }
    }
}

fn credential_guard(
    credential: &Mutex<QqMusicCredentialState>,
) -> std::sync::MutexGuard<'_, QqMusicCredentialState> {
    credential
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn map_login_error<E>(error: WechatQrLoginError<E>) -> AuthenticationError {
    match error {
        WechatQrLoginError::Protocol(error) => map_qr_error(&error),
        WechatQrLoginError::CredentialExchange(error) => map_exchange_error(&error),
        WechatQrLoginError::Cancelled => AuthenticationError::Cancelled,
        WechatQrLoginError::Superseded => AuthenticationError::Replaced,
        WechatQrLoginError::CoordinatorClosed => AuthenticationError::SessionClosed,
        WechatQrLoginError::SessionFinished => AuthenticationError::SessionFinished,
        WechatQrLoginError::SessionTimedOut => AuthenticationError::TimedOut,
        WechatQrLoginError::TransportFailureLimitReached { .. } => {
            AuthenticationError::TooManyNetworkFailures
        }
    }
}

fn map_qr_error<E>(error: &WechatQrError<E>) -> AuthenticationError {
    match error {
        WechatQrError::Transport(_) => AuthenticationError::Network,
        WechatQrError::HttpStatus { .. } => AuthenticationError::ServiceUnavailable,
        WechatQrError::ConnectPageTooLarge
        | WechatQrError::ConnectPageNotUtf8
        | WechatQrError::MissingIdentifier
        | WechatQrError::InvalidIdentifier
        | WechatQrError::ImageTooLarge
        | WechatQrError::InvalidImage
        | WechatQrError::ClockBeforeUnixEpoch
        | WechatQrError::PollResponseTooLarge
        | WechatQrError::PollResponseNotUtf8
        | WechatQrError::MissingPollStatus
        | WechatQrError::InvalidPollStatus
        | WechatQrError::MissingAuthorizationCode
        | WechatQrError::UnrecognizedPollStatus { .. } => AuthenticationError::InvalidResponse,
    }
}

fn map_exchange_error<E>(error: &WechatCredentialExchangeError<E>) -> AuthenticationError {
    match error {
        WechatCredentialExchangeError::Transport(_) => AuthenticationError::Network,
        WechatCredentialExchangeError::HttpStatus(_) => AuthenticationError::ServiceUnavailable,
        WechatCredentialExchangeError::Upstream { .. } => AuthenticationError::Rejected,
        WechatCredentialExchangeError::Serialize
        | WechatCredentialExchangeError::InvalidJson
        | WechatCredentialExchangeError::MissingGlobalCode
        | WechatCredentialExchangeError::MissingLoginResult
        | WechatCredentialExchangeError::MissingCredentialData
        | WechatCredentialExchangeError::InvalidCredential(_)
        | WechatCredentialExchangeError::InvalidExpiry(_)
        | WechatCredentialExchangeError::UnexpectedLoginType(_) => {
            AuthenticationError::InvalidResponse
        }
    }
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;

    use super::{QqMusicCredentialRestoreState, QqMusicProvider};
    use provider_api::{
        MusicProvider, ProviderCapability, QrAuthenticationProgress, QrAuthenticationProvider,
        QrAuthenticationSession, QrImageFormat,
    };
    use qqmusic_client::{
        Credential, CredentialExpiry, HttpMethod, HttpRequest, HttpResponse, HttpTransport,
        LoginType, QqMusicClient,
    };

    struct SuccessfulAuthenticationTransport;

    impl HttpTransport for SuccessfulAuthenticationTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            if request.url() == "https://open.weixin.qq.com/connect/qrconnect" {
                return Ok(HttpResponse::new(
                    200,
                    br#"<a href="?uuid=provider-fixture">login</a>"#.to_vec(),
                ));
            }
            if request
                .url()
                .starts_with("https://open.weixin.qq.com/connect/qrcode/")
            {
                return Ok(HttpResponse::new(
                    200,
                    b"\xff\xd8\xffprivate-qr-fixture".to_vec(),
                ));
            }
            if request.method() == HttpMethod::Get {
                return Ok(HttpResponse::new(
                    200,
                    b"window.wx_errcode=405;window.wx_code='private-oauth-code';".to_vec(),
                ));
            }

            Ok(HttpResponse::new(
                200,
                br#"{
                    "code": 0,
                    "music.login.LoginServer.Login": {
                        "code": 0,
                        "data": {
                            "str_musicid": "123456",
                            "musickey": "private-music-key",
                            "refresh_token": "private-refresh-token"
                        }
                    }
                }"#
                .to_vec(),
            ))
        }
    }

    #[test]
    fn descriptor_claims_only_the_implemented_authentication_capability() {
        let provider = QqMusicProvider::new(QqMusicClient::new(()));
        let descriptor = provider.descriptor();

        assert_eq!(descriptor.id.as_str(), "qq-music");
        assert_eq!(descriptor.display_name, "QQ Music");
        assert_eq!(
            descriptor.capabilities,
            [ProviderCapability::Authentication]
        );
    }

    #[test]
    fn restore_keeps_unverified_and_expired_credentials_unauthenticated() {
        let provider = QqMusicProvider::new(QqMusicClient::new(()));
        assert_eq!(
            provider
                .restore_credential_from_secure_storage(None, 2_000)
                .expect("absent storage is valid"),
            QqMusicCredentialRestoreState::SignedOut,
        );

        let unverified = Credential::new("123456", "private-key", LoginType::WECHAT)
            .expect("fixture credential")
            .encode_for_secure_storage()
            .expect("encode fixture");
        assert_eq!(
            provider
                .restore_credential_from_secure_storage(Some(&unverified), 2_000)
                .expect("valid stored credential"),
            QqMusicCredentialRestoreState::VerificationRequired,
        );
        assert!(!provider.has_authenticated_credential());
        let (state, restored) = provider
            .restored_credential()
            .expect("unverified credential is retained in Rust");
        assert_eq!(state, QqMusicCredentialRestoreState::VerificationRequired);
        assert_eq!(restored.music_id(), "123456");
        assert!(
            provider
                .encode_authenticated_credential()
                .expect("unverified credential must not export")
                .is_none()
        );

        let expired = Credential::new("123456", "private-key", LoginType::WECHAT)
            .expect("fixture credential")
            .with_expiry(CredentialExpiry::new(1_000, 300).expect("fixture expiry"))
            .encode_for_secure_storage()
            .expect("encode fixture");
        assert_eq!(
            provider
                .restore_credential_from_secure_storage(Some(&expired), 2_000)
                .expect("valid expired credential"),
            QqMusicCredentialRestoreState::LocallyExpired,
        );
        assert!(!provider.has_authenticated_credential());
        let (state, _) = provider
            .restored_credential()
            .expect("expired credential is retained for a future decision");
        assert_eq!(state, QqMusicCredentialRestoreState::LocallyExpired);
    }

    #[test]
    fn malformed_restore_does_not_replace_an_existing_restore_state() {
        let provider = QqMusicProvider::new(QqMusicClient::new(()));
        let unverified = Credential::new("123456", "private-key", LoginType::WECHAT)
            .expect("fixture credential")
            .encode_for_secure_storage()
            .expect("encode fixture");
        provider
            .restore_credential_from_secure_storage(Some(&unverified), 2_000)
            .expect("valid stored credential");

        assert!(
            provider
                .restore_credential_from_secure_storage(Some(b"not-json"), 2_000)
                .is_err()
        );
        assert!(matches!(
            &*super::credential_guard(&provider.credential),
            super::QqMusicCredentialState::PendingVerification(_)
        ));
    }

    #[tokio::test]
    async fn provider_maps_qr_flow_and_retains_credential_inside_the_provider() {
        let provider = QqMusicProvider::new(QqMusicClient::new(SuccessfulAuthenticationTransport));
        let mut session = provider
            .begin_qr_authentication()
            .await
            .expect("provider QR session");
        let challenge = session.challenge();

        assert_eq!(challenge.image_format(), QrImageFormat::Jpeg);
        assert_eq!(challenge.image_bytes(), b"\xff\xd8\xffprivate-qr-fixture");
        assert!(!format!("{challenge:?}").contains("private"));
        assert!(!provider.has_authenticated_credential());

        let progress = session.advance().await.expect("provider auth mapping");

        assert_eq!(progress, QrAuthenticationProgress::Authenticated);
        assert!(provider.has_authenticated_credential());
        assert!(!session.is_active());
        assert!(!format!("{session:?}").contains("private"));
        let encoded = provider
            .encode_authenticated_credential()
            .expect("encode credential")
            .expect("authenticated credential");
        let decoded = Credential::decode_from_secure_storage(&encoded)
            .expect("provider emits a valid credential document");
        assert_eq!(decoded.music_id(), "123456");
    }
}
