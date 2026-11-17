//! Bounded refresh foundation. No scheduling, credential installation, retry,
//! vault access or account automation occurs in this protocol operation.
use crate::{Credential, HttpRequest, HttpTransport, LoginType, QqMusicClient};
use serde_json::json;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CredentialRefreshError {
    NotRefreshable,
    UnsupportedLoginType,
    Network,
    RateLimited,
    CredentialRejected,
    RiskControl,
    SecondaryVerificationRequired,
    ProtocolUnavailable,
    InvalidResponse,
    MalformedResponse,
    UpstreamRejected,
    InvalidCredential,
    InvalidExpiry,
    UnexpectedLoginType,
    IncompleteRotation,
    AccountChanged,
}
impl std::fmt::Display for CredentialRefreshError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "QQ credential refresh: {self:?}")
    }
}
impl std::error::Error for CredentialRefreshError {}

const WECHAT_RESULT_KEY: &str = "music.login.LoginServer.Login";
const QQ_TYPE_TWO_RESULT_KEY: &str = "music.login.LoginServer.Login";

const fn result_key(login_type: LoginType) -> Result<&'static str, CredentialRefreshError> {
    match login_type.value() {
        1 => Ok(WECHAT_RESULT_KEY),
        2 => Ok(QQ_TYPE_TWO_RESULT_KEY),
        _ => Err(CredentialRefreshError::UnsupportedLoginType),
    }
}

fn request(credential: &Credential) -> Result<HttpRequest, CredentialRefreshError> {
    let secrets = credential.session_secrets();
    let required = |value: Option<&str>| {
        value
            .filter(|s| !s.is_empty() && s.len() <= 4096)
            .ok_or(CredentialRefreshError::NotRefreshable)
            .map(str::to_owned)
    };
    let optional = |value: Option<&str>| {
        value.map_or_else(
            || Ok(String::new()),
            |value| {
                (value.len() <= 4096)
                    .then(|| value.to_owned())
                    .ok_or(CredentialRefreshError::NotRefreshable)
            },
        )
    };
    // Each accepted login type has one evidence-backed request shape. There is
    // deliberately no endpoint fallback: a rejected QQ request must remain a
    // protocol-gate result rather than trying a different identity surface.
    let param = match credential.login_type() {
        LoginType::WECHAT => json!({
                "openid": optional(secrets.open_id())?,
                "refresh_token": required(secrets.refresh_token())?,
                "str_musicid": credential.music_id(), "musickey": credential.music_key(),
                "unionid": optional(secrets.union_id())?,
                "refresh_key": optional(secrets.refresh_key())?, "loginMode": 2,
        }),
        LoginType::QQ => json!({
                "openid": required(secrets.open_id())?,
                "access_token": required(secrets.access_token())?,
                "refresh_token": required(secrets.refresh_token())?,
                "expired_in": credential.refresh_expiry_value()
                    .ok_or(CredentialRefreshError::NotRefreshable)?,
                // The Type 2 LoginServer contract requires a JSON number here.
                // A string-shaped musicid is accepted by ordinary credential
                // transport but is rejected by the refresh operation.
                "musicid": credential.music_id().parse::<u64>()
                    .map_err(|_| CredentialRefreshError::InvalidCredential)?,
                "musickey": credential.music_key(),
                "refresh_key": required(secrets.refresh_key())?, "loginMode": 2,
        }),
        _ => return Err(CredentialRefreshError::UnsupportedLoginType),
    };
    let body = serde_json::to_vec(&json!({
        "comm": {"cv":crate::profile::WEB_MODERN_VERSION,"v":crate::profile::WEB_MODERN_VERSION,
            "ct":crate::profile::WEB_MODERN_TYPE,"tmeAppID":crate::profile::WEB_APP_ID,
            "format":"json","inCharset":"utf-8","outCharset":"utf-8",
            "uid":credential.music_id(),"qq":credential.music_id(),"loginUin":credential.music_id(),
            "authst":credential.music_key(),"tmeLoginType":credential.login_type().value()},
        WECHAT_RESULT_KEY: {"module":"music.login.LoginServer","method":"Login","param":param},
    }))
    .map_err(|_| CredentialRefreshError::InvalidResponse)?;
    Ok(HttpRequest::post("https://u.y.qq.com/cgi-bin/musicu.fcg")
        .header("Referer", crate::profile::QqProtocolProfile::Web.referer())
        .header("Content-Type", "application/json")
        .header("Cookie", credential.musicu_cookie_header())
        .body(body)
        .follow_redirects(false)
        .response_body_limit(64 * 1024)
        .timeout(std::time::Duration::from_secs(20)))
}

