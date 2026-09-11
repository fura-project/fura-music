use std::fmt;
use std::time::Duration;

use base64::Engine;
use serde::{Deserialize, Serialize};
use sha1::{Digest, Sha1};

use crate::credential::is_credential_rejection_code;
use crate::playlist_detail::{RawTrack, nonblank, safe_media_mid};
use crate::protocol_strategy::is_musicu_rate_limited_code;
use crate::{
    Credential, HttpRequest, HttpTransport, QqMusicAlbumSummary, QqMusicArtistSummary,
    QqMusicClient,
};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
// Local resource ceilings, not claims about QQ's retention or server page size.
const MAX_RECENT_PLAYS_RESPONSE_BYTES: usize = 8 * 1024 * 1024;
const MAX_RECENT_RECORDS: usize = 5_000;
const RECENT_PLAYS_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_PAGE_SIZE: u32 = 100;

pub enum QqMusicRecentPlaysError<E> {
    InvalidPageSize {
        size: u32,
    },
    Transport(E),
    Serialize,
    Signing,
    HttpStatus(u16),
    InvalidJson,
    MissingGlobalCode,
    MissingResult,
    MissingResultCode,
    Rejected {
        code: i64,
    },
    RateLimited {
        code: i64,
    },
    Upstream {
        global_code: i64,
        result_code: Option<i64>,
    },
    MissingData,
    MissingRecords,
    MissingDataCode,
    DataFailure {
        code: i64,
    },
    UnexpectedHistoryType,
    ResponseTooLarge,
    InvalidPagination,
}

impl<E> fmt::Debug for QqMusicRecentPlaysError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidPageSize { size } => formatter
                .debug_struct("InvalidPageSize")
                .field("size", size)
                .finish(),
            Self::Transport(_) => formatter.write_str("Transport([REDACTED])"),
            Self::Serialize => formatter.write_str("Serialize"),
            Self::Signing => formatter.write_str("Signing"),
            Self::HttpStatus(status) => formatter.debug_tuple("HttpStatus").field(status).finish(),
            Self::InvalidJson => formatter.write_str("InvalidJson([REDACTED])"),
            Self::MissingGlobalCode => formatter.write_str("MissingGlobalCode"),
            Self::MissingResult => formatter.write_str("MissingResult"),
            Self::MissingResultCode => formatter.write_str("MissingResultCode"),
            Self::Rejected { code } => formatter.debug_tuple("Rejected").field(code).finish(),
            Self::RateLimited { code } => formatter.debug_tuple("RateLimited").field(code).finish(),
            Self::Upstream {
                global_code,
                result_code,
            } => formatter
                .debug_struct("Upstream")
                .field("global_code", global_code)
                .field("result_code", result_code)
                .finish(),
            Self::MissingData => formatter.write_str("MissingData"),
            Self::MissingRecords => formatter.write_str("MissingRecords"),
            Self::MissingDataCode => formatter.write_str("MissingDataCode"),
            Self::DataFailure { code } => formatter
                .debug_struct("DataFailure")
                .field("code", code)
                .finish(),
            Self::UnexpectedHistoryType => formatter.write_str("UnexpectedHistoryType"),
            Self::ResponseTooLarge => formatter.write_str("ResponseTooLarge"),
            Self::InvalidPagination => formatter.write_str("InvalidPagination"),
        }
    }
}

impl<E> fmt::Display for QqMusicRecentPlaysError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidPageSize { size } => {
                write!(
                    formatter,
                    "recent-play page size {size} is outside 1..={MAX_PAGE_SIZE}"
                )
            }
            Self::Transport(_) => formatter.write_str("QQ Music recent-play request failed"),
            Self::Serialize => formatter.write_str("could not serialize recent-play request"),
            Self::Signing => formatter.write_str("could not sign recent-play request"),
            Self::HttpStatus(status) => {
                write!(formatter, "recent-play request returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("recent-play response was not valid JSON"),
            Self::MissingGlobalCode => {
                formatter.write_str("recent-play response has no global code")
            }
            Self::MissingResult => formatter.write_str("recent-play result is missing"),
            Self::MissingResultCode => formatter.write_str("recent-play result has no code"),
            Self::Rejected { code } => write!(
                formatter,
                "QQ Music rejected the credential with code {code}"
            ),
            Self::RateLimited { code } => write!(
                formatter,
                "QQ Music rate limited the request with code {code}"
            ),
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "recent-play request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("recent-play data is missing"),
            Self::MissingRecords => formatter.write_str("recent-play record array is missing"),
            Self::MissingDataCode => formatter.write_str("recent-play data has no result code"),
            Self::DataFailure { code } => {
                write!(formatter, "recent-play data failed with code {code}")
            }
            Self::UnexpectedHistoryType => {
                formatter.write_str("recent-play data is not song history")
            }
            Self::ResponseTooLarge => {
                formatter.write_str("recent-play snapshot exceeds local bounds")
            }
            Self::InvalidPagination => {
                formatter.write_str("recent-play pagination did not advance safely")
            }
        }
    }
}

