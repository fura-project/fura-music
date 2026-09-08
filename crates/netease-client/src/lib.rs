//! Bounded, direct `NetEase` HTTPS protocol. No account discovery or retry policy.
mod catalog;
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
    async fn request(
        &self,
        path: &str,
        mut payload: Value,
        eapi: bool,
        cookie: Option<&str>,
    ) -> Result<(Value, Vec<String>), Error> {
        payload["csrf_token"] = json!("");
        let text = serde_json::to_string(&payload).map_err(|_| Error::InputBound)?;
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
        let code = value
            .get("code")
            .and_then(Value::as_i64)
            .ok_or(Error::ResponseShapeMismatch)?;
        match code {
            200 => Ok((value, response.set_cookies)),
            301 => Err(Error::AuthenticationRequired),
            _ => Err(Error::UpstreamUnknown),
        }
    }
}
