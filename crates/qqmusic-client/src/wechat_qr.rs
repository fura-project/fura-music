use std::fmt;
use std::fmt::Write as _;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::{HttpRequest, HttpTransport, QqMusicClient};

const CONNECT_URL: &str = "https://open.weixin.qq.com/connect/qrconnect";
const IMAGE_URL_PREFIX: &str = "https://open.weixin.qq.com/connect/qrcode/";
const POLL_URL: &str = "https://lp.open.weixin.qq.com/connect/l/qrconnect";
const POLL_REFERER: &str = "https://open.weixin.qq.com/";
const WECHAT_APP_ID: &str = "wx48db31d50e334801";
const REDIRECT_URI: &str =
    "https://y.qq.com/portal/wx_redirect.html?login_type=2&surl=https://y.qq.com/";
const STYLE_HREF: &str =
    "https://y.qq.com/mediastyle/music_v17/src/css/popup_wechat.css#wechat_redirect";
const MAX_CONNECT_PAGE_BYTES: usize = 512 * 1024;
const MAX_QR_IMAGE_BYTES: usize = 2 * 1024 * 1024;
const MAX_POLL_RESPONSE_BYTES: usize = 64 * 1024;
const POLL_TIMEOUT: Duration = Duration::from_secs(35);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QrImageMediaType {
    Png,
    Jpeg,
}

impl QrImageMediaType {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Png => "image/png",
            Self::Jpeg => "image/jpeg",
        }
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QrImage {
    media_type: QrImageMediaType,
    bytes: Vec<u8>,
}

impl QrImage {
    pub(crate) const fn new_for_protocol(media_type: QrImageMediaType, bytes: Vec<u8>) -> Self {
        Self { media_type, bytes }
    }

    #[must_use]
    pub const fn media_type(&self) -> QrImageMediaType {
        self.media_type
    }

    #[must_use]
    pub fn bytes(&self) -> &[u8] {
        &self.bytes
    }
}

impl fmt::Debug for QrImage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QrImage")
            .field("media_type", &self.media_type)
            .field(
                "bytes",
                &format_args!("[REDACTED; {} bytes]", self.bytes.len()),
            )
            .finish()
    }
}

/// Transient, unconfirmed `WeChat` QR login material.
#[derive(Clone, Eq, PartialEq)]
pub struct WechatQrSession {
    identifier: String,
    image: QrImage,
}

impl WechatQrSession {
    /// Returns transient session material. Do not persist or log it.
    #[must_use]
    pub fn identifier(&self) -> &str {
        &self.identifier
    }

    #[must_use]
    pub const fn image(&self) -> &QrImage {
        &self.image
    }
}

impl fmt::Debug for WechatQrSession {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("WechatQrSession")
            .field("identifier", &"[REDACTED]")
            .field("image", &self.image)
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct WechatAuthorizationCode(String);

impl WechatAuthorizationCode {
    pub(crate) fn from_protocol(value: String) -> Self {
        Self(value)
    }

    /// Returns the short-lived authorization material for credential exchange.
    /// Do not persist or log it.
    #[must_use]
    pub fn expose(&self) -> &str {
        &self.0
    }
}

impl fmt::Debug for WechatAuthorizationCode {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("WechatAuthorizationCode([REDACTED])")
    }
}

#[derive(Clone, Eq, PartialEq)]
pub enum WechatQrPollResult {
    WaitingForScan,
    ScannedAwaitingConfirmation,
    Authorized(WechatAuthorizationCode),
    Expired,
    Refused,
}

impl fmt::Debug for WechatQrPollResult {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::WaitingForScan => formatter.write_str("WaitingForScan"),
            Self::ScannedAwaitingConfirmation => formatter.write_str("ScannedAwaitingConfirmation"),
            Self::Authorized(_) => formatter.write_str("Authorized([REDACTED])"),
            Self::Expired => formatter.write_str("Expired"),
            Self::Refused => formatter.write_str("Refused"),
        }
    }
}

