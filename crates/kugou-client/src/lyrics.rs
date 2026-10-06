use crate::{Error, KuGouClient, MAX_RESPONSE_BYTES, Request, Transport, search::MAX_TEXT_BYTES};
use base64::{Engine as _, engine::general_purpose::STANDARD};
use serde::Deserialize;

const SEARCH_ENDPOINT: &str = "https://krcs.kugou.com/search";
const DOWNLOAD_ENDPOINT: &str = "https://lyrics.kugou.com/download";
const MAX_CANDIDATES: usize = 100;
const MAX_LINES: usize = 10_000;

#[derive(Clone, Eq, PartialEq)]
pub struct LyricLine {
    pub start_ms: u32,
    pub text: String,
}

impl std::fmt::Debug for LyricLine {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("KuGouLyricLine")
            .field("start_ms", &self.start_ms)
            .field("text", &"[REDACTED]")
            .finish()
    }
}

pub struct Lyrics {
    pub lines: Vec<LyricLine>,
    pub omitted_line_count: u32,
}

impl std::fmt::Debug for Lyrics {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("KuGouLyrics")
            .field("line_count", &self.lines.len())
            .field("omitted_line_count", &self.omitted_line_count)
            .finish()
    }
}

#[derive(Deserialize)]
struct SearchEnvelope {
    status: i64,
    error_code: i64,
    candidates: Vec<Candidate>,
}

#[derive(Deserialize)]
struct Candidate {
    #[serde(deserialize_with = "string_or_number")]
    id: String,
    accesskey: String,
}

#[derive(Deserialize)]
struct DownloadEnvelope {
    status: i64,
    errcode: i64,
    #[serde(default)]
    fmt: Option<String>,
    content: String,
}

impl<T: Transport> KuGouClient<T> {
    /// Loads exact-hash synchronized LRC through the unsigned public lyric
    /// search and download pair. The server-issued candidate identity never
    /// leaves this client.
    ///
    /// # Errors
    /// Returns a bounded typed failure for invalid exact context, transport,
    /// unavailable lyrics or malformed candidate/LRC content.
    pub async fn lyrics(
        &self,
        standard_hash: &str,
        duration_seconds: u32,
    ) -> Result<Lyrics, Error> {
        validate_hash(standard_hash)?;
        if duration_seconds > 86_400 {
            return Err(Error::InputBound);
        }
        let mut search = url::Url::parse(SEARCH_ENDPOINT).map_err(|_| Error::InputBound)?;
        search
            .query_pairs_mut()
            .append_pair("ver", "1")
            .append_pair("man", "yes")
            .append_pair("client", "mobi")
            .append_pair("hash", standard_hash)
            .append_pair("duration", &duration_seconds.to_string());
        let response = send(&self.transport, search).await?;
        let envelope: SearchEnvelope =
            serde_json::from_slice(&response).map_err(|_| Error::ResponseShapeMismatch)?;
        if envelope.status != 200 || envelope.error_code != 200 {
            return Err(Error::UpstreamUnknown);
        }
        if envelope.candidates.len() > MAX_CANDIDATES {
            return Err(Error::ResponseBound);
        }
        let candidate = envelope
            .candidates
            .into_iter()
            .next()
            .ok_or(Error::ContentUnavailable)?;
        validate_candidate(&candidate)?;

        let mut download = url::Url::parse(DOWNLOAD_ENDPOINT).map_err(|_| Error::InputBound)?;
        download
            .query_pairs_mut()
            .append_pair("ver", "1")
            .append_pair("client", "pc")
            .append_pair("id", &candidate.id)
            .append_pair("accesskey", &candidate.accesskey)
            .append_pair("fmt", "lrc")
            .append_pair("charset", "utf8");
        let response = send(&self.transport, download).await?;
        let envelope: DownloadEnvelope =
            serde_json::from_slice(&response).map_err(|_| Error::ResponseShapeMismatch)?;
        if envelope.status != 200 || envelope.errcode != 0 {
            return Err(Error::UpstreamUnknown);
        }
        if envelope.fmt.as_deref().is_some_and(|fmt| fmt != "lrc") {
            return Err(Error::ResponseShapeMismatch);
        }
        let bytes = STANDARD
            .decode(envelope.content)
            .map_err(|_| Error::ResponseShapeMismatch)?;
        if bytes.len() > MAX_RESPONSE_BYTES {
            return Err(Error::ResponseBound);
        }
        let document = String::from_utf8(bytes).map_err(|_| Error::ResponseShapeMismatch)?;
        parse_lrc(&document)
    }
}

async fn send<T: Transport>(transport: &T, endpoint: url::Url) -> Result<Vec<u8>, Error> {
    if endpoint.as_str().len() > MAX_TEXT_BYTES {
        return Err(Error::InputBound);
    }
    let response = transport
        .send(Request {
            url: endpoint.into(),
            profile: crate::profile::KuGouProtocolProfile::Public,
        })
        .await?;
    match response.status {
        200 => {}
        429 => return Err(Error::RateLimited),
        _ => return Err(Error::ProtocolUnavailable),
    }
    if response.body.len() > MAX_RESPONSE_BYTES {
        return Err(Error::ResponseBound);
    }
    let content_type = response
        .content_type
        .as_deref()
        .and_then(|value| value.split(';').next())
        .map(str::trim);
    if !matches!(
        content_type,
        Some("application/json" | "text/plain" | "text/html")
    ) {
        return Err(Error::ResponseShapeMismatch);
    }
    Ok(response.body)
}

