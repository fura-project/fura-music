use crate::Error;
use std::{fmt, future::Future, time::Duration};

pub const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
/// Secret-bearing request parts; only the transport may inspect their values.
pub struct Request {
    pub(crate) url: String,
    pub(crate) form: Vec<(String, String)>,
    pub(crate) cookie: Option<String>,
}
impl Request {
    #[must_use]
    pub fn url(&self) -> &str {
        &self.url
    }
    #[must_use]
    pub fn form(&self) -> &[(String, String)] {
        &self.form
    }
    #[must_use]
    pub fn cookie(&self) -> Option<&str> {
        self.cookie.as_deref()
    }
}
impl fmt::Debug for Request {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("NetEaseRequest([REDACTED])")
    }
}
pub struct Response {
    pub status: u16,
    pub body: Vec<u8>,
    pub set_cookies: Vec<String>,
}
impl fmt::Debug for Response {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("NetEaseResponse")
            .field("status", &self.status)
            .finish_non_exhaustive()
    }
}
pub trait Transport: Send + Sync {
    fn send(&self, request: Request) -> impl Future<Output = Result<Response, Error>> + Send;
}
pub struct HttpsTransport {
    client: reqwest::Client,
}
impl HttpsTransport {
    /// # Errors
    /// Returns a coarse failure if the platform HTTPS client cannot be created.
    pub fn new() -> Result<Self, Error> {
        let client = reqwest::Client::builder()
            .https_only(true)
            .redirect(reqwest::redirect::Policy::none())
            .timeout(Duration::from_secs(20))
            .build()
            .map_err(|_| Error::TemporaryNetworkFailure)?;
        Ok(Self { client })
    }
}
impl Transport for HttpsTransport {
    async fn send(&self, request: Request) -> Result<Response, Error> {
        let mut builder = self
            .client
            .post(request.url)
            .header("Referer", "https://music.163.com/")
            .header("User-Agent", "Mozilla/5.0")
            .form(&request.form);
        if let Some(cookie) = request.cookie {
            builder = builder.header("Cookie", cookie);
        }
        let mut response = builder
            .send()
            .await
            .map_err(|_| Error::TemporaryNetworkFailure)?;
        let status = response.status().as_u16();
        let set_cookies = response
            .headers()
            .get_all("set-cookie")
            .iter()
            .map(|h| {
                h.to_str()
                    .map(str::to_owned)
                    .map_err(|_| Error::ResponseShapeMismatch)
            })
            .collect::<Result<Vec<_>, _>>()?;
        if set_cookies.len() > 32 || set_cookies.iter().any(|s| s.len() > 8192) {
            return Err(Error::ResponseShapeMismatch);
        }
        if response
            .content_length()
            .is_some_and(|n| n > MAX_RESPONSE_BYTES as u64)
        {
            return Err(Error::ResponseBound);
        }
        let mut body = Vec::new();
        while let Some(chunk) = response
            .chunk()
            .await
            .map_err(|_| Error::TemporaryNetworkFailure)?
        {
            if chunk.len() > MAX_RESPONSE_BYTES - body.len() {
                return Err(Error::ResponseBound);
            }
            body.extend_from_slice(&chunk);
        }
        Ok(Response {
            status,
            body,
            set_cookies,
        })
    }
}
