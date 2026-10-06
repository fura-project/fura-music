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
    ProtocolUnavailable,
    InvalidResponse,
    AccountChanged,
}
impl std::fmt::Display for CredentialRefreshError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "QQ credential refresh: {self:?}")
    }
}
impl std::error::Error for CredentialRefreshError {}

const RESULT_KEY: &str = "music.login.LoginServer.Login";

fn request(credential: &Credential) -> Result<HttpRequest, CredentialRefreshError> {
    // Only WeChat's full material set is corroborated by two current wire
    // families. Do not extrapolate the QQ loginType=2 shape from a port.
    if credential.login_type() != LoginType::WECHAT {
        return Err(CredentialRefreshError::UnsupportedLoginType);
    }
    let secrets = credential.session_secrets();
    let required = |value: Option<&str>| {
        value
            .filter(|s| !s.is_empty() && s.len() <= 4096)
            .ok_or(CredentialRefreshError::NotRefreshable)
            .map(str::to_owned)
    };
    let param = json!({
        "openid": required(secrets.open_id())?,
        "refresh_token": required(secrets.refresh_token())?,
        "str_musicid": credential.music_id(), "musickey": credential.music_key(),
        "unionid": required(secrets.union_id())?,
        "refresh_key": required(secrets.refresh_key())?, "loginMode": 2,
    });
    let body = serde_json::to_vec(&json!({
        "comm": {"cv":crate::profile::WEB_MODERN_VERSION,"v":crate::profile::WEB_MODERN_VERSION,
            "ct":crate::profile::WEB_MODERN_TYPE,"tmeAppID":crate::profile::WEB_APP_ID,
            "format":"json","inCharset":"utf-8","outCharset":"utf-8",
            "uid":credential.music_id(),"qq":credential.music_id(),"loginUin":credential.music_id(),
            "authst":credential.music_key(),"tmeLoginType":credential.login_type().value()},
        RESULT_KEY: {"module":"music.login.LoginServer","method":"Login","param":param},
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

impl<T: HttpTransport> QqMusicClient<T> {
    /// One explicit refresh attempt; the caller must verify the result and
    /// durably persist rotation before installing it. This is not wired into
    /// production auto-refresh pending live Web-profile compatibility proof.
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
        let refreshed = crate::login_credential::decode_login_credential(
            response.body(),
            RESULT_KEY,
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
            } => CredentialRefreshError::RateLimited,
            _ => CredentialRefreshError::InvalidResponse,
        })?;
        if refreshed.music_id() != credential.music_id() {
            return Err(CredentialRefreshError::AccountChanged);
        }
        // A partial credential must not silently lose the only rotation material.
        request(&refreshed)?;
        Ok(refreshed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{CredentialSessionSecrets, HttpResponse};
    use std::sync::Mutex;
    fn credential() -> Credential {
        Credential::new("123456", "synthetic-key", LoginType::WECHAT)
            .unwrap()
            .with_session_secrets(CredentialSessionSecrets::new(
                Some("synthetic-open".into()),
                None,
                Some("synthetic-refresh".into()),
                Some("synthetic-refresh-key".into()),
                Some("synthetic-union".into()),
                None,
            ))
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
        let old = credential();
        let client = QqMusicClient::new(Fake {
            reply: json!({"code":0,RESULT_KEY:{"code":0,"data":{
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
            body[RESULT_KEY]["param"],
            json!({"openid":"synthetic-open","refresh_token":"synthetic-refresh","str_musicid":"123456","musickey":"synthetic-key","unionid":"synthetic-union","refresh_key":"synthetic-refresh-key","loginMode":2})
        );
        assert_eq!(body["comm"]["ct"], "11");
        assert!(!format!("{:?}", requests[0]).contains("synthetic-refresh"));
    }
    #[tokio::test]
    async fn rejection_and_partial_rotation_are_fail_closed_without_retry() {
        for (reply, expected) in [
            (
                json!({"code":0,RESULT_KEY:{"code":104_401}}),
                CredentialRefreshError::CredentialRejected,
            ),
            (
                json!({"code":0,RESULT_KEY:{"code":0,"data":{"str_musicid":"123456","musickey":"new"}}}),
                CredentialRefreshError::NotRefreshable,
            ),
        ] {
            let client = QqMusicClient::new(Fake {
                reply,
                requests: Mutex::new(vec![]),
            });
            assert_eq!(
                client.refresh_credential(&credential()).await,
                Err(expected)
            );
            assert_eq!(client.transport().requests.lock().unwrap().len(), 1);
        }
        assert!(matches!(
            request(&Credential::new("123456", "key", LoginType::WECHAT).unwrap()),
            Err(CredentialRefreshError::NotRefreshable)
        ));
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
            let old = credential();
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
            reply: json!({"code":0,RESULT_KEY:{"code":0,"data":{
                "str_musicid":"654321","musickey":"new","loginType":1}}}),
            requests: Mutex::new(vec![]),
        });
        assert_eq!(
            client.refresh_credential(&credential()).await,
            Err(CredentialRefreshError::AccountChanged)
        );
        let unsupported = Credential::new("123456", "synthetic-key", LoginType::QQ).unwrap();
        assert_eq!(
            client.refresh_credential(&unsupported).await,
            Err(CredentialRefreshError::UnsupportedLoginType)
        );
        assert_eq!(client.transport().requests.lock().unwrap().len(), 1);
        assert!(matches!(
            request(
                &credential().with_session_secrets(CredentialSessionSecrets::new(
                    Some("x".repeat(4097)),
                    None,
                    Some("r".into()),
                    Some("k".into()),
                    Some("u".into()),
                    None,
                ))
            ),
            Err(CredentialRefreshError::NotRefreshable)
        ));
    }
}
