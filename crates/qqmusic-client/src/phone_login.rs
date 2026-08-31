use std::fmt;
use std::time::Duration;

use getrandom::fill;
use serde::{Deserialize, Serialize};

use crate::login_credential::{LoginCredentialError, decode_login_credential};
use crate::{Credential, HttpRequest, HttpTransport, LoginType, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_RESPONSE_BYTES: usize = 512 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const LOWER_HEX: &[u8; 16] = b"0123456789abcdef";

#[derive(Clone, Eq, PartialEq)]
pub struct PhoneAuthorizationSession {
    country_code: String,
    phone_number: String,
    device_id: String,
}

impl PhoneAuthorizationSession {
    /// Creates a secret-bearing, process-local phone authorization session.
    /// The phone number is never exposed by `Debug` and must not be persisted.
    ///
    /// # Errors
    ///
    /// Returns an input error for malformed country or phone digits, or when
    /// secure randomness is unavailable for the process-local device identity.
    pub fn new(country_code: &str, phone_number: &str) -> Result<Self, InvalidPhoneAuthorization> {
        let country_code = normalize_digits(country_code, 1, 4)?;
        let phone_number = normalize_digits(phone_number, 5, 15)?;
        let mut random = [0_u8; 16];
        fill(&mut random).map_err(|_| InvalidPhoneAuthorization::RandomnessUnavailable)?;
        let mut device_id = String::with_capacity(random.len() * 2);
        for byte in random {
            device_id.push(char::from(LOWER_HEX[usize::from(byte >> 4)]));
            device_id.push(char::from(LOWER_HEX[usize::from(byte & 0x0f)]));
        }
        Ok(Self {
            country_code,
            phone_number,
            device_id,
        })
    }
}

impl fmt::Debug for PhoneAuthorizationSession {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PhoneAuthorizationSession")
            .field("country_code", &"[REDACTED]")
            .field("phone_number", &"[REDACTED]")
            .field("device_id", &"[REDACTED]")
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum InvalidPhoneAuthorization {
    InvalidCountryCode,
    InvalidPhoneNumber,
    InvalidVerificationCode,
    RandomnessUnavailable,
}

impl fmt::Display for InvalidPhoneAuthorization {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidCountryCode => formatter.write_str("country code is invalid"),
            Self::InvalidPhoneNumber => formatter.write_str("phone number is invalid"),
            Self::InvalidVerificationCode => formatter.write_str("verification code is invalid"),
            Self::RandomnessUnavailable => formatter.write_str("secure randomness is unavailable"),
        }
    }
}

impl std::error::Error for InvalidPhoneAuthorization {}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum PhoneAuthCodeResult {
    Sent,
    CaptchaRequired { security_url: Option<String> },
    RateLimited,
}

pub enum PhoneLoginError<E> {
    Invalid(InvalidPhoneAuthorization),
    Transport(E),
    Serialize,
    HttpStatus(u16),
    InvalidJson,
    MissingResult,
    Upstream(i64),
    Credential(LoginCredentialError),
}

impl<E> fmt::Debug for PhoneLoginError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Invalid(error) => formatter.debug_tuple("Invalid").field(error).finish(),
            Self::Transport(_) => formatter.write_str("Transport([REDACTED])"),
            Self::Serialize => formatter.write_str("Serialize"),
            Self::HttpStatus(status) => formatter.debug_tuple("HttpStatus").field(status).finish(),
            Self::InvalidJson => formatter.write_str("InvalidJson([REDACTED])"),
            Self::MissingResult => formatter.write_str("MissingResult"),
            Self::Upstream(code) => formatter.debug_tuple("Upstream").field(code).finish(),
            Self::Credential(error) => formatter.debug_tuple("Credential").field(error).finish(),
        }
    }
}