impl<E> std::error::Error for QqMusicRecentPlaysError<E>
where
    E: std::error::Error + 'static,
{
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Transport(error) => Some(error),
            _ => None,
        }
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicRecentPlay {
    track: QqMusicRecentTrackSummary,
    /// Opaque source value. Public evidence does not establish its unit or
    /// whether it represents an absolute time, duration, or ordering token.
    source_play_time: Option<u64>,
}

impl QqMusicRecentPlay {
    #[must_use]
    pub const fn track(&self) -> &QqMusicRecentTrackSummary {
        &self.track
    }

    #[must_use]
    pub const fn source_play_time(&self) -> Option<u64> {
        self.source_play_time
    }
}

/// Track data returned by the account recent-play endpoint.
///
/// Unlike playlist-detail rows, public evidence only guarantees `mid`, title,
/// artist, album and duration. Numeric song identity and song type therefore
/// remain optional instead of being fabricated when the endpoint omits them.
#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicRecentTrackSummary {
    track_id: Option<u64>,
    song_mid: String,
    file_media_mid: Option<String>,
    title: String,
    subtitle: Option<String>,
    song_type: Option<u32>,
    duration_seconds: u32,
    artists: Vec<QqMusicArtistSummary>,
    album: Option<QqMusicAlbumSummary>,
}

impl QqMusicRecentTrackSummary {
    #[must_use]
    pub const fn track_id(&self) -> Option<u64> {
        self.track_id
    }

    #[must_use]
    pub fn song_mid(&self) -> &str {
        &self.song_mid
    }

    #[must_use]
    pub fn file_media_mid(&self) -> Option<&str> {
        self.file_media_mid.as_deref()
    }

    #[must_use]
    pub fn title(&self) -> &str {
        &self.title
    }

    #[must_use]
    pub fn subtitle(&self) -> Option<&str> {
        self.subtitle.as_deref()
    }

    #[must_use]
    pub const fn song_type(&self) -> Option<u32> {
        self.song_type
    }

    #[must_use]
    pub const fn duration_seconds(&self) -> u32 {
        self.duration_seconds
    }

    #[must_use]
    pub fn artists(&self) -> &[QqMusicArtistSummary] {
        &self.artists
    }

    #[must_use]
    pub const fn album(&self) -> Option<&QqMusicAlbumSummary> {
        self.album.as_ref()
    }
}

impl fmt::Debug for QqMusicRecentTrackSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRecentTrackSummary")
            .field("has_track_id", &self.track_id.is_some())
            .field("has_song_mid", &true)
            .field("has_file_media_mid", &self.file_media_mid.is_some())
            .field("has_song_type", &self.song_type.is_some())
            .field("artist_count", &self.artists.len())
            .field("has_album", &self.album.is_some())
            .finish_non_exhaustive()
    }
}

impl fmt::Debug for QqMusicRecentPlay {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRecentPlay")
            .field("track", &self.track)
            .field("has_source_play_time", &self.source_play_time.is_some())
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicRecentPlaysPage {
    offset: u32,
    next_offset: u32,
    total: u32,
    total_is_exact: bool,
    has_more: bool,
    omitted_track_count: u32,
    records: Vec<QqMusicRecentPlay>,
}

impl QqMusicRecentPlaysPage {
    #[must_use]
    pub const fn offset(&self) -> u32 {
        self.offset
    }
    #[must_use]
    pub const fn next_offset(&self) -> u32 {
        self.next_offset
    }
    #[must_use]
    pub const fn total(&self) -> u32 {
        self.total
    }
    #[must_use]
    pub const fn total_is_exact(&self) -> bool {
        self.total_is_exact
    }
    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }
    #[must_use]
    pub const fn omitted_track_count(&self) -> u32 {
        self.omitted_track_count
    }
    #[must_use]
    pub fn records(&self) -> &[QqMusicRecentPlay] {
        &self.records
    }
}

