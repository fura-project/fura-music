use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::{
    Credential, CredentialExpiry, CredentialSessionSecrets, HttpRequest, HttpTransport,
    InvalidCredential, InvalidCredentialExpiry, LoginType, QqMusicClient, WechatAuthorizationCode,
};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const WECHAT_APP_ID: &str = "wx48db31d50e334801";
const MAX_EXCHANGE_RESPONSE_BYTES: usize = 512 * 1024;
const EXCHANGE_TIMEOUT: Duration = Duration::from_secs(30);

pub enum WechatCredentialExchangeError<E> {
    Transport(E),
    Serialize,
    HttpStatus(u16),
    InvalidJson,
    MissingGlobalCode,
    MissingLoginResult,
    Upstream {
        global_code: i64,
        login_code: Option<i64>,
    },
    MissingCredentialData,
    InvalidCredential(InvalidCredential),
    InvalidExpiry(InvalidCredentialExpiry),
    UnexpectedLoginType(u32),
}

impl<E> fmt::Debug for WechatCredentialExchangeError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Transport(_) => formatter.write_str("Transport([REDACTED])"),
            Self::Serialize => formatter.write_str("Serialize"),
            Self::HttpStatus(status) => formatter.debug_tuple("HttpStatus").field(status).finish(),
            Self::InvalidJson => formatter.write_str("InvalidJson([REDACTED])"),
            Self::MissingGlobalCode => formatter.write_str("MissingGlobalCode"),
            Self::MissingLoginResult => formatter.write_str("MissingLoginResult"),
            Self::Upstream {
                global_code,
                login_code,
            } => formatter
                .debug_struct("Upstream")
                .field("global_code", global_code)
                .field("login_code", login_code)
                .finish(),
            Self::MissingCredentialData => formatter.write_str("MissingCredentialData"),
            Self::InvalidCredential(error) => formatter
                .debug_tuple("InvalidCredential")
                .field(error)
                .finish(),
            Self::InvalidExpiry(error) => {
                formatter.debug_tuple("InvalidExpiry").field(error).finish()
            }
            Self::UnexpectedLoginType(value) => formatter
                .debug_tuple("UnexpectedLoginType")
                .field(value)
                .finish(),
        }
    }
}

impl<E> fmt::Display for WechatCredentialExchangeError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Transport(_) => formatter.write_str("QQ Music credential exchange failed"),
            Self::Serialize => formatter.write_str("could not serialize credential exchange"),
            Self::HttpStatus(status) => {
                write!(formatter, "credential exchange returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("credential exchange returned invalid JSON"),
            Self::MissingGlobalCode => {
                formatter.write_str("credential exchange response has no global code")
            }
            Self::MissingLoginResult => {
                formatter.write_str("credential exchange response has no login result")
            }
            Self::Upstream {
                global_code,
                login_code,
            } => write!(
                formatter,
                "credential exchange failed with global code {global_code} and login code {login_code:?}"
            ),
            Self::MissingCredentialData => {
                formatter.write_str("credential exchange response has no credential data")
            }
            Self::InvalidCredential(error) => error.fmt(formatter),
            Self::InvalidExpiry(error) => error.fmt(formatter),
            Self::UnexpectedLoginType(value) => {
                write!(formatter, "WeChat exchange returned login type {value}")
            }
        }
    }
}

