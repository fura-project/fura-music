use std::fmt;
use std::fmt::Write as _;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use getrandom::fill;
use serde_json::Value;
use url::Url;

use crate::qq_qr::{
    DAID, LOGIN_JUMP_URL, QQ_CONNECT_APP_ID, QR_APP_ID, QR_REFERER, WEB_USER_AGENT, hash33,
    is_valid_cookie_value, response_cookies,
};
use crate::{Credential, HttpRequest, HttpTransport, QqMusicClient, QqQrError};

const LOCAL_LOGIN_HOST: &str = "localhost.ptlogin2.qq.com";
const LOCAL_LOGIN_PORTS: [u16; 5] = [4301, 4303, 4305, 4307, 4309];
const LOGIN_JUMP_URL_BASE: &str = "https://ssl.ptlogin2.qq.com/jump";
const MAX_LOCAL_RESPONSE_BYTES: usize = 64 * 1024;
const MAX_LOCAL_ACCOUNTS: usize = 10;
const LOCAL_DISCOVERY_TIMEOUT: Duration = Duration::from_millis(500);
const LOCAL_AUTHORIZATION_TIMEOUT: Duration = Duration::from_secs(8);
const REMOTE_AUTHORIZATION_TIMEOUT: Duration = Duration::from_secs(30);

#[derive(Clone, Eq, PartialEq)]
pub struct QqDesktopQuickLoginAccount {
    selection_id: u32,
    display_name: String,
    account_hint: String,
}

impl QqDesktopQuickLoginAccount {
    #[must_use]
    pub const fn selection_id(&self) -> u32 {
        self.selection_id
    }

    #[must_use]
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    #[must_use]
    pub fn account_hint(&self) -> &str {
        &self.account_hint
    }
}

impl fmt::Debug for QqDesktopQuickLoginAccount {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqDesktopQuickLoginAccount")
            .field("selection_id", &self.selection_id)
            .field("display_name", &"[REDACTED]")
            .field("account_hint", &"[REDACTED]")
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
struct LocalAccount {
    presentation: QqDesktopQuickLoginAccount,
    uin: String,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqDesktopQuickLoginSession {
    local_token: String,
    port: u16,
    accounts: Vec<LocalAccount>,
}

impl QqDesktopQuickLoginSession {
    #[must_use]
    pub fn accounts(&self) -> Vec<QqDesktopQuickLoginAccount> {
        self.accounts
            .iter()
            .map(|account| account.presentation.clone())
            .collect()
    }

    fn account(&self, selection_id: u32) -> Option<&LocalAccount> {
        self.accounts
            .iter()
            .find(|account| account.presentation.selection_id == selection_id)
    }
}

impl fmt::Debug for QqDesktopQuickLoginSession {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqDesktopQuickLoginSession")
            .field("local_token", &"[REDACTED]")
            .field("port", &self.port)
            .field("account_count", &self.accounts.len())
            .finish()
    }
}

pub enum QqDesktopQuickLoginError<E> {
    ClientUnavailable,
    Transport(E),
    HttpStatus { phase: &'static str, status: u16 },
    InvalidResponse,
    InvalidSelection,
    MissingClientKey,
    Rejected,
    RandomnessUnavailable,
    ClockBeforeUnixEpoch,
    QqConnect(QqQrError<E>),
}

impl<E> fmt::Debug for QqDesktopQuickLoginError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ClientUnavailable => formatter.write_str("ClientUnavailable"),
            Self::Transport(_) => formatter.write_str("Transport([REDACTED])"),
            Self::HttpStatus { phase, status } => formatter
                .debug_struct("HttpStatus")
                .field("phase", phase)
                .field("status", status)
                .finish(),
            Self::InvalidResponse => formatter.write_str("InvalidResponse"),
            Self::InvalidSelection => formatter.write_str("InvalidSelection"),
            Self::MissingClientKey => formatter.write_str("MissingClientKey"),
            Self::Rejected => formatter.write_str("Rejected"),
            Self::RandomnessUnavailable => formatter.write_str("RandomnessUnavailable"),
            Self::ClockBeforeUnixEpoch => formatter.write_str("ClockBeforeUnixEpoch"),
            Self::QqConnect(error) => formatter.debug_tuple("QqConnect").field(error).finish(),
        }
    }
}

