use std::fmt;
use std::time::Duration;

use reqwest::Url;
use serde::{Deserialize, Serialize};

use crate::credential::is_credential_rejection_code;
use crate::{Credential, HttpRequest, HttpTransport, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_MEDIA_RESPONSE_BYTES: usize = 256 * 1024;
const MEDIA_REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MP3_EXTENSION: &str = ".mp3";
const PREFERRED_CDN_HOST: &str = "dl.stream.qqmusic.qq.com";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MediaProtocolPhase {
    CdnDispatch,
    Vkey,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MediaResponseField {
    GlobalCode,
    Result,
    ResultCode,
    Data,
    DispatchCode,
    CdnBases,
    Expiration,
    RefreshTime,
    CacheTime,
    Items,
    ItemSongMid,
    ItemFilename,
    ItemResult,
    SourcePath,
}

pub enum QqMusicMediaError<E> {
    InvalidSongMid,
    InvalidFileMediaMid,
    RandomnessUnavailable,
    Serialize(MediaProtocolPhase),
    Transport {
        phase: MediaProtocolPhase,
        source: E,
    },
    HttpStatus {
        phase: MediaProtocolPhase,
        status: u16,
    },
    InvalidJson(MediaProtocolPhase),
    InvalidResponse {
        phase: MediaProtocolPhase,
        field: MediaResponseField,
    },
    Rejected {
        code: i64,
    },
    Upstream {
        phase: MediaProtocolPhase,
        global_code: i64,
        result_code: Option<i64>,
        data_code: Option<i64>,
    },
    Unavailable {
        result_code: i64,
    },
}

impl<E> fmt::Debug for QqMusicMediaError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidSongMid => formatter.write_str("InvalidSongMid"),
            Self::InvalidFileMediaMid => formatter.write_str("InvalidFileMediaMid"),
            Self::RandomnessUnavailable => formatter.write_str("RandomnessUnavailable"),
            Self::Serialize(phase) => formatter.debug_tuple("Serialize").field(phase).finish(),
            Self::Transport { phase, .. } => formatter
                .debug_struct("Transport")
                .field("phase", phase)
                .field("source", &"[REDACTED]")
                .finish(),
            Self::HttpStatus { phase, status } => formatter
                .debug_struct("HttpStatus")
                .field("phase", phase)
                .field("status", status)
                .finish(),
            Self::InvalidJson(phase) => formatter
                .debug_tuple("InvalidJson")
                .field(phase)
                .field(&"[REDACTED]")
                .finish(),
            Self::InvalidResponse { phase, field } => formatter
                .debug_struct("InvalidResponse")
                .field("phase", phase)
                .field("field", field)
                .finish(),
            Self::Rejected { code } => formatter
                .debug_struct("Rejected")
                .field("code", code)
                .finish(),
            Self::Upstream {
                phase,
                global_code,
                result_code,
                data_code,
            } => formatter
                .debug_struct("Upstream")
                .field("phase", phase)
                .field("global_code", global_code)
                .field("result_code", result_code)
                .field("data_code", data_code)
                .finish(),
            Self::Unavailable { result_code } => formatter
                .debug_struct("Unavailable")
                .field("result_code", result_code)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicMediaError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidSongMid => formatter.write_str("QQ Music song identity is invalid"),
            Self::InvalidFileMediaMid => {
                formatter.write_str("QQ Music file-media identity is invalid")
            }
            Self::RandomnessUnavailable => {
                formatter.write_str("could not create a QQ Music media request identifier")
            }
            Self::Serialize(phase) => write!(formatter, "could not serialize {phase:?} request"),
            Self::Transport { phase, .. } => write!(formatter, "{phase:?} request failed"),
            Self::HttpStatus { phase, status } => {
                write!(formatter, "{phase:?} request returned HTTP {status}")
            }
            Self::InvalidJson(phase) => write!(formatter, "{phase:?} response was not valid JSON"),
            Self::InvalidResponse { phase, field } => {
                write!(formatter, "{phase:?} response has an invalid {field:?}")
            }
            Self::Rejected { code } => {
                write!(
                    formatter,
                    "QQ Music rejected the credential with code {code}"
                )
            }
            Self::Upstream {
                phase,
                global_code,
                result_code,
                data_code,
            } => write!(
                formatter,
                "{phase:?} failed with global code {global_code}, result code {result_code:?}, and data code {data_code:?}"
            ),
            Self::Unavailable { result_code } => write!(
                formatter,
                "QQ Music did not provide a playable source (item code {result_code})"
            ),
        }
    }
}