fn validate_hash(value: &str) -> Result<(), Error> {
    if value.len() == 32 && value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        Ok(())
    } else {
        Err(Error::InputBound)
    }
}

fn validate_candidate(candidate: &Candidate) -> Result<(), Error> {
    if candidate.id.is_empty()
        || candidate.id.len() > 128
        || !candidate.id.bytes().all(|byte| byte.is_ascii_digit())
        || candidate.accesskey.is_empty()
        || candidate.accesskey.len() > 256
        || !candidate.accesskey.bytes().all(|byte| {
            byte.is_ascii_alphanumeric() || matches!(byte, b'+' | b'/' | b'=' | b'-' | b'_')
        })
    {
        Err(Error::ResponseShapeMismatch)
    } else {
        Ok(())
    }
}

fn string_or_number<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: serde::Deserializer<'de>,
{
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum Value {
        String(String),
        Number(u64),
    }
    Ok(match Value::deserialize(deserializer)? {
        Value::String(value) => value,
        Value::Number(value) => value.to_string(),
    })
}

fn parse_lrc(document: &str) -> Result<Lyrics, Error> {
    if document.len() > MAX_RESPONSE_BYTES {
        return Err(Error::ResponseBound);
    }
    let mut lines = Vec::new();
    let mut omitted_line_count = 0_u32;
    for raw_line in document.lines() {
        if raw_line.len() > MAX_TEXT_BYTES {
            omitted_line_count = omitted_line_count
                .checked_add(1)
                .ok_or(Error::ResponseBound)?;
            continue;
        }
        match parse_line(raw_line) {
            Ok(parsed) => {
                if lines.len().saturating_add(parsed.len()) > MAX_LINES {
                    return Err(Error::ResponseBound);
                }
                lines.extend(parsed);
            }
            Err(()) => {
                omitted_line_count = omitted_line_count
                    .checked_add(1)
                    .ok_or(Error::ResponseBound)?;
            }
        }
    }
    if lines.is_empty() {
        return Err(Error::ContentUnavailable);
    }
    lines.sort_by_key(|line| line.start_ms);
    Ok(Lyrics {
        lines,
        omitted_line_count,
    })
}

fn parse_line(mut line: &str) -> Result<Vec<LyricLine>, ()> {
    let mut timestamps = Vec::new();
    while let Some(rest) = line.strip_prefix('[') {
        let end = rest.find(']').ok_or(())?;
        let marker = &rest[..end];
        let Some(start_ms) = timestamp(marker)? else {
            return Ok(Vec::new());
        };
        timestamps.push(start_ms);
        line = &rest[end + 1..];
    }
    if timestamps.is_empty() {
        return Ok(Vec::new());
    }
    if line.len() > MAX_TEXT_BYTES || line.chars().any(char::is_control) {
        return Err(());
    }
    Ok(timestamps
        .into_iter()
        .map(|start_ms| LyricLine {
            start_ms,
            text: line.to_owned(),
        })
        .collect())
}

fn timestamp(value: &str) -> Result<Option<u32>, ()> {
    let Some((minutes, seconds)) = value.split_once(':') else {
        return Ok(None);
    };
    if minutes.is_empty() || minutes.len() > 3 || !minutes.bytes().all(|byte| byte.is_ascii_digit())
    {
        return Ok(None);
    }
    let (whole, fraction) = seconds.split_once('.').unwrap_or((seconds, ""));
    if whole.len() != 2
        || !whole.bytes().all(|byte| byte.is_ascii_digit())
        || fraction.len() > 3
        || !fraction.bytes().all(|byte| byte.is_ascii_digit())
    {
        return Err(());
    }
    let minutes = minutes.parse::<u32>().map_err(|_| ())?;
    let seconds = whole.parse::<u32>().map_err(|_| ())?;
    if seconds >= 60 {
        return Err(());
    }
    let fraction_ms = match fraction.len() {
        0 => 0,
        1 => fraction.parse::<u32>().map_err(|_| ())? * 100,
        2 => fraction.parse::<u32>().map_err(|_| ())? * 10,
        3 => fraction.parse::<u32>().map_err(|_| ())?,
        _ => return Err(()),
    };
    minutes
        .checked_mul(60_000)
        .and_then(|value| value.checked_add(seconds * 1_000))
        .and_then(|value| value.checked_add(fraction_ms))
        .ok_or(())
        .map(Some)
}

#[cfg(test)]
mod tests {
    use super::parse_lrc;

    #[test]
    fn parses_metadata_multiple_timestamps_and_malformed_rows() {
        let parsed =
            parse_lrc("[ar:Fixture]\n[00:01.2][00:02.034]Line\n[00:61.00]bad\n[00:03]End").unwrap();
        assert_eq!(parsed.lines.len(), 3);
        assert_eq!(parsed.lines[0].start_ms, 1_200);
        assert_eq!(parsed.lines[1].start_ms, 2_034);
        assert_eq!(parsed.lines[2].start_ms, 3_000);
        assert_eq!(parsed.omitted_line_count, 1);
    }
}