pub enum WechatQrError<E> {
    Transport(E),
    HttpStatus { phase: &'static str, status: u16 },
    ConnectPageTooLarge,
    ConnectPageNotUtf8,
    MissingIdentifier,
    InvalidIdentifier,
    ImageTooLarge,
    InvalidImage,
    ClockBeforeUnixEpoch,
    PollResponseTooLarge,
    PollResponseNotUtf8,
    MissingPollStatus,
    InvalidPollStatus,
    MissingAuthorizationCode,
    UnrecognizedPollStatus { status: u16 },
}

impl<E> fmt::Debug for WechatQrError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Transport(_) => formatter.write_str("Transport([REDACTED])"),
            Self::HttpStatus { phase, status } => formatter
                .debug_struct("HttpStatus")
                .field("phase", phase)
                .field("status", status)
                .finish(),
            Self::ConnectPageTooLarge => formatter.write_str("ConnectPageTooLarge"),
            Self::ConnectPageNotUtf8 => formatter.write_str("ConnectPageNotUtf8"),
            Self::MissingIdentifier => formatter.write_str("MissingIdentifier"),
            Self::InvalidIdentifier => formatter.write_str("InvalidIdentifier"),
            Self::ImageTooLarge => formatter.write_str("ImageTooLarge"),
            Self::InvalidImage => formatter.write_str("InvalidImage"),
            Self::ClockBeforeUnixEpoch => formatter.write_str("ClockBeforeUnixEpoch"),
            Self::PollResponseTooLarge => formatter.write_str("PollResponseTooLarge"),
            Self::PollResponseNotUtf8 => formatter.write_str("PollResponseNotUtf8"),
            Self::MissingPollStatus => formatter.write_str("MissingPollStatus"),
            Self::InvalidPollStatus => formatter.write_str("InvalidPollStatus"),
            Self::MissingAuthorizationCode => formatter.write_str("MissingAuthorizationCode"),
            Self::UnrecognizedPollStatus { status } => formatter
                .debug_struct("UnrecognizedPollStatus")
                .field("status", status)
                .finish(),
        }
    }
}

impl<E> fmt::Display for WechatQrError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Transport(_) => formatter.write_str("WeChat QR transport failed"),
            Self::HttpStatus { phase, status } => {
                write!(formatter, "WeChat QR {phase} returned HTTP {status}")
            }
            Self::ConnectPageTooLarge => formatter.write_str("WeChat QR connect page is too large"),
            Self::ConnectPageNotUtf8 => formatter.write_str("WeChat QR connect page is not UTF-8"),
            Self::MissingIdentifier => formatter.write_str("WeChat QR response has no identifier"),
            Self::InvalidIdentifier => formatter.write_str("WeChat QR identifier is malformed"),
            Self::ImageTooLarge => formatter.write_str("WeChat QR image is too large"),
            Self::InvalidImage => formatter.write_str("WeChat QR response is not a PNG or JPEG"),
            Self::ClockBeforeUnixEpoch => {
                formatter.write_str("system clock is before the Unix epoch")
            }
            Self::PollResponseTooLarge => {
                formatter.write_str("WeChat QR poll response is too large")
            }
            Self::PollResponseNotUtf8 => {
                formatter.write_str("WeChat QR poll response is not UTF-8")
            }
            Self::MissingPollStatus => formatter.write_str("WeChat QR poll response has no status"),
            Self::InvalidPollStatus => {
                formatter.write_str("WeChat QR poll response has a malformed status")
            }
            Self::MissingAuthorizationCode => {
                formatter.write_str("confirmed WeChat QR response has no authorization code")
            }
            Self::UnrecognizedPollStatus { status } => {
                write!(formatter, "unrecognized WeChat QR poll status {status}")
            }
        }
    }
}

