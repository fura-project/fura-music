use std::fmt;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use getrandom::fill;
use serde::Serialize;
use url::Url;

use crate::login_credential::{LoginCredentialError, decode_login_credential};
use crate::{
    Credential, HttpRequest, HttpResponse, HttpTransport, LoginType, QqMusicClient, QrImage,
    QrImageMediaType,
};

const QR_URL: &str = "https://ssl.ptlogin2.qq.com/ptqrshow";
const POLL_URL: &str = "https://ssl.ptlogin2.qq.com/ptqrlogin";
const CHECK_SIG_URL: &str = "https://ssl.ptlogin2.graph.qq.com/check_sig";
const AUTHORIZE_URL: &str = "https://graph.qq.com/oauth2.0/authorize";
const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const LOGIN_JUMP_URL: &str = "https://graph.qq.com/oauth2.0/login_jump";
const QR_REFERER: &str = "https://xui.ptlogin2.qq.com/";
const WEB_USER_AGENT: &str = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 \
                              (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
const QQ_CONNECT_APP_ID: &str = "100497308";
const QR_APP_ID: &str = "716027609";
const DAID: &str = "383";
const MAX_IMAGE_BYTES: usize = 2 * 1024 * 1024;
const MAX_TEXT_BYTES: usize = 128 * 1024;
const MAX_LOGIN_BYTES: usize = 512 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqQrPollResult {
    WaitingForScan,
    ScannedAwaitingConfirmation,
    Authorized,
    Expired,
    Refused,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqQrSession {
    qrsig: String,
    image: QrImage,
    authorization: Option<QqQrAuthorization>,
}

impl QqQrSession {
    #[must_use]
    pub const fn image(&self) -> &QrImage {
        &self.image
    }

    pub(crate) fn take_authorization(&mut self) -> Option<QqQrAuthorization> {
        self.authorization.take()
    }
}

impl fmt::Debug for QqQrSession {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqQrSession")
            .field("qrsig", &"[REDACTED]")
            .field("image", &self.image)
            .field("authorization_ready", &self.authorization.is_some())
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqQrAuthorization {
    uin: String,
    sigx: String,
    qrsig: String,
}

impl fmt::Debug for QqQrAuthorization {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("QqQrAuthorization([REDACTED])")
    }
}

pub enum QqQrError<E> {
    Transport(E),
    HttpStatus { phase: &'static str, status: u16 },
    InvalidImage,
    MissingQrsig,
    InvalidCookie,
    ClockBeforeUnixEpoch,
    RandomnessUnavailable,
    ResponseNotUtf8,
    InvalidPollResponse,
    UnrecognizedPollStatus(u16),
    MissingAuthorization,
    MissingPSkey,
    MissingRedirect,
    MissingAuthorizationCode,
    Serialize,
    Credential(LoginCredentialError),
}

impl<E> fmt::Debug for QqQrError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Transport(_) => formatter.write_str("Transport([REDACTED])"),
            Self::HttpStatus { phase, status } => formatter
                .debug_struct("HttpStatus")
                .field("phase", phase)
                .field("status", status)
                .finish(),
            Self::InvalidImage => formatter.write_str("InvalidImage"),
            Self::MissingQrsig => formatter.write_str("MissingQrsig"),
            Self::InvalidCookie => formatter.write_str("InvalidCookie"),
            Self::ClockBeforeUnixEpoch => formatter.write_str("ClockBeforeUnixEpoch"),
            Self::RandomnessUnavailable => formatter.write_str("RandomnessUnavailable"),
            Self::ResponseNotUtf8 => formatter.write_str("ResponseNotUtf8"),
            Self::InvalidPollResponse => formatter.write_str("InvalidPollResponse"),
            Self::UnrecognizedPollStatus(status) => formatter
                .debug_tuple("UnrecognizedPollStatus")
                .field(status)
                .finish(),
            Self::MissingAuthorization => formatter.write_str("MissingAuthorization"),
            Self::MissingPSkey => formatter.write_str("MissingPSkey"),
            Self::MissingRedirect => formatter.write_str("MissingRedirect"),
            Self::MissingAuthorizationCode => formatter.write_str("MissingAuthorizationCode"),
            Self::Serialize => formatter.write_str("Serialize"),
            Self::Credential(error) => formatter.debug_tuple("Credential").field(error).finish(),
        }
    }
}

