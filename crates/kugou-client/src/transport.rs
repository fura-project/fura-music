use crate::Error;
use std::{fmt, future::Future, time::Duration};

pub const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;

/// One secret-safe public request. Query values are deliberately redacted from
/// `Debug`; only the transport may inspect the complete URI.
pub struct Request {
    pub(crate) url: String,
}

impl Request {
    #[must_use]
    pub fn url(&self) -> &str {
        &self.url
    }
}

impl fmt::Debug for Request {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("KuGouRequest([REDACTED])")
    }
}

pub struct Response {
    pub status: u16,
    pub content_type: Option<String>,
    pub body: Vec<u8>,
}

impl fmt::Debug for Response {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("KuGouResponse")
            .field("status", &self.status)
            .field("body_bytes", &self.body.len())
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
    /// Returns a coarse failure when the bounded HTTPS client cannot be built.
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
        let parsed = url::Url::parse(&request.url).map_err(|_| Error::InputBound)?;
        if parsed.scheme() != "https"
            || parsed.host_str() != Some("songsearch.kugou.com")
            || !parsed.username().is_empty()
            || parsed.password().is_some()
            || parsed.port().is_some()
            || parsed.fragment().is_some()
        {
            return Err(Error::InputBound);
        }

        let mut response = self
            .client
            .get(request.url)
            .header(reqwest::header::ACCEPT, "application/json,text/plain;q=0.9")
            .header(reqwest::header::USER_AGENT, "fura-music/0.1")
            .send()
            .await
            .map_err(|_| Error::TemporaryNetworkFailure)?;
        let status = response.status().as_u16();
        let content_type = response
            .headers()
            .get(reqwest::header::CONTENT_TYPE)
            .map(|value| {
                value
                    .to_str()
                    .map(str::to_owned)
                    .map_err(|_| Error::ResponseShapeMismatch)
            })
            .transpose()?;
        if response
            .content_length()
            .is_some_and(|length| length > MAX_RESPONSE_BYTES as u64)
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
            content_type,
            body,
        })
    }
}
