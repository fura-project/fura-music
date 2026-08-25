use std::fmt;
use std::future::Future;
use std::time::Duration;

const DEFAULT_RESPONSE_BODY_LIMIT: usize = 4 * 1024 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum HttpMethod {
    Get,
}

/// Provider-protocol request with deliberately buffered, inspectable parts.
///
/// Debug output lists query/header names but never values so future credential
/// requests cannot leak through ordinary diagnostics.
#[derive(Clone, Eq, PartialEq)]
pub struct HttpRequest {
    method: HttpMethod,
    url: String,
    query: Vec<(String, String)>,
    headers: Vec<(String, String)>,
    response_body_limit: usize,
}

impl HttpRequest {
    #[must_use]
    pub fn get(url: impl Into<String>) -> Self {
        Self {
            method: HttpMethod::Get,
            url: url.into(),
            query: Vec::new(),
            headers: Vec::new(),
            response_body_limit: DEFAULT_RESPONSE_BODY_LIMIT,
        }
    }

    #[must_use]
    pub fn query(mut self, name: impl Into<String>, value: impl Into<String>) -> Self {
        self.query.push((name.into(), value.into()));
        self
    }

    #[must_use]
    pub fn header(mut self, name: impl Into<String>, value: impl Into<String>) -> Self {
        self.headers.push((name.into(), value.into()));
        self
    }

    #[must_use]
    pub const fn response_body_limit(mut self, bytes: usize) -> Self {
        self.response_body_limit = bytes;
        self
    }

    #[must_use]
    pub const fn method(&self) -> HttpMethod {
        self.method
    }

    #[must_use]
    pub fn url(&self) -> &str {
        &self.url
    }

    #[must_use]
    pub fn query_pairs(&self) -> &[(String, String)] {
        &self.query
    }

    #[must_use]
    pub fn headers(&self) -> &[(String, String)] {
        &self.headers
    }

    #[must_use]
    pub const fn max_response_body_bytes(&self) -> usize {
        self.response_body_limit
    }
}

impl fmt::Debug for HttpRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let url_without_query = self.url.split_once('?').map_or(self.url(), |(url, _)| url);
        formatter
            .debug_struct("HttpRequest")
            .field("method", &self.method)
            .field("url", &url_without_query)
            .field(
                "query_names",
                &self.query.iter().map(|(name, _)| name).collect::<Vec<_>>(),
            )
            .field(
                "header_names",
                &self
                    .headers
                    .iter()
                    .map(|(name, _)| name)
                    .collect::<Vec<_>>(),
            )
            .field("response_body_limit", &self.response_body_limit)
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct HttpResponse {
    status: u16,
    body: Vec<u8>,
}

impl HttpResponse {
    #[must_use]
    pub const fn new(status: u16, body: Vec<u8>) -> Self {
        Self { status, body }
    }

    #[must_use]
    pub const fn status(&self) -> u16 {
        self.status
    }

    #[must_use]
    pub fn body(&self) -> &[u8] {
        &self.body
    }
}

impl fmt::Debug for HttpResponse {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("HttpResponse")
            .field("status", &self.status)
            .field("body_bytes", &self.body.len())
            .finish()
    }
}

pub trait HttpTransport: Send + Sync {
    type Error: std::error::Error + Send + Sync + 'static;

    fn execute(
        &self,
        request: HttpRequest,
    ) -> impl Future<Output = Result<HttpResponse, Self::Error>> + Send;
}

/// Reusable production transport for native Flutter targets.
#[derive(Clone, Debug)]
pub struct ReqwestTransport {
    client: reqwest::Client,
}

pub enum ReqwestTransportError {
    Request(reqwest::Error),
    ResponseBodyTooLarge { limit: usize },
}

impl fmt::Debug for ReqwestTransportError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Request(_) => formatter.write_str("Request([REDACTED])"),
            Self::ResponseBodyTooLarge { limit } => formatter
                .debug_struct("ResponseBodyTooLarge")
                .field("limit", limit)
                .finish(),
        }
    }
}

impl fmt::Display for ReqwestTransportError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Request(_) => formatter.write_str("HTTP request failed"),
            Self::ResponseBodyTooLarge { limit } => {
                write!(formatter, "HTTP response exceeded the {limit}-byte limit")
            }
        }
    }
}

impl std::error::Error for ReqwestTransportError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Request(error) => Some(error),
            Self::ResponseBodyTooLarge { .. } => None,
        }
    }
}

impl ReqwestTransport {
    /// # Errors
    ///
    /// Returns the underlying TLS/client construction error.
    pub fn new() -> Result<Self, reqwest::Error> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(30))
            .user_agent(concat!("flutterustmusic/", env!("CARGO_PKG_VERSION")))
            .build()?;
        Ok(Self { client })
    }
}

impl HttpTransport for ReqwestTransport {
    type Error = ReqwestTransportError;

    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
        let mut builder = match request.method {
            HttpMethod::Get => self.client.get(&request.url),
        };
        builder = builder.query(&request.query);
        for (name, value) in request.headers {
            builder = builder.header(name, value);
        }

        let mut response = builder
            .send()
            .await
            .map_err(reqwest::Error::without_url)
            .map_err(ReqwestTransportError::Request)?;
        let status = response.status().as_u16();
        let limit = request.response_body_limit;
        if response
            .content_length()
            .is_some_and(|length| length > limit as u64)
        {
            return Err(ReqwestTransportError::ResponseBodyTooLarge { limit });
        }

        let initial_capacity = response
            .content_length()
            .and_then(|length| usize::try_from(length).ok())
            .unwrap_or(0);
        let mut body = Vec::with_capacity(initial_capacity);
        while let Some(chunk) = response
            .chunk()
            .await
            .map_err(reqwest::Error::without_url)
            .map_err(ReqwestTransportError::Request)?
        {
            extend_bounded(&mut body, &chunk, limit)?;
        }
        Ok(HttpResponse::new(status, body))
    }
}

fn extend_bounded(
    body: &mut Vec<u8>,
    chunk: &[u8],
    limit: usize,
) -> Result<(), ReqwestTransportError> {
    if body.len().saturating_add(chunk.len()) > limit {
        return Err(ReqwestTransportError::ResponseBodyTooLarge { limit });
    }
    body.extend_from_slice(chunk);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{HttpRequest, HttpResponse, ReqwestTransportError, extend_bounded};

    #[test]
    fn request_debug_output_omits_values() {
        let request = HttpRequest::get("https://example.test/path?embedded=secret-url-query")
            .query("token", "secret-query")
            .header("Authorization", "secret-header");
        let debug = format!("{request:?}");

        assert!(debug.contains("https://example.test/path"));
        assert!(debug.contains("token"));
        assert!(debug.contains("Authorization"));
        assert!(!debug.contains("secret-url-query"));
        assert!(!debug.contains("secret-query"));
        assert!(!debug.contains("secret-header"));
    }

    #[test]
    fn response_debug_output_omits_body() {
        let response = HttpResponse::new(200, b"secret-response".to_vec());
        let debug = format!("{response:?}");

        assert!(debug.contains("body_bytes: 15"));
        assert!(!debug.contains("secret-response"));
    }

    #[test]
    fn streaming_response_limit_is_enforced_before_appending_a_chunk() {
        let mut body = vec![0; 4];

        let error = extend_bounded(&mut body, &[1, 2], 5).expect_err("six bytes exceed limit");

        assert!(matches!(
            error,
            ReqwestTransportError::ResponseBodyTooLarge { limit: 5 }
        ));
        assert_eq!(body.len(), 4);
    }
}