/// Validates whether the current credential can build the one supported
/// refresh request without sending it.
///
/// # Errors
///
/// Returns a coarse local eligibility failure and never exposes credential
/// material.
pub fn validate_credential_refresh_material(
    credential: &Credential,
) -> Result<(), CredentialRefreshError> {
    request(credential).map(drop)
}

fn merge_wechat_refresh_delta(bytes: &[u8], source: &Credential) -> Vec<u8> {
    let Ok(mut envelope) = serde_json::from_slice::<serde_json::Value>(bytes) else {
        return bytes.to_vec();
    };
    let Some(data) = envelope
        .get_mut(WECHAT_RESULT_KEY)
        .and_then(|login| login.get_mut("data"))
        .and_then(serde_json::Value::as_object_mut)
    else {
        return bytes.to_vec();
    };

    let insert_if_absent = |data: &mut serde_json::Map<String, serde_json::Value>,
                            canonical: &str,
                            aliases: &[&str],
                            value: Option<&str>| {
        if data.contains_key(canonical) || aliases.iter().any(|alias| data.contains_key(*alias)) {
            return;
        }
        if let Some(value) = value {
            data.insert(canonical.to_owned(), json!(value));
        }
    };

    if !data.contains_key("str_musicid") && !data.contains_key("musicid") {
        data.insert("str_musicid".to_owned(), json!(source.music_id()));
    }
    let secrets = source.session_secrets();
    insert_if_absent(
        data,
        "openid",
        &["psrf_wxopenid", "wxopenid"],
        secrets.open_id(),
    );
    insert_if_absent(data, "access_token", &[], secrets.access_token());
    insert_if_absent(
        data,
        "refresh_token",
        &["psrf_wxrefresh_token", "wxrefresh_token"],
        secrets.refresh_token(),
    );
    insert_if_absent(data, "refresh_key", &[], secrets.refresh_key());
    insert_if_absent(
        data,
        "unionid",
        &["psrf_wxunionid", "wxunionid"],
        secrets.union_id(),
    );
    insert_if_absent(data, "encryptUin", &[], secrets.encrypted_uin());

    serde_json::to_vec(&envelope).unwrap_or_else(|_| bytes.to_vec())
}