impl<E> std::error::Error for QqMusicMediaError<E>
where
    E: std::error::Error + 'static,
{
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Transport { source, .. } => Some(source),
            _ => None,
        }
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicCdnDispatch {
    bases: Vec<Url>,
    expiration_seconds: u32,
    refresh_after_seconds: u32,
    cache_for_seconds: u32,
}

impl QqMusicCdnDispatch {
    #[must_use]
    pub fn base_count(&self) -> usize {
        self.bases.len()
    }

    #[must_use]
    pub const fn expiration_seconds(&self) -> u32 {
        self.expiration_seconds
    }

    #[must_use]
    pub const fn refresh_after_seconds(&self) -> u32 {
        self.refresh_after_seconds
    }

    #[must_use]
    pub const fn cache_for_seconds(&self) -> u32 {
        self.cache_for_seconds
    }
}

impl fmt::Debug for QqMusicCdnDispatch {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicCdnDispatch")
            .field("base_count", &self.bases.len())
            .field("expiration_seconds", &self.expiration_seconds)
            .field("refresh_after_seconds", &self.refresh_after_seconds)
            .field("cache_for_seconds", &self.cache_for_seconds)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicAudioQuality {
    Standard,
    High,
}

impl QqMusicAudioQuality {
    const fn prefix(self) -> &'static str {
        match self {
            Self::Standard => "M500",
            Self::High => "M800",
        }
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicMediaSource {
    uri: String,
    quality: QqMusicAudioQuality,
    valid_for_seconds: u32,
}

impl QqMusicMediaSource {
    /// Returns the short-lived authorization URI for immediate playback.
    /// This value must never be logged or persisted past its validity.
    #[must_use]
    pub fn uri(&self) -> &str {
        &self.uri
    }

    #[must_use]
    pub const fn quality(&self) -> QqMusicAudioQuality {
        self.quality
    }

