use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::{
    HttpRequest, HttpTransport, QqMusicAlbumSummary, QqMusicArtistSummary, QqMusicClient,
    QqMusicTrackSummary,
};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_PAGE_SIZE: u32 = 30;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ArtistTrackField {
    Wrapper,
    TrackId,
    SongMid,
    FileMediaMid,
    Title,
    SongType,
    Artists,
    ArtistName,
}

pub enum QqMusicArtistTracksError<E> {
    InvalidArtistId,
    InvalidArtistMid,
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
    Upstream {
        global_code: i64,
        result_code: Option<i64>,
    },
    MissingData,
    MissingArtistMid,
    MismatchedArtistMid,
    MissingTotal,
    MissingTracks,
    InvalidPagination,
    InvalidTrack {
        index: usize,
        field: ArtistTrackField,
    },
    InvalidArtist {
        track_index: usize,
        artist_index: usize,
    },
}

impl<E> fmt::Debug for QqMusicArtistTracksError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidArtistId => formatter.write_str("InvalidArtistId([REDACTED])"),
            Self::InvalidArtistMid => formatter.write_str("InvalidArtistMid([REDACTED])"),
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
            Self::Upstream {
                global_code,
                result_code,
            } => formatter
                .debug_struct("Upstream")
                .field("global_code", global_code)
                .field("result_code", result_code)
                .finish(),
            Self::MissingData => formatter.write_str("MissingData"),
            Self::MissingArtistMid => formatter.write_str("MissingArtistMid"),
            Self::MismatchedArtistMid => formatter.write_str("MismatchedArtistMid([REDACTED])"),
            Self::MissingTotal => formatter.write_str("MissingTotal"),
            Self::MissingTracks => formatter.write_str("MissingTracks"),
            Self::InvalidPagination => formatter.write_str("InvalidPagination"),
            Self::InvalidTrack { index, field } => formatter
                .debug_struct("InvalidTrack")
                .field("index", index)
                .field("field", field)
                .finish(),
            Self::InvalidArtist {
                track_index,
                artist_index,
            } => formatter
                .debug_struct("InvalidArtist")
                .field("track_index", track_index)
                .field("artist_index", artist_index)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicArtistTracksError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidArtistId => formatter.write_str("artist ID is invalid"),
            Self::InvalidArtistMid => formatter.write_str("artist MID is invalid"),
            Self::InvalidPageSize { size } => {
                write!(
                    formatter,
                    "artist page size {size} is outside 1..={MAX_PAGE_SIZE}"
                )
            }
            Self::Transport(_) => formatter.write_str("QQ Music Artist request failed"),
            Self::Serialize => formatter.write_str("could not serialize Artist request"),
            Self::HttpStatus(status) => write!(formatter, "Artist request returned HTTP {status}"),
            Self::InvalidJson => formatter.write_str("Artist response was not valid JSON"),
            Self::MissingGlobalCode => formatter.write_str("Artist response has no global code"),
            Self::MissingResult => formatter.write_str("Artist result is missing"),
            Self::MissingResultCode => formatter.write_str("Artist result has no code"),
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "Artist request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("Artist data is missing"),
            Self::MissingArtistMid => formatter.write_str("Artist MID is missing"),
            Self::MismatchedArtistMid => {
                formatter.write_str("Artist MID did not match the request")
            }
            Self::MissingTotal => formatter.write_str("Artist Track total is missing"),
            Self::MissingTracks => formatter.write_str("Artist Track list is missing"),
            Self::InvalidPagination => formatter.write_str("Artist pagination is invalid"),
            Self::InvalidTrack { index, field } => {
                write!(formatter, "Artist Track {index} has an invalid {field:?}")
            }
            Self::InvalidArtist {
                track_index,
                artist_index,
            } => write!(
                formatter,
                "Artist Track {track_index} credited Artist {artist_index} is invalid"
            ),
        }
    }
}

impl<E> std::error::Error for QqMusicArtistTracksError<E>
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
pub struct QqMusicArtistTrackPage {
    offset: u32,
    total: u32,
    has_more: bool,
    tracks: Vec<QqMusicTrackSummary>,
}

