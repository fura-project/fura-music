//! Bounded, direct `NetEase` HTTPS protocol. No account discovery or retry policy.
mod auth;
mod catalog;
pub use auth::{Account, Credential, QrKey, QrPoll, UserPlaylist, UserPlaylistPage};
mod crypto;
mod lyrics;
mod media;
mod transport;
pub use catalog::*;
pub use lyrics::{LyricLine, Lyrics, parse_lrc};
pub use media::{Media, MediaFormat};
use serde_json::{Value, json};
pub use transport::{HttpsTransport, MAX_RESPONSE_BYTES, Request, Response, Transport};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Error {
    AuthenticationRequired,
    CredentialRejected,
    RateLimited,
    SecurityVerificationRequired,
    AccountRestricted,
    EntitlementDenied,
    CopyrightRestricted,
    RegionRestricted,
    TrackUnavailable,
    ProtocolUnavailable,
    ResponseShapeMismatch,
    TemporaryNetworkFailure,
    UpstreamUnknown,
    InputBound,
    ResponseBound,
}
impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "NetEase {self:?}")
    }
}
impl std::error::Error for Error {}

pub struct NeteaseClient<T> {
    transport: T,
}
impl<T> NeteaseClient<T> {
    #[must_use]
    pub const fn new(transport: T) -> Self {
        Self { transport }
    }
}
impl<T: Transport> NeteaseClient<T> {
    async fn raw_request(
        &self,
        path: &str,
        mut payload: Value,
        eapi: bool,
        cookie: Option<&str>,
    ) -> Result<(Value, Vec<String>), Error> {
        let text = request_payload(&mut payload, eapi, cookie)?;
        let (base, form) = if eapi {
            (
                "https://interface.music.163.com/eapi/",
                crypto::eapi(path, &text)?,
            )
        } else {
            (
                "https://music.163.com/weapi/",
                crypto::weapi(&text, &crypto::random_key()?)?,
            )
        };
        let response = self
            .transport
            .send(Request {
                url: format!(
                    "{base}{}",
                    path.strip_prefix("/api/").ok_or(Error::InputBound)?
                ),
                form,
                cookie: cookie.map(str::to_owned),
            })
            .await?;
        if response.body.len() > MAX_RESPONSE_BYTES {
            return Err(Error::ResponseBound);
        }
        match response.status {
            200 => {}
            429 => return Err(Error::RateLimited),
            _ => return Err(Error::ProtocolUnavailable),
        }
        let value: Value =
            serde_json::from_slice(&response.body).map_err(|_| Error::ResponseShapeMismatch)?;
        Ok((value, response.set_cookies))
    }
    async fn request(
        &self,
        path: &str,
        payload: Value,
        eapi: bool,
        cookie: Option<&str>,
    ) -> Result<(Value, Vec<String>), Error> {
        let (value, cookies) = self.raw_request(path, payload, eapi, cookie).await?;
        match value
            .get("code")
            .and_then(Value::as_i64)
            .ok_or(Error::ResponseShapeMismatch)?
        {
            200 => Ok((value, cookies)),
            301 if cookie.is_some() => Err(Error::CredentialRejected),
            301 => Err(Error::AuthenticationRequired),
            _ => Err(Error::UpstreamUnknown),
        }
    }
}

fn request_payload(payload: &mut Value, eapi: bool, cookie: Option<&str>) -> Result<String, Error> {
    let csrf = cookie
        .and_then(|c| c.split("; ").find_map(|p| p.strip_prefix("__csrf=")))
        .unwrap_or("");
    payload["csrf_token"] = json!(csrf);
    if eapi && let Some(cookie) = cookie {
        let music_u = cookie
            .split("; ")
            .find_map(|p| p.strip_prefix("MUSIC_U="))
            .ok_or(Error::ResponseShapeMismatch)?;
        payload["header"] = json!({"MUSIC_U":music_u,"__csrf":csrf});
    }
    let text = serde_json::to_string(payload).map_err(|_| Error::InputBound)?;
    if text.len() > 65536 {
        return Err(Error::InputBound);
    }
    Ok(text)
}
#[cfg(test)]
mod request_tests {
    use super::*;
    #[test]
    fn authenticated_envelopes_keep_csrf_and_session_in_protocol_layer() {
        let mut payload = json!({"ids":"[1]","level":"standard","e_r":false});
        let eapi = request_payload(
            &mut payload,
            true,
            Some("MUSIC_U=synthetic-session; __csrf=synthetic-csrf"),
        )
        .unwrap();
        let parsed: Value = serde_json::from_str(&eapi).unwrap();
        assert_eq!(parsed["header"]["MUSIC_U"], "synthetic-session");
        assert_eq!(parsed["header"]["__csrf"], "synthetic-csrf");
        assert_eq!(parsed["csrf_token"], "synthetic-csrf");
        let mut payload = json!({});
        let text = request_payload(&mut payload, false, None).unwrap();
        assert_eq!(text, r#"{"csrf_token":""}"#);
    }
}