    #[must_use]
    pub const fn valid_for_seconds(&self) -> u32 {
        self.valid_for_seconds
    }
}

impl fmt::Debug for QqMusicMediaSource {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicMediaSource")
            .field("uri", &"[REDACTED]")
            .field("format", &"MP3")
            .field("quality", &self.quality)
            .field("valid_for_seconds", &self.valid_for_seconds)
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Fetches the current QQ Music audio CDN bases and their cache policy.
    ///
    /// # Errors
    ///
    /// Returns a typed, diagnostics-safe error for transport, upstream, or
    /// response-shape failures.
    pub async fn cdn_dispatch(&self) -> Result<QqMusicCdnDispatch, QqMusicMediaError<T::Error>> {
        let phase = MediaProtocolPhase::CdnDispatch;
        let guid = request_guid().map_err(|()| QqMusicMediaError::RandomnessUnavailable)?;
        let body = serde_json::to_vec(&CdnDispatchRequest::new(&guid))
            .map_err(|_| QqMusicMediaError::Serialize(phase))?;
        let response = self
            .transport()
            .execute(musicu_request(body, None))
            .await
            .map_err(|source| QqMusicMediaError::Transport { phase, source })?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicMediaError::HttpStatus {
                phase,
                status: response.status(),
            });
        }
        let envelope: MusicuEnvelope<CdnDispatchData> = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicMediaError::InvalidJson(phase))?;
        let data = extract_data(envelope, phase, false)?;
        let dispatch_code = data.retcode.ok_or(QqMusicMediaError::InvalidResponse {
            phase,
            field: MediaResponseField::DispatchCode,
        })?;
        if dispatch_code != 0 {
            return Err(QqMusicMediaError::Upstream {
                phase,
                global_code: 0,
                result_code: Some(0),
                data_code: Some(dispatch_code),
            });
        }
        let bases = data.sip.ok_or(QqMusicMediaError::InvalidResponse {
            phase,
            field: MediaResponseField::CdnBases,
        })?;
        let bases = parse_cdn_bases(bases).ok_or(QqMusicMediaError::InvalidResponse {
            phase,
            field: MediaResponseField::CdnBases,
        })?;
        let expiration_seconds =
            positive_seconds(data.expiration).ok_or(QqMusicMediaError::InvalidResponse {
                phase,
                field: MediaResponseField::Expiration,
            })?;
        let refresh_after_seconds =
            positive_seconds(data.refresh_time).ok_or(QqMusicMediaError::InvalidResponse {
                phase,
                field: MediaResponseField::RefreshTime,
            })?;
        let cache_for_seconds =
            positive_seconds(data.cache_time).ok_or(QqMusicMediaError::InvalidResponse {
                phase,
                field: MediaResponseField::CacheTime,
            })?;
        Ok(QqMusicCdnDispatch {
            bases,
            expiration_seconds,
            refresh_after_seconds,
            cache_for_seconds,
        })
    }

    /// Resolves one exact MP3 quality using a previously fetched CDN dispatch.
    /// The source URI is short-lived and secret-bearing. Fallback policy stays
    /// outside the protocol client so an unavailable quality is not confused
    /// with transport, credential, or response failures.
    ///
    /// # Errors
    ///
    /// Rejects malformed identities before transport, keeps explicit
    /// credential rejection separate, and preserves unknown per-item outcomes
    /// as [`QqMusicMediaError::Unavailable`].
    pub async fn mp3_source(
        &self,
        credential: &Credential,
        song_mid: &str,
        file_media_mid: Option<&str>,
        quality: QqMusicAudioQuality,
        dispatch: &QqMusicCdnDispatch,
    ) -> Result<QqMusicMediaSource, QqMusicMediaError<T::Error>> {
        let phase = MediaProtocolPhase::Vkey;
        if !is_safe_media_mid(song_mid) {
            return Err(QqMusicMediaError::InvalidSongMid);
        }
        if file_media_mid.is_some_and(|value| !is_safe_media_mid(value)) {
            return Err(QqMusicMediaError::InvalidFileMediaMid);
        }
        let filename = mp3_filename(song_mid, file_media_mid, quality);
        let guid = request_guid().map_err(|()| QqMusicMediaError::RandomnessUnavailable)?;
        let body = serde_json::to_vec(&StandardVkeyRequest::new(
            credential,
            song_mid,
            filename.clone(),
            &guid,
        ))
        .map_err(|_| QqMusicMediaError::Serialize(phase))?;
        let cookie = credential.musicu_cookie_header();
        let response = self
            .transport()
            .execute(musicu_request(body, Some(&cookie)))
            .await
            .map_err(|source| QqMusicMediaError::Transport { phase, source })?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicMediaError::HttpStatus {
                phase,
                status: response.status(),
            });
        }
        let envelope: MusicuEnvelope<StandardVkeyData> = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicMediaError::InvalidJson(phase))?;
        let data = extract_data(envelope, phase, true)?;
        if let Some(code) = data
            .retcode
            .filter(|code| is_credential_rejection_code(*code))
        {
            return Err(QqMusicMediaError::Rejected { code });
        }
        if data.retcode.is_some_and(|code| code != 0) {
            return Err(QqMusicMediaError::Upstream {
                phase,
                global_code: 0,
                result_code: Some(0),
                data_code: data.retcode,
            });
        }
        let expiration_seconds =
            positive_seconds(data.expiration).ok_or(QqMusicMediaError::InvalidResponse {
                phase,
                field: MediaResponseField::Expiration,
            })?;
        let items = data.midurlinfo.ok_or(QqMusicMediaError::InvalidResponse {
            phase,
            field: MediaResponseField::Items,
        })?;
        let [item] = items.as_slice() else {
            return Err(QqMusicMediaError::InvalidResponse {
                phase,
                field: MediaResponseField::Items,
            });
        };
        if item.song_mid.as_deref() != Some(song_mid) {
            return Err(QqMusicMediaError::InvalidResponse {
                phase,
                field: MediaResponseField::ItemSongMid,
            });
        }
        if item.filename.as_deref() != Some(filename.as_str()) {
            return Err(QqMusicMediaError::InvalidResponse {
                phase,
                field: MediaResponseField::ItemFilename,
            });
        }
        let result_code = item.result.ok_or(QqMusicMediaError::InvalidResponse {
            phase,
            field: MediaResponseField::ItemResult,
        })?;
        if result_code != 0 {
            return Err(QqMusicMediaError::Unavailable { result_code });
        }
        let path = item
            .purl
            .as_deref()
            .filter(|value| !value.trim().is_empty())
            .ok_or(QqMusicMediaError::InvalidResponse {
                phase,
                field: MediaResponseField::SourcePath,
            })?;
        let uri = join_source_path(&dispatch.bases, path, &filename).ok_or(
            QqMusicMediaError::InvalidResponse {
                phase,
                field: MediaResponseField::SourcePath,
            },
        )?;
        Ok(QqMusicMediaSource {
            uri,
            quality,
            valid_for_seconds: expiration_seconds.min(dispatch.expiration_seconds),
        })
    }
}

fn musicu_request(body: Vec<u8>, cookie: Option<&str>) -> HttpRequest {
    let request = HttpRequest::post(MUSICU_URL)
        .header("Content-Type", "application/json")
        .header("Origin", "https://y.qq.com")
        .header("Referer", "https://y.qq.com/")
        .body(body)
        .response_body_limit(MAX_MEDIA_RESPONSE_BYTES)
        .timeout(MEDIA_REQUEST_TIMEOUT);
    match cookie {
        Some(cookie) => request.header("Cookie", cookie),
        None => request,
    }
}