impl<E> fmt::Display for QqQrError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Transport(_) => formatter.write_str("QQ QR network request failed"),
            Self::HttpStatus { phase, status } => {
                write!(formatter, "QQ QR {phase} returned HTTP {status}")
            }
            Self::InvalidImage => formatter.write_str("QQ QR response is not a PNG image"),
            Self::MissingQrsig | Self::InvalidCookie => {
                formatter.write_str("QQ QR response did not establish a valid session")
            }
            Self::ClockBeforeUnixEpoch => formatter.write_str("system clock is invalid"),
            Self::RandomnessUnavailable => formatter.write_str("secure randomness is unavailable"),
            Self::ResponseNotUtf8 | Self::InvalidPollResponse => {
                formatter.write_str("QQ QR returned an invalid response")
            }
            Self::UnrecognizedPollStatus(status) => {
                write!(formatter, "QQ QR returned unknown status {status}")
            }
            Self::MissingAuthorization
            | Self::MissingPSkey
            | Self::MissingRedirect
            | Self::MissingAuthorizationCode => {
                formatter.write_str("QQ authorization response was incomplete")
            }
            Self::Serialize | Self::Credential(_) => {
                formatter.write_str("QQ Music rejected an invalid login response")
            }
        }
    }
}

impl<E> std::error::Error for QqQrError<E>
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
    /// Creates a first-party QQ Web QR challenge.
    ///
    /// # Errors
    ///
    /// Returns a transport, HTTP, image, cookie, or clock error when a bounded
    /// challenge cannot be created safely.
    pub async fn create_qq_qr(&self) -> Result<QqQrSession, QqQrError<T::Error>> {
        let timestamp = unix_millis()?;
        let response = self
            .transport()
            .execute(
                HttpRequest::get(QR_URL)
                    .query("appid", QR_APP_ID)
                    .query("e", "2")
                    .query("l", "M")
                    .query("s", "3")
                    .query("d", "72")
                    .query("v", "4")
                    .query("t", format!("0.{timestamp}"))
                    .query("daid", DAID)
                    .query("pt_3rd_aid", QQ_CONNECT_APP_ID)
                    .header("Referer", QR_REFERER)
                    .header("User-Agent", WEB_USER_AGENT)
                    .response_body_limit(MAX_IMAGE_BYTES)
                    .timeout(REQUEST_TIMEOUT),
            )
            .await
            .map_err(QqQrError::Transport)?;
        ensure_success("bootstrap", response.status())?;
        if !response.body().starts_with(b"\x89PNG\r\n\x1a\n") {
            return Err(QqQrError::InvalidImage);
        }
        let qrsig = response
            .header_values("set-cookie")
            .find_map(|header| cookie_value(header, "qrsig"))
            .ok_or(QqQrError::MissingQrsig)?;
        validate_cookie_value(&qrsig)?;

        Ok(QqQrSession {
            qrsig,
            image: QrImage::from_protocol(QrImageMediaType::Png, response.body().to_vec()),
            authorization: None,
        })
    }

    /// Advances an existing QQ Web QR challenge by one bounded poll.
    ///
    /// # Errors
    ///
    /// Returns a transport, HTTP, protocol-shape, status, or clock error. Any
    /// authorization values remain inside the secret-bearing session.
    pub async fn poll_qq_qr(
        &self,
        session: &mut QqQrSession,
    ) -> Result<QqQrPollResult, QqQrError<T::Error>> {
        let timestamp = unix_millis()?;
        let response = self
            .transport()
            .execute(
                HttpRequest::get(POLL_URL)
                    .query("u1", LOGIN_JUMP_URL)
                    .query("ptqrtoken", hash33(&session.qrsig, 0).to_string())
                    .query("ptredirect", "0")
                    .query("h", "1")
                    .query("t", "1")
                    .query("g", "1")
                    .query("from_ui", "1")
                    .query("ptlang", "2052")
                    .query("action", format!("0-0-{timestamp}"))
                    .query("js_ver", "20102616")
                    .query("js_type", "1")
                    .query("pt_uistyle", "40")
                    .query("aid", QR_APP_ID)
                    .query("daid", DAID)
                    .query("pt_3rd_aid", QQ_CONNECT_APP_ID)
                    .query("has_onekey", "1")
                    .header("Referer", QR_REFERER)
                    .header("User-Agent", WEB_USER_AGENT)
                    .header("Cookie", format!("qrsig={}", session.qrsig))
                    .response_body_limit(MAX_TEXT_BYTES)
                    .timeout(REQUEST_TIMEOUT),
            )
            .await
            .map_err(QqQrError::Transport)?;
        ensure_success("poll", response.status())?;
        let body = std::str::from_utf8(response.body()).map_err(|_| QqQrError::ResponseNotUtf8)?;
        let args = parse_callback_args(body).ok_or(QqQrError::InvalidPollResponse)?;
        let status = args
            .first()
            .and_then(|value| value.parse::<u16>().ok())
            .ok_or(QqQrError::InvalidPollResponse)?;
        match status {
            66 => Ok(QqQrPollResult::WaitingForScan),
            67 => Ok(QqQrPollResult::ScannedAwaitingConfirmation),
            65 => Ok(QqQrPollResult::Expired),
            68 => Ok(QqQrPollResult::Refused),
            0 => {
                let redirect = args.get(2).ok_or(QqQrError::MissingAuthorization)?;
                let url = Url::parse(redirect).map_err(|_| QqQrError::MissingAuthorization)?;
                let uin = query_value(&url, "uin").ok_or(QqQrError::MissingAuthorization)?;
                let sigx = query_value(&url, "ptsigx").ok_or(QqQrError::MissingAuthorization)?;
                session.authorization = Some(QqQrAuthorization {
                    uin,
                    sigx,
                    qrsig: session.qrsig.clone(),
                });
                Ok(QqQrPollResult::Authorized)
            }
            status => Err(QqQrError::UnrecognizedPollStatus(status)),
        }
    }

    /// Exchanges an approved QQ Web authorization for a QQ Music credential.
    ///
    /// # Errors
    ///
    /// Returns a transport, HTTP, redirect, authorization, serialization, or
    /// credential-decoding error without exposing authorization values.
    pub async fn exchange_qq_qr(
        &self,
        authorization: &QqQrAuthorization,
    ) -> Result<Credential, QqQrError<T::Error>> {
        let check = self
            .transport()
            .execute(
                HttpRequest::get(CHECK_SIG_URL)
                    .query("uin", &authorization.uin)
                    .query("pttype", "1")
                    .query("service", "ptqrlogin")
                    .query("nodirect", "0")
                    .query("ptsigx", &authorization.sigx)
                    .query("s_url", LOGIN_JUMP_URL)
                    .query("ptlang", "2052")
                    .query("ptredirect", "100")
                    .query("aid", QR_APP_ID)
                    .query("daid", DAID)
                    .query("j_later", "0")
                    .query("low_login_hour", "0")
                    .query("regmaster", "0")
                    .query("pt_login_type", "3")
                    .query("pt_aid", "0")
                    .query("pt_aaid", "16")
                    .query("pt_light", "0")
                    .query("pt_3rd_aid", QQ_CONNECT_APP_ID)
                    .header("Referer", QR_REFERER)
                    .header("User-Agent", WEB_USER_AGENT)
                    .header("Cookie", format!("qrsig={}", authorization.qrsig))
                    .follow_redirects(false)
                    .response_body_limit(MAX_TEXT_BYTES)
                    .timeout(REQUEST_TIMEOUT),
            )
            .await
            .map_err(QqQrError::Transport)?;
        ensure_redirect_or_success("check signature", check.status())?;
        let cookies = response_cookies(&check);
        let p_skey = cookies
            .iter()
            .find_map(|(name, value)| (name == "p_skey").then_some(value.as_str()))
            .ok_or(QqQrError::MissingPSkey)?;
        let cookie_header = cookies
            .iter()
            .map(|(name, value)| format!("{name}={value}"))
            .collect::<Vec<_>>()
            .join("; ");
        let body = authorize_form(p_skey)?;
        let authorize = self
            .transport()
            .execute(
                HttpRequest::post(AUTHORIZE_URL)
                    .header("Content-Type", "application/x-www-form-urlencoded")
                    .header("User-Agent", WEB_USER_AGENT)
                    .header("Cookie", cookie_header)
                    .body(body.into_bytes())
                    .follow_redirects(false)
                    .response_body_limit(MAX_TEXT_BYTES)
                    .timeout(REQUEST_TIMEOUT),
            )
            .await
            .map_err(QqQrError::Transport)?;
        ensure_redirect_or_success("authorization", authorize.status())?;
        let location = authorize
            .header_values("location")
            .next()
            .ok_or(QqQrError::MissingRedirect)?;
        let location = Url::parse(location).map_err(|_| QqQrError::MissingRedirect)?;
        let code = query_value(&location, "code").ok_or(QqQrError::MissingAuthorizationCode)?;

        let payload =
            serde_json::to_vec(&QqLoginRequest::new(&code)).map_err(|_| QqQrError::Serialize)?;
        let login = self
            .transport()
            .execute(
                HttpRequest::post(MUSICU_URL)
                    .header("Content-Type", "application/json")
                    .header("User-Agent", WEB_USER_AGENT)
                    .header("Origin", "https://y.qq.com")
                    .header("Referer", "https://y.qq.com/")
                    .body(payload)
                    .response_body_limit(MAX_LOGIN_BYTES)
                    .timeout(REQUEST_TIMEOUT),
            )
            .await
            .map_err(QqQrError::Transport)?;
        ensure_success("credential exchange", login.status())?;
        decode_login_credential(
            login.body(),
            "QQConnectLogin.LoginServer.QQLogin",
            LoginType::QQ,
        )
        .map_err(QqQrError::Credential)
    }
}

