use std::fmt;
use std::fmt::Write as _;

use crate::{HttpRequest, HttpTransport, QqMusicClient};

const CONNECT_URL: &str = "https://open.weixin.qq.com/connect/qrconnect";
const IMAGE_URL_PREFIX: &str = "https://open.weixin.qq.com/connect/qrcode/";
const WECHAT_APP_ID: &str = "wx48db31d50e334801";
const REDIRECT_URI: &str =
    "https://y.qq.com/portal/wx_redirect.html?login_type=2&surl=https://y.qq.com/";
const STYLE_HREF: &str =
    "https://y.qq.com/mediastyle/music_v17/src/css/popup_wechat.css#wechat_redirect";
const MAX_CONNECT_PAGE_BYTES: usize = 512 * 1024;
const MAX_QR_IMAGE_BYTES: usize = 2 * 1024 * 1024;

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

pub enum WechatQrError<E> {
    Transport(E),
    HttpStatus { phase: &'static str, status: u16 },
    ConnectPageTooLarge,
    ConnectPageNotUtf8,
    MissingIdentifier,
    InvalidIdentifier,
    ImageTooLarge,
    InvalidImage,
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

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::convert::Infallible;
    use std::sync::Mutex;

    use super::{QrImageMediaType, WechatQrError};
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
}