impl<E> std::error::Error for WechatQrError<E>
where
    E: std::error::Error + 'static,
{
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Transport(error) => Some(error),
            _ => None,
        }
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Starts an unconfirmed `WeChat` QR session without using account data.
    ///
    /// # Errors
    ///
    /// Returns [`WechatQrError`] for transport/status failures, an unexpected
    /// connect page, or a response that is not a bounded PNG/JPEG image.
    pub async fn create_wechat_qr(&self) -> Result<WechatQrSession, WechatQrError<T::Error>> {
        let connect_response = self
            .transport()
            .execute(connect_request())
            .await
            .map_err(WechatQrError::Transport)?;
        ensure_success("bootstrap", connect_response.status())?;
        if connect_response.body().len() > MAX_CONNECT_PAGE_BYTES {
            return Err(WechatQrError::ConnectPageTooLarge);
        }

        let connect_page = std::str::from_utf8(connect_response.body())
            .map_err(|_| WechatQrError::ConnectPageNotUtf8)?;
        let identifier = parse_identifier(connect_page)?;
        let image_url = format!("{IMAGE_URL_PREFIX}{}", encode_path_segment(&identifier));

        let image_response = self
            .transport()
            .execute(
                HttpRequest::get(image_url)
                    .response_body_limit(MAX_QR_IMAGE_BYTES)
                    .header("Referer", CONNECT_URL),
            )
            .await
            .map_err(WechatQrError::Transport)?;
        ensure_success("image", image_response.status())?;
        if image_response.body().len() > MAX_QR_IMAGE_BYTES {
            return Err(WechatQrError::ImageTooLarge);
        }
        let media_type =
            image_media_type(image_response.body()).ok_or(WechatQrError::InvalidImage)?;

        Ok(WechatQrSession {
            identifier,
            image: QrImage {
                media_type,
                bytes: image_response.body().to_vec(),
            },
        })
    }

    /// Performs one bounded long-poll for an existing `WeChat` QR session.
    ///
    /// This method reports protocol state only. Repetition, cancellation, and
    /// replacement of sessions belong to a higher-level login coordinator.
    ///
    /// # Errors
    ///
    /// Returns [`WechatQrError`] for clock, transport, status, or response
    /// parsing failures. Unknown upstream states remain errors instead of being
    /// assigned guessed product meanings.
    pub async fn poll_wechat_qr(
        &self,
        session: &WechatQrSession,
    ) -> Result<WechatQrPollResult, WechatQrError<T::Error>> {
        let cache_buster = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|_| WechatQrError::ClockBeforeUnixEpoch)?
            .as_millis();
        self.poll_wechat_qr_at(session, cache_buster).await
    }

    async fn poll_wechat_qr_at(
        &self,
        session: &WechatQrSession,
        cache_buster: u128,
    ) -> Result<WechatQrPollResult, WechatQrError<T::Error>> {
        let response = self
            .transport()
            .execute(poll_request(session.identifier(), cache_buster))
            .await
            .map_err(WechatQrError::Transport)?;
        ensure_success("poll", response.status())?;
        if response.body().len() > MAX_POLL_RESPONSE_BYTES {
            return Err(WechatQrError::PollResponseTooLarge);
        }
        let body =
            std::str::from_utf8(response.body()).map_err(|_| WechatQrError::PollResponseNotUtf8)?;
        parse_poll_result(body)
    }
}

fn connect_request() -> HttpRequest {
    HttpRequest::get(CONNECT_URL)
        .response_body_limit(MAX_CONNECT_PAGE_BYTES)
        .query("appid", WECHAT_APP_ID)
        .query("redirect_uri", REDIRECT_URI)
        .query("response_type", "code")
        .query("scope", "snsapi_login")
        .query("state", "STATE")
        .query("href", STYLE_HREF)
}

fn poll_request(identifier: &str, cache_buster: u128) -> HttpRequest {
    HttpRequest::get(POLL_URL)
        .response_body_limit(MAX_POLL_RESPONSE_BYTES)
        .timeout(POLL_TIMEOUT)
        .query("uuid", identifier)
        .query("_", cache_buster.to_string())
        .header("Referer", POLL_REFERER)
}

fn ensure_success<E>(phase: &'static str, status: u16) -> Result<(), WechatQrError<E>> {
    if (200..300).contains(&status) {
        Ok(())
    } else {
        Err(WechatQrError::HttpStatus { phase, status })
    }
}

fn parse_identifier<E>(page: &str) -> Result<String, WechatQrError<E>> {
    let (_, rest) = page
        .split_once("uuid=")
        .ok_or(WechatQrError::MissingIdentifier)?;
    let (identifier, _) = rest
        .split_once('"')
        .ok_or(WechatQrError::MissingIdentifier)?;

    if identifier.is_empty()
        || identifier.len() > 256
        || !identifier.bytes().all(|byte| byte.is_ascii_graphic())
    {
        return Err(WechatQrError::InvalidIdentifier);
    }

    Ok(identifier.to_owned())
}

fn encode_path_segment(value: &str) -> String {
    let mut encoded = String::with_capacity(value.len());
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'.' | b'_' | b'~') {
            encoded.push(char::from(byte));
        } else {
            write!(encoded, "%{byte:02X}").expect("writing to String cannot fail");
        }
    }
    encoded
}

