use crate::{Credential, Error, NeteaseClient, Transport};
use serde::Deserialize;
use serde_json::{Value, json};

/// Short-lived direct source; no serialization or content-bearing Debug.
pub struct Media {
    pub(crate) uri: String,
    pub format: MediaFormat,
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
    let parsed = url::Url::parse(&uri).map_err(|_| Error::ResponseShapeMismatch)?;
    if !matches!(parsed.scheme(), "https" | "http")
        || parsed.host_str().is_none()
        || !parsed.username().is_empty()
        || parsed.password().is_some()
        || parsed.fragment().is_some()
    {
        return Err(Error::ResponseShapeMismatch);
    }
    let format = match item.format.as_deref() {
        Some("mp3") => MediaFormat::Mp3,
        Some("m4a" | "aac") => MediaFormat::M4a,
        _ => return Err(Error::ProtocolUnavailable),
    };
    if item.level.as_deref() != Some("standard") {
        return Err(Error::ProtocolUnavailable);
    }
    let ttl = item
        .ttl
        .filter(|ttl| *ttl > 0 && *ttl <= 86400)
        .ok_or(Error::ResponseShapeMismatch)?;
    Ok(Media {
        uri,
        format,
        valid_for_seconds: ttl,
    })
}
impl<T: Transport> NeteaseClient<T> {
    /// One normal, standard-quality source request. No fallback, substitution or trial escalation.
    /// # Errors
    /// Access denial, missing source, unknown codes and unsupported profiles all stop.
    pub async fn media(&self, id: u64) -> Result<Media, Error> {
        crate::catalog::id(id)?;
        let (v, _) = self
            .request(
                "/api/song/enhance/player/url/v1",
                json!({"ids":format!("[{id}]"),"level":"standard","encodeType":"aac","e_r":false}),
                true,
                None,
            )
            .await?;
        decode_media(&v, id)
    }

    /// Resolves one standard source using the current desktop EAPI route and
    /// the already-verified account session. The richer desktop context is
    /// request-local and is never persisted with the credential.
    /// # Errors
    /// Access denial, missing source, unknown codes and unsupported profiles all stop.
    pub async fn authenticated_media(
        &self,
        credential: &Credential,
        id: u64,
    ) -> Result<Media, Error> {
        crate::catalog::id(id)?;
        let (cookie, header) = credential.media_context()?;
        let response = self
            .raw_interface3_eapi_request(
                "/api/song/enhance/player/url/v1",
                json!({
                    "ids":format!("[{id}]"),
                    "level":"standard",
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
        decode_media(&value, id)
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
        assert!(!format!("{source:?}").contains("fixture.invalid"));
        assert!(decode_media(&value(), 8).is_err());
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
        ] {
            let mut v = value();
            v["data"][0]["url"] = json!(url);
            assert!(decode_media(&v, 7).is_err());
        }
    }

    struct RecordingTransport {
        request: Arc<Mutex<Option<crate::Request>>>,
    }

    impl Transport for RecordingTransport {
        async fn send(&self, request: crate::Request) -> Result<crate::Response, Error> {
            *self.request.lock().unwrap() = Some(request);
            Ok(crate::Response {
                status: 200,
                body: serde_json::to_vec(&json!({
                    "code":200,
                    "data":[{
                        "id":7,
                        "code":200,
                        "url":"https://fixture.invalid/source",
                        "type":"mp3",
                        "expi":1200,
                        "freeTrialInfo":null,
                        "level":"standard"
                    }]
                }))
                .unwrap(),
                set_cookies: vec![],
            })
        }
    }

    fn decode_eapi_payload(encrypted: &str) -> Value {
        let bytes = encrypted
            .as_bytes()
            .chunks_exact(2)
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
}