impl QrImage {
    pub(crate) fn from_protocol(media_type: QrImageMediaType, bytes: Vec<u8>) -> Self {
        Self::new_for_protocol(media_type, bytes)
    }
}

#[derive(Serialize)]
struct QqLoginRequest<'a> {
    comm: QqLoginComm,
    #[serde(rename = "QQConnectLogin.LoginServer.QQLogin")]
    login: QqLoginRpc<'a>,
}

impl<'a> QqLoginRequest<'a> {
    const fn new(code: &'a str) -> Self {
        Self {
            comm: QqLoginComm {
                cv: 13_020_508,
                version: 13_020_508,
                client_type: "11",
                app_id: "qqmusic",
                format: "json",
                login_type: 2,
            },
            login: QqLoginRpc {
                module: "QQConnectLogin.LoginServer",
                method: "QQLogin",
                param: QqLoginParam { code },
            },
        }
    }
}

#[derive(Serialize)]
struct QqLoginComm {
    cv: u32,
    #[serde(rename = "v")]
    version: u32,
    #[serde(rename = "ct")]
    client_type: &'static str,
    #[serde(rename = "tmeAppID")]
    app_id: &'static str,
    format: &'static str,
    #[serde(rename = "tmeLoginType")]
    login_type: u32,
}

#[derive(Serialize)]
struct QqLoginRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: QqLoginParam<'a>,
}