impl<T: HttpTransport> QqMusicClient<T> {
    /// One explicit refresh attempt; the caller must verify the result and
    /// durably persist rotation before installing it. This method does not
    /// activate refresh by itself. QQ `loginType=2` remains production-gated
    /// pending a Human-operated live
    /// Web-profile compatibility proof; this protocol method itself performs
    /// exactly one request for either supported credential type.
    /// # Errors
    /// Returns only coarse failures, never upstream bodies or secrets.
    pub async fn refresh_credential(
        &self,
        credential: &Credential,
    ) -> Result<Credential, CredentialRefreshError> {
        let response = self
            .transport()
            .execute(request(credential)?)
            .await
            .map_err(|_| CredentialRefreshError::Network)?;
        match response.status() {
            200 => {}
            429 => return Err(CredentialRefreshError::RateLimited),
            _ => return Err(CredentialRefreshError::ProtocolUnavailable),
        }
        if response.body().len() > 64 * 1024 {
            return Err(CredentialRefreshError::InvalidResponse);
        }
        let decoded_body = if credential.login_type() == LoginType::WECHAT {
            merge_wechat_refresh_delta(response.body(), credential)
        } else {
            response.body().to_vec()
        };
        let refreshed = crate::login_credential::decode_login_credential(
            &decoded_body,
            result_key(credential.login_type())?,
            credential.login_type(),
        )
        .map_err(|e| match e {
            crate::login_credential::LoginCredentialError::Upstream {
                global_code,
                login_code,
            } if [global_code, login_code.unwrap_or(0)]
                .iter()
                .any(|c| matches!(c, 1000 | 104_400 | 104_401)) =>
            {
                CredentialRefreshError::CredentialRejected
            }
            crate::login_credential::LoginCredentialError::Upstream {
                global_code: 2001, ..
            }
            | crate::login_credential::LoginCredentialError::Upstream {
                login_code: Some(2001),
                ..
            }
            | crate::login_credential::LoginCredentialError::Upstream {
                global_code: 104_604,
                ..
            }
            | crate::login_credential::LoginCredentialError::Upstream {
                login_code: Some(104_604),
                ..
            } => CredentialRefreshError::RateLimited,
            crate::login_credential::LoginCredentialError::Upstream {
                global_code,
                login_code,
            } if [global_code, login_code.unwrap_or(0)]
                .iter()
                .any(|c| matches!(c, 20_271 | 20_277 | 20_278 | 20_279 | 20_450)) =>
            {
                CredentialRefreshError::RiskControl
            }
            crate::login_credential::LoginCredentialError::Upstream {
                global_code,
                login_code,
            } if [global_code, login_code.unwrap_or(0)]
                .iter()
                .any(|c| matches!(c, 20_272 | 20_274)) =>
            {
                CredentialRefreshError::SecondaryVerificationRequired
            }
            crate::login_credential::LoginCredentialError::Upstream {
                global_code,
                login_code,
            } if global_code == 20_261 || login_code == Some(20_261) => {
                CredentialRefreshError::ProtocolUnavailable
            }
            crate::login_credential::LoginCredentialError::InvalidJson
            | crate::login_credential::LoginCredentialError::MissingGlobalCode
            | crate::login_credential::LoginCredentialError::MissingLoginResult
            | crate::login_credential::LoginCredentialError::MissingCredentialData => {
                CredentialRefreshError::MalformedResponse
            }
            crate::login_credential::LoginCredentialError::Upstream { .. } => {
                CredentialRefreshError::UpstreamRejected
            }
            crate::login_credential::LoginCredentialError::InvalidCredential(_) => {
                CredentialRefreshError::InvalidCredential
            }
            crate::login_credential::LoginCredentialError::InvalidExpiry(_) => {
                CredentialRefreshError::InvalidExpiry
            }
            crate::login_credential::LoginCredentialError::UnexpectedLoginType(_) => {
                CredentialRefreshError::UnexpectedLoginType
            }
        })?;
        if refreshed.music_id() != credential.music_id() {
            return Err(CredentialRefreshError::AccountChanged);
        }
        // A partial credential must not silently lose the only rotation material.
        request(&refreshed).map_err(|_| CredentialRefreshError::IncompleteRotation)?;
        Ok(refreshed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{CredentialSessionSecrets, HttpResponse};
    use std::sync::Mutex;
    fn credential(login_type: LoginType) -> Credential {
        let mut credential = Credential::new("123456", "synthetic-key", login_type)
            .unwrap()
            .with_session_secrets(CredentialSessionSecrets::new(
                Some("synthetic-open".into()),
                Some("synthetic-access".into()),
                Some("synthetic-refresh".into()),
                Some("synthetic-refresh-key".into()),
                Some("synthetic-union".into()),
                None,
            ));
        if login_type == LoginType::QQ {
            credential = credential
                .with_expiry(
                    crate::CredentialExpiry::new(1_900_000_000, 100_000_000)
                        .expect("music-key fixture expiry"),
                )
                .with_refresh_expiry(
                    crate::CredentialRefreshExpiry::new(1_950_000_000)
                        .expect("OAuth fixture expiry"),
                );
        }
        credential
    }
    struct Fake {
        reply: serde_json::Value,
        requests: Mutex<Vec<HttpRequest>>,
    }
    impl HttpTransport for Fake {
        type Error = std::io::Error;
        fn execute(
            &self,
            r: HttpRequest,
        ) -> impl std::future::Future<Output = Result<HttpResponse, Self::Error>> + Send {
            self.requests.lock().unwrap().push(r);
            std::future::ready(Ok(HttpResponse::new(
                200,
                serde_json::to_vec(&self.reply).unwrap(),
            )))
        }
    }
    #[tokio::test]
    async fn exact_material_rotation_account_and_redaction() {
        let old = credential(LoginType::WECHAT);
        let client = QqMusicClient::new(Fake {
            reply: json!({"code":0,WECHAT_RESULT_KEY:{"code":0,"data":{
            "str_musicid":"123456","musickey":"rotated-key","loginType":1,
            "openid":"synthetic-open","unionid":"synthetic-union","refresh_token":"rotated-refresh","refresh_key":"rotated-refresh-key"}}}),
            requests: Mutex::new(vec![]),
        });
        let new = client.refresh_credential(&old).await.unwrap();
        assert_eq!(
            new.session_secrets().refresh_token(),
            Some("rotated-refresh")
        );
        assert_ne!(old, new);
        assert!(!format!("{new:?}").contains("rotated-refresh"));
        let requests = client.transport().requests.lock().unwrap();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].url(), "https://u.y.qq.com/cgi-bin/musicu.fcg");
        assert!(!requests[0].redirects_are_followed());
        let body: serde_json::Value =
            serde_json::from_slice(requests[0].body_bytes().unwrap()).unwrap();
        assert_eq!(
            body[WECHAT_RESULT_KEY]["param"],
            json!({"openid":"synthetic-open","refresh_token":"synthetic-refresh","str_musicid":"123456","musickey":"synthetic-key","unionid":"synthetic-union","refresh_key":"synthetic-refresh-key","loginMode":2})
        );
        assert_eq!(body["comm"]["ct"], "11");
        assert!(!format!("{:?}", requests[0]).contains("synthetic-refresh"));
    }
    #[tokio::test]
    async fn rejection_and_partial_rotation_are_fail_closed_without_retry() {
        for (reply, expected) in [
            (
                json!({"code":0,WECHAT_RESULT_KEY:{"code":104_401}}),
                CredentialRefreshError::CredentialRejected,
            ),
            (
                json!({"code":0,WECHAT_RESULT_KEY:{"code":0,"data":{"str_musicid":"123456","musickey":"new","refresh_token":null}}}),
                CredentialRefreshError::IncompleteRotation,
            ),
        ] {
            let client = QqMusicClient::new(Fake {
                reply,
                requests: Mutex::new(vec![]),
            });
            assert_eq!(
                client
                    .refresh_credential(&credential(LoginType::WECHAT))
                    .await,
                Err(expected)
            );
            assert_eq!(client.transport().requests.lock().unwrap().len(), 1);
        }
        assert!(matches!(
            request(&Credential::new("123456", "key", LoginType::WECHAT).unwrap()),
            Err(CredentialRefreshError::NotRefreshable)
        ));
    }