impl<E> fmt::Display for QqDesktopQuickLoginError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ClientUnavailable => formatter.write_str("desktop QQ quick login is unavailable"),
            Self::Transport(_) => formatter.write_str("desktop QQ quick login request failed"),
            Self::HttpStatus { phase, status } => {
                write!(formatter, "desktop QQ {phase} returned HTTP {status}")
            }
            Self::InvalidResponse => {
                formatter.write_str("desktop QQ returned an invalid quick-login response")
            }
            Self::InvalidSelection => formatter.write_str("desktop QQ account choice is invalid"),
            Self::MissingClientKey => {
                formatter.write_str("desktop QQ did not return a quick-login ticket")
            }
            Self::Rejected => formatter.write_str("desktop QQ quick login was rejected"),
            Self::RandomnessUnavailable => {
                formatter.write_str("desktop QQ quick login could not create a local token")
            }
            Self::ClockBeforeUnixEpoch => {
                formatter.write_str("desktop QQ quick login clock is invalid")
            }
            Self::QqConnect(error) => error.fmt(formatter),
        }
    }
}

impl<E> std::error::Error for QqDesktopQuickLoginError<E>
where
    E: std::error::Error + 'static,
{
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Transport(error) => Some(error),
            Self::QqConnect(error) => Some(error),
            _ => None,
        }
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Discovers accounts exposed by the loopback-only quick-login service of
    /// a running desktop QQ client.
    ///
    /// # Errors
    ///
    /// Returns a typed local-client, transport, HTTP, parsing, clock, or
    /// randomness failure without logging account data.
    pub async fn discover_desktop_qq_accounts(
        &self,
    ) -> Result<QqDesktopQuickLoginSession, QqDesktopQuickLoginError<T::Error>> {
        let local_token = local_token()?;
        let cache_buster = cache_buster()?;
        for port in LOCAL_LOGIN_PORTS {
            let response = self
                .transport()
                .execute(local_request(
                    port,
                    "pt_get_uins",
                    &local_token,
                    cache_buster,
                    [("callback", "ptui_getuins_CB")],
                    LOCAL_DISCOVERY_TIMEOUT,
                ))
                .await;
            let Ok(response) = response else {
                continue;
            };
            ensure_success("account discovery", response.status())?;
            let accounts = parse_accounts(response.body())?;
            return Ok(QqDesktopQuickLoginSession {
                local_token,
                port,
                accounts,
            });
        }
        Err(QqDesktopQuickLoginError::ClientUnavailable)
    }

    /// Requests a one-time ticket from desktop QQ for the selected account and
    /// exchanges the resulting QQ Connect authorization for a QQ Music
    /// credential.
    ///
    /// # Errors
    ///
    /// Returns a typed local-client, selection, transport, response,
    /// authorization, or credential-exchange failure.
    pub async fn authorize_desktop_qq_account(
        &self,
        session: &QqDesktopQuickLoginSession,
        selection_id: u32,
    ) -> Result<Credential, QqDesktopQuickLoginError<T::Error>> {
        let account = session
            .account(selection_id)
            .ok_or(QqDesktopQuickLoginError::InvalidSelection)?;
        let cache_buster = cache_buster()?;
        let ticket = self
            .transport()
            .execute(local_request(
                session.port,
                "pt_get_st",
                &session.local_token,
                cache_buster,
                [
                    ("callback", "ptui_getst_CB"),
                    ("clientuin", account.uin.as_str()),
                ],
                LOCAL_AUTHORIZATION_TIMEOUT,
            ))
            .await
            .map_err(QqDesktopQuickLoginError::Transport)?;
        ensure_success("ticket request", ticket.status())?;
        let ticket_payload = parse_jsonp(ticket.body(), "ptui_getst_CB")?
            .as_object()
            .ok_or(QqDesktopQuickLoginError::InvalidResponse)?
            .clone();
        if ticket_payload.get("uin").and_then(protocol_uin).as_deref() != Some(account.uin.as_str())
        {
            return Err(QqDesktopQuickLoginError::InvalidResponse);
        }
        let key_index = ticket_payload
            .get("keyindex")
            .and_then(protocol_u64)
            .unwrap_or(9);
        if key_index > 99 {
            return Err(QqDesktopQuickLoginError::InvalidResponse);
        }
        let ticket_cookies = response_cookies(&ticket);
        let client_key = ticket_cookies
            .iter()
            .find_map(|(name, value)| (name == "clientkey").then_some(value.as_str()))
            .filter(|value| is_valid_cookie_value(value))
            .ok_or(QqDesktopQuickLoginError::MissingClientKey)?;
        let cookie_header = cookie_header(
            &ticket_cookies,
            [
                ("pt_local_token", session.local_token.as_str()),
                ("clientuin", account.uin.as_str()),
            ],
        );
        let jump = self
            .transport()
            .execute(
                HttpRequest::get(LOGIN_JUMP_URL_BASE)
                    .query("clientuin", &account.uin)
                    .query("keyindex", key_index.to_string())
                    .query("pt_aid", QR_APP_ID)
                    .query("daid", DAID)
                    .query("u1", LOGIN_JUMP_URL)
                    .query("pt_local_tk", hash33(client_key, 5381).to_string())
                    .header("Cookie", cookie_header)
                    .header("Referer", QR_REFERER)
                    .header("User-Agent", WEB_USER_AGENT)
                    .follow_redirects(false)
                    .response_body_limit(MAX_LOCAL_RESPONSE_BYTES)
                    .timeout(REMOTE_AUTHORIZATION_TIMEOUT),
            )
            .await
            .map_err(QqDesktopQuickLoginError::Transport)?;
        ensure_redirect_or_success("ticket exchange", jump.status())?;
        let body = std::str::from_utf8(jump.body())
            .map_err(|_| QqDesktopQuickLoginError::InvalidResponse)?;
        let callback = parse_single_quoted_callback_args(body, "ptui_qlogin_CB")
            .ok_or(QqDesktopQuickLoginError::InvalidResponse)?;
        if callback.first().map(String::as_str) != Some("0") {
            return Err(QqDesktopQuickLoginError::Rejected);
        }
        let redirect = callback
            .get(1)
            .and_then(|value| Url::parse(value).ok())
            .filter(|url| {
                url.scheme() == "https"
                    && url.host_str() == Some("graph.qq.com")
                    && url.path() == "/oauth2.0/login_jump"
            })
            .ok_or(QqDesktopQuickLoginError::InvalidResponse)?;
        drop(redirect);

        let cookies = response_cookies(&jump);
        self.exchange_qq_connect_cookies(&cookies)
            .await
            .map_err(QqDesktopQuickLoginError::QqConnect)
    }
}