impl QqMusicArtistTrackPage {
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

impl fmt::Debug for QqMusicArtistTrackPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicArtistTrackPage")
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
    /// Loads one public offset-paged Artist Track list without account material.
    ///
    /// # Errors
    ///
    /// Keeps input, transport, service, response-shape, pagination, and Track
    /// mapping failures distinct without retaining Artist or Track content.
    pub async fn artist_tracks(
        &self,
        artist_id: u64,
        expected_mid: &str,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicArtistTrackPage, QqMusicArtistTracksError<T::Error>> {
        if artist_id == 0 {
            return Err(QqMusicArtistTracksError::InvalidArtistId);
        }
        if !safe_mid(expected_mid) {
            return Err(QqMusicArtistTracksError::InvalidArtistMid);
        }
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicArtistTracksError::InvalidPageSize { size });
        }
        let body = serde_json::to_vec(&ArtistTracksRequest::new(artist_id, offset, size))
            .map_err(|_| QqMusicArtistTracksError::Serialize)?;
        self.execute_artist_tracks(body, expected_mid, offset, size)
            .await
    }

    /// Loads one public Artist Track page using only the validated Artist MID.
    ///
    /// This is the independently evidenced QQ route used when an account
    /// collection does not expose the optional numeric Artist identity.
    ///
    /// # Errors
    ///
    /// Preserves the same validation and response mapping as
    /// [`Self::artist_tracks`] without inventing a numeric identity.
    pub async fn artist_tracks_by_mid(
        &self,
        expected_mid: &str,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicArtistTrackPage, QqMusicArtistTracksError<T::Error>> {
        if !safe_mid(expected_mid) {
            return Err(QqMusicArtistTracksError::InvalidArtistMid);
        }
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicArtistTracksError::InvalidPageSize { size });
        }
        let body = serde_json::to_vec(&MidArtistTracksRequest::new(expected_mid, offset, size))
            .map_err(|_| QqMusicArtistTracksError::Serialize)?;
        self.execute_artist_tracks(body, expected_mid, offset, size)
            .await
    }

    async fn execute_artist_tracks(
        &self,
        body: Vec<u8>,
        expected_mid: &str,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicArtistTrackPage, QqMusicArtistTracksError<T::Error>> {
        let response = self
            .transport()
            .execute(
                HttpRequest::post(MUSICU_URL)
                    .header("Content-Type", "application/json")
                    .header("Origin", "https://y.qq.com")
                    .header("Referer", "https://y.qq.com/")
                    .body(body)
                    .response_body_limit(MAX_RESPONSE_BYTES)
                    .timeout(REQUEST_TIMEOUT),
            )
            .await
            .map_err(QqMusicArtistTracksError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicArtistTracksError::HttpStatus(response.status()));
        }
        let envelope: ArtistTracksResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicArtistTracksError::InvalidJson)?;
        map_response(envelope, expected_mid, offset, size)
    }
}

#[derive(Serialize)]
struct ArtistTracksRequest {
    comm: ArtistComm,
    #[serde(rename = "artistSongs")]
    artist_songs: ArtistTracksRpc,
}