impl<E> fmt::Display for PhoneLoginError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Invalid(error) => error.fmt(formatter),
            Self::Transport(_) => formatter.write_str("phone authorization network request failed"),
            Self::Serialize => {
                formatter.write_str("phone authorization request could not be encoded")
            }
            Self::HttpStatus(status) => {
                write!(formatter, "phone authorization returned HTTP {status}")
            }
            Self::InvalidJson | Self::MissingResult => {
                formatter.write_str("phone authorization returned an invalid response")
            }
            Self::Upstream(code) => write!(
                formatter,
                "phone authorization was rejected with code {code}"
            ),
            Self::Credential(error) => error.fmt(formatter),
        }
    }
}

impl<E> std::error::Error for PhoneLoginError<E>
where
    E: std::error::Error + 'static,
{
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Invalid(error) => Some(error),
            Self::Transport(error) => Some(error),
            Self::Credential(error) => Some(error),
            _ => None,
        }
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Requests one SMS authorization code for this process-local session.
    ///
    /// # Errors
    ///
    /// Returns a validation, transport, HTTP, service, or response-shape error.
    /// CAPTCHA and rate limiting remain successful, explicit result states.
    pub async fn send_phone_auth_code(
        &self,
        session: &PhoneAuthorizationSession,
    ) -> Result<PhoneAuthCodeResult, PhoneLoginError<T::Error>> {
        let body = serde_json::to_vec(&PhoneCodeRequest::new(session))
            .map_err(|_| PhoneLoginError::Serialize)?;
        let response = self
            .transport()
            .execute(phone_request(body))
            .await
            .map_err(PhoneLoginError::Transport)?;
        ensure_success(response.status())?;
        let envelope: PhoneCodeEnvelope =
            serde_json::from_slice(response.body()).map_err(|_| PhoneLoginError::InvalidJson)?;
        let result = envelope.result.ok_or(PhoneLoginError::MissingResult)?;
        match result.code.ok_or(PhoneLoginError::MissingResult)? {
            0 => Ok(PhoneAuthCodeResult::Sent),
            20_276 => Ok(PhoneAuthCodeResult::CaptchaRequired {
                security_url: result.data.and_then(|data| data.security_url),
            }),
            100_001 => Ok(PhoneAuthCodeResult::RateLimited),
            code => Err(PhoneLoginError::Upstream(code)),
        }
    }

    /// Exchanges a valid one-time SMS code for a QQ Music credential.
    ///
    /// # Errors
    ///
    /// Returns a validation, transport, HTTP, service, response-shape, or
    /// credential-decoding error. The submitted code is never included in it.
    pub async fn authorize_phone(
        &self,
        session: &PhoneAuthorizationSession,
        verification_code: &str,
    ) -> Result<Credential, PhoneLoginError<T::Error>> {
        let verification_code =
            normalize_verification_code(verification_code).map_err(PhoneLoginError::Invalid)?;
        let body = serde_json::to_vec(&PhoneLoginRequest::new(session, &verification_code))
            .map_err(|_| PhoneLoginError::Serialize)?;
        let response = self
            .transport()
            .execute(phone_request(body))
            .await
            .map_err(PhoneLoginError::Transport)?;
        ensure_success(response.status())?;
        decode_login_credential(response.body(), "req_0", LoginType::QQ)
            .map_err(PhoneLoginError::Credential)
    }
}

fn phone_request(body: Vec<u8>) -> HttpRequest {
    HttpRequest::post(MUSICU_URL)
        .header("Content-Type", "application/json")
        .header("User-Agent", "QQMusic 14090008(android 13)")
        .body(body)
        .response_body_limit(MAX_RESPONSE_BYTES)
        .timeout(REQUEST_TIMEOUT)
}