fn local_request<'a, const N: usize>(
    port: u16,
    path: &str,
    local_token: &str,
    cache_buster: u128,
    params: [(&'a str, &'a str); N],
    timeout: Duration,
) -> HttpRequest {
    let mut request = HttpRequest::get(format!("https://{LOCAL_LOGIN_HOST}:{port}/{path}"));
    for (name, value) in params {
        request = request.query(name, value);
    }
    request
        .query("r", format!("0.{cache_buster}"))
        .query("pt_local_tk", local_token)
        .query("pt_aid", QR_APP_ID)
        .query("daid", DAID)
        .query("pt_3rd_aid", QQ_CONNECT_APP_ID)
        .query("u1", LOGIN_JUMP_URL)
        .header("Cookie", format!("pt_local_token={local_token}"))
        .header("Referer", QR_REFERER)
        .header("User-Agent", WEB_USER_AGENT)
        .response_body_limit(MAX_LOCAL_RESPONSE_BYTES)
        .timeout(timeout)
}

fn parse_accounts<E>(body: &[u8]) -> Result<Vec<LocalAccount>, QqDesktopQuickLoginError<E>> {
    let value = parse_jsonp(body, "ptui_getuins_CB")?;
    let accounts = value
        .as_array()
        .ok_or(QqDesktopQuickLoginError::InvalidResponse)?;
    if accounts.len() > MAX_LOCAL_ACCOUNTS {
        return Err(QqDesktopQuickLoginError::InvalidResponse);
    }
    accounts
        .iter()
        .enumerate()
        .map(|(index, value)| {
            let account = value
                .as_object()
                .ok_or(QqDesktopQuickLoginError::InvalidResponse)?;
            let uin = account
                .get("uin")
                .and_then(protocol_uin)
                .ok_or(QqDesktopQuickLoginError::InvalidResponse)?;
            let display_name = account
                .get("nickname")
                .and_then(Value::as_str)
                .and_then(display_text)
                .unwrap_or_else(|| "QQ account".to_owned());
            Ok(LocalAccount {
                presentation: QqDesktopQuickLoginAccount {
                    selection_id: u32::try_from(index)
                        .map_err(|_| QqDesktopQuickLoginError::InvalidResponse)?,
                    display_name,
                    account_hint: masked_account_hint(&uin),
                },
                uin,
            })
        })
        .collect()
}