impl ArtistTracksRequest {
    const fn new(artist_id: u64, offset: u32, size: u32) -> Self {
        Self {
            comm: ArtistComm {
                client_type: 20,
                client_version: 1770,
                token: 5381,
                uin: "0",
                format: "json",
                input_charset: "utf-8",
                output_charset: "utf-8",
                platform: "wk_v17",
                uid: "",
                guid: "",
            },
            artist_songs: ArtistTracksRpc {
                module: "music.musichallSong.SongListInter",
                method: "GetSingerSongList",
                param: ArtistTracksParam {
                    artist_id,
                    offset,
                    size,
                    order: 1,
                    new_song: 1,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct ArtistComm {
    #[serde(rename = "ct")]
    client_type: u32,
    #[serde(rename = "cv")]
    client_version: u32,
    #[serde(rename = "g_tk")]
    token: u32,
    uin: &'static str,
    format: &'static str,
    #[serde(rename = "inCharset")]
    input_charset: &'static str,
    #[serde(rename = "outCharset")]
    output_charset: &'static str,
    platform: &'static str,
    uid: &'static str,
    guid: &'static str,
}

#[derive(Serialize)]
struct ArtistTracksRpc {
    module: &'static str,
    method: &'static str,
    param: ArtistTracksParam,
}

#[derive(Serialize)]
struct ArtistTracksParam {
    #[serde(rename = "singerid")]
    artist_id: u64,
    #[serde(rename = "begin")]
    offset: u32,
    #[serde(rename = "num")]
    size: u32,
    order: u8,
    #[serde(rename = "newsong")]
    new_song: u8,
}

#[derive(Serialize)]
struct MidArtistTracksRequest<'a> {
    comm: ArtistComm,
    #[serde(rename = "artistSongs")]
    artist_songs: MidArtistTracksRpc<'a>,
}

impl<'a> MidArtistTracksRequest<'a> {
    const fn new(artist_mid: &'a str, offset: u32, size: u32) -> Self {
        Self {
            comm: ArtistComm {
                client_type: 20,
                client_version: 1770,
                token: 5381,
                uin: "0",
                format: "json",
                input_charset: "utf-8",
                output_charset: "utf-8",
                platform: "wk_v17",
                uid: "",
                guid: "",
            },
            artist_songs: MidArtistTracksRpc {
                module: "musichall.song_list_server",
                method: "GetSingerSongList",
                param: MidArtistTracksParam {
                    artist_mid,
                    offset,
                    size,
                    order: 1,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct MidArtistTracksRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: MidArtistTracksParam<'a>,
}

#[derive(Serialize)]
struct MidArtistTracksParam<'a> {
    #[serde(rename = "singerMid")]
    artist_mid: &'a str,
    #[serde(rename = "begin")]
    offset: u32,
    #[serde(rename = "number")]
    size: u32,
    order: u8,
}

#[derive(Deserialize)]
struct ArtistTracksResponse {
    code: Option<i64>,
    #[serde(rename = "artistSongs")]
    artist_songs: Option<ArtistTracksResult>,
}

#[derive(Deserialize)]
struct ArtistTracksResult {
    code: Option<i64>,
    data: Option<ArtistTracksData>,
}

#[derive(Deserialize)]
struct ArtistTracksData {
    #[serde(rename = "singerMid")]
    artist_mid: Option<String>,
    #[serde(rename = "totalNum")]
    total: Option<u32>,
    #[serde(rename = "songList")]
    tracks: Option<Vec<RawArtistTrackWrapper>>,
}

#[derive(Deserialize)]
struct RawArtistTrackWrapper {
    #[serde(rename = "songInfo")]
    track: Option<RawArtistTrack>,
}

#[derive(Deserialize)]
struct RawArtistTrack {
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
    envelope: ArtistTracksResponse,
    requested_mid: &str,
    requested_offset: u32,
    requested_size: u32,
) -> Result<QqMusicArtistTrackPage, QqMusicArtistTracksError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicArtistTracksError::MissingGlobalCode)?;
    let result_code = envelope
        .artist_songs
        .as_ref()
        .and_then(|result| result.code);
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicArtistTracksError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .artist_songs
        .ok_or(QqMusicArtistTracksError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicArtistTracksError::MissingResultCode)?;
    let data = result.data.ok_or(QqMusicArtistTracksError::MissingData)?;
    let artist_mid = data
        .artist_mid
        .ok_or(QqMusicArtistTracksError::MissingArtistMid)?;
    if artist_mid != requested_mid {
        return Err(QqMusicArtistTracksError::MismatchedArtistMid);
    }
    let total = data.total.ok_or(QqMusicArtistTracksError::MissingTotal)?;
    if requested_offset > total {
        return Err(QqMusicArtistTracksError::InvalidPagination);
    }
    let raw_tracks = data.tracks.ok_or(QqMusicArtistTracksError::MissingTracks)?;
    let count =
        u32::try_from(raw_tracks.len()).map_err(|_| QqMusicArtistTracksError::InvalidPagination)?;
    if count > requested_size {
        return Err(QqMusicArtistTracksError::InvalidPagination);
    }
    let end = requested_offset
        .checked_add(count)
        .ok_or(QqMusicArtistTracksError::InvalidPagination)?;
    if end > total {
        return Err(QqMusicArtistTracksError::InvalidPagination);
    }
    let has_more = end < total;
    if has_more && raw_tracks.is_empty() {
        return Err(QqMusicArtistTracksError::InvalidPagination);
    }
    let tracks = raw_tracks
        .into_iter()
        .enumerate()
        .map(|(index, wrapper)| {
            let raw = wrapper
                .track
                .ok_or(QqMusicArtistTracksError::InvalidTrack {
                    index,
                    field: ArtistTrackField::Wrapper,
                })?;
            map_track(raw, index)
        })
        .collect::<Result<Vec<_>, _>>()?;
    Ok(QqMusicArtistTrackPage {
        offset: requested_offset,
        total,
        has_more,
        tracks,
    })
}

fn map_track<E>(
    raw: RawArtistTrack,
    index: usize,
) -> Result<QqMusicTrackSummary, QqMusicArtistTracksError<E>> {
    let track_id =
        raw.id
            .filter(|value| *value != 0)
            .ok_or(QqMusicArtistTracksError::InvalidTrack {
                index,
                field: ArtistTrackField::TrackId,
            })?;
    let song_mid = safe_media_mid(raw.mid).ok_or(QqMusicArtistTracksError::InvalidTrack {
        index,
        field: ArtistTrackField::SongMid,
    })?;
    let file_media_mid = match raw.file.and_then(|file| file.media_mid) {
        Some(value) if value.trim().is_empty() => None,
        Some(value) => Some(safe_media_mid(Some(value)).ok_or(
            QqMusicArtistTracksError::InvalidTrack {
                index,
                field: ArtistTrackField::FileMediaMid,
            },
        )?),
        None => None,
    };
    let title = nonblank(raw.title).or_else(|| nonblank(raw.name)).ok_or(
        QqMusicArtistTracksError::InvalidTrack {
            index,
            field: ArtistTrackField::Title,
        },
    )?;
    let song_type = raw
        .song_type
        .ok_or(QqMusicArtistTracksError::InvalidTrack {
            index,
            field: ArtistTrackField::SongType,
        })?;
    let raw_artists = raw.singer.ok_or(QqMusicArtistTracksError::InvalidTrack {
        index,
        field: ArtistTrackField::Artists,
    })?;
    let artists = raw_artists
        .into_iter()
        .enumerate()
        .map(|(artist_index, artist)| {
            let name = nonblank(artist.name).ok_or(QqMusicArtistTracksError::InvalidArtist {
                track_index: index,
                artist_index,
            })?;
            Ok(QqMusicArtistSummary::new(
                artist.id.filter(|value| *value != 0),
                nonblank(artist.mid),
                name,
            ))
        })
        .collect::<Result<Vec<_>, _>>()?;
    let album = raw.album.map(|album| {
        QqMusicAlbumSummary::new(
            album.id.filter(|value| *value != 0),
            nonblank(album.mid).or_else(|| nonblank(album.pmid)),
            nonblank(album.title).or_else(|| nonblank(album.name)),
        )
    });
    Ok(QqMusicTrackSummary::new(
        track_id,
        song_mid,
        file_media_mid,
        title,
        nonblank(raw.subtitle),
        song_type,
        raw.interval.unwrap_or(0),
        artists,
        album,
    ))
}

fn nonblank(value: Option<String>) -> Option<String> {
    value.filter(|value| !value.trim().is_empty())
}

fn safe_mid(value: &str) -> bool {
    !value.is_empty() && value.len() <= 64 && value.bytes().all(|byte| byte.is_ascii_alphanumeric())
}

fn safe_media_mid(value: Option<String>) -> Option<String> {
    nonblank(value).filter(|value| safe_mid(value))
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use crate::{HttpMethod, HttpRequest, HttpResponse, HttpTransport, QqMusicClient};

    use super::QqMusicArtistTracksError;

    struct ArtistTransport {
        response: HttpResponse,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl ArtistTransport {
        fn new(response: &Value) -> Self {
            Self {
                response: HttpResponse::new(
                    200,
                    serde_json::to_vec(response).expect("fixture JSON"),
                ),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn requests(&self) -> Vec<HttpRequest> {
            self.requests.lock().expect("request lock").clone()
        }
    }

    impl HttpTransport for ArtistTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("request lock").push(request);
            Ok(self.response.clone())
        }
    }

    #[tokio::test]
    async fn serializes_evidenced_artist_page_and_maps_tracks() {
        let client = QqMusicClient::new(ArtistTransport::new(&artist_page_json(
            "fixtureArtistMid",
            31,
            &synthetic_tracks(),
        )));
        let page = client
            .artist_tracks(42001, "fixtureArtistMid", 30, 5)
            .await
            .expect("Artist page");

        assert_eq!(page.offset(), 30);
        assert_eq!(page.total(), 31);
        assert!(!page.has_more());
        assert_eq!(page.tracks().len(), 1);
        assert_eq!(page.tracks()[0].song_mid(), "fixtureTrackMid1");
        let requests = client.transport().requests();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].method(), HttpMethod::Post);
        assert_eq!(requests[0].max_response_body_bytes(), 2 * 1024 * 1024);
        let body: Value = serde_json::from_slice(requests[0].body_bytes().expect("request body"))
            .expect("request JSON");
        assert_eq!(body["comm"]["ct"], 20);
        assert_eq!(
            body["artistSongs"]["module"],
            "music.musichallSong.SongListInter"
        );
        assert_eq!(body["artistSongs"]["method"], "GetSingerSongList");
        assert_eq!(body["artistSongs"]["param"]["singerid"], 42001);
        assert_eq!(body["artistSongs"]["param"]["begin"], 30);
        assert_eq!(body["artistSongs"]["param"]["num"], 5);
        assert_eq!(body["artistSongs"]["param"]["newsong"], 1);
        let debug = format!("{page:?} {:?}", requests[0]);
        assert!(!debug.contains("fixtureArtistMid"));
        assert!(!debug.contains("Synthetic Track"));
    }

    #[tokio::test]
    async fn serializes_evidenced_mid_only_artist_page_without_fabricating_id() {
        let client = QqMusicClient::new(ArtistTransport::new(&artist_page_json(
            "fixtureArtistMid",
            1,
            &synthetic_tracks(),
        )));
        let page = client
            .artist_tracks_by_mid("fixtureArtistMid", 0, 20)
            .await
            .expect("MID-only Artist page");

        assert_eq!(page.tracks().len(), 1);
        let requests = client.transport().requests();
        assert_eq!(requests.len(), 1);
        let body: Value = serde_json::from_slice(requests[0].body_bytes().expect("request body"))
            .expect("request JSON");
        assert_eq!(body["artistSongs"]["module"], "musichall.song_list_server");
        assert_eq!(body["artistSongs"]["method"], "GetSingerSongList");
        assert_eq!(
            body["artistSongs"]["param"]["singerMid"],
            "fixtureArtistMid"
        );
        assert_eq!(body["artistSongs"]["param"]["begin"], 0);
        assert_eq!(body["artistSongs"]["param"]["number"], 20);
        assert!(body["artistSongs"]["param"].get("singerid").is_none());
    }

    #[tokio::test]
    async fn rejects_invalid_input_and_pagination_without_transport_or_content_leak() {
        let client = QqMusicClient::new(ArtistTransport::new(&artist_page_json(
            "fixtureArtistMid",
            0,
            &json!([]),
        )));
        assert!(matches!(
            client.artist_tracks(0, "fixtureArtistMid", 0, 5).await,
            Err(QqMusicArtistTracksError::InvalidArtistId)
        ));
        assert!(matches!(
            client.artist_tracks(42001, "unsafe/mid", 0, 5).await,
            Err(QqMusicArtistTracksError::InvalidArtistMid)
        ));
        assert!(matches!(
            client.artist_tracks(42001, "safeMid", 0, 31).await,
            Err(QqMusicArtistTracksError::InvalidPageSize { size: 31 })
        ));
        assert!(matches!(
            client.artist_tracks_by_mid("unsafe/mid", 0, 5).await,
            Err(QqMusicArtistTracksError::InvalidArtistMid)
        ));
        assert!(client.transport().requests().is_empty());

        let invalid = QqMusicClient::new(ArtistTransport::new(&artist_page_json(
            "fixtureArtistMid",
            1,
            &synthetic_tracks(),
        )))
        .artist_tracks(42001, "fixtureArtistMid", 1, 5)
        .await
        .expect_err("wrong pagination");
        assert!(matches!(
            invalid,
            QqMusicArtistTracksError::InvalidPagination
        ));
        assert!(!format!("{invalid:?} {invalid}").contains("Synthetic Track"));
    }

    fn artist_page_json(artist_mid: &str, total: u32, tracks: &Value) -> Value {
        json!({
            "code": 0,
            "artistSongs": {
                "code": 0,
                "data": {
                    "singerMid": artist_mid,
                    "totalNum": total,
                    "songList": tracks
                }
            }
        })
    }

    fn synthetic_tracks() -> Value {
        json!([{"songInfo": {
            "id": 41001,
            "mid": "fixtureTrackMid1",
            "title": "Synthetic Track",
            "subtitle": "Synthetic subtitle",
            "type": 0,
            "interval": 245,
            "file": {"media_mid": "fixtureFileMid1"},
            "singer": [{"id": 42001, "mid": "fixtureArtistMid", "name": "Artist one"}],
            "album": {"id": 43001, "mid": "fixtureAlbumMid", "name": "Synthetic album"}
        }}])
    }
}
