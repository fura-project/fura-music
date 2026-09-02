use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::credential::is_credential_rejection_code;
use crate::protocol_strategy::is_musicu_rate_limited_code;
use crate::{Credential, HttpRequest, HttpTransport, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_PLAYLIST_DETAIL_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const PLAYLIST_DETAIL_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_PAGE_SIZE: u32 = 100;
const LIKED_SONGS_DIRECTORY_ID: u64 = 201;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PlaylistDetailTrackField {
    TrackId,
    SongMid,
    FileMediaMid,
    Title,
    SongType,
    Artists,
    ArtistName,
}

pub enum QqMusicPlaylistDetailError<E> {
    InvalidPlaylistId,
    MissingEncryptedUin,
    InvalidPageSize {
        size: u32,
    },
    Transport(E),
    Serialize,
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
        data_code: Option<i64>,
    },
    MissingData,
    MissingTracks,
    MissingTotal,
    MissingHasMore,
    InvalidHasMore,
    InvalidTrack {
        index: usize,
        field: PlaylistDetailTrackField,
    },
    InvalidArtist {
        track_index: usize,
        artist_index: usize,
        field: PlaylistDetailTrackField,
    },
}

impl<E> fmt::Debug for QqMusicPlaylistDetailError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidPlaylistId => formatter.write_str("InvalidPlaylistId"),
            Self::MissingEncryptedUin => formatter.write_str("MissingEncryptedUin"),
            Self::InvalidPageSize { size } => formatter
                .debug_struct("InvalidPageSize")
                .field("size", size)
                .finish(),
            Self::Transport(_) => formatter.write_str("Transport([REDACTED])"),
            Self::Serialize => formatter.write_str("Serialize"),
            Self::HttpStatus(status) => formatter.debug_tuple("HttpStatus").field(status).finish(),
            Self::InvalidJson => formatter.write_str("InvalidJson([REDACTED])"),
            Self::MissingGlobalCode => formatter.write_str("MissingGlobalCode"),
            Self::MissingResult => formatter.write_str("MissingResult"),
            Self::MissingResultCode => formatter.write_str("MissingResultCode"),
            Self::Rejected { code } => formatter
                .debug_struct("Rejected")
                .field("code", code)
                .finish(),
            Self::RateLimited { code } => formatter
                .debug_struct("RateLimited")
                .field("code", code)
                .finish(),
            Self::Upstream {
                global_code,
                result_code,
                data_code,
            } => formatter
                .debug_struct("Upstream")
                .field("global_code", global_code)
                .field("result_code", result_code)
                .field("data_code", data_code)
                .finish(),
            Self::MissingData => formatter.write_str("MissingData"),
            Self::MissingTracks => formatter.write_str("MissingTracks"),
            Self::MissingTotal => formatter.write_str("MissingTotal"),
            Self::MissingHasMore => formatter.write_str("MissingHasMore"),
            Self::InvalidHasMore => formatter.write_str("InvalidHasMore"),
            Self::InvalidTrack { index, field } => formatter
                .debug_struct("InvalidTrack")
                .field("index", index)
                .field("field", field)
                .finish(),
            Self::InvalidArtist {
                track_index,
                artist_index,
                field,
            } => formatter
                .debug_struct("InvalidArtist")
                .field("track_index", track_index)
                .field("artist_index", artist_index)
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicPlaylistDetailError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidPlaylistId => formatter.write_str("playlist identity is invalid"),
            Self::MissingEncryptedUin => {
                formatter.write_str("credential has no encrypted account identity")
            }
            Self::InvalidPageSize { size } => write!(
                formatter,
                "playlist-detail page size {size} is outside 1..={MAX_PAGE_SIZE}"
            ),
            Self::Transport(_) => formatter.write_str("QQ Music playlist-detail request failed"),
            Self::Serialize => formatter.write_str("could not serialize playlist-detail request"),
            Self::HttpStatus(status) => {
                write!(formatter, "playlist-detail request returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("playlist-detail response was not valid JSON"),
            Self::MissingGlobalCode => {
                formatter.write_str("playlist-detail response has no global code")
            }
            Self::MissingResult => formatter.write_str("playlist-detail result is missing"),
            Self::MissingResultCode => formatter.write_str("playlist-detail result has no code"),
            Self::Rejected { code } => {
                write!(
                    formatter,
                    "QQ Music rejected the credential with code {code}"
                )
            }
            Self::RateLimited { code } => {
                write!(
                    formatter,
                    "QQ Music rate limited the request with code {code}"
                )
            }
            Self::Upstream {
                global_code,
                result_code,
                data_code,
            } => write!(
                formatter,
                "playlist-detail request failed with global code {global_code}, result code {result_code:?}, and data code {data_code:?}"
            ),
            Self::MissingData => formatter.write_str("playlist-detail data is missing"),
            Self::MissingTracks => formatter.write_str("playlist-detail track array is missing"),
            Self::MissingTotal => formatter.write_str("playlist-detail total is missing"),
            Self::MissingHasMore => {
                formatter.write_str("playlist-detail continuation flag is missing")
            }
            Self::InvalidHasMore => {
                formatter.write_str("playlist-detail continuation flag is invalid")
            }
            Self::InvalidTrack { index, field } => {
                write!(formatter, "playlist track {index} has an invalid {field:?}")
            }
            Self::InvalidArtist {
                track_index,
                artist_index,
                field,
            } => write!(
                formatter,
                "playlist track {track_index} artist {artist_index} has an invalid {field:?}"
            ),
        }
    }
}