#[derive(Serialize)]
struct QqLoginParam<'a> {
    code: &'a str,
}

fn authorize_form<E>(p_skey: &str) -> Result<String, QqQrError<E>> {
    let timestamp = unix_millis()?;
    let ui = random_uuid()?;
    Ok(url::form_urlencoded::Serializer::new(String::new())
        .append_pair("response_type", "code")
        .append_pair("client_id", QQ_CONNECT_APP_ID)
        .append_pair(
            "redirect_uri",
            "https://y.qq.com/portal/wx_redirect.html?login_type=1&surl=https://y.qq.com/",
        )
        .append_pair("scope", "get_user_info,get_app_friends")
        .append_pair("state", "state")
        .append_pair("switch", "")
        .append_pair("from_ptlogin", "1")
        .append_pair("src", "1")
        .append_pair("update_auth", "1")
        .append_pair("openapi", "1010_1030")
        .append_pair("g_tk", &hash33(p_skey, 5381).to_string())
        .append_pair("auth_time", &timestamp.to_string())
        .append_pair("ui", &ui)
        .finish())
}

fn random_uuid<E>() -> Result<String, QqQrError<E>> {
    let mut bytes = [0_u8; 16];
    fill(&mut bytes).map_err(|_| QqQrError::RandomnessUnavailable)?;
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    Ok(format!(
        "{:02x}{:02x}{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
        bytes[0],
        bytes[1],
        bytes[2],
        bytes[3],
        bytes[4],
        bytes[5],
        bytes[6],
        bytes[7],
        bytes[8],
        bytes[9],
        bytes[10],
        bytes[11],
        bytes[12],
        bytes[13],
        bytes[14],
        bytes[15]
    ))
}