fn extract_data<E, D>(
    envelope: MusicuEnvelope<D>,
    phase: MediaProtocolPhase,
    credential_aware: bool,
) -> Result<D, QqMusicMediaError<E>> {
    let global_code = envelope.code.ok_or(QqMusicMediaError::InvalidResponse {
        phase,
        field: MediaResponseField::GlobalCode,
    })?;
    if global_code != 0 {
        if credential_aware && is_credential_rejection_code(global_code) {
            return Err(QqMusicMediaError::Rejected { code: global_code });
        }
        return Err(QqMusicMediaError::Upstream {
            phase,
            global_code,
            result_code: None,
            data_code: None,
        });
    }
    let result = envelope.result.ok_or(QqMusicMediaError::InvalidResponse {
        phase,
        field: MediaResponseField::Result,
    })?;
    let result_code = result.code.ok_or(QqMusicMediaError::InvalidResponse {
        phase,
        field: MediaResponseField::ResultCode,
    })?;
    if result_code != 0 {
        if credential_aware && is_credential_rejection_code(result_code) {
            return Err(QqMusicMediaError::Rejected { code: result_code });
        }
        return Err(QqMusicMediaError::Upstream {
            phase,
            global_code,
            result_code: Some(result_code),
            data_code: None,
        });
    }
    result.data.ok_or(QqMusicMediaError::InvalidResponse {
        phase,
        field: MediaResponseField::Data,
    })
}

pub(crate) fn request_guid() -> Result<String, ()> {
    const HEX: &[u8; 16] = b"0123456789abcdef";

    let mut bytes = [0_u8; 16];
    getrandom::fill(&mut bytes).map_err(|_| ())?;
    let mut guid = String::with_capacity(32);
    for byte in bytes {
        guid.push(char::from(HEX[usize::from(byte >> 4)]));
        guid.push(char::from(HEX[usize::from(byte & 0x0f)]));
    }
    Ok(guid)
}

fn is_safe_media_mid(value: &str) -> bool {
    !value.is_empty() && value.len() <= 64 && value.bytes().all(|byte| byte.is_ascii_alphanumeric())
}

fn mp3_filename(
    song_mid: &str,
    file_media_mid: Option<&str>,
    quality: QqMusicAudioQuality,
) -> String {
    file_media_mid.map_or_else(
        || format!("{}{song_mid}{song_mid}{}", quality.prefix(), MP3_EXTENSION),
        |file_media_mid| format!("{}{file_media_mid}{}", quality.prefix(), MP3_EXTENSION),
    )
}

fn positive_seconds(value: Option<i64>) -> Option<u32> {
    value
        .and_then(|value| u32::try_from(value).ok())
        .filter(|value| *value > 0)
}

fn parse_cdn_bases(raw_bases: Vec<String>) -> Option<Vec<Url>> {
    if raw_bases.is_empty() {
        return None;
    }
    raw_bases
        .into_iter()
        .map(|raw| {
            let base = Url::parse(&raw).ok()?;
            let valid = matches!(base.scheme(), "http" | "https")
                && base.has_host()
                && base.username().is_empty()
                && base.password().is_none()
                && base.query().is_none()
                && base.fragment().is_none()
                && base.path().ends_with('/');
            valid.then_some(base)
        })
        .collect()
}

fn join_source_path(bases: &[Url], path: &str, expected_filename: &str) -> Option<String> {
    if path.trim() != path || path.starts_with('/') || path.starts_with("//") {
        return None;
    }
    let mut bases = bases.iter().collect::<Vec<_>>();
    bases.sort_by_key(|base| cdn_preference(base));
    for base in bases {
        let joined = base.join(path).ok()?;
        let same_authority = joined.scheme() == base.scheme()
            && joined.host_str() == base.host_str()
            && joined.port_or_known_default() == base.port_or_known_default()
            && joined.username().is_empty()
            && joined.password().is_none();
        let expected_file = joined
            .path_segments()
            .and_then(Iterator::last)
            .is_some_and(|filename| filename == expected_filename);
        if same_authority && expected_file {
            return Some(joined.into());
        }
    }
    None
}

fn cdn_preference(base: &Url) -> u8 {
    match base.host_str() {
        Some(PREFERRED_CDN_HOST) => 0,
        Some(host) if !host.starts_with("ws.stream.") && !host.starts_with("isure.stream.") => 1,
        Some(host) if !host.starts_with("ws.stream.") => 2,
        _ => 3,
    }
}

#[derive(Serialize)]
struct CdnDispatchRequest<'a> {
    comm: AnonymousComm,
    #[serde(rename = "req_0")]
    request: CdnDispatchRpc<'a>,
}

