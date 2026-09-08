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
const MAX_RECENT_PLAYS_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
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

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Returns one bounded page of the authenticated account's QQ cloud
    /// recent-play records using the evidenced `begin` / `num` contract.
    ///
    /// # Errors
    ///
    /// Returns a typed protocol error for invalid bounds, transport or response
    /// failures, explicit credential rejection, and unsafe pagination.
    pub async fn recent_plays_page(
        &self,
        credential: &Credential,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicRecentPlaysPage, QqMusicRecentPlaysError<T::Error>> {
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicRecentPlaysError::InvalidPageSize { size });
        }
        let body = serde_json::to_vec(&RecentPlaysRequest::new(credential, offset, size))
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
        let envelope: RecentPlaysResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicRecentPlaysError::InvalidJson)?;
        map_response(envelope, offset, size)
    }
}

#[derive(Serialize)]
struct RecentPlaysRequest<'a> {
    comm: RecentPlaysComm<'a>,
    req_0: RecentPlaysRpc<'a>,
}

impl<'a> RecentPlaysRequest<'a> {
    fn new(credential: &'a Credential, offset: u32, size: u32) -> Self {
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
                module: "music.musichallSong.RecentPlayList",
                method: "GetRecentPlayList",
                param: RecentPlaysParam {
                    uin: credential.music_id(),
                    offset,
                    size,
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
struct RecentPlaysRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: RecentPlaysParam<'a>,
}

#[derive(Serialize)]
struct RecentPlaysParam<'a> {
    uin: &'a str,
    #[serde(rename = "begin")]
    offset: u32,
    #[serde(rename = "num")]
    size: u32,
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
    #[serde(rename = "vecPlayRecord")]
    records: Option<Vec<RawRecentPlay>>,
    #[serde(default, alias = "totalnum", alias = "total_num")]
    total: Option<u32>,
    #[serde(default, alias = "hasmore")]
    has_more: Option<RawHasMore>,
}

#[derive(Deserialize)]
struct RawRecentPlay {
    #[serde(rename = "unPlayTime")]
    source_play_time: Option<u64>,
    #[serde(rename = "stSongInfo")]
    track: Option<RawTrack>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum RawHasMore {
    Boolean(bool),
    Number(i64),
}

impl RawHasMore {
    const fn value(self) -> Option<bool> {
        match self {
            Self::Boolean(value) => Some(value),
            Self::Number(0) => Some(false),
            Self::Number(1) => Some(true),
            Self::Number(_) => None,
        }
    }
}

fn map_response<E>(
    envelope: RecentPlaysResponse,
    offset: u32,
    size: u32,
) -> Result<QqMusicRecentPlaysPage, QqMusicRecentPlaysError<E>> {
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
    let raw_records = data
        .records
        .ok_or(QqMusicRecentPlaysError::MissingRecords)?;
    let raw_count =
        u32::try_from(raw_records.len()).map_err(|_| QqMusicRecentPlaysError::InvalidPagination)?;
    if raw_count > size {
        return Err(QqMusicRecentPlaysError::InvalidPagination);
    }
    let next_offset = offset
        .checked_add(raw_count)
        .ok_or(QqMusicRecentPlaysError::InvalidPagination)?;
    let inferred_has_more = raw_count == size;
    let has_more = match data.has_more {
        Some(value) => value
            .value()
            .ok_or(QqMusicRecentPlaysError::InvalidPagination)?,
        None => inferred_has_more,
    };
    let total_is_exact = data.total.is_some();
    let total = data.total.unwrap_or_else(|| {
        if has_more {
            next_offset.saturating_add(1)
        } else {
            next_offset
        }
    });
    if total < next_offset || (has_more && next_offset == offset) {
        return Err(QqMusicRecentPlaysError::InvalidPagination);
    }

    let mut records = Vec::with_capacity(raw_records.len());
    let mut omitted_track_count = 0_u32;
    for (index, raw) in raw_records.into_iter().enumerate() {
        let Some(track) = raw.track else {
            omitted_track_count = omitted_track_count.saturating_add(1);
            continue;
        };
        match map_recent_track(track, index) {
            Ok(track) => records.push(QqMusicRecentPlay {
                track,
                source_play_time: raw.source_play_time,
            }),
            Err(_) => {
                omitted_track_count = omitted_track_count.saturating_add(1);
            }
        }
    }
    Ok(QqMusicRecentPlaysPage {
        offset,
        next_offset,
        total,
        total_is_exact,
        has_more,
        omitted_track_count,
        records,
    })
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

    fn track(id: u64, mid: &str) -> String {
        format!(
            r#"{{"unPlayTime":1700000000,"stSongInfo":{{"id":{id},"mid":"{mid}","name":"Fixture","type":0,"interval":123,"singer":[{{"id":9,"mid":"singerMid","name":"Singer"}}],"album":{{"id":7,"mid":"albumMid","name":"Album"}},"file":{{"media_mid":"{mid}"}}}}}}"#
        )
    }

    #[tokio::test]
    async fn constructs_authenticated_paged_request_and_maps_records() {
        let response = format!(
            r#"{{"code":0,"req_0":{{"code":0,"data":{{"vecPlayRecord":[{}],"total":205,"has_more":1}}}}}}"#,
            track(41, "songMid01")
        );
        let (client, requests) = client(&response);

        let page = client
            .recent_plays_page(&credential(), 100, 100)
            .await
            .expect("page");

        assert_eq!(page.offset(), 100);
        assert_eq!(page.next_offset(), 101);
        assert_eq!(page.total(), 205);
        assert!(page.total_is_exact());
        assert!(page.has_more());
        assert_eq!(page.records().len(), 1);
        assert_eq!(page.records()[0].track().song_mid(), "songMid01");
        assert_eq!(page.records()[0].source_play_time(), Some(1_700_000_000));
        let requests = requests.lock().expect("requests");
        let request = &requests[0];
        assert_eq!(request.url(), "https://u.y.qq.com/cgi-bin/musicu.fcg");
        assert_eq!(
            request.query_pairs(),
            [(
                "sign".to_owned(),
                "zzc4e09d09jupdlt5wxxhuemvphmdacir6hgdf4f9900".to_owned(),
            )]
        );
        assert!(
            request
                .headers()
                .iter()
                .any(|(name, value)| name == "Cookie" && value.contains("qqmusic_key=secret-key"))
        );
        let body: Value =
            serde_json::from_slice(request.body_bytes().expect("body")).expect("body");
        assert_eq!(body["comm"]["uin"], "123456");
        assert_eq!(body["comm"]["g_tk_new_20200303"], 340_831_009);
        assert_eq!(body["comm"]["g_tk"], 340_831_009);
        assert_eq!(
            body["req_0"]["module"],
            "music.musichallSong.RecentPlayList"
        );
        assert_eq!(body["req_0"]["method"], "GetRecentPlayList");
        assert_eq!(body["req_0"]["param"]["uin"], "123456");
        assert_eq!(body["req_0"]["param"]["begin"], 100);
        assert_eq!(body["req_0"]["param"]["num"], 100);
        assert!(!format!("{request:?}").contains("secret-key"));
    }

    #[tokio::test]
    async fn empty_page_is_a_success_not_an_unavailable_state() {
        let (client, _) = client(r#"{"code":0,"req_0":{"code":0,"data":{"vecPlayRecord":[]}}}"#);
        let page = client
            .recent_plays_page(&credential(), 0, 100)
            .await
            .expect("empty");
        assert_eq!(page.total(), 0);
        assert!(!page.has_more());
        assert!(page.records().is_empty());
    }

    #[tokio::test]
    async fn full_page_without_total_exposes_a_safe_lower_bound_cursor() {
        let records = (0..100)
            .map(|index| track(index + 1, &format!("songMid{index:03}")))
            .collect::<Vec<_>>()
            .join(",");
        let response =
            format!(r#"{{"code":0,"req_0":{{"code":0,"data":{{"vecPlayRecord":[{records}]}}}}}}"#);
        let (client, _) = client(&response);
        let page = client
            .recent_plays_page(&credential(), 200, 100)
            .await
            .expect("page");
        assert_eq!(page.next_offset(), 300);
        assert_eq!(page.total(), 301);
        assert!(!page.total_is_exact());
        assert!(page.has_more());
    }

    #[tokio::test]
    async fn credential_rejection_is_not_disguised_as_empty_history() {
        let (client, _) = client(r#"{"code":0,"req_0":{"code":1000,"data":{}}}"#);
        assert!(matches!(
            client.recent_plays_page(&credential(), 0, 100).await,
            Err(QqMusicRecentPlaysError::Rejected { code: 1000 })
        ));
    }

    #[tokio::test]
    async fn malformed_and_missing_shapes_remain_explicit() {
        let (malformed, _) = client("not-json");
        assert!(matches!(
            malformed.recent_plays_page(&credential(), 0, 100).await,
            Err(QqMusicRecentPlaysError::InvalidJson)
        ));
        let (missing, _) = client(r#"{"code":0,"req_0":{"code":0,"data":{}}}"#);
        assert!(matches!(
            missing.recent_plays_page(&credential(), 0, 100).await,
            Err(QqMusicRecentPlaysError::MissingRecords)
        ));
    }

    #[tokio::test]
    async fn mid_only_identity_maps_without_fabricating_ids_and_invalid_rows_advance_cursor() {
        let (client, _) = client(
            r#"{"code":0,"req_0":{"code":0,"data":{"vecPlayRecord":[{"unPlayTime":1,"stSongInfo":{"mid":"onlyMid","name":"Fixture","interval":123,"singer":[{"name":"Singer"}],"album":{"name":"Album"}}},{"unPlayTime":2,"stSongInfo":{"mid":"missingDisplayFields"}}]}}}"#,
        );
        let page = client
            .recent_plays_page(&credential(), 0, 100)
            .await
            .expect("page");
        assert_eq!(page.next_offset(), 2);
        assert_eq!(page.omitted_track_count(), 1);
        assert_eq!(page.records().len(), 1);
        let track = page.records()[0].track();
        assert_eq!(track.track_id(), None);
        assert_eq!(track.song_type(), None);
        assert_eq!(track.song_mid(), "onlyMid");
        assert_eq!(track.title(), "Fixture");
    }
}
