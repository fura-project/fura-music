use crate::{Error, NeteaseClient, Transport};
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
}
#[cfg(test)]
mod tests {
    use super::*;
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
}