    #[test]
    fn wechat_request_requires_refresh_token_but_not_optional_identity_material() {
        for (open_id, refresh_key, union_id) in [
            (
                Some("synthetic-open"),
                Some("synthetic-key-2"),
                Some("synthetic-union"),
            ),
            (None, Some("synthetic-key-2"), Some("synthetic-union")),
            (Some("synthetic-open"), None, Some("synthetic-union")),
            (Some("synthetic-open"), Some("synthetic-key-2"), None),
            (None, None, None),
        ] {
            let credential = Credential::new("123456", "synthetic-key", LoginType::WECHAT)
                .expect("credential")
                .with_session_secrets(CredentialSessionSecrets::new(
                    open_id.map(str::to_owned),
                    None,
                    Some("synthetic-refresh".into()),
                    refresh_key.map(str::to_owned),
                    union_id.map(str::to_owned),
                    None,
                ));

            let built = request(&credential).expect("optional fields do not block refresh");
            let body: serde_json::Value =
                serde_json::from_slice(built.body_bytes().expect("request body"))
                    .expect("request JSON");
            assert_eq!(
                body[WECHAT_RESULT_KEY]["param"],
                json!({
                    "openid":open_id.unwrap_or_default(),
                    "refresh_token":"synthetic-refresh",
                    "str_musicid":"123456", "musickey":"synthetic-key",
                    "unionid":union_id.unwrap_or_default(),
                    "refresh_key":refresh_key.unwrap_or_default(), "loginMode":2
                })
            );
        }

        let missing_refresh_token =
            Credential::new("123456", "synthetic-key", LoginType::WECHAT).expect("credential");
        assert!(matches!(
            request(&missing_refresh_token),
            Err(CredentialRefreshError::NotRefreshable)
        ));
    }

