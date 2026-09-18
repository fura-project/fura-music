use crate::{Credential, Error, NeteaseClient, Transport};
use serde::Deserialize;
use serde_json::{Value, json};

/// Short-lived direct source; no serialization or content-bearing Debug.
pub struct Media {
    pub(crate) uri: String,
    pub format: MediaFormat,
    pub quality: MediaQuality,
    pub valid_for_seconds: u32,
}
impl Media {
    #[must_use]
    pub fn uri(&self) -> &str {
        &self.uri
    }
}
impl std::fmt::Debug for Media {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("NetEaseMedia([REDACTED])")
    }
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MediaFormat {
    Mp3,
    M4a,
    Flac,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MediaQuality {
    Standard,
    High,
    Lossless,
}
impl MediaQuality {
    const fn request_level(self) -> &'static str {
        match self {
            Self::Standard => "standard",
            Self::High => "exhigh",
            Self::Lossless => "lossless",
        }
    }
}
#[derive(Deserialize)]
struct MediaItem {
    id: u64,
    code: i64,
    url: Option<String>,
    #[serde(rename = "type")]
    format: Option<String>,
    #[serde(rename = "expi")]
    ttl: Option<u32>,
    #[serde(rename = "freeTrialInfo")]
    trial: Option<Value>,
    level: Option<String>,
}
pub(crate) fn decode_media(v: &Value, expected: u64) -> Result<Media, Error> {
    let data: Vec<MediaItem> =
        crate::catalog::decode(v.get("data").cloned().ok_or(Error::ResponseShapeMismatch)?)?;
    if data.len() != 1 {
        return Err(Error::ResponseShapeMismatch);
    }
    let item = data
        .into_iter()
        .next()
        .ok_or(Error::ResponseShapeMismatch)?;
    if item.id != expected {
        return Err(Error::ResponseShapeMismatch);
    }
    if item.code != 200 {
        return Err(Error::UpstreamUnknown);
    }
    if item.trial.is_some() {
        return Err(Error::EntitlementDenied);
    }
    let uri = item.url.ok_or(Error::TrackUnavailable)?;
    if uri.len() > 8192 {
        return Err(Error::ResponseBound);
    }
    let uri = normalize_media_uri(&uri)?;
    let format = match item.format.as_deref() {
        Some("mp3") => MediaFormat::Mp3,
        Some("m4a" | "aac") => MediaFormat::M4a,
        Some("flac") => MediaFormat::Flac,
        _ => return Err(Error::ProtocolUnavailable),
    };
    // NetEase may legally return a lower account-entitled level than requested.
    // Preserve the response level as the actual quality instead of claiming the
    // preference was fulfilled. `higher` is 192 kbps, so it remains below the
    // app's 320 kbps HQ contract and is reported as Standard.
    let quality = match item.level.as_deref() {
        Some("standard" | "higher") => MediaQuality::Standard,
        Some("exhigh") => MediaQuality::High,
        Some("lossless" | "hires") => MediaQuality::Lossless,
        _ => return Err(Error::ProtocolUnavailable),
    };
    let ttl = item
        .ttl
        .filter(|ttl| *ttl > 0 && *ttl <= 86400)
        .ok_or(Error::ResponseShapeMismatch)?;
    Ok(Media {
        uri,
        format,
        quality,
        valid_for_seconds: ttl,
    })
}

fn normalize_media_uri(uri: &str) -> Result<String, Error> {
    let mut parsed = url::Url::parse(uri).map_err(|_| Error::ResponseShapeMismatch)?;
    let host = parsed.host_str().ok_or(Error::ResponseShapeMismatch)?;
    if !parsed.username().is_empty()
        || parsed.password().is_some()
        || parsed.port().is_some()
        || uri
            .split_once("://")
            .and_then(|(_, remainder)| remainder.split(['/', '?', '#']).next())
            .is_some_and(|authority| authority.contains(':'))
        || parsed.fragment().is_some()
    {
        return Err(Error::ResponseShapeMismatch);
    }
    match parsed.scheme() {
        "https" => {}
        "http" if trusted_cleartext_media_host(host) => {
            parsed
                .set_scheme("https")
                .map_err(|()| Error::ResponseShapeMismatch)?;
        }
        _ => return Err(Error::ResponseShapeMismatch),
    }
    Ok(parsed.into())
}

fn trusted_cleartext_media_host(host: &str) -> bool {
    let Some(label) = host.strip_suffix(".music.126.net") else {
        return false;
    };
    let Some(digits) = label.strip_prefix('m') else {
        return false;
    };
    !digits.is_empty() && digits.len() <= 4 && digits.bytes().all(|byte| byte.is_ascii_digit())
}