impl<E> std::error::Error for QqMusicPlaylistDetailError<E>
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
pub struct QqMusicArtistSummary {
    artist_id: Option<u64>,
    media_mid: Option<String>,
    name: String,
}

impl QqMusicArtistSummary {
    pub(crate) fn new(artist_id: Option<u64>, media_mid: Option<String>, name: String) -> Self {
        Self {
            artist_id,
            media_mid,
            name,
        }
    }

    #[must_use]
    pub const fn artist_id(&self) -> Option<u64> {
        self.artist_id
    }

    #[must_use]
    pub fn media_mid(&self) -> Option<&str> {
        self.media_mid.as_deref()
    }

    #[must_use]
    pub fn name(&self) -> &str {
        &self.name
    }
}

impl fmt::Debug for QqMusicArtistSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicArtistSummary")
            .field("has_artist_id", &self.artist_id.is_some())
            .field("has_media_mid", &self.media_mid.is_some())
            .field("name", &"[REDACTED]")
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicAlbumSummary {
    album_id: Option<u64>,
    media_mid: Option<String>,
    name: Option<String>,
}

impl QqMusicAlbumSummary {
    pub(crate) fn new(
        album_id: Option<u64>,
        media_mid: Option<String>,
        name: Option<String>,
    ) -> Self {
        Self {
            album_id,
            media_mid,
            name,
        }
    }

    #[must_use]
    pub const fn album_id(&self) -> Option<u64> {
        self.album_id
    }

    #[must_use]
    pub fn media_mid(&self) -> Option<&str> {
        self.media_mid.as_deref()
    }

    #[must_use]
    pub fn name(&self) -> Option<&str> {
        self.name.as_deref()
    }
}

impl fmt::Debug for QqMusicAlbumSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicAlbumSummary")
            .field("has_album_id", &self.album_id.is_some())
            .field("has_media_mid", &self.media_mid.is_some())
            .field("has_name", &self.name.is_some())
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicTrackSummary {
    track_id: u64,
    song_mid: String,
    file_media_mid: Option<String>,
    title: String,
    subtitle: Option<String>,
    song_type: u32,
    duration_seconds: u32,
    artists: Vec<QqMusicArtistSummary>,
    album: Option<QqMusicAlbumSummary>,
}

impl QqMusicTrackSummary {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new(
        track_id: u64,
        song_mid: String,
        file_media_mid: Option<String>,
        title: String,
        subtitle: Option<String>,
        song_type: u32,
        duration_seconds: u32,
        artists: Vec<QqMusicArtistSummary>,
        album: Option<QqMusicAlbumSummary>,
    ) -> Self {
        Self {
            track_id,
            song_mid,
            file_media_mid,
            title,
            subtitle,
            song_type,
            duration_seconds,
            artists,
            album,
        }
    }