impl<E> std::error::Error for WechatCredentialExchangeError<E>
where
    E: std::error::Error + 'static,
{
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Transport(error) => Some(error),
            Self::InvalidCredential(error) => Some(error),
            Self::InvalidExpiry(error) => Some(error),
            _ => None,
        }
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Exchanges a confirmed `WeChat` OAuth code for a QQ Music credential.
    ///
    /// # Errors
    ///
    /// Returns precise transport, HTTP, envelope, upstream-code, and credential
    /// validation errors. No upstream message or response body is retained in
    /// the error.
    pub async fn exchange_wechat_code(
        &self,
        code: &WechatAuthorizationCode,
    ) -> Result<Credential, WechatCredentialExchangeError<T::Error>> {
        let body = serde_json::to_vec(&ExchangeRequest::new(code.expose()))
            .map_err(|_| WechatCredentialExchangeError::Serialize)?;
        let response = self
            .transport()
            .execute(
                HttpRequest::post(MUSICU_URL)
                    .header("Content-Type", "application/json")
                    .header("Origin", "https://y.qq.com")
                    .header("Referer", "https://y.qq.com/")
                    .body(body)
                    .response_body_limit(MAX_EXCHANGE_RESPONSE_BYTES)
                    .timeout(EXCHANGE_TIMEOUT),
            )
            .await
            .map_err(WechatCredentialExchangeError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(WechatCredentialExchangeError::HttpStatus(response.status()));
        }

        let envelope: ExchangeResponse = serde_json::from_slice(response.body())
            .map_err(|_| WechatCredentialExchangeError::InvalidJson)?;
        credential_from_response(envelope)
    }
}

#[derive(Serialize)]
struct ExchangeRequest<'a> {
    comm: ExchangeComm,
    #[serde(rename = "music.login.LoginServer.Login")]
    login: ExchangeRpc<'a>,
}