fn parse_jsonp<E>(body: &[u8], callback: &str) -> Result<Value, QqDesktopQuickLoginError<E>> {
    let body = std::str::from_utf8(body)
        .map_err(|_| QqDesktopQuickLoginError::InvalidResponse)?
        .trim();
    let argument = body
        .strip_prefix(callback)
        .map(str::trim_start)
        .and_then(|body| body.strip_prefix('('))
        .and_then(|body| body.strip_suffix(';').or(Some(body)))
        .and_then(|body| body.strip_suffix(')'))
        .map(str::trim)
        .ok_or(QqDesktopQuickLoginError::InvalidResponse)?;
    serde_json::from_str(argument).map_err(|_| QqDesktopQuickLoginError::InvalidResponse)
}

fn parse_single_quoted_callback_args(body: &str, callback: &str) -> Option<Vec<String>> {
    let prefix = format!("{callback}(");
    let start = body.find(&prefix)? + prefix.len();
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

fn protocol_uin(value: &Value) -> Option<String> {
    let value = match value {
        Value::String(value) => value.clone(),
        Value::Number(value) => value.as_u64()?.to_string(),
        _ => return None,
    };
    (!value.is_empty()
        && value.len() <= 20
        && value != "0"
        && value.bytes().all(|byte| byte.is_ascii_digit()))
    .then_some(value)
}

fn protocol_u64(value: &Value) -> Option<u64> {
    match value {
        Value::Number(value) => value.as_u64(),
        Value::String(value) => value.parse().ok(),
        _ => None,
    }
}

fn display_text(value: &str) -> Option<String> {
    let value = value.trim();
    (!value.is_empty() && value.len() <= 160 && !value.chars().any(char::is_control))
        .then(|| value.to_owned())
}

fn masked_account_hint(uin: &str) -> String {
    if uin.len() <= 4 {
        return "••••".to_owned();
    }
    format!("{}••••{}", &uin[..2], &uin[uin.len() - 2..])
}

fn cookie_header<const N: usize>(
    cookies: &[(String, String)],
    additional: [(&str, &str); N],
) -> String {
    cookies
        .iter()
        .map(|(name, value)| format!("{name}={value}"))
        .chain(
            additional
                .into_iter()
                .map(|(name, value)| format!("{name}={value}")),
        )
        .collect::<Vec<_>>()
        .join("; ")
}

fn local_token<E>() -> Result<String, QqDesktopQuickLoginError<E>> {
    let mut bytes = [0_u8; 16];
    fill(&mut bytes).map_err(|_| QqDesktopQuickLoginError::RandomnessUnavailable)?;
    let mut token = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        write!(&mut token, "{byte:02x}").expect("writing to String cannot fail");
    }
    Ok(token)
}

fn cache_buster<E>() -> Result<u128, QqDesktopQuickLoginError<E>> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .map_err(|_| QqDesktopQuickLoginError::ClockBeforeUnixEpoch)
}

fn ensure_success<E>(phase: &'static str, status: u16) -> Result<(), QqDesktopQuickLoginError<E>> {
    if (200..300).contains(&status) {
        Ok(())
    } else {
        Err(QqDesktopQuickLoginError::HttpStatus { phase, status })
    }
}