fn image_media_type(bytes: &[u8]) -> Option<QrImageMediaType> {
    if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        Some(QrImageMediaType::Png)
    } else if bytes.starts_with(&[0xff, 0xd8, 0xff]) {
        Some(QrImageMediaType::Jpeg)
    } else {
        None
    }
}

fn parse_poll_result<E>(body: &str) -> Result<WechatQrPollResult, WechatQrError<E>> {
    const STATUS_PREFIX: &str = "window.wx_errcode=";
    const CODE_PREFIX: &str = "window.wx_code='";

    let (_, status_tail) = body
        .split_once(STATUS_PREFIX)
        .ok_or(WechatQrError::MissingPollStatus)?;
    let (status_text, _) = status_tail
        .split_once(';')
        .ok_or(WechatQrError::InvalidPollStatus)?;
    if status_text.is_empty() || !status_text.bytes().all(|byte| byte.is_ascii_digit()) {
        return Err(WechatQrError::InvalidPollStatus);
    }
    let status = status_text
        .parse::<u16>()
        .map_err(|_| WechatQrError::InvalidPollStatus)?;

    match status {
        408 => Ok(WechatQrPollResult::WaitingForScan),
        404 => Ok(WechatQrPollResult::ScannedAwaitingConfirmation),
        405 => {
            let (_, code_tail) = body
                .split_once(CODE_PREFIX)
                .ok_or(WechatQrError::MissingAuthorizationCode)?;
            let (code, _) = code_tail
                .split_once("';")
                .ok_or(WechatQrError::MissingAuthorizationCode)?;
            if code.is_empty() {
                return Err(WechatQrError::MissingAuthorizationCode);
            }
            Ok(WechatQrPollResult::Authorized(
                WechatAuthorizationCode::from_protocol(code.to_owned()),
            ))
        }
        402 => Ok(WechatQrPollResult::Expired),
        403 => Ok(WechatQrPollResult::Refused),
        status => Err(WechatQrError::UnrecognizedPollStatus { status }),
    }
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::convert::Infallible;
    use std::sync::Mutex;

    use super::{QrImageMediaType, WechatQrError, WechatQrPollResult};
    use crate::{HttpRequest, HttpResponse, HttpTransport, QqMusicClient};

    struct FakeTransport {
        responses: Mutex<VecDeque<HttpResponse>>,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl FakeTransport {
        fn new(responses: impl IntoIterator<Item = HttpResponse>) -> Self {
            Self {
                responses: Mutex::new(responses.into_iter().collect()),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn requests(&self) -> Vec<HttpRequest> {
            self.requests.lock().expect("request lock").clone()
        }
    }

    impl HttpTransport for FakeTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("request lock").push(request);
            Ok(self
                .responses
                .lock()
                .expect("response lock")
                .pop_front()
                .expect("fixture response"))
        }
    }

    fn connect_page(identifier: &str) -> Vec<u8> {
        format!(r#"<html><img data-purpose="qr" src="/connect/qrcode/uuid={identifier}" /></html>"#)
            .into_bytes()
    }

    fn poll_page(status: u16, code: &str) -> Vec<u8> {
        format!("window.wx_errcode={status};window.wx_code='{code}';").into_bytes()
    }

    #[tokio::test]
    async fn creates_session_from_exact_cross_validated_request() {
        let transport = FakeTransport::new([
            HttpResponse::new(200, connect_page("fixture-uuid")),
            HttpResponse::new(200, b"\xff\xd8\xfffixture-jpeg".to_vec()),
        ]);
        let client = QqMusicClient::new(transport);

        let session = client.create_wechat_qr().await.expect("valid QR session");

        assert_eq!(session.identifier(), "fixture-uuid");
        assert_eq!(session.image().media_type(), QrImageMediaType::Jpeg);
        let requests = client.transport().requests();
        assert_eq!(requests.len(), 2);
        assert_eq!(
            requests[0].url(),
            "https://open.weixin.qq.com/connect/qrconnect",
        );
        assert_eq!(requests[0].max_response_body_bytes(), 512 * 1024);
        assert_eq!(
            requests[0].query_pairs(),
            [
                ("appid".into(), "wx48db31d50e334801".into()),
                (
                    "redirect_uri".into(),
                    "https://y.qq.com/portal/wx_redirect.html?login_type=2&surl=https://y.qq.com/"
                        .into(),
                ),
                ("response_type".into(), "code".into()),
                ("scope".into(), "snsapi_login".into()),
                ("state".into(), "STATE".into()),
                (
                    "href".into(),
                    "https://y.qq.com/mediastyle/music_v17/src/css/popup_wechat.css#wechat_redirect"
                        .into(),
                ),
            ],
        );
        assert_eq!(
            requests[1].url(),
            "https://open.weixin.qq.com/connect/qrcode/fixture-uuid",
        );
        assert_eq!(requests[1].max_response_body_bytes(), 2 * 1024 * 1024);
        assert_eq!(
            requests[1].headers(),
            [(
                "Referer".into(),
                "https://open.weixin.qq.com/connect/qrconnect".into()
            )],
        );
    }

    #[tokio::test]
    async fn percent_encodes_identifier_as_one_path_segment() {
        let transport = FakeTransport::new([
            HttpResponse::new(200, connect_page("fixture+/=")),
            HttpResponse::new(200, b"\x89PNG\r\n\x1a\nfixture".to_vec()),
        ]);
        let client = QqMusicClient::new(transport);

        let session = client.create_wechat_qr().await.expect("valid QR session");

        assert_eq!(session.image().media_type(), QrImageMediaType::Png);
        assert_eq!(
            client.transport().requests()[1].url(),
            "https://open.weixin.qq.com/connect/qrcode/fixture%2B%2F%3D",
        );
    }

    #[tokio::test]
    async fn rejects_missing_identifier_before_image_request() {
        let transport = FakeTransport::new([HttpResponse::new(200, b"<html></html>".to_vec())]);
        let client = QqMusicClient::new(transport);

        let error = client.create_wechat_qr().await.expect_err("missing UUID");

        assert!(matches!(error, WechatQrError::MissingIdentifier));
        assert_eq!(client.transport().requests().len(), 1);
    }

    #[tokio::test]
    async fn rejects_non_image_response() {
        let transport = FakeTransport::new([
            HttpResponse::new(200, connect_page("fixture-uuid")),
            HttpResponse::new(200, b"<html>blocked</html>".to_vec()),
        ]);
        let client = QqMusicClient::new(transport);

        let error = client.create_wechat_qr().await.expect_err("invalid image");

        assert!(matches!(error, WechatQrError::InvalidImage));
    }

    #[tokio::test]
    async fn maps_http_status_to_the_precise_phase() {
        let transport = FakeTransport::new([HttpResponse::new(429, Vec::new())]);
        let client = QqMusicClient::new(transport);

        let error = client.create_wechat_qr().await.expect_err("rate limited");

        assert!(matches!(
            error,
            WechatQrError::HttpStatus {
                phase: "bootstrap",
                status: 429,
            },
        ));
    }

    #[tokio::test]
    async fn session_debug_output_redacts_identifier_and_image() {
        let transport = FakeTransport::new([
            HttpResponse::new(200, connect_page("secret-identifier")),
            HttpResponse::new(200, b"\xff\xd8\xffsecret-image".to_vec()),
        ]);
        let client = QqMusicClient::new(transport);

        let session = client.create_wechat_qr().await.expect("valid QR session");
        let debug = format!("{session:?}");

        assert!(!debug.contains("secret-identifier"));
        assert!(!debug.contains("secret-image"));
        assert!(debug.contains("REDACTED"));
    }

    #[tokio::test]
    async fn polls_with_cross_validated_request_and_maps_waiting_state() {
        let transport = FakeTransport::new([
            HttpResponse::new(200, connect_page("fixture-uuid")),
            HttpResponse::new(200, b"\xff\xd8\xfffixture-jpeg".to_vec()),
            HttpResponse::new(200, poll_page(408, "")),
        ]);
        let client = QqMusicClient::new(transport);
        let session = client.create_wechat_qr().await.expect("valid QR session");

        let result = client
            .poll_wechat_qr_at(&session, 1_777_777_777_123)
            .await
            .expect("valid poll result");

        assert_eq!(result, WechatQrPollResult::WaitingForScan);
        let requests = client.transport().requests();
        assert_eq!(requests.len(), 3);
        assert_eq!(
            requests[2].url(),
            "https://lp.open.weixin.qq.com/connect/l/qrconnect"
        );
        assert_eq!(
            requests[2].query_pairs(),
            [
                ("uuid".into(), "fixture-uuid".into()),
                ("_".into(), "1777777777123".into()),
            ]
        );
        assert_eq!(
            requests[2].headers(),
            [("Referer".into(), "https://open.weixin.qq.com/".into())]
        );
        assert_eq!(requests[2].max_response_body_bytes(), 64 * 1024);
        assert_eq!(
            requests[2].request_timeout(),
            Some(std::time::Duration::from_secs(35))
        );
    }

    #[tokio::test]
    async fn maps_scanned_expired_and_refused_states_without_guessing() {
        for (status, expected) in [
            (404, WechatQrPollResult::ScannedAwaitingConfirmation),
            (402, WechatQrPollResult::Expired),
            (403, WechatQrPollResult::Refused),
        ] {
            let transport = FakeTransport::new([
                HttpResponse::new(200, connect_page("fixture-uuid")),
                HttpResponse::new(200, b"\xff\xd8\xfffixture-jpeg".to_vec()),
                HttpResponse::new(200, poll_page(status, "")),
            ]);
            let client = QqMusicClient::new(transport);
            let session = client.create_wechat_qr().await.expect("valid QR session");

            let actual = client
                .poll_wechat_qr_at(&session, 1)
                .await
                .expect("known poll status");

            assert_eq!(actual, expected);
        }
    }

    #[tokio::test]
    async fn authorized_result_carries_but_does_not_log_the_code() {
        let transport = FakeTransport::new([
            HttpResponse::new(200, connect_page("fixture-uuid")),
            HttpResponse::new(200, b"\xff\xd8\xfffixture-jpeg".to_vec()),
            HttpResponse::new(200, poll_page(405, "secret-oauth-code")),
        ]);
        let client = QqMusicClient::new(transport);
        let session = client.create_wechat_qr().await.expect("valid QR session");

        let result = client
            .poll_wechat_qr_at(&session, 1)
            .await
            .expect("authorized poll status");

        let WechatQrPollResult::Authorized(code) = &result else {
            panic!("expected authorized result");
        };
        assert_eq!(code.expose(), "secret-oauth-code");
        assert!(!format!("{result:?}").contains("secret-oauth-code"));
    }

    #[tokio::test]
    async fn rejects_unknown_status_and_confirmed_result_without_code() {
        for (body, expected_debug) in [
            (poll_page(499, ""), "UnrecognizedPollStatus { status: 499 }"),
            (poll_page(405, ""), "MissingAuthorizationCode"),
        ] {
            let transport = FakeTransport::new([
                HttpResponse::new(200, connect_page("fixture-uuid")),
                HttpResponse::new(200, b"\xff\xd8\xfffixture-jpeg".to_vec()),
                HttpResponse::new(200, body),
            ]);
            let client = QqMusicClient::new(transport);
            let session = client.create_wechat_qr().await.expect("valid QR session");

            let actual = client
                .poll_wechat_qr_at(&session, 1)
                .await
                .expect_err("invalid poll response");

            assert_eq!(format!("{actual:?}"), expected_debug);
        }
    }

    #[tokio::test]
    async fn rejects_unbounded_or_malformed_poll_responses() {
        for (body, expected_debug) in [
            (vec![b'x'; 64 * 1024 + 1], "PollResponseTooLarge"),
            (vec![0xff], "PollResponseNotUtf8"),
            (b"window.wx_code='';".to_vec(), "MissingPollStatus"),
            (
                b"window.wx_errcode=not-a-number;window.wx_code='';".to_vec(),
                "InvalidPollStatus",
            ),
        ] {
            let transport = FakeTransport::new([
                HttpResponse::new(200, connect_page("fixture-uuid")),
                HttpResponse::new(200, b"\xff\xd8\xfffixture-jpeg".to_vec()),
                HttpResponse::new(200, body),
            ]);
            let client = QqMusicClient::new(transport);
            let session = client.create_wechat_qr().await.expect("valid QR session");

            let actual = client
                .poll_wechat_qr_at(&session, 1)
                .await
                .expect_err("invalid poll response");

            assert_eq!(format!("{actual:?}"), expected_debug);
        }
    }
}