impl<'a> ExchangeRequest<'a> {
    const fn new(code: &'a str) -> Self {
        Self {
            comm: ExchangeComm {
                cv: 13_020_508,
                version: 13_020_508,
                client_type: "11",
                app_id: "qqmusic",
                format: "json",
                input_charset: "utf-8",
                output_charset: "utf-8",
                user_id: "0",
                login_type: "1",
            },
            login: ExchangeRpc {
                module: "music.login.LoginServer",
                method: "Login",
                param: ExchangeParam {
                    code,
                    app_id: WECHAT_APP_ID,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct ExchangeComm {
    cv: u32,
    #[serde(rename = "v")]
    version: u32,
    #[serde(rename = "ct")]
    client_type: &'static str,
    #[serde(rename = "tmeAppID")]
    app_id: &'static str,
    format: &'static str,
    #[serde(rename = "inCharset")]
    input_charset: &'static str,
    #[serde(rename = "outCharset")]
    output_charset: &'static str,
    #[serde(rename = "uid")]
    user_id: &'static str,
    #[serde(rename = "tmeLoginType")]
    login_type: &'static str,
}

#[derive(Serialize)]
struct ExchangeRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: ExchangeParam<'a>,
}

#[derive(Serialize)]
struct ExchangeParam<'a> {
    code: &'a str,
    #[serde(rename = "strAppid")]
    app_id: &'static str,
}

#[derive(Deserialize)]
struct ExchangeResponse {
    code: Option<i64>,
    #[serde(rename = "music.login.LoginServer.Login")]
    login: Option<LoginResponse>,
}

#[derive(Deserialize)]
struct LoginResponse {
    code: Option<i64>,
    data: Option<RawCredential>,
}

#[derive(Deserialize, Default)]
struct RawCredential {
    #[serde(default)]
    musicid: Option<ProtocolIdentifier>,
    #[serde(default)]
    str_musicid: String,
    #[serde(default)]
    musickey: String,
    #[serde(default, rename = "loginType")]
    login_type: Option<u32>,
    #[serde(default, rename = "musickeyCreateTime")]
    created_at: Option<u64>,
    #[serde(default, rename = "keyExpiresIn")]
    lifetime: Option<u64>,
    #[serde(default)]
    openid: Option<String>,
    #[serde(default)]
    access_token: Option<String>,
    #[serde(default)]
    refresh_token: Option<String>,
    #[serde(default)]
    refresh_key: Option<String>,
    #[serde(default)]
    unionid: Option<String>,
    #[serde(default, rename = "encryptUin")]
    encrypted_uin: Option<String>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum ProtocolIdentifier {
    String(String),
    Unsigned(u64),
    Signed(i64),
}

impl ProtocolIdentifier {
    fn into_nonzero_string(self) -> Option<String> {
        match self {
            Self::String(value) => usable_identifier(&value),
            Self::Unsigned(0) | Self::Signed(i64::MIN..=0) => None,
            Self::Unsigned(value) => Some(value.to_string()),
            Self::Signed(value) => Some(value.to_string()),
        }
    }
}

fn credential_from_response<E>(
    envelope: ExchangeResponse,
) -> Result<Credential, WechatCredentialExchangeError<E>> {
    let global_code = envelope
        .code
        .ok_or(WechatCredentialExchangeError::MissingGlobalCode)?;
    let login = envelope
        .login
        .ok_or(WechatCredentialExchangeError::MissingLoginResult)?;
    if global_code != 0 || login.code != Some(0) {
        return Err(WechatCredentialExchangeError::Upstream {
            global_code,
            login_code: login.code,
        });
    }

    let raw = login
        .data
        .ok_or(WechatCredentialExchangeError::MissingCredentialData)?;
    if raw.login_type.is_some_and(|value| value != 0 && value != 1) {
        return Err(WechatCredentialExchangeError::UnexpectedLoginType(
            raw.login_type.expect("checked as Some"),
        ));
    }
    let music_id = usable_identifier(&raw.str_musicid)
        .or_else(|| {
            raw.musicid
                .and_then(ProtocolIdentifier::into_nonzero_string)
        })
        .ok_or(WechatCredentialExchangeError::InvalidCredential(
            InvalidCredential::MissingMusicId,
        ))?;
    let mut credential = Credential::new(music_id, raw.musickey, LoginType::WECHAT)
        .map_err(WechatCredentialExchangeError::InvalidCredential)?
        .with_session_secrets(CredentialSessionSecrets::new(
            raw.openid,
            raw.access_token,
            raw.refresh_token,
            raw.refresh_key,
            raw.unionid,
            raw.encrypted_uin,
        ));

    match (raw.created_at.unwrap_or(0), raw.lifetime.unwrap_or(0)) {
        (0, 0) => {}
        (created_at, lifetime) => {
            let expiry = CredentialExpiry::new(created_at, lifetime)
                .map_err(WechatCredentialExchangeError::InvalidExpiry)?;
            credential = credential.with_expiry(expiry);
        }
    }
    Ok(credential)
}

fn usable_identifier(value: &str) -> Option<String> {
    let value = value.trim().to_owned();
    (!value.is_empty() && value != "0").then_some(value)
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use super::WechatCredentialExchangeError;
    use crate::{
        HttpMethod, HttpRequest, HttpResponse, HttpTransport, LoginType, QqMusicClient,
        WechatAuthorizationCode,
    };

    struct FakeTransport {
        responses: Mutex<VecDeque<HttpResponse>>,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl FakeTransport {
        fn new(response: &Value) -> Self {
            Self {
                responses: Mutex::new(
                    [HttpResponse::new(
                        200,
                        serde_json::to_vec(&response).expect("fixture JSON"),
                    )]
                    .into(),
                ),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn request(&self) -> HttpRequest {
            self.requests.lock().expect("request lock")[0].clone()
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

    fn code() -> WechatAuthorizationCode {
        WechatAuthorizationCode::from_protocol("secret-oauth-code".into())
    }

    fn success_fixture() -> Value {
        json!({
            "code": 0,
            "music.login.LoginServer.Login": {
                "code": 0,
                "data": {
                    "musicid": 0,
                    "str_musicid": "456",
                    "musickey": "secret-music-key",
                    "openid": "secret-open-id",
                    "access_token": "secret-access-token",
                    "refresh_token": "secret-refresh-token",
                    "refresh_key": "secret-refresh-key",
                    "unionid": "secret-union-id",
                    "encryptUin": "secret-encrypted-uin",
                    "musickeyCreateTime": 1_700_000_000,
                    "keyExpiresIn": 259_200
                }
            }
        })
    }

    #[tokio::test]
    async fn serializes_verified_named_rpc_and_maps_complete_credential() {
        let transport = FakeTransport::new(&success_fixture());
        let client = QqMusicClient::new(transport);

        let credential = client
            .exchange_wechat_code(&code())
            .await
            .expect("valid credential fixture");

        assert_eq!(credential.music_id(), "456");
        assert_eq!(credential.music_key(), "secret-music-key");
        assert_eq!(credential.login_type(), LoginType::WECHAT);
        assert_eq!(
            credential.session_secrets().refresh_token(),
            Some("secret-refresh-token")
        );
        assert_eq!(
            credential.session_secrets().encrypted_uin(),
            Some("secret-encrypted-uin")
        );

        let request = client.transport().request();
        assert_eq!(request.method(), HttpMethod::Post);
        assert_eq!(request.url(), "https://u.y.qq.com/cgi-bin/musicu.fcg");
        assert_eq!(request.max_response_body_bytes(), 512 * 1024);
        assert_eq!(
            request.request_timeout(),
            Some(std::time::Duration::from_secs(30))
        );
        let payload: Value =
            serde_json::from_slice(request.body_bytes().expect("credential exchange JSON body"))
                .expect("valid request JSON");
        assert_eq!(payload["comm"]["tmeLoginType"], "1");
        assert_eq!(
            payload["music.login.LoginServer.Login"]["module"],
            "music.login.LoginServer"
        );
        assert_eq!(payload["music.login.LoginServer.Login"]["method"], "Login");
        assert_eq!(
            payload["music.login.LoginServer.Login"]["param"]["code"],
            "secret-oauth-code"
        );
        assert_eq!(
            payload["music.login.LoginServer.Login"]["param"]["strAppid"],
            "wx48db31d50e334801"
        );
        assert!(!format!("{request:?}").contains("secret-oauth-code"));
        assert!(!format!("{credential:?}").contains("secret-"));
    }

    #[tokio::test]
    async fn preserves_global_and_login_error_codes_without_guessing() {
        for (fixture, expected) in [
            (
                json!({
                    "code": 7,
                    "music.login.LoginServer.Login": { "code": 1000, "data": {} }
                }),
                "Upstream { global_code: 7, login_code: Some(1000) }",
            ),
            (
                json!({
                    "code": 0,
                    "music.login.LoginServer.Login": { "code": 1000, "data": {} }
                }),
                "Upstream { global_code: 0, login_code: Some(1000) }",
            ),
        ] {
            let client = QqMusicClient::new(FakeTransport::new(&fixture));

            let error = client
                .exchange_wechat_code(&code())
                .await
                .expect_err("non-zero upstream code");

            assert_eq!(format!("{error:?}"), expected);
        }
    }

    #[tokio::test]
    async fn rejects_missing_identity_key_or_partial_expiry() {
        for (data, expected) in [
            (
                json!({ "musicid": 0, "str_musicid": "", "musickey": "key" }),
                "InvalidCredential(MissingMusicId)",
            ),
            (
                json!({ "musicid": 456, "musickey": "" }),
                "InvalidCredential(MissingMusicKey)",
            ),
            (
                json!({
                    "musicid": 456,
                    "musickey": "key",
                    "musickeyCreateTime": 1_700_000_000
                }),
                "InvalidExpiry(InvalidCredentialExpiry)",
            ),
        ] {
            let client = QqMusicClient::new(FakeTransport::new(&json!({
                "code": 0,
                "music.login.LoginServer.Login": { "code": 0, "data": data }
            })));

            let error = client
                .exchange_wechat_code(&code())
                .await
                .expect_err("malformed credential");

            assert_eq!(format!("{error:?}"), expected);
        }
    }

    #[tokio::test]
    async fn rejects_conflicting_nonzero_login_type() {
        let mut fixture = success_fixture();
        fixture["music.login.LoginServer.Login"]["data"]["loginType"] = json!(2);
        let client = QqMusicClient::new(FakeTransport::new(&fixture));

        let error = client
            .exchange_wechat_code(&code())
            .await
            .expect_err("QQ type conflicts with WeChat flow");

        assert!(matches!(
            error,
            WechatCredentialExchangeError::UnexpectedLoginType(2)
        ));
    }
}