fn ensure_redirect_or_success<E>(
    phase: &'static str,
    status: u16,
) -> Result<(), QqDesktopQuickLoginError<E>> {
    if (200..400).contains(&status) {
        Ok(())
    } else {
        Err(QqDesktopQuickLoginError::HttpStatus { phase, status })
    }
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::convert::Infallible;
    use std::sync::Mutex;

    use super::{QqDesktopQuickLoginError, masked_account_hint};
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

    fn account_response() -> HttpResponse {
        HttpResponse::new(
            200,
            br#"ptui_getuins_CB([{"uin":2180923690,"account":"2180923690","face_index":1,"nickname":"Synthetic listener","uin_flag":0}]);"#.to_vec(),
        )
    }

    #[tokio::test]
    async fn discovers_only_masked_presentation_accounts_over_loopback_https() {
        let client = QqMusicClient::new(FakeTransport::new([account_response()]));

        let session = client
            .discover_desktop_qq_accounts()
            .await
            .expect("synthetic desktop QQ discovery");

        let accounts = session.accounts();
        assert_eq!(accounts.len(), 1);
        assert_eq!(accounts[0].selection_id(), 0);
        assert_eq!(accounts[0].display_name(), "Synthetic listener");
        assert_eq!(accounts[0].account_hint(), "21••••90");
        let request = &client.transport().requests()[0];
        assert_eq!(
            request.url(),
            "https://localhost.ptlogin2.qq.com:4301/pt_get_uins"
        );
        assert!(
            request
                .query_pairs()
                .contains(&("pt_3rd_aid".to_owned(), "100497308".to_owned()))
        );
        let debug = format!("{session:?} {accounts:?} {request:?}");
        assert!(!debug.contains("2180923690"));
        assert!(!debug.contains("Synthetic listener"));
    }

    #[tokio::test]
    async fn exchanges_selected_desktop_account_through_existing_qq_connect_login() {
        let credential = serde_json::json!({
            "code": 0,
            "QQConnectLogin.LoginServer.QQLogin": {
                "code": 0,
                "data": {
                    "str_musicid": "456",
                    "musickey": "secret-music-key",
                    "loginType": 2
                }
            }
        });
        let transport = FakeTransport::new([
            account_response(),
            HttpResponse::new(
                200,
                br#"ptui_getst_CB({"uin":"2180923690","keyindex":9});"#.to_vec(),
            )
            .with_headers(vec![(
                "set-cookie".into(),
                "clientkey=secret-client-key; Domain=.ptlogin2.qq.com".into(),
            )]),
            HttpResponse::new(
                200,
                b"ptui_qlogin_CB('0','https://graph.qq.com/oauth2.0/login_jump','ok');".to_vec(),
            )
            .with_headers(vec![
                ("set-cookie".into(), "p_skey=secret-p-skey; Path=/".into()),
                ("set-cookie".into(), "uin=o02180923690; Path=/".into()),
            ]),
            HttpResponse::new(302, Vec::new()).with_headers(vec![(
                "location".into(),
                "https://y.qq.com/portal/wx_redirect.html?code=secret-code&state=state".into(),
            )]),
            HttpResponse::new(200, serde_json::to_vec(&credential).expect("fixture JSON")),
        ]);
        let client = QqMusicClient::new(transport);
        let session = client
            .discover_desktop_qq_accounts()
            .await
            .expect("synthetic desktop QQ discovery");

        let credential = client
            .authorize_desktop_qq_account(&session, 0)
            .await
            .unwrap_or_else(|error| {
                panic!(
                    "synthetic desktop QQ authorization failed: {error:?}; request_count={}",
                    client.transport().requests().len()
                )
            });

        assert_eq!(credential.login_type(), LoginType::QQ);
        let requests = client.transport().requests();
        assert_eq!(
            requests[1].url(),
            "https://localhost.ptlogin2.qq.com:4301/pt_get_st"
        );
        assert_eq!(requests[2].url(), "https://ssl.ptlogin2.qq.com/jump");
        assert_eq!(requests[3].url(), "https://graph.qq.com/oauth2.0/authorize");
        assert_eq!(requests[4].url(), "https://u.y.qq.com/cgi-bin/musicu.fcg");
        assert!(!format!("{credential:?} {requests:?}").contains("secret-client-key"));
    }

    #[tokio::test]
    async fn rejects_invalid_account_selection_before_requesting_a_ticket() {
        let client = QqMusicClient::new(FakeTransport::new([account_response()]));
        let session = client
            .discover_desktop_qq_accounts()
            .await
            .expect("synthetic desktop QQ discovery");

        let error = client
            .authorize_desktop_qq_account(&session, 9)
            .await
            .expect_err("unknown selection must fail");

        assert!(matches!(error, QqDesktopQuickLoginError::InvalidSelection));
        assert_eq!(client.transport().requests().len(), 1);
    }

    #[test]
    fn account_hint_never_exposes_the_complete_identifier() {
        assert_eq!(masked_account_hint("2180923690"), "21••••90");
        assert_eq!(masked_account_hint("1234"), "••••");
    }
}