    #[tokio::test]
    async fn wechat_partial_rotation_retains_only_omitted_session_material() {
        let old = credential(LoginType::WECHAT);
        let client = QqMusicClient::new(Fake {
            reply: json!({"code":0,WECHAT_RESULT_KEY:{"code":0,"data":{
                "musickey":"rotated-key","loginType":1
            }}}),
            requests: Mutex::new(vec![]),
        });

        let rotated = client
            .refresh_credential(&old)
            .await
            .expect("omitted fields retain the source rotation material");
        assert_eq!(rotated.music_id(), old.music_id());
        assert_eq!(rotated.music_key(), "rotated-key");
        assert_eq!(rotated.session_secrets(), old.session_secrets());
        request(&rotated).expect("rotated candidate remains refreshable offline");

        for explicit_deletion in [serde_json::Value::Null, json!("")] {
            let client = QqMusicClient::new(Fake {
                reply: json!({"code":0,WECHAT_RESULT_KEY:{"code":0,"data":{
                    "musickey":"rotated-key","loginType":1,
                    "refresh_token":explicit_deletion
                }}}),
                requests: Mutex::new(vec![]),
            });
            assert_eq!(
                client.refresh_credential(&old).await,
                Err(CredentialRefreshError::IncompleteRotation),
                "an explicit refresh-token deletion must not resurrect the old secret"
            );
        }

        let client = QqMusicClient::new(Fake {
            reply: json!({"code":0,WECHAT_RESULT_KEY:{"code":0,"data":{
                "musickey":"rotated-key","loginType":1,"refresh_key":""
            }}}),
            requests: Mutex::new(vec![]),
        });
        let without_refresh_key = client
            .refresh_credential(&old)
            .await
            .expect("refresh key is optional when refresh token remains");
        assert_eq!(without_refresh_key.session_secrets().refresh_key(), None);
        request(&without_refresh_key).expect("explicit optional-key deletion remains refreshable");
    }

    #[tokio::test]
    async fn network_and_http_failures_retain_input_and_never_retry() {
        struct FailureFake {
            status: Option<u16>,
            calls: std::sync::atomic::AtomicUsize,
        }
        impl HttpTransport for FailureFake {
            type Error = std::io::Error;
            fn execute(
                &self,
                _: HttpRequest,
            ) -> impl std::future::Future<Output = Result<HttpResponse, Self::Error>> + Send
            {
                self.calls.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                std::future::ready(
                    self.status
                        .map(|status| HttpResponse::new(status, vec![]))
                        .ok_or_else(|| std::io::Error::other("must-not-leak-upstream-cause")),
                )
            }
        }
        for (status, expected) in [
            (None, CredentialRefreshError::Network),
            (Some(429), CredentialRefreshError::RateLimited),
            (Some(503), CredentialRefreshError::ProtocolUnavailable),
        ] {
            let client = QqMusicClient::new(FailureFake {
                status,
                calls: std::sync::atomic::AtomicUsize::new(0),
            });
            let old = credential(LoginType::WECHAT);
            let retained = old.clone();
            let error = client.refresh_credential(&old).await.unwrap_err();
            assert_eq!(error, expected);
            assert_eq!(old, retained);
            assert_eq!(
                client
                    .transport()
                    .calls
                    .load(std::sync::atomic::Ordering::SeqCst),
                1
            );
            assert!(!format!("{error:?} {error}").contains("must-not-leak"));
        }
    }

    #[tokio::test]
    async fn response_cannot_replace_account_or_lose_rotation_material() {
        let client = QqMusicClient::new(Fake {
            reply: json!({"code":0,WECHAT_RESULT_KEY:{"code":0,"data":{
                "str_musicid":"654321","musickey":"new","loginType":1}}}),
            requests: Mutex::new(vec![]),
        });
        assert_eq!(
            client
                .refresh_credential(&credential(LoginType::WECHAT))
                .await,
            Err(CredentialRefreshError::AccountChanged)
        );
        let unsupported =
            Credential::new("123456", "synthetic-key", LoginType::QQ_MUSIC_APP).unwrap();
        assert_eq!(
            client.refresh_credential(&unsupported).await,
            Err(CredentialRefreshError::UnsupportedLoginType)
        );
        assert_eq!(client.transport().requests.lock().unwrap().len(), 1);
        assert!(matches!(
            request(&credential(LoginType::WECHAT).with_session_secrets(
                CredentialSessionSecrets::new(
                    Some("x".repeat(4097)),
                    None,
                    Some("r".into()),
                    Some("k".into()),
                    Some("u".into()),
                    None,
                )
            )),
            Err(CredentialRefreshError::NotRefreshable)
        ));
    }