    #[must_use]
    pub const fn track_id(&self) -> u64 {
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
    pub const fn song_type(&self) -> u32 {
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

impl fmt::Debug for QqMusicTrackSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicTrackSummary")
            .field("track_id", &"[REDACTED]")
            .field("song_mid", &"[REDACTED]")
            .field("has_file_media_mid", &self.file_media_mid.is_some())
            .field("title", &"[REDACTED]")
            .field("has_subtitle", &self.subtitle.is_some())
            .field("song_type", &self.song_type)
            .field("duration_seconds", &self.duration_seconds)
            .field("artist_count", &self.artists.len())
            .field("has_album", &self.album.is_some())
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicPlaylistTracksPage {
    offset: u32,
    total: u32,
    has_more: bool,
    tracks: Vec<QqMusicTrackSummary>,
}

impl QqMusicPlaylistTracksPage {
    #[must_use]
    pub const fn offset(&self) -> u32 {
        self.offset
    }

    #[must_use]
    pub const fn total(&self) -> u32 {
        self.total
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn tracks(&self) -> &[QqMusicTrackSummary] {
        &self.tracks
    }
}

impl fmt::Debug for QqMusicPlaylistTracksPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicPlaylistTracksPage")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("track_count", &self.tracks.len())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Returns one bounded page from an ordinary QQ Music playlist.
    ///
    /// # Errors
    ///
    /// Rejects a zero playlist identity and page sizes outside `1..=100`
    /// before transport. Network, service, credential rejection, response
    /// shape, pagination, and invalid track identities remain distinct.
    pub async fn playlist_tracks_page(
        &self,
        credential: &Credential,
        playlist_id: u64,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicPlaylistTracksPage, QqMusicPlaylistDetailError<T::Error>> {
        if playlist_id == 0 {
            return Err(QqMusicPlaylistDetailError::InvalidPlaylistId);
        }
        self.playlist_tracks_page_for_route(
            Some(credential),
            PlaylistRoute::Ordinary { playlist_id },
            offset,
            size,
        )
        .await
    }

    /// Returns one bounded anonymous page from a public QQ Music playlist.
    ///
    /// This uses the same evidenced `CgiGetDiss` contract as authenticated
    /// playlist detail, but deliberately omits account fields and Cookie.
    /// Account-owned and liked-song directories must use their authenticated
    /// entry points instead.
    ///
    /// # Errors
    ///
    /// Rejects a zero playlist identity and page sizes outside `1..=100`
    /// before transport. Anonymous upstream failures remain service outcomes
    /// rather than being guessed into credential rejection.
    pub async fn public_playlist_tracks_page(
        &self,
        playlist_id: u64,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicPlaylistTracksPage, QqMusicPlaylistDetailError<T::Error>> {
        if playlist_id == 0 {
            return Err(QqMusicPlaylistDetailError::InvalidPlaylistId);
        }
        self.playlist_tracks_page_for_route(
            None,
            PlaylistRoute::Ordinary { playlist_id },
            offset,
            size,
        )
        .await
    }

    /// Returns one bounded page from the authenticated account's built-in
    /// liked-songs directory.
    ///
    /// # Errors
    ///
    /// In addition to playlist page failures, rejects a missing encrypted UIN
    /// before transport because QQ Music requires it for directory `201`.
    pub async fn liked_songs_page(
        &self,
        credential: &Credential,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicPlaylistTracksPage, QqMusicPlaylistDetailError<T::Error>> {
        let encrypted_uin = credential
            .session_secrets()
            .encrypted_uin()
            .filter(|value| !value.trim().is_empty())
            .ok_or(QqMusicPlaylistDetailError::MissingEncryptedUin)?;
        self.playlist_tracks_page_for_route(
            Some(credential),
            PlaylistRoute::LikedSongs { encrypted_uin },
            offset,
            size,
        )
        .await
    }

    async fn playlist_tracks_page_for_route(
        &self,
        credential: Option<&Credential>,
        route: PlaylistRoute<'_>,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicPlaylistTracksPage, QqMusicPlaylistDetailError<T::Error>> {
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicPlaylistDetailError::InvalidPageSize { size });
        }
        let body = serde_json::to_vec(&PlaylistDetailRequest::new(credential, route, offset, size))
            .map_err(|_| QqMusicPlaylistDetailError::Serialize)?;
        let request = HttpRequest::post(MUSICU_URL)
            .header("Content-Type", "application/json")
            .header("Origin", "https://y.qq.com")
            .header("Referer", "https://y.qq.com/")
            .body(body)
            .response_body_limit(MAX_PLAYLIST_DETAIL_RESPONSE_BYTES)
            .timeout(PLAYLIST_DETAIL_TIMEOUT);
        let request = match credential {
            Some(credential) => request.header("Cookie", credential.musicu_cookie_header()),
            None => request,
        };
        let response = self
            .transport()
            .execute(request)
            .await
            .map_err(QqMusicPlaylistDetailError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicPlaylistDetailError::HttpStatus(response.status()));
        }

        let envelope: PlaylistDetailResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicPlaylistDetailError::InvalidJson)?;
        map_response(envelope, offset, credential.is_some())
    }
}

#[derive(Clone, Copy)]
enum PlaylistRoute<'a> {
    Ordinary { playlist_id: u64 },
    LikedSongs { encrypted_uin: &'a str },
}

#[derive(Serialize)]
struct PlaylistDetailRequest<'a> {
    comm: PlaylistDetailComm<'a>,
    #[serde(rename = "music.srfDissInfo.DissInfo")]
    request: PlaylistDetailRpc<'a>,
}

impl<'a> PlaylistDetailRequest<'a> {
    fn new(
        credential: Option<&'a Credential>,
        route: PlaylistRoute<'a>,
        offset: u32,
        size: u32,
    ) -> Self {
        let param = match route {
            PlaylistRoute::Ordinary { playlist_id } => PlaylistDetailParam {
                playlist_id,
                directory_id: 0,
                tag: true,
                offset,
                size,
                user_info: true,
                order_list: true,
                only_song_list: Some(false),
                encrypted_host_uin: None,
            },
            PlaylistRoute::LikedSongs { encrypted_uin } => PlaylistDetailParam {
                playlist_id: 0,
                directory_id: LIKED_SONGS_DIRECTORY_ID,
                tag: true,
                offset,
                size,
                user_info: true,
                order_list: true,
                only_song_list: None,
                encrypted_host_uin: Some(encrypted_uin),
            },
        };
        Self {
            comm: PlaylistDetailComm {
                cv: 13_020_508,
                version: 13_020_508,
                client_type: "11",
                app_id: "qqmusic",
                format: "json",
                input_charset: "utf-8",
                output_charset: "utf-8",
                user_id: credential.map(Credential::music_id),
                account_id: credential.map(Credential::music_id),
                auth_key: credential.map(Credential::music_key),
                login_type: credential.map(|credential| credential.login_type().value()),
                login_uin: credential.map(Credential::music_id),
            },
            request: PlaylistDetailRpc {
                module: "music.srfDissInfo.DissInfo",
                method: "CgiGetDiss",
                param,
            },
        }
    }
}

#[derive(Serialize)]
struct PlaylistDetailComm<'a> {
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
    #[serde(skip_serializing_if = "Option::is_none")]
    user_id: Option<&'a str>,
    #[serde(rename = "qq")]
    #[serde(skip_serializing_if = "Option::is_none")]
    account_id: Option<&'a str>,
    #[serde(rename = "authst")]
    #[serde(skip_serializing_if = "Option::is_none")]
    auth_key: Option<&'a str>,
    #[serde(rename = "tmeLoginType")]
    #[serde(skip_serializing_if = "Option::is_none")]
    login_type: Option<u32>,
    #[serde(rename = "loginUin")]
    #[serde(skip_serializing_if = "Option::is_none")]
    login_uin: Option<&'a str>,
}