fn log_media_source(media: &Media) {
    let Ok(uri) = url::Url::parse(media.uri()) else {
        return;
    };
    media_debug(format_args!(
        "phase=source outcome=ready scheme={} host={} format={:?} quality={:?} ttl={}",
        uri.scheme(),
        uri.host_str().unwrap_or("none"),
        media.format,
        media.quality,
        media.valid_for_seconds,
    ));
}
impl<T: Transport> NeteaseClient<T> {
    /// Compatibility entry point for one normal, standard-quality source.
    /// # Errors
    /// Access denial, missing source, unknown codes and unsupported profiles all stop.
    pub async fn media(&self, id: u64) -> Result<Media, Error> {
        self.media_with_quality(id, MediaQuality::Standard).await
    }

    /// Resolves one anonymous source at the selected quality. `NetEase` may
    /// return a lower actual level when the account or Track is not entitled;
    /// that actual level is retained in [`Media::quality`].
    /// # Errors
    /// Access denial, missing source, unknown codes and unsupported profiles all stop.
    pub async fn media_with_quality(
        &self,
        id: u64,
        preferred: MediaQuality,
    ) -> Result<Media, Error> {
        crate::catalog::id(id)?;
        let level = preferred.request_level();
        let encode_type = if preferred == MediaQuality::Standard {
            "aac"
        } else {
            "flac"
        };
        let (v, _) = self
            .request(
                "/api/song/enhance/player/url/v1",
                json!({"ids":format!("[{id}]"),"level":level,"encodeType":encode_type,"e_r":false}),
                true,
                None,
            )
            .await?;
        let media = decode_media(&v, id)?;
        log_media_source(&media);
        Ok(media)
    }

    /// Compatibility entry point for one authenticated standard source.
    /// # Errors
    /// Access denial, missing source, unknown codes and unsupported profiles all stop.
    pub async fn authenticated_media(
        &self,
        credential: &Credential,
        id: u64,
    ) -> Result<Media, Error> {
        self.authenticated_media_with_quality(credential, id, MediaQuality::Standard)
            .await
    }

    /// Resolves one selected-quality source using the current desktop EAPI route and
    /// the already-verified account session. The richer desktop context is
    /// request-local and is never persisted with the credential.
    /// # Errors
    /// Access denial, missing source, unknown codes and unsupported profiles all stop.
    pub async fn authenticated_media_with_quality(
        &self,
        credential: &Credential,
        id: u64,
        preferred: MediaQuality,
    ) -> Result<Media, Error> {
        crate::catalog::id(id)?;
        let (cookie, header) = credential.media_context()?;
        let level = preferred.request_level();
        let response = self
            .raw_interface3_eapi_request(
                "/api/song/enhance/player/url/v1",
                json!({
                    "ids":format!("[{id}]"),
                    "level":level,
                    "encodeType":"flac",
                    "header":header,
                }),
                Some(&cookie),
                vec![("Referer".into(), "https://music.163.com/".into())],
            )
            .await;
        let (value, cookies) = match response {
            Ok(response) => response,
            Err(error) => {
                media_debug(format_args!(
                    "phase=request outcome=failure failure={error:?}"
                ));
                return Err(error);
            }
        };
        media_debug(format_args!(
            "phase=response transport=ok business_code={} item_code={} has_data={} has_url={} level={} format={}",
            value.get("code").and_then(Value::as_i64).unwrap_or(-1),
            value
                .pointer("/data/0/code")
                .and_then(Value::as_i64)
                .unwrap_or(-1),
            value.get("data").is_some_and(Value::is_array),
            value
                .pointer("/data/0/url")
                .is_some_and(|url| url.as_str().is_some_and(|url| !url.is_empty())),
            value
                .pointer("/data/0/level")
                .and_then(Value::as_str)
                .unwrap_or("none"),
            value
                .pointer("/data/0/type")
                .and_then(Value::as_str)
                .unwrap_or("none"),
        ));
        let (value, _) = Self::accepted_response(value, cookies, true)?;
        let media = decode_media(&value, id)?;
        log_media_source(&media);
        Ok(media)
    }
}