#[derive(Serialize)]
struct AndroidComm<'a> {
    ct: u32,
    cv: u32,
    v: u32,
    chid: &'static str,
    #[serde(rename = "tmeAppID")]
    app_id: &'static str,
    #[serde(rename = "tmeLoginMethod")]
    login_method: u32,
    #[serde(rename = "tmeLoginType", skip_serializing_if = "Option::is_none")]
    login_type: Option<u32>,
    #[serde(rename = "QIMEI")]
    qimei: &'static str,
    #[serde(rename = "QIMEI36")]
    qimei_36: &'static str,
    #[serde(rename = "OpenUDID")]
    open_udid: &'a str,
    udid: &'a str,
    uid: &'a str,
    #[serde(rename = "OpenUDID2")]
    open_udid_2: &'a str,
    sid: &'a str,
    aid: &'a str,
    os_ver: &'static str,
    phonetype: &'static str,
    devicelevel: &'static str,
    newdevicelevel: &'static str,
    rom: &'static str,
}

impl<'a> AndroidComm<'a> {
    fn new(session: &'a PhoneAuthorizationSession, login_type: Option<u32>) -> Self {
        Self {
            ct: 11,
            cv: 14_090_008,
            v: 14_090_008,
            chid: "10003505",
            app_id: "qqmusic",
            login_method: 3,
            login_type,
            qimei: "",
            qimei_36: "",
            open_udid: &session.device_id,
            udid: &session.device_id,
            uid: &session.device_id,
            open_udid_2: &session.device_id,
            sid: &session.device_id,
            aid: &session.device_id,
            os_ver: "13",
            phonetype: "flutterustmusic",
            devicelevel: "33",
            newdevicelevel: "33",
            rom: "flutterustmusic/release",
        }
    }
}

#[derive(Serialize)]
struct PhoneCodeRequest<'a> {
    comm: AndroidComm<'a>,
    req_0: PhoneCodeRpc<'a>,
}

