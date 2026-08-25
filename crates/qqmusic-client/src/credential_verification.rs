use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::credential::is_credential_rejection_code;
use crate::{Credential, HttpRequest, HttpTransport, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_VERIFICATION_RESPONSE_BYTES: usize = 512 * 1024;
const VERIFICATION_TIMEOUT: Duration = Duration::from_secs(30);

pub enum CredentialVerificationError<E> {
    Transport(E),
    Serialize,
    HttpStatus(u16),
    InvalidJson,
    MissingGlobalCode,
    MissingVerificationResult,
    MissingVerificationCode,
    Rejected {
        code: i64,
    },
    Upstream {
        global_code: i64,
        verification_code: Option<i64>,
    },
}

impl<E> fmt::Debug for CredentialVerificationError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Transport(_) => formatter.write_str("Transport([REDACTED])"),
            Self::Serialize => formatter.write_str("Serialize"),
            Self::HttpStatus(status) => formatter.debug_tuple("HttpStatus").field(status).finish(),
            Self::InvalidJson => formatter.write_str("InvalidJson([REDACTED])"),
            Self::MissingGlobalCode => formatter.write_str("MissingGlobalCode"),
            Self::MissingVerificationResult => formatter.write_str("MissingVerificationResult"),
            Self::MissingVerificationCode => formatter.write_str("MissingVerificationCode"),
            Self::Rejected { code } => formatter
                .debug_struct("Rejected")
                .field("code", code)
                .finish(),
            Self::Upstream {
                global_code,
                verification_code,
            } => formatter
                .debug_struct("Upstream")
                .field("global_code", global_code)
                .field("verification_code", verification_code)
                .finish(),
        }
    }
}

impl<E> fmt::Display for CredentialVerificationError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Transport(_) => formatter.write_str("QQ Music credential verification failed"),
            Self::Serialize => formatter.write_str("could not serialize credential verification"),
            Self::HttpStatus(status) => {
                write!(formatter, "credential verification returned HTTP {status}")
            }
            Self::InvalidJson => {
                formatter.write_str("credential verification returned invalid JSON")
            }
            Self::MissingGlobalCode => {
                formatter.write_str("credential verification response has no global code")
            }
            Self::MissingVerificationResult => {
                formatter.write_str("credential verification result is missing")
            }
            Self::MissingVerificationCode => {
                formatter.write_str("credential verification result has no code")
            }
            Self::Rejected { code } => {
                write!(
                    formatter,
                    "QQ Music rejected the credential with code {code}"
                )
            }
            Self::Upstream {
                global_code,
                verification_code,
            } => write!(
                formatter,
                "credential verification failed with global code {global_code} and result code {verification_code:?}"
            ),
        }
    }
}

impl<E> std::error::Error for CredentialVerificationError<E>
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
    /// Asks QQ Music whether it accepts a structurally valid credential.
    ///
    /// # Errors
    ///
    /// Keeps transport, HTTP, response-shape, credential rejection, and other
    /// upstream failures distinct. No response body or credential value is
    /// retained in an error.
    pub async fn verify_credential(
        &self,
        credential: &Credential,
    ) -> Result<(), CredentialVerificationError<T::Error>> {
        let body = serde_json::to_vec(&VerificationRequest::new(credential))
            .map_err(|_| CredentialVerificationError::Serialize)?;
        let response = self
            .transport()
            .execute(
                HttpRequest::post(MUSICU_URL)
                    .header("Content-Type", "application/json")
                    .header("Origin", "https://y.qq.com")
                    .header("Referer", "https://y.qq.com/")
                    .header("Cookie", credential.musicu_cookie_header())
                    .body(body)
                    .response_body_limit(MAX_VERIFICATION_RESPONSE_BYTES)
                    .timeout(VERIFICATION_TIMEOUT),
            )
            .await
            .map_err(CredentialVerificationError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(CredentialVerificationError::HttpStatus(response.status()));
        }

        let envelope: VerificationResponse = serde_json::from_slice(response.body())
            .map_err(|_| CredentialVerificationError::InvalidJson)?;
        verify_response(envelope)
    }
}

#[derive(Serialize)]
struct VerificationRequest<'a> {
    comm: VerificationComm<'a>,
    #[serde(rename = "music.UserInfo.userInfoServer")]
    verification: VerificationRpc,
}

impl<'a> VerificationRequest<'a> {
    fn new(credential: &'a Credential) -> Self {
        Self {
            comm: VerificationComm {
                cv: 13_020_508,
                version: 13_020_508,
                client_type: "11",
                app_id: "qqmusic",
                format: "json",
                input_charset: "utf-8",
                output_charset: "utf-8",
                user_id: credential.music_id(),
                account_id: credential.music_id(),
                auth_key: credential.music_key(),
                login_type: credential.login_type().value(),
                login_uin: credential.music_id(),
            },
            verification: VerificationRpc {
                module: "music.UserInfo.userInfoServer",
                method: "GetLoginUserInfo",
                param: EmptyParam {},
            },
        }
    }
}