impl fmt::Debug for QqMusicRecentPlaysPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRecentPlaysPage")
            .field("offset", &self.offset)
            .field("next_offset", &self.next_offset)
            .field("total", &self.total)
            .field("total_is_exact", &self.total_is_exact)
            .field("has_more", &self.has_more)
            .field("omitted_track_count", &self.omitted_track_count)
            .field("record_count", &self.records.len())
            .finish()
    }
}

/// One bounded full song-history snapshot. The provider retains it only within
/// the authenticated session and serves UI pages without repeated full reads.
#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicRecentPlaysSnapshot {
    // Keep omitted positions so page progress and omission counts remain exact.
    records: Vec<Option<QqMusicRecentPlay>>,
}

impl fmt::Debug for QqMusicRecentPlaysSnapshot {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRecentPlaysSnapshot")
            .field("record_count", &self.records.len())
            .finish()
    }
}

impl QqMusicRecentPlaysSnapshot {
    /// Returns a local page from this immutable snapshot.
    ///
    /// # Errors
    /// Rejects an invalid page size or an offset beyond the snapshot.
    pub fn page(
        &self,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicRecentPlaysPage, QqMusicRecentPlaysError<std::convert::Infallible>> {
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicRecentPlaysError::InvalidPageSize { size });
        }
        let total = u32::try_from(self.records.len())
            .map_err(|_| QqMusicRecentPlaysError::InvalidPagination)?;
        if offset > total {
            return Err(QqMusicRecentPlaysError::InvalidPagination);
        }
        let next_offset = offset.saturating_add(size).min(total);
        let window = &self.records[offset as usize..next_offset as usize];
        let records: Vec<_> = window.iter().flatten().cloned().collect();
        let omitted_track_count = next_offset
            - offset
            - u32::try_from(records.len())
                .map_err(|_| QqMusicRecentPlaysError::InvalidPagination)?;
        Ok(QqMusicRecentPlaysPage {
            offset,
            next_offset,
            total,
            total_is_exact: true,
            has_more: next_offset < total,
            omitted_track_count,
            records,
        })
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Reads one full cloud song-history snapshot using the official Windows
    /// `PlayRecentlyRead.GetPlayRecentlyInfo` request: type=2, updateTime=0.
    /// This endpoint has no evidenced begin/num pagination. No delta merge or
    /// automatic retry is performed. Bytes and record count have local ceilings.
    ///
    /// # Errors
    /// Returns a typed protocol error for transport, bounds, rejection, service
    /// and response-shape failures. Diagnostics are explicitly opt-in and redacted.
    pub async fn recent_plays_snapshot(
        &self,
        credential: &Credential,
    ) -> Result<QqMusicRecentPlaysSnapshot, QqMusicRecentPlaysError<T::Error>> {
        let diagnostics =
            std::env::var("FURA_QQMUSIC_RECENT_PLAYS_DIAGNOSTICS").is_ok_and(|value| value == "1");
        if diagnostics {
            eprintln!(
                "{}",
                recent_plays_diagnostic(credential.login_type(), "request")
            );
        }
        let result = self.request_recent_plays_snapshot(credential).await;
        if diagnostics {
            let outcome = match &result {
                Ok(_) => "success".to_owned(),
                Err(error) => format!("{error:?}"),
            };
            eprintln!(
                "{}",
                recent_plays_diagnostic(credential.login_type(), &outcome)
            );
        }
        result
    }

    async fn request_recent_plays_snapshot(
        &self,
        credential: &Credential,
    ) -> Result<QqMusicRecentPlaysSnapshot, QqMusicRecentPlaysError<T::Error>> {
        let body = serde_json::to_vec(&RecentPlaysRequest::new(credential))
            .map_err(|_| QqMusicRecentPlaysError::Serialize)?;
        let sign =
            recent_plays_request_sign(&body).map_err(|()| QqMusicRecentPlaysError::Signing)?;
        let request = HttpRequest::post(MUSICU_URL)
            .query("sign", sign)
            .header("Content-Type", "application/json")
            .header("Origin", "https://y.qq.com")
            .header("Referer", "https://y.qq.com/")
            .header("Cookie", credential.musicu_cookie_header())
            .body(body)
            .response_body_limit(MAX_RECENT_PLAYS_RESPONSE_BYTES)
            .timeout(RECENT_PLAYS_TIMEOUT);
        let response = self
            .transport()
            .execute(request)
            .await
            .map_err(QqMusicRecentPlaysError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicRecentPlaysError::HttpStatus(response.status()));
        }
        if response.body().len() > MAX_RECENT_PLAYS_RESPONSE_BYTES {
            return Err(QqMusicRecentPlaysError::ResponseTooLarge);
        }
        let envelope: RecentPlaysResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicRecentPlaysError::InvalidJson)?;
        map_response(envelope)
    }
}