    #[tokio::test]
    async fn qq_type_two_uses_one_explicit_login_server_shape() {
        let old = credential(LoginType::QQ);
        let client = QqMusicClient::new(Fake {
            reply: json!({"code":0,QQ_TYPE_TWO_RESULT_KEY:{"code":0,"data":{
                "str_musicid":"123456","musickey":"rotated-key","loginType":2,
                "openid":"synthetic-open","access_token":"rotated-access",
                "refresh_token":"rotated-refresh","refresh_key":"rotated-refresh-key",
                "expired_at":2_100_000_000
            }}}),
            requests: Mutex::new(vec![]),
        });

        let refreshed = client.refresh_credential(&old).await.unwrap();
        assert_eq!(refreshed.login_type(), LoginType::QQ);
        assert_eq!(refreshed.expires_at_unix_seconds(), None);
        assert_eq!(refreshed.refresh_expiry_value(), Some(2_100_000_000));
        assert_eq!(
            refreshed.session_secrets().access_token(),
            Some("rotated-access")
        );
        let requests = client.transport().requests.lock().unwrap();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].url(), "https://u.y.qq.com/cgi-bin/musicu.fcg");
        let body: serde_json::Value =
            serde_json::from_slice(requests[0].body_bytes().unwrap()).unwrap();
        assert_eq!(body["comm"]["ct"], "11");
        assert_eq!(body["comm"]["tmeLoginType"], 2);
        assert_eq!(
            body[QQ_TYPE_TWO_RESULT_KEY]["param"],
            json!({
                "openid":"synthetic-open","access_token":"synthetic-access",
                "refresh_token":"synthetic-refresh","expired_in":1_950_000_000_u64,
                "musicid":123_456,"musickey":"synthetic-key",
                "refresh_key":"synthetic-refresh-key","loginMode":2
            })
        );
        assert!(body[QQ_TYPE_TWO_RESULT_KEY]["param"]["musicid"].is_number());
        assert_eq!(
            body[QQ_TYPE_TWO_RESULT_KEY]["module"],
            "music.login.LoginServer"
        );
        assert_eq!(body[QQ_TYPE_TWO_RESULT_KEY]["method"], "Login");
    }

    #[test]
    fn qq_type_two_missing_any_required_material_sends_no_request() {
        let without_expiry = Credential::new("123456", "synthetic-key", LoginType::QQ)
            .unwrap()
            .with_session_secrets(CredentialSessionSecrets::new(
                Some("open".into()),
                Some("access".into()),
                Some("refresh".into()),
                Some("key".into()),
                None,
                None,
            ));
        assert!(matches!(
            request(&without_expiry),
            Err(CredentialRefreshError::NotRefreshable)
        ));
        let missing_access =
            credential(LoginType::QQ).with_session_secrets(CredentialSessionSecrets::new(
                Some("open".into()),
                None,
                Some("refresh".into()),
                Some("key".into()),
                None,
                None,
            ));
        assert!(matches!(
            request(&missing_access),
            Err(CredentialRefreshError::NotRefreshable)
        ));
    }

    #[tokio::test]
    async fn qq_refresh_risk_and_secondary_codes_are_typed_without_retry() {
        for (code, expected) in [
            (104_604, CredentialRefreshError::RateLimited),
            (20_271, CredentialRefreshError::RiskControl),
            (
                20_272,
                CredentialRefreshError::SecondaryVerificationRequired,
            ),
            (20_261, CredentialRefreshError::ProtocolUnavailable),
        ] {
            let client = QqMusicClient::new(Fake {
                reply: json!({"code":0,QQ_TYPE_TWO_RESULT_KEY:{"code":code}}),
                requests: Mutex::new(vec![]),
            });
            assert_eq!(
                client.refresh_credential(&credential(LoginType::QQ)).await,
                Err(expected)
            );
            assert_eq!(client.transport().requests.lock().unwrap().len(), 1);
        }
    }

    #[tokio::test]
    async fn unclassified_upstream_and_invalid_rotation_are_distinct() {
        for (reply, expected) in [
            (
                json!({"code":0,QQ_TYPE_TWO_RESULT_KEY:{"code":654_321}}),
                CredentialRefreshError::UpstreamRejected,
            ),
            (
                json!({"code":0,QQ_TYPE_TWO_RESULT_KEY:{"code":0,"data":{
                    "str_musicid":"123456","musickey":"new","loginType":2,
                    "openid":"synthetic-open",
                    "refresh_token":"rotated-refresh","refresh_key":"rotated-refresh-key",
                    "expired_at":0
                }}}),
                CredentialRefreshError::IncompleteRotation,
            ),
        ] {
            let client = QqMusicClient::new(Fake {
                reply,
                requests: Mutex::new(vec![]),
            });
            assert_eq!(
                client.refresh_credential(&credential(LoginType::QQ)).await,
                Err(expected)
            );
            assert_eq!(client.transport().requests.lock().unwrap().len(), 1);
        }
    }
}