#[derive(Serialize)]
struct PlaylistDetailRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: PlaylistDetailParam<'a>,
}

#[derive(Serialize)]
struct PlaylistDetailParam<'a> {
    #[serde(rename = "disstid")]
    playlist_id: u64,
    #[serde(rename = "dirid")]
    directory_id: u64,
    tag: bool,
    #[serde(rename = "song_begin")]
    offset: u32,
    #[serde(rename = "song_num")]
    size: u32,
    #[serde(rename = "userinfo")]
    user_info: bool,
    #[serde(rename = "orderlist")]
    order_list: bool,
    #[serde(rename = "onlysonglist", skip_serializing_if = "Option::is_none")]
    only_song_list: Option<bool>,
    #[serde(rename = "enc_host_uin", skip_serializing_if = "Option::is_none")]
    encrypted_host_uin: Option<&'a str>,
}

#[derive(Deserialize)]
struct PlaylistDetailResponse {
    code: Option<i64>,
    #[serde(rename = "music.srfDissInfo.DissInfo")]
    result: Option<PlaylistDetailResult>,
}

#[derive(Deserialize)]
struct PlaylistDetailResult {
    code: Option<i64>,
    data: Option<PlaylistDetailData>,
}

#[derive(Deserialize)]
struct PlaylistDetailData {
    code: Option<i64>,
    #[serde(rename = "songlist")]
    tracks: Option<Vec<RawTrack>>,
    #[serde(rename = "total_song_num")]
    total: Option<u32>,
    hasmore: Option<RawHasMore>,
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

#[derive(Deserialize)]
struct RawTrack {
    id: Option<u64>,
    mid: Option<String>,
    name: Option<String>,
    title: Option<String>,
    subtitle: Option<String>,
    #[serde(rename = "type")]
    song_type: Option<u32>,
    interval: Option<u32>,
    singer: Option<Vec<RawArtist>>,
    album: Option<RawAlbum>,
    file: Option<RawFile>,
}

#[derive(Deserialize)]
struct RawFile {
    media_mid: Option<String>,
}

#[derive(Deserialize)]
struct RawArtist {
    id: Option<u64>,
    mid: Option<String>,
    name: Option<String>,
}

#[derive(Deserialize)]
struct RawAlbum {
    id: Option<u64>,
    mid: Option<String>,
    pmid: Option<String>,
    name: Option<String>,
    title: Option<String>,
}

fn map_response<E>(
    envelope: PlaylistDetailResponse,
    offset: u32,
    credential_aware: bool,
) -> Result<QqMusicPlaylistTracksPage, QqMusicPlaylistDetailError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicPlaylistDetailError::MissingGlobalCode)?;
    let result_code = envelope.result.as_ref().and_then(|result| result.code);
    let data_code = envelope
        .result
        .as_ref()
        .and_then(|result| result.data.as_ref())
        .and_then(|data| data.code);
    let codes = [Some(global_code), result_code, data_code];
    if let Some(code) = codes
        .into_iter()
        .flatten()
        .find(|code| is_musicu_rate_limited_code(*code))
    {
        return Err(QqMusicPlaylistDetailError::RateLimited { code });
    }
    if let Some(code) = codes
        .into_iter()
        .flatten()
        .find(|code| credential_aware && is_credential_rejection_code(*code))
    {
        return Err(QqMusicPlaylistDetailError::Rejected { code });
    }
    if global_code != 0 {
        return Err(QqMusicPlaylistDetailError::Upstream {
            global_code,
            result_code,
            data_code,
        });
    }

    let result = envelope
        .result
        .ok_or(QqMusicPlaylistDetailError::MissingResult)?;
    let result_code = result
        .code
        .ok_or(QqMusicPlaylistDetailError::MissingResultCode)?;
    if result_code != 0 {
        return Err(QqMusicPlaylistDetailError::Upstream {
            global_code,
            result_code: Some(result_code),
            data_code,
        });
    }
    let data = result.data.ok_or(QqMusicPlaylistDetailError::MissingData)?;
    if data.code.is_some_and(|code| code != 0) {
        return Err(QqMusicPlaylistDetailError::Upstream {
            global_code,
            result_code: Some(result_code),
            data_code: data.code,
        });
    }

    let raw_tracks = data
        .tracks
        .ok_or(QqMusicPlaylistDetailError::MissingTracks)?;
    let total = data.total.ok_or(QqMusicPlaylistDetailError::MissingTotal)?;
    let has_more = data
        .hasmore
        .ok_or(QqMusicPlaylistDetailError::MissingHasMore)?
        .value()
        .ok_or(QqMusicPlaylistDetailError::InvalidHasMore)?;
    let tracks = raw_tracks
        .into_iter()
        .enumerate()
        .map(|(index, raw)| map_track(raw, index))
        .collect::<Result<Vec<_>, _>>()?;

    Ok(QqMusicPlaylistTracksPage {
        offset,
        total,
        has_more,
        tracks,
    })
}