fn unix_millis<E>() -> Result<u128, QqQrError<E>> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .map_err(|_| QqQrError::ClockBeforeUnixEpoch)
}

fn hash33(value: &str, initial: u32) -> u32 {
    value.bytes().fold(initial, |hash, byte| {
        (hash << 5).wrapping_add(hash).wrapping_add(u32::from(byte))
    }) & 0x7fff_ffff
}

fn parse_callback_args(body: &str) -> Option<Vec<String>> {
    let start = body.find("ptuiCB(")? + "ptuiCB(".len();
    let end = body[start..].find(')')? + start;
    let mut values = Vec::new();
    let mut chars = body[start..end].chars().peekable();
    while let Some(character) = chars.next() {
        if character != '\'' {
            continue;
        }
        let mut value = String::new();
        while let Some(character) = chars.next() {
            match character {
                '\\' => value.push(chars.next()?),
                '\'' => break,
                character => value.push(character),
            }
        }
        values.push(value);
    }
    (!values.is_empty()).then_some(values)
}

fn response_cookies(response: &HttpResponse) -> Vec<(String, String)> {
    response
        .header_values("set-cookie")
        .filter_map(|header| {
            let pair = header.split(';').next()?;
            let (name, value) = pair.split_once('=')?;
            let name = name.trim();
            let value = value.trim();
            (!name.is_empty() && is_valid_cookie_value(value))
                .then(|| (name.to_owned(), value.to_owned()))
        })
        .collect()
}

fn cookie_value(header: &str, expected_name: &str) -> Option<String> {
    let pair = header.split(';').next()?;
    let (name, value) = pair.split_once('=')?;
    (name.trim() == expected_name).then(|| value.trim().to_owned())
}

fn validate_cookie_value<E>(value: &str) -> Result<(), QqQrError<E>> {
    if is_valid_cookie_value(value) {
        Ok(())
    } else {
        Err(QqQrError::InvalidCookie)
    }
}

fn is_valid_cookie_value(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 4096
        && !value.bytes().any(|byte| byte <= 0x20 || byte == b';')
}

fn query_value(url: &Url, name: &str) -> Option<String> {
    url.query_pairs()
        .find_map(|(candidate, value)| (candidate == name).then(|| value.into_owned()))
        .filter(|value| !value.is_empty())
}

fn ensure_success<E>(phase: &'static str, status: u16) -> Result<(), QqQrError<E>> {
    if (200..300).contains(&status) {
        Ok(())
    } else {
        Err(QqQrError::HttpStatus { phase, status })
    }
}