impl<'a> PhoneCodeRequest<'a> {
    fn new(session: &'a PhoneAuthorizationSession) -> Self {
        Self {
            comm: AndroidComm::new(session, None),
            req_0: PhoneCodeRpc {
                module: "music.login.LoginServer",
                method: "SendPhoneAuthCode",
                param: PhoneCodeParam {
                    app_id: "qqmusic",
                    country_code: &session.country_code,
                    phone_number: &session.phone_number,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct PhoneCodeRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: PhoneCodeParam<'a>,
}

#[derive(Serialize)]
struct PhoneCodeParam<'a> {
    #[serde(rename = "tmeAppid")]
    app_id: &'static str,
    #[serde(rename = "areaCode")]
    country_code: &'a str,
    #[serde(rename = "phoneNo")]
    phone_number: &'a str,
}

#[derive(Serialize)]
struct PhoneLoginRequest<'a> {
    comm: AndroidComm<'a>,
    req_0: PhoneLoginRpc<'a>,
}

impl<'a> PhoneLoginRequest<'a> {
    fn new(session: &'a PhoneAuthorizationSession, code: &'a str) -> Self {
        Self {
            comm: AndroidComm::new(session, Some(0)),
            req_0: PhoneLoginRpc {
                module: "music.login.LoginServer",
                method: "Login",
                param: PhoneLoginParam {
                    code,
                    login_mode: 1,
                    phone_number: &session.phone_number,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct PhoneLoginRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: PhoneLoginParam<'a>,
}

#[derive(Serialize)]
struct PhoneLoginParam<'a> {
    code: &'a str,
    #[serde(rename = "loginMode")]
    login_mode: u32,
    #[serde(rename = "phoneNo")]
    phone_number: &'a str,
}

#[derive(Deserialize)]
struct PhoneCodeEnvelope {
    #[serde(rename = "req_0")]
    result: Option<PhoneCodeResponse>,
}

#[derive(Deserialize)]
struct PhoneCodeResponse {
    code: Option<i64>,
    data: Option<PhoneCodeData>,
}

#[derive(Deserialize)]
struct PhoneCodeData {
    #[serde(default, rename = "securityURL", alias = "securityUrl")]
    security_url: Option<String>,
}

fn normalize_digits(
    value: &str,
    minimum: usize,
    maximum: usize,
) -> Result<String, InvalidPhoneAuthorization> {
    let value = value.trim().trim_start_matches('+');
    if value.len() < minimum
        || value.len() > maximum
        || !value.bytes().all(|byte| byte.is_ascii_digit())
    {
        return Err(if maximum == 4 {
            InvalidPhoneAuthorization::InvalidCountryCode
        } else {
            InvalidPhoneAuthorization::InvalidPhoneNumber
        });
    }
    Ok(value.to_owned())
}

fn normalize_verification_code(value: &str) -> Result<String, InvalidPhoneAuthorization> {
    let value = value.trim();
    if value.len() != 6 || !value.bytes().all(|byte| byte.is_ascii_digit()) {
        Err(InvalidPhoneAuthorization::InvalidVerificationCode)
    } else {
        Ok(value.to_owned())
    }
}

fn ensure_success<E>(status: u16) -> Result<(), PhoneLoginError<E>> {
    if (200..300).contains(&status) {
        Ok(())
    } else {
        Err(PhoneLoginError::HttpStatus(status))
    }
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::Value;

    use super::{PhoneAuthCodeResult, PhoneAuthorizationSession};
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

    #[tokio::test]
    async fn sends_code_and_authorizes_with_one_session_device_identity() {
        let transport = FakeTransport::new([
            HttpResponse::new(
                200,
                serde_json::to_vec(&serde_json::json!({
                    "code": 0,
                    "req_0": { "code": 0, "data": {} }
                }))
                .expect("code fixture"),
            ),
            HttpResponse::new(
                200,
                serde_json::to_vec(&serde_json::json!({
                    "code": 0,
                    "req_0": {
                        "code": 0,
                        "data": {
                            "str_musicid": "789",
                            "musickey": "secret-phone-key",
                            "loginType": 2
                        }
                    }
                }))
                .expect("login fixture"),
            ),
        ]);
        let client = QqMusicClient::new(transport);
        let session =
            PhoneAuthorizationSession::new("+86", "13000000000").expect("valid phone session");

        assert_eq!(
            client
                .send_phone_auth_code(&session)
                .await
                .expect("send code"),
            PhoneAuthCodeResult::Sent
        );
        let credential = client
            .authorize_phone(&session, "123456")
            .await
            .expect("phone authorization");
        assert_eq!(credential.login_type(), LoginType::QQ);

        let requests = client.transport().requests();
        let send: Value = serde_json::from_slice(requests[0].body_bytes().expect("send JSON"))
            .expect("valid send JSON");
        let login: Value = serde_json::from_slice(requests[1].body_bytes().expect("login JSON"))
            .expect("valid login JSON");
        assert_eq!(send["req_0"]["method"], "SendPhoneAuthCode");
        assert_eq!(send["req_0"]["param"]["areaCode"], "86");
        assert_eq!(login["req_0"]["param"]["code"], "123456");
        assert_eq!(send["comm"]["OpenUDID"], login["comm"]["OpenUDID"]);
        assert!(!format!("{session:?}").contains("13000000000"));
        assert!(!format!("{:?}", requests[0]).contains("13000000000"));
    }

    #[tokio::test]
    async fn reports_captcha_and_rate_limit_without_guessing_success() {
        for (code, expected) in [
            (
                20_276,
                PhoneAuthCodeResult::CaptchaRequired {
                    security_url: Some("https://example.test/security".into()),
                },
            ),
            (100_001, PhoneAuthCodeResult::RateLimited),
        ] {
            let client = QqMusicClient::new(FakeTransport::new([HttpResponse::new(
                200,
                serde_json::to_vec(&serde_json::json!({
                    "code": 0,
                    "req_0": {
                        "code": code,
                        "data": { "securityURL": "https://example.test/security" }
                    }
                }))
                .expect("fixture"),
            )]));
            let session =
                PhoneAuthorizationSession::new("86", "13000000000").expect("valid phone session");
            assert_eq!(
                client.send_phone_auth_code(&session).await.expect("state"),
                expected
            );
        }
    }
}