fn map_track<E>(
    raw: RawTrack,
    index: usize,
) -> Result<QqMusicTrackSummary, QqMusicPlaylistDetailError<E>> {
    let track_id =
        raw.id
            .filter(|value| *value != 0)
            .ok_or(QqMusicPlaylistDetailError::InvalidTrack {
                index,
                field: PlaylistDetailTrackField::TrackId,
            })?;
    let song_mid = safe_media_mid(raw.mid).ok_or(QqMusicPlaylistDetailError::InvalidTrack {
        index,
        field: PlaylistDetailTrackField::SongMid,
    })?;
    let raw_file_media_mid = raw.file.and_then(|file| file.media_mid);
    let file_media_mid = match raw_file_media_mid {
        Some(value) if value.trim().is_empty() => None,
        Some(value) => Some(safe_media_mid(Some(value)).ok_or(
            QqMusicPlaylistDetailError::InvalidTrack {
                index,
                field: PlaylistDetailTrackField::FileMediaMid,
            },
        )?),
        None => None,
    };
    let title = nonblank(raw.title).or_else(|| nonblank(raw.name)).ok_or(
        QqMusicPlaylistDetailError::InvalidTrack {
            index,
            field: PlaylistDetailTrackField::Title,
        },
    )?;
    let song_type = raw
        .song_type
        .ok_or(QqMusicPlaylistDetailError::InvalidTrack {
            index,
            field: PlaylistDetailTrackField::SongType,
        })?;
    let raw_artists = raw.singer.ok_or(QqMusicPlaylistDetailError::InvalidTrack {
        index,
        field: PlaylistDetailTrackField::Artists,
    })?;
    let artists = raw_artists
        .into_iter()
        .enumerate()
        .map(|(artist_index, artist)| {
            let name = nonblank(artist.name).ok_or(QqMusicPlaylistDetailError::InvalidArtist {
                track_index: index,
                artist_index,
                field: PlaylistDetailTrackField::ArtistName,
            })?;
            Ok(QqMusicArtistSummary {
                artist_id: artist.id.filter(|value| *value != 0),
                media_mid: nonblank(artist.mid),
                name,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;
    let album = raw.album.map(|album| QqMusicAlbumSummary {
        album_id: album.id.filter(|value| *value != 0),
        media_mid: nonblank(album.mid).or_else(|| nonblank(album.pmid)),
        name: nonblank(album.title).or_else(|| nonblank(album.name)),
    });

    Ok(QqMusicTrackSummary {
        track_id,
        song_mid,
        file_media_mid,
        title,
        subtitle: nonblank(raw.subtitle),
        song_type,
        duration_seconds: raw.interval.unwrap_or(0),
        artists,
        album,
    })
}

fn nonblank(value: Option<String>) -> Option<String> {
    value.filter(|value| !value.trim().is_empty())
}

fn safe_media_mid(value: Option<String>) -> Option<String> {
    nonblank(value)
        .filter(|value| value.len() <= 64 && value.bytes().all(|byte| byte.is_ascii_alphanumeric()))
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::convert::Infallible;
    use std::sync::Mutex;
    use std::time::Duration;

    use serde_json::{Value, json};

    use super::{PlaylistDetailTrackField, QqMusicPlaylistDetailError};
    use crate::{
        Credential, CredentialSessionSecrets, HttpMethod, HttpRequest, HttpResponse, HttpTransport,
        LoginType, QqMusicClient,
    };

    struct FakeTransport {
        responses: Mutex<VecDeque<HttpResponse>>,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl FakeTransport {
        fn new(responses: impl IntoIterator<Item = Value>) -> Self {
            Self {
                responses: Mutex::new(
                    responses
                        .into_iter()
                        .map(|response| {
                            HttpResponse::new(
                                200,
                                serde_json::to_vec(&response).expect("fixture JSON"),
                            )
                        })
                        .collect(),
                ),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn requests(&self) -> Vec<HttpRequest> {
            self.requests.lock().expect("request lock").clone()
        }
    }

    impl HttpTransport for FakeTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("request lock").push(request);
            Ok(self
                .responses
                .lock()
                .expect("response lock")
                .pop_front()
                .expect("fixture response"))
        }
    }

    fn credential() -> Credential {
        Credential::new("123456", "W_X_private-key", LoginType::WECHAT)
            .expect("fixture credential")
            .with_session_secrets(CredentialSessionSecrets::new(
                None,
                None,
                None,
                None,
                None,
                Some("secret-encrypted-uin".into()),
            ))
    }

    fn page_fixture() -> Value {
        json!({
            "code": 0,
            "music.srfDissInfo.DissInfo": {
                "code": 0,
                "data": {
                    "code": 0,
                    "songlist": [{
                        "id": 41001,
                        "mid": "fixtureTrackMid1",
                        "name": "Fallback fixture title",
                        "title": "Fixture title",
                        "subtitle": "Fixture subtitle",
                        "type": 0,
                        "songtype": 13,
                        "interval": 245,
                        "file": {"media_mid": "fixtureFileMid1"},
                        "singer": [{
                            "id": 42001,
                            "mid": "fixture-artist-mid",
                            "name": "Fixture artist"
                        }],
                        "album": {
                            "id": 43001,
                            "mid": "fixture-album-mid",
                            "name": "Fallback fixture album",
                            "title": "Fixture album"
                        }
                    }],
                    "total_song_num": 51,
                    "hasmore": 1
                }
            }
        })
    }

    #[tokio::test]
    async fn serializes_ordinary_playlist_page_and_maps_minimum_track_data() {
        let client = QqMusicClient::new(FakeTransport::new([page_fixture()]));

        let page = client
            .playlist_tracks_page(&credential(), 7001, 50, 1)
            .await
            .expect("fixture playlist page");
        assert_eq!(page.offset(), 50);
        assert_eq!(page.total(), 51);
        assert!(page.has_more());
        let track = &page.tracks()[0];
        assert_eq!(track.track_id(), 41001);
        assert_eq!(track.song_mid(), "fixtureTrackMid1");
        assert_eq!(track.file_media_mid(), Some("fixtureFileMid1"));
        assert_eq!(track.title(), "Fixture title");
        assert_eq!(track.subtitle(), Some("Fixture subtitle"));
        assert_eq!(track.song_type(), 0);
        assert_eq!(track.duration_seconds(), 245);
        assert_eq!(track.artists()[0].artist_id(), Some(42001));
        assert_eq!(track.artists()[0].media_mid(), Some("fixture-artist-mid"));
        assert_eq!(track.artists()[0].name(), "Fixture artist");
        assert_eq!(
            track.album().and_then(super::QqMusicAlbumSummary::album_id),
            Some(43001)
        );
        assert_eq!(
            track
                .album()
                .and_then(super::QqMusicAlbumSummary::media_mid),
            Some("fixture-album-mid")
        );
        assert_eq!(
            track.album().and_then(super::QqMusicAlbumSummary::name),
            Some("Fixture album")
        );

        let request = &client.transport().requests()[0];
        assert_eq!(request.method(), HttpMethod::Post);
        assert_eq!(request.url(), "https://u.y.qq.com/cgi-bin/musicu.fcg");
        assert_eq!(request.max_response_body_bytes(), 2 * 1024 * 1024);
        assert_eq!(request.request_timeout(), Some(Duration::from_secs(30)));
        let body: Value =
            serde_json::from_slice(request.body_bytes().expect("playlist-detail request body"))
                .expect("request JSON");
        let rpc = &body["music.srfDissInfo.DissInfo"];
        assert_eq!(rpc["module"], "music.srfDissInfo.DissInfo");
        assert_eq!(rpc["method"], "CgiGetDiss");
        assert_eq!(rpc["param"]["disstid"], 7001);
        assert_eq!(rpc["param"]["dirid"], 0);
        assert_eq!(rpc["param"]["song_begin"], 50);
        assert_eq!(rpc["param"]["song_num"], 1);
        assert_eq!(rpc["param"]["onlysonglist"], false);
        assert!(rpc["param"].get("enc_host_uin").is_none());
        assert!(!format!("{request:?}").contains("W_X_private-key"));
        assert!(!format!("{page:?}").contains("Fixture title"));
        assert!(!format!("{track:?}").contains("fixtureTrackMid1"));
    }

    #[tokio::test]
    async fn serializes_public_playlist_without_account_context() {
        let client = QqMusicClient::new(FakeTransport::new([page_fixture()]));

        let page = client
            .public_playlist_tracks_page(7001, 0, 1)
            .await
            .expect("public fixture playlist page");
        assert_eq!(page.tracks().len(), 1);

        let request = &client.transport().requests()[0];
        assert!(request.headers().iter().all(|(name, _)| name != "Cookie"));
        let body: Value =
            serde_json::from_slice(request.body_bytes().expect("playlist-detail request body"))
                .expect("request JSON");
        let comm = body["comm"].as_object().expect("comm object");
        for account_field in ["uid", "qq", "authst", "tmeLoginType", "loginUin"] {
            assert!(!comm.contains_key(account_field));
        }
        assert_eq!(body["music.srfDissInfo.DissInfo"]["param"]["disstid"], 7001);
    }

    #[tokio::test]
    async fn accepts_valid_empty_public_playlist_page() {
        let client = QqMusicClient::new(FakeTransport::new([json!({
            "code": 0,
            "music.srfDissInfo.DissInfo": {
                "code": 0,
                "data": {
                    "code": 0,
                    "songlist": [],
                    "total_song_num": 0,
                    "hasmore": 0
                }
            }
        })]));

        let page = client
            .public_playlist_tracks_page(7001, 0, 100)
            .await
            .expect("valid empty public playlist page");
        assert_eq!(page.offset(), 0);
        assert_eq!(page.total(), 0);
        assert!(!page.has_more());
        assert!(page.tracks().is_empty());
        assert_eq!(client.transport().requests().len(), 1);
    }

    #[tokio::test]
    async fn serializes_liked_songs_as_the_evidenced_directory_route() {
        let mut fixture = page_fixture();
        fixture["music.srfDissInfo.DissInfo"]["data"]
            .as_object_mut()
            .expect("fixture data")
            .remove("code");
        let client = QqMusicClient::new(FakeTransport::new([fixture]));

        client
            .liked_songs_page(&credential(), 100, 100)
            .await
            .expect("fixture liked-songs page");

        let request = &client.transport().requests()[0];
        let body: Value =
            serde_json::from_slice(request.body_bytes().expect("liked-songs request body"))
                .expect("request JSON");
        let param = &body["music.srfDissInfo.DissInfo"]["param"];
        assert_eq!(param["disstid"], 0);
        assert_eq!(param["dirid"], 201);
        assert_eq!(param["song_begin"], 100);
        assert_eq!(param["song_num"], 100);
        assert_eq!(param["enc_host_uin"], "secret-encrypted-uin");
        assert!(param.get("onlysonglist").is_none());
        assert!(!format!("{request:?}").contains("secret-encrypted-uin"));
    }

    #[tokio::test]
    async fn rejects_invalid_inputs_before_transport() {
        let client = QqMusicClient::new(FakeTransport::new([]));
        let no_encrypted_uin =
            Credential::new("123456", "key", LoginType::WECHAT).expect("fixture credential");

        assert!(matches!(
            client.playlist_tracks_page(&credential(), 0, 0, 100).await,
            Err(QqMusicPlaylistDetailError::InvalidPlaylistId)
        ));
        assert!(matches!(
            client.playlist_tracks_page(&credential(), 1, 0, 0).await,
            Err(QqMusicPlaylistDetailError::InvalidPageSize { size: 0 })
        ));
        assert!(matches!(
            client.playlist_tracks_page(&credential(), 1, 0, 101).await,
            Err(QqMusicPlaylistDetailError::InvalidPageSize { size: 101 })
        ));
        assert!(matches!(
            client.liked_songs_page(&no_encrypted_uin, 0, 100).await,
            Err(QqMusicPlaylistDetailError::MissingEncryptedUin)
        ));
        assert!(client.transport().requests().is_empty());
    }

    #[tokio::test]
    async fn keeps_three_level_rejection_and_upstream_codes_distinct() {
        let client = QqMusicClient::new(FakeTransport::new([
            json!({
                "code": 0,
                "music.srfDissInfo.DissInfo": {"code": 0, "data": {"code": 104_400}}
            }),
            json!({
                "code": 0,
                "music.srfDissInfo.DissInfo": {"code": 80_120, "data": {"code": 0}}
            }),
        ]));

        assert!(matches!(
            client.playlist_tracks_page(&credential(), 1, 0, 100).await,
            Err(QqMusicPlaylistDetailError::Rejected { code: 104_400 })
        ));
        assert!(matches!(
            client.playlist_tracks_page(&credential(), 1, 0, 100).await,
            Err(QqMusicPlaylistDetailError::Upstream {
                global_code: 0,
                result_code: Some(80_120),
                data_code: Some(0),
            })
        ));
    }

    #[tokio::test]
    async fn anonymous_codes_are_not_guessed_as_credential_rejection_and_rate_limit_stops() {
        let client = QqMusicClient::new(FakeTransport::new([
            json!({
                "code": 0,
                "music.srfDissInfo.DissInfo": {"code": 1000, "data": {"code": 0}}
            }),
            json!({
                "code": 2001,
                "music.srfDissInfo.DissInfo": {"code": 0, "data": {"code": 0}}
            }),
        ]));

        assert!(matches!(
            client.public_playlist_tracks_page(1, 0, 100).await,
            Err(QqMusicPlaylistDetailError::Upstream {
                global_code: 0,
                result_code: Some(1000),
                data_code: Some(0),
            })
        ));
        assert!(matches!(
            client.public_playlist_tracks_page(1, 0, 100).await,
            Err(QqMusicPlaylistDetailError::RateLimited { code: 2001 })
        ));
        assert_eq!(client.transport().requests().len(), 2);
    }

    #[tokio::test]
    async fn rejects_invalid_pagination_and_rows_without_leaking_content() {
        let client = QqMusicClient::new(FakeTransport::new([
            json!({
                "code": 0,
                "music.srfDissInfo.DissInfo": {
                    "code": 0,
                    "data": {
                        "code": 0,
                        "songlist": [],
                        "total_song_num": 0,
                        "hasmore": 2
                    }
                }
            }),
            json!({
                "code": 0,
                "music.srfDissInfo.DissInfo": {
                    "code": 0,
                    "data": {
                        "code": 0,
                        "songlist": [{
                            "id": 1,
                            "mid": "mustNotLeakMid",
                            "title": "must-not-leak-title",
                            "type": 0,
                            "singer": [{"name": ""}]
                        }],
                        "total_song_num": 1,
                        "hasmore": false
                    }
                }
            }),
        ]));

        assert!(matches!(
            client.playlist_tracks_page(&credential(), 1, 0, 100).await,
            Err(QqMusicPlaylistDetailError::InvalidHasMore)
        ));
        let error = client
            .playlist_tracks_page(&credential(), 1, 0, 100)
            .await
            .expect_err("empty artist name must fail");
        assert!(matches!(
            error,
            QqMusicPlaylistDetailError::InvalidArtist {
                track_index: 0,
                artist_index: 0,
                field: PlaylistDetailTrackField::ArtistName,
            }
        ));
        assert!(!format!("{error:?}").contains("must-not-leak"));
    }
}
