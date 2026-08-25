//! QQ Music provider mapping layer.

use std::sync::{Arc, Mutex};

use music_domain::ProviderId;
use provider_api::{
    AuthenticationError, MusicProvider, ProviderCapability, ProviderDescriptor,
    QrAuthenticationChallenge, QrAuthenticationProgress, QrAuthenticationProvider,
    QrAuthenticationSession, QrImageFormat,
};
use qqmusic_client::{
    Credential, HttpTransport, QqMusicClient, QrImageMediaType, WechatCredentialExchangeError,
    WechatQrError, WechatQrLoginCancellation, WechatQrLoginCoordinator, WechatQrLoginError,
    WechatQrLoginProgress, WechatQrLoginSession,
};

#[derive(Debug)]
pub struct QqMusicProvider<T> {
    login: WechatQrLoginCoordinator<T>,
    credential: Arc<Mutex<Option<Credential>>>,
}

impl<T> QqMusicProvider<T> {
    #[must_use]
    pub fn new(client: QqMusicClient<T>) -> Self {
        Self {
            login: WechatQrLoginCoordinator::new(client),
            credential: Arc::new(Mutex::new(None)),
        }
    }

    #[must_use]
    pub fn client(&self) -> &QqMusicClient<T> {
        self.login.client()
    }

    #[must_use]
    pub fn has_authenticated_credential(&self) -> bool {
        credential_guard(&self.credential).is_some()
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
    credential: Arc<Mutex<Option<Credential>>>,
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
                *credential_guard(&self.credential) = Some(*credential);
                Ok(QrAuthenticationProgress::Authenticated)
            }
            WechatQrLoginProgress::Expired => Ok(QrAuthenticationProgress::Expired),
            WechatQrLoginProgress::Refused => Ok(QrAuthenticationProgress::Refused),
            WechatQrLoginProgress::TimedOut => Ok(QrAuthenticationProgress::TimedOut),
        }
    }
}

fn credential_guard(
    credential: &Mutex<Option<Credential>>,
) -> std::sync::MutexGuard<'_, Option<Credential>> {
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

    use super::QqMusicProvider;
    use provider_api::{
        MusicProvider, ProviderCapability, QrAuthenticationProgress, QrAuthenticationProvider,
        QrAuthenticationSession, QrImageFormat,
    };
    use qqmusic_client::{HttpMethod, HttpRequest, HttpResponse, HttpTransport, QqMusicClient};

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
    }
}