#[derive(Serialize)]
struct VerificationComm<'a> {
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
    user_id: &'a str,
    #[serde(rename = "qq")]
    account_id: &'a str,
    #[serde(rename = "authst")]
    auth_key: &'a str,
    #[serde(rename = "tmeLoginType")]
    login_type: u32,
    #[serde(rename = "loginUin")]
    login_uin: &'a str,
}

#[derive(Serialize)]
struct VerificationRpc {
    module: &'static str,
    method: &'static str,
    param: EmptyParam,
}

#[derive(Serialize)]
struct EmptyParam {}

#[derive(Deserialize)]
struct VerificationResponse {
    code: Option<i64>,
    #[serde(rename = "music.UserInfo.userInfoServer")]
    verification: Option<VerificationResult>,
}

#[derive(Deserialize)]
struct VerificationResult {
    code: Option<i64>,
}

fn verify_response<E>(
    envelope: VerificationResponse,
) -> Result<(), CredentialVerificationError<E>> {
    let global_code = envelope
        .code
        .ok_or(CredentialVerificationError::MissingGlobalCode)?;
    let verification_code = envelope
        .verification
        .as_ref()
        .and_then(|result| result.code);

    if let Some(code) = [Some(global_code), verification_code]
        .into_iter()
        .flatten()
        .find(|code| is_credential_rejection_code(*code))
    {
        return Err(CredentialVerificationError::Rejected { code });
    }
    if global_code != 0 {
        return Err(CredentialVerificationError::Upstream {
            global_code,
            verification_code,
        });
    }

    let verification = envelope
        .verification
        .ok_or(CredentialVerificationError::MissingVerificationResult)?;
    let verification_code = verification
        .code
        .ok_or(CredentialVerificationError::MissingVerificationCode)?;
    if verification_code != 0 {
        return Err(CredentialVerificationError::Upstream {
            global_code,
            verification_code: Some(verification_code),
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::convert::Infallible;
    use std::sync::Mutex;
    use std::time::Duration;

    use serde_json::{Value, json};

    use super::CredentialVerificationError;
    use crate::{
        Credential, HttpMethod, HttpRequest, HttpResponse, HttpTransport, LoginType, QqMusicClient,
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
                        serde_json::to_vec(response).expect("fixture JSON"),
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

    fn credential() -> Credential {
        Credential::new("123456", "W_X_private-key", LoginType::WECHAT).expect("fixture credential")
    }

    #[tokio::test]
    async fn serializes_cross_validated_request_and_accepts_zero_codes() {
        let transport = FakeTransport::new(&json!({
            "code": 0,
            "music.UserInfo.userInfoServer": {"code": 0, "data": {"info": {}}}
        }));
        let client = QqMusicClient::new(transport);

        client
            .verify_credential(&credential())
            .await
            .expect("zero codes verify credential");

        let request = client.transport().request();
        assert_eq!(request.method(), HttpMethod::Post);
        assert_eq!(request.url(), "https://u.y.qq.com/cgi-bin/musicu.fcg");
        assert_eq!(request.max_response_body_bytes(), 512 * 1024);
        assert_eq!(request.request_timeout(), Some(Duration::from_secs(30)));
        let body: Value =
            serde_json::from_slice(request.body_bytes().expect("verification request body"))
                .expect("request JSON");
        assert_eq!(
            body["music.UserInfo.userInfoServer"]["module"],
            "music.UserInfo.userInfoServer"
        );
        assert_eq!(
            body["music.UserInfo.userInfoServer"]["method"],
            "GetLoginUserInfo"
        );
        assert_eq!(body["comm"]["authst"], "W_X_private-key");
        assert_eq!(body["comm"]["tmeLoginType"], 1);
        let cookie = request
            .headers()
            .iter()
            .find(|(name, _)| name == "Cookie")
            .map(|(_, value)| value)
            .expect("credential cookie");
        assert!(cookie.contains("uin=123456"));
        assert!(cookie.contains("qm_keyst=W_X_private-key"));
        assert!(cookie.contains("wxuin=123456"));
        assert!(!format!("{request:?}").contains("private-key"));
    }

    #[tokio::test]
    async fn maps_all_cross_validated_rejection_codes() {
        for code in [1000, 104_400, 104_401] {
            let client = QqMusicClient::new(FakeTransport::new(&json!({
                "code": 0,
                "music.UserInfo.userInfoServer": {"code": code, "data": {}}
            })));

            assert!(matches!(
                client.verify_credential(&credential()).await,
                Err(CredentialVerificationError::Rejected { code: actual }) if actual == code
            ));
        }
    }

    #[tokio::test]
    async fn keeps_non_rejection_and_malformed_responses_distinct() {
        let upstream = QqMusicClient::new(FakeTransport::new(&json!({
            "code": 0,
            "music.UserInfo.userInfoServer": {"code": 50006, "data": {}}
        })));
        assert!(matches!(
            upstream.verify_credential(&credential()).await,
            Err(CredentialVerificationError::Upstream {
                global_code: 0,
                verification_code: Some(50006),
            })
        ));

        let malformed = QqMusicClient::new(FakeTransport::new(&json!({"code": 0})));
        assert!(matches!(
            malformed.verify_credential(&credential()).await,
            Err(CredentialVerificationError::MissingVerificationResult)
        ));
    }
}