fn media_debug(message: std::fmt::Arguments<'_>) {
    if std::env::var_os("FURA_NETEASE_MEDIA_DEBUG").is_some() {
        eprintln!("FURA_DIAGNOSTIC netease_media_core {message}");
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};
    fn value() -> Value {
        json!({"data":[{"id":7,"code":200,"url":"https://fixture.invalid/source","type":"mp3","expi":1200,"freeTrialInfo":null,"level":"standard"}]})
    }
    #[test]
    fn source_is_exact_short_lived_and_redacted() {
        let source = decode_media(&value(), 7).unwrap();
        assert_eq!(source.valid_for_seconds, 1200);
        assert_eq!(source.quality, MediaQuality::Standard);
        assert!(!format!("{source:?}").contains("fixture.invalid"));
        assert!(decode_media(&value(), 8).is_err());
    }

    #[test]
    fn response_level_and_format_report_actual_quality_including_downgrade() {
        let mut high = value();
        high["data"][0]["level"] = json!("exhigh");
        assert_eq!(decode_media(&high, 7).unwrap().quality, MediaQuality::High);

        let mut lossless = value();
        lossless["data"][0]["level"] = json!("lossless");
        lossless["data"][0]["type"] = json!("flac");
        let source = decode_media(&lossless, 7).unwrap();
        assert_eq!(source.quality, MediaQuality::Lossless);
        assert_eq!(source.format, MediaFormat::Flac);

        // A service-side fallback is accepted and reported as what actually
        // arrived, rather than what the caller preferred.
        let mut fallback = value();
        fallback["data"][0]["level"] = json!("higher");
        assert_eq!(
            decode_media(&fallback, 7).unwrap().quality,
            MediaQuality::Standard
        );

        let mut unknown = value();
        unknown["data"][0]["level"] = json!("future-profile");
        assert!(matches!(
            decode_media(&unknown, 7),
            Err(Error::ProtocolUnavailable)
        ));
    }
    #[test]
    fn trial_missing_source_unknown_code_and_bad_url_stop() {
        let mut v = value();
        v["data"][0]["freeTrialInfo"] = json!({"start":0,"end":60});
        assert!(matches!(decode_media(&v, 7), Err(Error::EntitlementDenied)));
        let mut v = value();
        v["data"][0]["url"] = Value::Null;
        assert!(matches!(decode_media(&v, 7), Err(Error::TrackUnavailable)));
        let mut v = value();
        v["data"][0]["code"] = json!(999);
        assert!(matches!(decode_media(&v, 7), Err(Error::UpstreamUnknown)));
        for url in [
            "file:///secret",
            "https://u:p@example.test/a",
            "https://example.test/a#token",
            "http://m701.music.126.net.evil.test/source",
            "http://evil.music.126.net/source",
            "http://m701.music.126.net:80/source",
            "https://fixture.invalid:443/source",
            "http://m.music.126.net/source",
            "http://m12345.music.126.net/source",
            "http://m701a.music.126.net/source",
        ] {
            let mut v = value();
            v["data"][0]["url"] = json!(url);
            assert!(decode_media(&v, 7).is_err());
        }
    }

    #[test]
    fn trusted_cleartext_media_is_upgraded_without_changing_path_or_query() {
        let mut v = value();
        v["data"][0]["url"] =
            json!("http://m701.music.126.net/a%2Fb/source.m4a?token=synthetic%2Fvalue");
        v["data"][0]["type"] = json!("m4a");
        let source = decode_media(&v, 7).unwrap();
        assert_eq!(
            source.uri(),
            "https://m701.music.126.net/a%2Fb/source.m4a?token=synthetic%2Fvalue"
        );
        assert_eq!(source.format, MediaFormat::M4a);
    }

    #[test]
    fn native_https_media_is_preserved() {
        let source = decode_media(&value(), 7).unwrap();
        assert_eq!(source.uri(), "https://fixture.invalid/source");
    }

    struct RecordingTransport {
        request: Arc<Mutex<Option<crate::Request>>>,
        response_level: &'static str,
        response_format: &'static str,
    }

    impl Transport for RecordingTransport {
        fn send(
            &self,
            request: crate::Request,
        ) -> impl std::future::Future<Output = Result<crate::Response, Error>> + Send {
            *self.request.lock().unwrap() = Some(request);
            std::future::ready(Ok(crate::Response {
                status: 200,
                body: serde_json::to_vec(&json!({
                    "code":200,
                    "data":[{
                        "id":7,
                        "code":200,
                        "url":"https://fixture.invalid/source",
                        "type":self.response_format,
                        "expi":1200,
                        "freeTrialInfo":null,
                        "level":self.response_level
                    }]
                }))
                .unwrap(),
                set_cookies: vec![],
            }))
        }
    }

    fn decode_eapi_payload(encrypted: &str) -> Value {
        let bytes = encrypted
            .as_bytes()
            .as_chunks::<2>()
            .0
            .iter()
            .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap())
            .collect::<Vec<_>>();
        let decoded = String::from_utf8(crate::crypto::eapi_response(&bytes).unwrap()).unwrap();
        let (_, payload_and_digest) = decoded.split_once("-36cd479b6b5-").unwrap();
        let (payload, _) = payload_and_digest.rsplit_once("-36cd479b6b5-").unwrap();
        serde_json::from_str(payload).unwrap()
    }

    #[tokio::test]
    async fn authenticated_source_uses_current_interface_and_desktop_context() {
        let captured = Arc::new(Mutex::new(None));
        let client = NeteaseClient::new(RecordingTransport {
            request: Arc::clone(&captured),
            response_level: "standard",
            response_format: "mp3",
        });
        let credential = Credential::import(
            &serde_json::to_vec(&json!({
                "version":1,
                "provider":"netease-cloud-music",
                "music_u":"synthetic-session",
                "csrf":"synthetic-csrf"
            }))
            .unwrap(),
        )
        .unwrap();

        let source = client.authenticated_media(&credential, 7).await.unwrap();
        assert_eq!(source.format, MediaFormat::Mp3);

        let request = captured.lock().unwrap().take().unwrap();
        assert_eq!(
            request.url(),
            "https://interface3.music.163.com/eapi/song/enhance/player/url/v1"
        );
        let cookie = request.cookie().unwrap();
        for name in [
            "MUSIC_U=synthetic-session",
            "__csrf=synthetic-csrf",
            "os=pc",
            "appver=8.0.0",
            "requestId=",
        ] {
            assert!(cookie.contains(name));
        }
        assert_eq!(
            request.headers(),
            &[("Referer".into(), "https://music.163.com/".into())]
        );
        let payload = decode_eapi_payload(&request.form()[0].1);
        assert_eq!(payload["ids"], "[7]");
        assert_eq!(payload["level"], "standard");
        assert_eq!(payload["encodeType"], "flac");
        assert_eq!(payload["header"]["MUSIC_U"], "synthetic-session");
        assert_eq!(payload["header"]["__csrf"], "synthetic-csrf");
        assert_eq!(payload["header"]["os"], "pc");
        assert_eq!(payload["header"]["appver"], "8.0.0");
        assert!(
            payload["header"]["requestId"]
                .as_str()
                .unwrap()
                .contains('_')
        );
    }

    #[tokio::test]
    async fn anonymous_high_request_uses_exhigh_and_reports_the_response_level() {
        let captured = Arc::new(Mutex::new(None));
        let client = NeteaseClient::new(RecordingTransport {
            request: Arc::clone(&captured),
            response_level: "exhigh",
            response_format: "mp3",
        });

        let source = client
            .media_with_quality(7, MediaQuality::High)
            .await
            .unwrap();
        assert_eq!(source.quality, MediaQuality::High);
        assert_eq!(source.format, MediaFormat::Mp3);

        let request = captured.lock().unwrap().take().unwrap();
        assert_eq!(
            request.url(),
            "https://interface.music.163.com/eapi/song/enhance/player/url/v1"
        );
        assert!(request.cookie().is_none());
        let payload = decode_eapi_payload(&request.form()[0].1);
        assert_eq!(payload["ids"], "[7]");
        assert_eq!(payload["level"], "exhigh");
        assert_eq!(payload["encodeType"], "flac");
    }

    #[tokio::test]
    async fn authenticated_lossless_request_uses_lossless_and_reports_flac() {
        let captured = Arc::new(Mutex::new(None));
        let client = NeteaseClient::new(RecordingTransport {
            request: Arc::clone(&captured),
            response_level: "lossless",
            response_format: "flac",
        });
        let credential = Credential::import(
            &serde_json::to_vec(&json!({
                "version":1,
                "provider":"netease-cloud-music",
                "music_u":"synthetic-session",
                "csrf":"synthetic-csrf"
            }))
            .unwrap(),
        )
        .unwrap();

        let source = client
            .authenticated_media_with_quality(&credential, 7, MediaQuality::Lossless)
            .await
            .unwrap();
        assert_eq!(source.quality, MediaQuality::Lossless);
        assert_eq!(source.format, MediaFormat::Flac);

        let request = captured.lock().unwrap().take().unwrap();
        let payload = decode_eapi_payload(&request.form()[0].1);
        assert_eq!(payload["level"], "lossless");
        assert_eq!(payload["encodeType"], "flac");
    }
}
