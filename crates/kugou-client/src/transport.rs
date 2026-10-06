use crate::Error;
use std::{fmt, future::Future, time::Duration};

pub const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;

/// One secret-safe public request. Query values are deliberately redacted from
/// `Debug`; only the transport may inspect the complete URI.
pub struct Request {
    pub(crate) url: String,
    pub(crate) profile: crate::profile::KuGouProtocolProfile,
}

impl Request {
    #[must_use]
    pub fn url(&self) -> &str {
        &self.url
    }

    #[must_use]
    pub fn headers(&self) -> [(&'static str, &'static str); 2] {
        self.profile.headers()
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
            || !allowed_route(&parsed)
            || !parsed.username().is_empty()
            || parsed.password().is_some()
            || parsed.port().is_some()
            || parsed.fragment().is_some()
        {
            return Err(Error::InputBound);
        }

        let mut builder = self.client.get(&request.url);
        for (name, value) in request.headers() {
            builder = builder.header(name, value);
        }
        let mut response = builder
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

fn allowed_route(parsed: &url::Url) -> bool {
    matches!(
        (parsed.host_str(), parsed.path()),
        (Some("songsearch.kugou.com"), "/song_search_v2")
            | (
                Some("m.kugou.com"),
                "/app/i/getSongInfo.php" | "/rank/list" | "/rank/info/"
            )
            | (Some("krcs.kugou.com"), "/search")
            | (Some("lyrics.kugou.com"), "/download")
    )
}

#[cfg(test)]
mod tests {
    use super::allowed_route;

    #[test]
    fn route_allowlist_is_exact_and_rejects_host_and_path_lookalikes() {
        for value in [
            "https://songsearch.kugou.com/song_search_v2",
            "https://m.kugou.com/app/i/getSongInfo.php",
            "https://m.kugou.com/rank/list",
            "https://m.kugou.com/rank/info/",
            "https://krcs.kugou.com/search",
            "https://lyrics.kugou.com/download",
        ] {
            assert!(allowed_route(&url::Url::parse(value).unwrap()));
        }
        for value in [
            "https://example.invalid/song_search_v2",
            "https://songsearch.kugou.com.evil.invalid/song_search_v2",
            "https://m.kugou.com/rank/info",
            "https://m.kugou.com/app/i/getSongInfo.php/extra",
            "https://lyrics.kugou.com/v1/download",
        ] {
            assert!(!allowed_route(&url::Url::parse(value).unwrap()));
        }
    }
}