fn recent_plays_diagnostic(login: crate::LoginType, outcome: &str) -> String {
    let channel = match login {
        crate::LoginType::WECHAT => "wechat",
        crate::LoginType::QQ => "qq",
        _ => "other",
    };
    format!(
        "[qqmusic.recent_plays] route=PlayRecentlyRead channel={channel} type=2 updateTime=0 outcome={outcome}"
    )
}

#[derive(Serialize)]
struct RecentPlaysRequest<'a> {
    comm: RecentPlaysComm<'a>,
    req_0: RecentPlaysRpc,
}

impl<'a> RecentPlaysRequest<'a> {
    fn new(credential: &'a Credential) -> Self {
        let csrf_token = credential_music_key_hash(credential.music_key());
        Self {
            comm: RecentPlaysComm {
                cv: 4_747_474,
                client_type: 11,
                format: "json",
                input_charset: "utf-8",
                output_charset: "utf-8",
                notice: 0,
                platform: "yqq.json",
                need_new_code: 0,
                user_id: credential.music_id(),
                account_id: credential.music_id(),
                auth_key: credential.music_key(),
                login_type: credential.login_type().value(),
                app_id: "qqmusic",
                csrf_token,
                legacy_csrf_token: csrf_token,
            },
            req_0: RecentPlaysRpc {
                module: "music.musicasset.PlayRecentlyRead",
                method: "GetPlayRecentlyInfo",
                param: RecentPlaysParam {
                    history_type: 2,
                    update_time: 0,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct RecentPlaysComm<'a> {
    cv: u32,
    #[serde(rename = "ct")]
    client_type: u32,
    format: &'static str,
    #[serde(rename = "inCharset")]
    input_charset: &'static str,
    #[serde(rename = "outCharset")]
    output_charset: &'static str,
    notice: u32,
    platform: &'static str,
    #[serde(rename = "needNewCode")]
    need_new_code: u32,
    #[serde(rename = "uin")]
    user_id: &'a str,
    #[serde(rename = "qq")]
    account_id: &'a str,
    #[serde(rename = "authst")]
    auth_key: &'a str,
    #[serde(rename = "tmeLoginType")]
    login_type: u32,
    #[serde(rename = "tmeAppID")]
    app_id: &'static str,
    #[serde(rename = "g_tk_new_20200303")]
    csrf_token: u32,
    #[serde(rename = "g_tk")]
    legacy_csrf_token: u32,
}

#[derive(Serialize)]
struct RecentPlaysRpc {
    module: &'static str,
    method: &'static str,
    param: RecentPlaysParam,
}

#[derive(Serialize)]
struct RecentPlaysParam {
    #[serde(rename = "type")]
    history_type: u32,
    #[serde(rename = "updateTime")]
    update_time: u32,
}

fn credential_music_key_hash(key: &str) -> u32 {
    key.bytes().fold(5_381_u32, |hash, byte| {
        hash.wrapping_add(hash.wrapping_shl(5))
            .wrapping_add(u32::from(byte))
    }) & 0x7fff_ffff
}

fn recent_plays_request_sign(body: &[u8]) -> Result<String, ()> {
    const FIRST_HEX_INDICES: [usize; 7] = [23, 14, 6, 36, 16, 7, 19];
    const SECOND_HEX_INDICES: [usize; 8] = [16, 1, 32, 12, 19, 27, 8, 5];
    const XOR_MASK: [u8; 20] = [
        89, 39, 179, 150, 218, 82, 58, 252, 177, 52, 186, 123, 120, 64, 242, 133, 143, 161, 121,
        179,
    ];

    let digest = Sha1::digest(body);
    let mut uppercase_hex = String::with_capacity(40);
    for byte in &digest {
        use std::fmt::Write;
        write!(&mut uppercase_hex, "{byte:02X}").map_err(|_| ())?;
    }
    let hex = uppercase_hex.as_bytes();
    let first = FIRST_HEX_INDICES
        .into_iter()
        .map(|index| char::from(hex[index]))
        .collect::<String>();
    let second = SECOND_HEX_INDICES
        .into_iter()
        .map(|index| char::from(hex[index]))
        .collect::<String>();
    let encoded = base64::engine::general_purpose::STANDARD.encode(
        digest
            .iter()
            .zip(XOR_MASK)
            .map(|(byte, mask)| *byte ^ mask)
            .collect::<Vec<_>>(),
    );
    let filtered = encoded
        .chars()
        .filter(|character| !matches!(character, '/' | '+' | '='))
        .collect::<String>();
    Ok(format!("zzc{first}{filtered}{second}").to_ascii_lowercase())
}

#[derive(Deserialize)]
struct RecentPlaysResponse {
    code: Option<i64>,
    req_0: Option<RecentPlaysResult>,
}

#[derive(Deserialize)]
struct RecentPlaysResult {
    code: Option<i64>,
    data: Option<RecentPlaysData>,
}

#[derive(Deserialize)]
struct RecentPlaysData {
    code: Option<i64>,
    #[serde(rename = "type")]
    history_type: Option<u32>,
    data: Option<RecentPlaysPayload>,
}

#[derive(Deserialize)]
struct RecentPlaysPayload {
    #[serde(rename = "songList")]
    records: Option<Vec<RawRecentPlay>>,
}

#[derive(Deserialize)]
struct RawRecentPlay {
    #[serde(rename = "lastTime")]
    source_play_time: Option<u64>,
    track: Option<RawTrack>,
}

fn map_response<E>(
    envelope: RecentPlaysResponse,
) -> Result<QqMusicRecentPlaysSnapshot, QqMusicRecentPlaysError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicRecentPlaysError::MissingGlobalCode)?;
    let result_code = envelope.req_0.as_ref().and_then(|result| result.code);
    for code in [global_code, result_code.unwrap_or(0)] {
        if is_musicu_rate_limited_code(code) {
            return Err(QqMusicRecentPlaysError::RateLimited { code });
        }
        if is_credential_rejection_code(code) {
            return Err(QqMusicRecentPlaysError::Rejected { code });
        }
    }
    if global_code != 0 {
        return Err(QqMusicRecentPlaysError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .req_0
        .ok_or(QqMusicRecentPlaysError::MissingResult)?;
    let result_code = result
        .code
        .ok_or(QqMusicRecentPlaysError::MissingResultCode)?;
    if result_code != 0 {
        return Err(QqMusicRecentPlaysError::Upstream {
            global_code,
            result_code: Some(result_code),
        });
    }
    let data = result.data.ok_or(QqMusicRecentPlaysError::MissingData)?;
    let code = data.code.ok_or(QqMusicRecentPlaysError::MissingDataCode)?;
    if is_musicu_rate_limited_code(code) {
        return Err(QqMusicRecentPlaysError::RateLimited { code });
    }
    if is_credential_rejection_code(code) {
        return Err(QqMusicRecentPlaysError::Rejected { code });
    }
    // The official Windows reader admits these exact data status values before
    // checking the typed song-list payload. Do not infer permission semantics or
    // treat a missing payload as an empty snapshot for any status.
    if !matches!(code, 0 | -300 | -301) {
        return Err(QqMusicRecentPlaysError::DataFailure { code });
    }
    if data.history_type != Some(2) {
        return Err(QqMusicRecentPlaysError::UnexpectedHistoryType);
    }
    let raw_records = data
        .data
        .ok_or(QqMusicRecentPlaysError::MissingData)?
        .records
        .ok_or(QqMusicRecentPlaysError::MissingRecords)?;
    if raw_records.len() > MAX_RECENT_RECORDS {
        return Err(QqMusicRecentPlaysError::ResponseTooLarge);
    }
    let records = raw_records
        .into_iter()
        .enumerate()
        .map(|(index, raw)| {
            Some(QqMusicRecentPlay {
                track: map_recent_track(raw.track?, index).ok()?,
                source_play_time: raw.source_play_time,
            })
        })
        .collect();
    Ok(QqMusicRecentPlaysSnapshot { records })
}

fn map_recent_track(raw: RawTrack, index: usize) -> Result<QqMusicRecentTrackSummary, usize> {
    let song_mid = safe_media_mid(raw.mid).ok_or(index)?;
    let raw_file_media_mid = raw.file.and_then(|file| file.media_mid);
    let file_media_mid = match raw_file_media_mid {
        Some(value) if value.trim().is_empty() => None,
        Some(value) => Some(safe_media_mid(Some(value)).ok_or(index)?),
        None => None,
    };
    let title = nonblank(raw.title)
        .or_else(|| nonblank(raw.name))
        .ok_or(index)?;
    let raw_artists = raw.singer.ok_or(index)?;
    let artists = raw_artists
        .into_iter()
        .map(|artist| {
            Some(QqMusicArtistSummary::new(
                artist.id.filter(|value| *value != 0),
                nonblank(artist.mid),
                nonblank(artist.name)?,
            ))
        })
        .collect::<Option<Vec<_>>>()
        .ok_or(index)?;
    let album = raw.album.map(|album| {
        QqMusicAlbumSummary::new(
            album.id.filter(|value| *value != 0),
            nonblank(album.mid).or_else(|| nonblank(album.pmid)),
            nonblank(album.title).or_else(|| nonblank(album.name)),
        )
    });
    Ok(QqMusicRecentTrackSummary {
        track_id: raw.id.filter(|value| *value != 0),
        song_mid,
        file_media_mid,
        title,
        subtitle: nonblank(raw.subtitle),
        song_type: raw.song_type,
        duration_seconds: raw.interval.unwrap_or(0),
        artists,
        album,
    })
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::{Arc, Mutex};

    use serde_json::Value;

    use crate::{Credential, HttpRequest, HttpResponse, HttpTransport, LoginType, QqMusicClient};

    use super::QqMusicRecentPlaysError;

    #[derive(Clone)]
    struct RecordingTransport {
        requests: Arc<Mutex<Vec<HttpRequest>>>,
        response: HttpResponse,
    }

    impl HttpTransport for RecordingTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("requests").push(request);
            Ok(self.response.clone())
        }
    }

    fn credential() -> Credential {
        Credential::new("123456", "secret-key", LoginType::QQ).expect("credential")
    }

    fn client(
        body: &str,
    ) -> (
        QqMusicClient<RecordingTransport>,
        Arc<Mutex<Vec<HttpRequest>>>,
    ) {
        let requests = Arc::new(Mutex::new(Vec::new()));
        let transport = RecordingTransport {
            requests: Arc::clone(&requests),
            response: HttpResponse::new(200, body.as_bytes().to_vec()),
        };
        (QqMusicClient::new(transport), requests)
    }

    fn track(id: u64, mid: &str) -> Value {
        serde_json::json!({
            "lastTime": 1_700_000_000_u64, "listenCnt": 1,
            "track": {"id":id, "mid":mid, "name":"Fixture", "type":0, "interval":123,
                "singer":[{"id":9,"mid":"singerMid","name":"Singer"}],
                "album":{"id":7,"mid":"albumMid","name":"Album"},
                "file":{"media_mid":mid}}
        })
    }

    fn response(records: Vec<Value>) -> String {
        let records = Value::Array(records);
        serde_json::json!({"code":0,"req_0":{"code":0,"data":{
            "code":0,"type":2,"updateTime":1_700_000_000_u64,
            "data":{"songList":records}
        }}})
        .to_string()
    }

    #[tokio::test]
    async fn official_snapshot_request_and_typed_track_mapping() {
        let (client, requests) = client(&response(vec![track(41, "songMid01")]));
        let snapshot = client
            .recent_plays_snapshot(&credential())
            .await
            .expect("snapshot");
        let page = snapshot.page(0, 100).expect("page");
        assert_eq!((page.offset(), page.next_offset(), page.total()), (0, 1, 1));
        assert!(page.total_is_exact());
        assert!(!page.has_more());
        assert_eq!(page.records()[0].track().song_mid(), "songMid01");
        assert_eq!(page.records()[0].track().track_id(), Some(41));
        assert_eq!(page.records()[0].source_play_time(), Some(1_700_000_000));
        let requests = requests.lock().expect("requests");
        assert_eq!(requests.len(), 1);
        let request = &requests[0];
        assert_eq!(request.url(), "https://u.y.qq.com/cgi-bin/musicu.fcg");
        // Independently calculated with Python hashlib/Base64 from this exact DTO.
        assert_eq!(
            request.query_pairs(),
            [(
                "sign".to_owned(),
                "zzcd47079fj60471zz573ke0vg8xb5ggoqc24768df08b".to_owned()
            )]
        );
        let body: Value =
            serde_json::from_slice(request.body_bytes().expect("body")).expect("JSON");
        assert_eq!(body["comm"]["uin"], "123456");
        assert_eq!(body["comm"]["g_tk"], 340_831_009);
        assert_eq!(body["comm"]["g_tk_new_20200303"], 340_831_009);
        assert_eq!(body["req_0"]["module"], "music.musicasset.PlayRecentlyRead");
        assert_eq!(body["req_0"]["method"], "GetPlayRecentlyInfo");
        assert_eq!(
            body["req_0"]["param"],
            serde_json::json!({"type":2,"updateTime":0})
        );
        assert!(!format!("{request:?}").contains("secret-key"));
        for private in ["songMid01", "Fixture", "1700000000"] {
            assert!(!format!("{snapshot:?}").contains(private));
        }
    }

    #[tokio::test]
    async fn both_channels_keep_their_own_cookie_and_login_identity() {
        for login in [LoginType::QQ, LoginType::WECHAT] {
            let (client, requests) = client(&response(vec![]));
            let credential =
                Credential::new("987654321", "synthetic-key", login).expect("credential");
            let snapshot = client
                .recent_plays_snapshot(&credential)
                .await
                .expect("valid empty");
            let page = snapshot.page(0, 100).expect("empty page");
            assert_eq!(page.total(), 0);
            assert!(!page.has_more());
            let requests = requests.lock().expect("requests");
            assert_eq!(requests.len(), 1);
            let body: Value =
                serde_json::from_slice(requests[0].body_bytes().expect("body")).expect("JSON");
            assert_eq!(body["comm"]["tmeLoginType"], login.value());
            assert_eq!(body["comm"]["uin"], "987654321");
            assert_eq!(body["comm"]["qq"], "987654321");
            let cookie = &requests[0]
                .headers()
                .iter()
                .find(|(name, _)| name == "Cookie")
                .expect("cookie")
                .1;
            assert!(cookie.contains("qqmusic_key=synthetic-key"));
            assert!(cookie.contains(&format!("tmeLoginType={};", login.value())));
            assert_eq!(
                cookie.contains("wxuin=987654321;"),
                login == LoginType::WECHAT
            );
        }
    }

    #[tokio::test]
    async fn snapshot_pages_are_exact_bounded_and_do_not_refetch() {
        let records = (0..205)
            .map(|i| track(i + 1, &format!("mid{i:03}")))
            .collect();
        let (client, requests) = client(&response(records));
        let snapshot = client
            .recent_plays_snapshot(&credential())
            .await
            .expect("snapshot");
        for (offset, next, count, more) in [
            (0, 100, 100, true),
            (100, 200, 100, true),
            (200, 205, 5, false),
        ] {
            let page = snapshot.page(offset, 100).expect("page");
            assert_eq!(page.next_offset(), next);
            assert_eq!(page.total(), 205);
            assert_eq!(page.records().len(), count);
            assert_eq!(page.has_more(), more);
            assert_eq!(
                page.records()[0].track().song_mid(),
                format!("mid{offset:03}")
            );
        }
        assert!(snapshot.page(205, 100).expect("end").records().is_empty());
        for (offset, size) in [(206, 100), (u32::MAX, 100), (0, 0), (0, 101)] {
            assert!(snapshot.page(offset, size).is_err());
        }
        assert_eq!(requests.lock().expect("requests").len(), 1);
    }

    #[tokio::test]
    async fn omitted_rows_keep_page_progress_without_fabricating_identity() {
        let (client, _) = client(&response(vec![
            serde_json::json!({"lastTime":1,"track":{
            "mid":"onlyMid","name":"Fixture","interval":123,"singer":[{"name":"Singer"}]}}),
            serde_json::json!({"track":{"mid":"invalid"}}),
        ]));
        let snapshot = client
            .recent_plays_snapshot(&credential())
            .await
            .expect("snapshot");
        let page = snapshot.page(0, 1).expect("first");
        assert_eq!(page.records()[0].track().track_id(), None);
        assert_eq!(page.records()[0].track().song_type(), None);
        let page = snapshot.page(1, 1).expect("omitted final row");
        assert_eq!((page.next_offset(), page.omitted_track_count()), (2, 1));
        assert!(!page.has_more());
        assert!(page.records().is_empty());
    }

    #[tokio::test]
    async fn all_result_layers_stop_on_failure_without_retry_or_empty_success() {
        for (body, expected) in [
            (r#"{"code":1000}"#, "Rejected(1000)"),
            (r#"{"code":0,"req_0":{"code":1000}}"#, "Rejected(1000)"),
            (
                r#"{"code":0,"req_0":{"code":500003}}"#,
                "Upstream { global_code: 0, result_code: Some(500003) }",
            ),
            (
                r#"{"code":0,"req_0":{"code":0,"data":{"code":2001}}}"#,
                "RateLimited(2001)",
            ),
            (
                r#"{"code":0,"req_0":{"code":0,"data":{"code":500003}}}"#,
                "DataFailure { code: 500003 }",
            ),
        ] {
            let (client, requests) = client(body);
            let error = client
                .recent_plays_snapshot(&credential())
                .await
                .expect_err("failure");
            assert_eq!(format!("{error:?}"), expected);
            assert_eq!(requests.lock().expect("requests").len(), 1);
        }
    }

    #[tokio::test]
    async fn official_nonfatal_data_statuses_still_require_a_typed_snapshot() {
        for code in [-300, -301] {
            let mut body: Value =
                serde_json::from_str(&response(vec![track(1, "midOne")])).expect("fixture");
            body["req_0"]["data"]["code"] = code.into();
            let (complete, _) = client(&body.to_string());
            let snapshot = complete
                .recent_plays_snapshot(&credential())
                .await
                .expect("official admitted status");
            assert_eq!(snapshot.page(0, 100).expect("page").records().len(), 1);
            body["req_0"]["data"]["data"] = serde_json::json!({});
            let (missing, _) = client(&body.to_string());
            assert!(matches!(
                missing.recent_plays_snapshot(&credential()).await,
                Err(QqMusicRecentPlaysError::MissingRecords)
            ));
        }
    }

    #[tokio::test]
    async fn old_or_malformed_shapes_cannot_be_accepted_as_empty_history() {
        for (body, expected) in [
            ("not-json", "InvalidJson([REDACTED])"),
            (
                r#"{"code":0,"req_0":{"code":0,"data":{"vecPlayRecord":[]}}}"#,
                "MissingDataCode",
            ),
            (
                r#"{"code":0,"req_0":{"code":0,"data":{"code":0,"type":1,"data":{"mvList":[]}}}}"#,
                "UnexpectedHistoryType",
            ),
            (
                r#"{"code":0,"req_0":{"code":0,"data":{"code":0,"type":2,"data":{}}}}"#,
                "MissingRecords",
            ),
        ] {
            let (client, _) = client(body);
            assert_eq!(
                format!(
                    "{:?}",
                    client
                        .recent_plays_snapshot(&credential())
                        .await
                        .expect_err("malformed")
                ),
                expected
            );
        }
    }

    #[tokio::test]
    async fn oversized_snapshots_fail_instead_of_silently_truncating() {
        let (too_many, _) = client(&response(vec![
            serde_json::json!({});
            super::MAX_RECENT_RECORDS + 1
        ]));
        assert!(matches!(
            too_many.recent_plays_snapshot(&credential()).await,
            Err(QqMusicRecentPlaysError::ResponseTooLarge)
        ));
        let (too_large, _) = client(&" ".repeat(super::MAX_RECENT_PLAYS_RESPONSE_BYTES + 1));
        assert!(matches!(
            too_large.recent_plays_snapshot(&credential()).await,
            Err(QqMusicRecentPlaysError::ResponseTooLarge)
        ));
    }

    #[test]
    fn diagnostic_error_debug_redacts_secrets_and_marks_the_new_route() {
        let transport = QqMusicRecentPlaysError::Transport(
            "Cookie=secret; account=987654321; private response",
        );
        let output = super::recent_plays_diagnostic(LoginType::QQ, &format!("{transport:?}"));
        assert!(output.contains("route=PlayRecentlyRead channel=qq"));
        assert!(output.contains("Transport([REDACTED])"));
        for private in ["secret", "987654321", "private response", "Cookie"] {
            assert!(!output.contains(private));
        }
    }
}