impl<'a> CdnDispatchRequest<'a> {
    fn new(guid: &'a str) -> Self {
        Self {
            comm: AnonymousComm::new(),
            request: CdnDispatchRpc {
                module: "music.audioCdnDispatch.cdnDispatch",
                method: "GetCdnDispatch",
                param: CdnDispatchParam {
                    guid,
                    uid: "0",
                    use_new_domain: 1,
                    use_ipv6: 1,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct CdnDispatchRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: CdnDispatchParam<'a>,
}

#[derive(Serialize)]
struct CdnDispatchParam<'a> {
    guid: &'a str,
    uid: &'static str,
    use_new_domain: u8,
    use_ipv6: u8,
}

#[derive(Serialize)]
struct StandardVkeyRequest<'a> {
    comm: AuthenticatedComm<'a>,
    #[serde(rename = "req_0")]
    request: StandardVkeyRpc<'a>,
}

impl<'a> StandardVkeyRequest<'a> {
    fn new(credential: &'a Credential, song_mid: &'a str, filename: String, guid: &'a str) -> Self {
        Self {
            comm: AuthenticatedComm::new(credential),
            request: StandardVkeyRpc {
                module: "music.vkey.GetVkey",
                method: "UrlGetVkey",
                param: StandardVkeyParam {
                    user_id: credential.music_id(),
                    filename: [filename],
                    guid,
                    song_mid: [song_mid],
                    song_type: [0],
                    context: 0,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct StandardVkeyRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: StandardVkeyParam<'a>,
}

#[derive(Serialize)]
struct StandardVkeyParam<'a> {
    #[serde(rename = "uin")]
    user_id: &'a str,
    filename: [String; 1],
    guid: &'a str,
    #[serde(rename = "songmid")]
    song_mid: [&'a str; 1],
    #[serde(rename = "songtype")]
    song_type: [u32; 1],
    #[serde(rename = "ctx")]
    context: u8,
}

#[derive(Serialize)]
struct AnonymousComm {
    cv: u32,
    #[serde(rename = "v")]
    version: u32,
    #[serde(rename = "ct")]
    client_type: &'static str,
    #[serde(rename = "tmeAppID")]
    app_id: &'static str,
    format: &'static str,
    #[serde(rename = "inCharset")]
    input_charset: &'static str,
    #[serde(rename = "outCharset")]
    output_charset: &'static str,
    #[serde(rename = "uid")]
    user_id: &'static str,
    #[serde(rename = "qq")]
    account_id: &'static str,
}

impl AnonymousComm {
    const fn new() -> Self {
        Self {
            cv: 13_020_508,
            version: 13_020_508,
            client_type: "11",
            app_id: "qqmusic",
            format: "json",
            input_charset: "utf-8",
            output_charset: "utf-8",
            user_id: "0",
            account_id: "0",
        }
    }
}

#[derive(Serialize)]
struct AuthenticatedComm<'a> {
    cv: u32,
    #[serde(rename = "v")]
    version: u32,
    #[serde(rename = "ct")]
    client_type: &'static str,
    #[serde(rename = "tmeAppID")]
    app_id: &'static str,
    format: &'static str,
    #[serde(rename = "inCharset")]
    input_charset: &'static str,
    #[serde(rename = "outCharset")]
    output_charset: &'static str,
    #[serde(rename = "uid")]
    user_id: &'a str,
    #[serde(rename = "qq")]
    account_id: &'a str,
    #[serde(rename = "authst")]
    auth_key: &'a str,
    #[serde(rename = "tmeLoginType")]
    login_type: u32,
    #[serde(rename = "loginUin")]
    login_uin: &'a str,
}

impl<'a> AuthenticatedComm<'a> {
    fn new(credential: &'a Credential) -> Self {
        Self {
            cv: 13_020_508,
            version: 13_020_508,
            client_type: "11",
            app_id: "qqmusic",
            format: "json",
            input_charset: "utf-8",
            output_charset: "utf-8",
            user_id: credential.music_id(),
            account_id: credential.music_id(),
            auth_key: credential.music_key(),
            login_type: credential.login_type().value(),
            login_uin: credential.music_id(),
        }
    }
}

#[derive(Deserialize)]
struct MusicuEnvelope<D> {
    code: Option<i64>,
    #[serde(rename = "req_0")]
    result: Option<MusicuResult<D>>,
}

#[derive(Deserialize)]
struct MusicuResult<D> {
    code: Option<i64>,
    data: Option<D>,
}

#[derive(Deserialize)]
struct CdnDispatchData {
    retcode: Option<i64>,
    sip: Option<Vec<String>>,
    expiration: Option<i64>,
    #[serde(rename = "refreshTime")]
    refresh_time: Option<i64>,
    #[serde(rename = "cacheTime")]
    cache_time: Option<i64>,
}

#[derive(Deserialize)]
struct StandardVkeyData {
    retcode: Option<i64>,
    expiration: Option<i64>,
    midurlinfo: Option<Vec<StandardVkeyItem>>,
}

#[derive(Deserialize)]
struct StandardVkeyItem {
    #[serde(rename = "songmid")]
    song_mid: Option<String>,
    filename: Option<String>,
    purl: Option<String>,
    result: Option<i64>,
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use super::{
        MAX_MEDIA_RESPONSE_BYTES, MEDIA_REQUEST_TIMEOUT, MediaProtocolPhase, MediaResponseField,
        QqMusicAudioQuality, QqMusicCdnDispatch, QqMusicMediaError,
    };
    use crate::{Credential, HttpRequest, HttpResponse, HttpTransport, LoginType, QqMusicClient};

    fn credential() -> Credential {
        Credential::new(
            "123456",
            "W_X_private-key",
            LoginType::new(1).expect("login type"),
        )
        .expect("credential")
    }

    fn dispatch_fixture() -> Value {
        json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {
                    "retcode": 0,
                    "sip": [
                        "http://ws.stream.qqmusic.qq.com/",
                        "http://dl.stream.qqmusic.qq.com/"
                    ],
                    "expiration": 86400,
                    "refreshTime": 1800,
                    "cacheTime": 86400
                }
            }
        })
    }

    fn vkey_fixture(path: &str) -> Value {
        json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {
                    "retcode": 0,
                    "expiration": 7200,
                    "midurlinfo": [{
                        "songmid": "fixtureMid1",
                        "filename": "M500fixtureFileMid1.mp3",
                        "purl": path,
                        "vkey": "fixture-secret-vkey",
                        "result": 0
                    }]
                }
            }
        })
    }

    #[tokio::test]
    async fn resolves_standard_mp3_with_bounded_redacted_requests() {
        let transport = FakeTransport::new([
            dispatch_fixture(),
            vkey_fixture("M500fixtureFileMid1.mp3?vkey=fixture-secret-vkey"),
        ]);
        let client = QqMusicClient::new(transport);
        let dispatch = client.cdn_dispatch().await.expect("dispatch");
        let source = client
            .mp3_source(
                &credential(),
                "fixtureMid1",
                Some("fixtureFileMid1"),
                QqMusicAudioQuality::Standard,
                &dispatch,
            )
            .await
            .expect("source");

        assert_eq!(dispatch.base_count(), 2);
        assert_eq!(dispatch.expiration_seconds(), 86_400);
        assert_eq!(dispatch.refresh_after_seconds(), 1_800);
        assert_eq!(dispatch.cache_for_seconds(), 86_400);
        assert_eq!(source.valid_for_seconds(), 7_200);
        assert_eq!(
            source.uri(),
            "http://dl.stream.qqmusic.qq.com/M500fixtureFileMid1.mp3?vkey=fixture-secret-vkey"
        );
        assert!(!format!("{source:?}").contains("fixture-secret"));
        assert!(!format!("{dispatch:?}").contains("qqmusic.qq.com"));

        let requests = client.transport().requests();
        assert_eq!(requests.len(), 2);
        for request in &requests {
            assert_eq!(request.max_response_body_bytes(), MAX_MEDIA_RESPONSE_BYTES);
            assert_eq!(request.request_timeout(), Some(MEDIA_REQUEST_TIMEOUT));
        }
        assert!(
            !requests[0]
                .headers()
                .iter()
                .any(|(name, _)| name == "Cookie")
        );
        assert!(
            requests[1]
                .headers()
                .iter()
                .any(|(name, _)| name == "Cookie")
        );
        let dispatch_body: Value =
            serde_json::from_slice(requests[0].body_bytes().expect("dispatch request body"))
                .expect("dispatch request JSON");
        assert_eq!(
            dispatch_body["req_0"]["module"],
            "music.audioCdnDispatch.cdnDispatch"
        );
        let vkey_body: Value =
            serde_json::from_slice(requests[1].body_bytes().expect("vkey request body"))
                .expect("vkey request JSON");
        assert_eq!(vkey_body["req_0"]["module"], "music.vkey.GetVkey");
        assert_eq!(vkey_body["req_0"]["method"], "UrlGetVkey");
        assert_eq!(
            vkey_body["req_0"]["param"]["filename"],
            json!(["M500fixtureFileMid1.mp3"])
        );
        assert_eq!(vkey_body["req_0"]["param"]["songtype"], json!([0]));
        assert_eq!(
            vkey_body["req_0"]["param"]["guid"].as_str().map(str::len),
            Some(32)
        );
        assert!(!format!("{:?}", requests[1]).contains("private-key"));
    }

    #[tokio::test]
    async fn resolves_high_mp3_and_reports_the_requested_quality() {
        let mut fixture = vkey_fixture("M800fixtureFileMid1.mp3?vkey=fixture-secret-vkey");
        fixture["req_0"]["data"]["midurlinfo"][0]["filename"] = json!("M800fixtureFileMid1.mp3");
        let client = QqMusicClient::new(FakeTransport::new([fixture]));

        let source = client
            .mp3_source(
                &credential(),
                "fixtureMid1",
                Some("fixtureFileMid1"),
                QqMusicAudioQuality::High,
                &valid_dispatch(),
            )
            .await
            .expect("high-quality source");

        assert_eq!(source.quality(), QqMusicAudioQuality::High);
        assert_eq!(
            source.uri(),
            "http://audio.example.test/M800fixtureFileMid1.mp3?vkey=fixture-secret-vkey"
        );
        let request = &client.transport().requests()[0];
        let body: Value =
            serde_json::from_slice(request.body_bytes().expect("high vkey request body"))
                .expect("high vkey request JSON");
        assert_eq!(
            body["req_0"]["param"]["filename"],
            json!(["M800fixtureFileMid1.mp3"])
        );
    }

    #[tokio::test]
    async fn falls_back_to_the_evidenced_double_song_mid_filename() {
        let mut fixture = vkey_fixture("M500fixtureMid1fixtureMid1.mp3?vkey=fixture-secret-vkey");
        fixture["req_0"]["data"]["midurlinfo"][0]["filename"] =
            json!("M500fixtureMid1fixtureMid1.mp3");
        let client = QqMusicClient::new(FakeTransport::new([fixture]));

        let source = client
            .mp3_source(
                &credential(),
                "fixtureMid1",
                None,
                QqMusicAudioQuality::Standard,
                &valid_dispatch(),
            )
            .await
            .expect("fallback source");
        assert_eq!(
            source.uri(),
            "http://audio.example.test/M500fixtureMid1fixtureMid1.mp3?vkey=fixture-secret-vkey"
        );

        let request = &client.transport().requests()[0];
        let body: Value =
            serde_json::from_slice(request.body_bytes().expect("fallback vkey request body"))
                .expect("fallback request JSON");
        assert_eq!(
            body["req_0"]["param"]["filename"],
            json!(["M500fixtureMid1fixtureMid1.mp3"])
        );
        assert_eq!(body["req_0"]["param"]["songtype"], json!([0]));
    }

    #[tokio::test]
    async fn rejects_invalid_identity_and_dispatch_before_media_transport() {
        let client = QqMusicClient::new(FakeTransport::new([json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {
                    "retcode": 0,
                    "sip": [],
                    "expiration": 1,
                    "refreshTime": 1,
                    "cacheTime": 1
                }
            }
        })]));
        assert!(matches!(
            client.cdn_dispatch().await,
            Err(QqMusicMediaError::InvalidResponse {
                phase: MediaProtocolPhase::CdnDispatch,
                field: MediaResponseField::CdnBases,
            })
        ));
        assert_eq!(client.transport().requests().len(), 1);

        let dispatch = valid_dispatch();
        assert!(matches!(
            client
                .mp3_source(
                    &credential(),
                    "unsafe/mid",
                    Some("fixtureFileMid1"),
                    QqMusicAudioQuality::Standard,
                    &dispatch,
                )
                .await,
            Err(QqMusicMediaError::InvalidSongMid)
        ));
        assert!(matches!(
            client
                .mp3_source(
                    &credential(),
                    "fixtureMid1",
                    Some("unsafe/file"),
                    QqMusicAudioQuality::Standard,
                    &dispatch,
                )
                .await,
            Err(QqMusicMediaError::InvalidFileMediaMid)
        ));
        assert_eq!(client.transport().requests().len(), 1);
    }

    #[tokio::test]
    async fn preserves_unknown_item_result_as_unavailable() {
        let client = QqMusicClient::new(FakeTransport::new([json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {
                    "retcode": 0,
                    "expiration": 7200,
                    "midurlinfo": [{
                        "songmid": "fixtureMid1",
                        "filename": "M500fixtureFileMid1.mp3",
                        "purl": "",
                        "vkey": "",
                        "result": 101_404
                    }]
                }
            }
        })]));
        assert!(matches!(
            client
                .mp3_source(
                    &credential(),
                    "fixtureMid1",
                    Some("fixtureFileMid1"),
                    QqMusicAudioQuality::Standard,
                    &valid_dispatch(),
                )
                .await,
            Err(QqMusicMediaError::Unavailable {
                result_code: 101_404
            })
        ));
    }

    #[tokio::test]
    async fn keeps_rejection_distinct_from_unrelated_upstream_failure() {
        for (code, rejected) in [(1000, true), (50_006, false)] {
            let client = QqMusicClient::new(FakeTransport::new([json!({
                "code": 0,
                "req_0": { "code": code }
            })]));
            let result = client
                .mp3_source(
                    &credential(),
                    "fixtureMid1",
                    Some("fixtureFileMid1"),
                    QqMusicAudioQuality::Standard,
                    &valid_dispatch(),
                )
                .await;
            assert_eq!(
                matches!(result, Err(QqMusicMediaError::Rejected { .. })),
                rejected
            );
            if !rejected {
                assert!(matches!(
                    result,
                    Err(QqMusicMediaError::Upstream {
                        phase: MediaProtocolPhase::Vkey,
                        result_code: Some(50_006),
                        ..
                    })
                ));
            }
        }

        let nested_rejection = QqMusicClient::new(FakeTransport::new([json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": { "retcode": 104_400 }
            }
        })]));
        assert!(matches!(
            nested_rejection
                .mp3_source(
                    &credential(),
                    "fixtureMid1",
                    Some("fixtureFileMid1"),
                    QqMusicAudioQuality::Standard,
                    &valid_dispatch(),
                )
                .await,
            Err(QqMusicMediaError::Rejected { code: 104_400 })
        ));
    }

    #[tokio::test]
    async fn rejects_absolute_source_and_mismatched_item_identity() {
        let absolute = QqMusicClient::new(FakeTransport::new([vkey_fixture(
            "https://untrusted.example/fixture.mp3?vkey=secret",
        )]));
        assert!(matches!(
            absolute
                .mp3_source(
                    &credential(),
                    "fixtureMid1",
                    Some("fixtureFileMid1"),
                    QqMusicAudioQuality::Standard,
                    &valid_dispatch(),
                )
                .await,
            Err(QqMusicMediaError::InvalidResponse {
                phase: MediaProtocolPhase::Vkey,
                field: MediaResponseField::SourcePath,
            })
        ));

        let mut mismatched = vkey_fixture("fixture.mp3?vkey=secret");
        mismatched["req_0"]["data"]["midurlinfo"][0]["songmid"] = json!("otherMid");
        let mismatched = QqMusicClient::new(FakeTransport::new([mismatched]));
        assert!(matches!(
            mismatched
                .mp3_source(
                    &credential(),
                    "fixtureMid1",
                    Some("fixtureFileMid1"),
                    QqMusicAudioQuality::Standard,
                    &valid_dispatch(),
                )
                .await,
            Err(QqMusicMediaError::InvalidResponse {
                phase: MediaProtocolPhase::Vkey,
                field: MediaResponseField::ItemSongMid,
            })
        ));

        let mut wrong_file = vkey_fixture("fixture.mp3?vkey=secret");
        wrong_file["req_0"]["data"]["midurlinfo"][0]["filename"] = json!("C400other.m4a");
        let wrong_file = QqMusicClient::new(FakeTransport::new([wrong_file]));
        assert!(matches!(
            wrong_file
                .mp3_source(
                    &credential(),
                    "fixtureMid1",
                    Some("fixtureFileMid1"),
                    QqMusicAudioQuality::Standard,
                    &valid_dispatch(),
                )
                .await,
            Err(QqMusicMediaError::InvalidResponse {
                phase: MediaProtocolPhase::Vkey,
                field: MediaResponseField::ItemFilename,
            })
        ));
    }

    fn valid_dispatch() -> QqMusicCdnDispatch {
        QqMusicCdnDispatch {
            bases: vec!["http://audio.example.test/".parse().expect("CDN base")],
            expiration_seconds: 86_400,
            refresh_after_seconds: 1_800,
            cache_for_seconds: 86_400,
        }
    }

    #[derive(Default)]
    struct FakeTransport {
        responses: Mutex<VecDeque<HttpResponse>>,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl FakeTransport {
        fn new<const N: usize>(responses: [Value; N]) -> Self {
            Self {
                responses: Mutex::new(
                    responses
                        .into_iter()
                        .map(|value| {
                            HttpResponse::new(
                                200,
                                serde_json::to_vec(&value).expect("fixture JSON"),
                            )
                        })
                        .collect(),
                ),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn requests(&self) -> Vec<HttpRequest> {
            self.requests.lock().expect("requests lock").clone()
        }
    }

    impl HttpTransport for FakeTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("requests lock").push(request);
            Ok(self
                .responses
                .lock()
                .expect("responses lock")
                .pop_front()
                .expect("queued response"))
        }
    }
}