fn ensure_redirect_or_success<E>(phase: &'static str, status: u16) -> Result<(), QqQrError<E>> {
    if (200..400).contains(&status) {
        Ok(())
    } else {
        Err(QqQrError::HttpStatus { phase, status })
    }
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::Value;

    use super::{QqQrPollResult, hash33};
    use crate::{HttpRequest, HttpResponse, HttpTransport, LoginType, QqMusicClient};

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

    fn png() -> Vec<u8> {
        b"\x89PNG\r\n\x1a\nfixture".to_vec()
    }

    #[test]
    fn uses_the_distinct_qq_token_and_oauth_hash33_seeds() {
        assert_eq!(hash33("secret-qrsig", 0), 318_298_937);
        assert_eq!(hash33("secret-p-skey", 5381), 1_473_895_633);
    }

    #[tokio::test]
    async fn creates_and_polls_qq_web_qr_without_exposing_qrsig() {
        let transport = FakeTransport::new([
            HttpResponse::new(200, png()).with_headers(vec![(
                "set-cookie".into(),
                "qrsig=secret-qrsig; Path=/; Secure".into(),
            )]),
            HttpResponse::new(
                200,
                b"ptuiCB('0','0','https://graph.qq.com/oauth2.0/login_jump?uin=123456&service=ptqrlogin&ptsigx=secret-sigx&s_url=x','0','ok','');".to_vec(),
            ),
        ]);
        let client = QqMusicClient::new(transport);
        let mut session = client.create_qq_qr().await.expect("QQ QR bootstrap");
        assert_eq!(
            client.poll_qq_qr(&mut session).await.expect("QQ QR poll"),
            QqQrPollResult::Authorized
        );
        let requests = client.transport().requests();
        assert_eq!(requests[0].url(), "https://ssl.ptlogin2.qq.com/ptqrshow");
        assert_eq!(requests[1].url(), "https://ssl.ptlogin2.qq.com/ptqrlogin");
        assert!(
            requests[1]
                .query_pairs()
                .contains(&("ptqrtoken".into(), hash33("secret-qrsig", 0).to_string()))
        );
        assert!(!format!("{session:?}").contains("secret-qrsig"));
        assert!(!format!("{:?}", requests[1]).contains("secret-qrsig"));
    }

    #[tokio::test]
    async fn exchanges_confirmed_qq_authorization_through_redirect_chain() {
        let credential = serde_json::json!({
            "code": 0,
            "QQConnectLogin.LoginServer.QQLogin": {
                "code": 0,
                "data": {
                    "str_musicid": "456",
                    "musickey": "secret-music-key",
                    "loginType": 2,
                    "refresh_token": "secret-refresh"
                }
            }
        });
        let transport = FakeTransport::new([
            HttpResponse::new(200, png()).with_headers(vec![(
                "set-cookie".into(),
                "qrsig=secret-qrsig; Path=/".into(),
            )]),
            HttpResponse::new(
                200,
                b"ptuiCB('0','0','https://graph.qq.com/oauth2.0/login_jump?uin=456&service=ptqrlogin&ptsigx=secret-sigx&s_url=x','0','ok','');".to_vec(),
            ),
            HttpResponse::new(302, Vec::new()).with_headers(vec![
                ("set-cookie".into(), "p_skey=secret-p-skey; Path=/".into()),
                ("set-cookie".into(), "uin=o0456; Path=/".into()),
            ]),
            HttpResponse::new(302, Vec::new()).with_headers(vec![(
                "location".into(),
                "https://y.qq.com/portal/wx_redirect.html?code=secret-code&state=state".into(),
            )]),
            HttpResponse::new(200, serde_json::to_vec(&credential).expect("fixture JSON")),
        ]);
        let client = QqMusicClient::new(transport);
        let mut session = client.create_qq_qr().await.expect("QQ QR bootstrap");
        client.poll_qq_qr(&mut session).await.expect("QQ QR poll");
        let authorization = session.take_authorization().expect("authorization");
        let credential = client
            .exchange_qq_qr(&authorization)
            .await
            .expect("QQ credential");

        assert_eq!(credential.login_type(), LoginType::QQ);
        assert_eq!(credential.music_id(), "456");
        let requests = client.transport().requests();
        assert!(!requests[2].redirects_are_followed());
        assert!(!requests[3].redirects_are_followed());
        let form = std::str::from_utf8(requests[3].body_bytes().expect("authorize form"))
            .expect("UTF-8 form");
        assert!(form.contains("g_tk="));
        let login: Value =
            serde_json::from_slice(requests[4].body_bytes().expect("QQ Music login JSON"))
                .expect("valid login JSON");
        assert_eq!(login["comm"]["tmeLoginType"], 2);
        assert_eq!(
            login["QQConnectLogin.LoginServer.QQLogin"]["param"]["code"],
            "secret-code"
        );
        assert!(!format!("{:?}", requests[4]).contains("secret-code"));
        assert!(!format!("{credential:?}").contains("secret-music-key"));
    }
}
