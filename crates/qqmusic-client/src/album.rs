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
pub enum AlbumTrackField {
    Wrapper,
    TrackId,
    SongMid,
    FileMediaMid,
    Title,
    SongType,
    Artists,
    ArtistName,
}

pub enum QqMusicAlbumTracksError<E> {
    InvalidAlbumMid,
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
    MissingAlbumMid,
    MismatchedAlbumMid,
    MissingOffset,
    MissingTotal,
    MissingTracks,
    InvalidPagination,
    InvalidTrack {
        index: usize,
        field: AlbumTrackField,
    },
    InvalidArtist {
        track_index: usize,
        artist_index: usize,
    },
}

impl<E> fmt::Debug for QqMusicAlbumTracksError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidAlbumMid => formatter.write_str("InvalidAlbumMid([REDACTED])"),
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
            Self::MissingAlbumMid => formatter.write_str("MissingAlbumMid"),
            Self::MismatchedAlbumMid => formatter.write_str("MismatchedAlbumMid([REDACTED])"),
            Self::MissingOffset => formatter.write_str("MissingOffset"),
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

impl<E> fmt::Display for QqMusicAlbumTracksError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidAlbumMid => formatter.write_str("album MID is invalid"),
            Self::InvalidPageSize { size } => {
                write!(
                    formatter,
                    "album page size {size} is outside 1..={MAX_PAGE_SIZE}"
                )
            }
            Self::Transport(_) => formatter.write_str("QQ Music Album request failed"),
            Self::Serialize => formatter.write_str("could not serialize Album request"),
            Self::HttpStatus(status) => write!(formatter, "Album request returned HTTP {status}"),
            Self::InvalidJson => formatter.write_str("Album response was not valid JSON"),
            Self::MissingGlobalCode => formatter.write_str("Album response has no global code"),
            Self::MissingResult => formatter.write_str("Album result is missing"),
            Self::MissingResultCode => formatter.write_str("Album result has no code"),
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "Album request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("Album data is missing"),
            Self::MissingAlbumMid => formatter.write_str("Album MID is missing"),
            Self::MismatchedAlbumMid => formatter.write_str("Album MID did not match the request"),
            Self::MissingOffset => formatter.write_str("Album page offset is missing"),
            Self::MissingTotal => formatter.write_str("Album Track total is missing"),
            Self::MissingTracks => formatter.write_str("Album Track list is missing"),
            Self::InvalidPagination => formatter.write_str("Album pagination is invalid"),
            Self::InvalidTrack { index, field } => {
                write!(formatter, "Album Track {index} has an invalid {field:?}")
            }
            Self::InvalidArtist {
                track_index,
                artist_index,
            } => write!(
                formatter,
                "Album Track {track_index} artist {artist_index} is invalid"
            ),
        }
    }
}

impl<E> std::error::Error for QqMusicAlbumTracksError<E>
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
pub struct QqMusicAlbumTrackPage {
    offset: u32,
    total: u32,
    has_more: bool,
    tracks: Vec<QqMusicTrackSummary>,
}

impl QqMusicAlbumTrackPage {
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

impl fmt::Debug for QqMusicAlbumTrackPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicAlbumTrackPage")
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
    /// Loads one public offset-paged Album Track list without account material.
    ///
    /// # Errors
    ///
    /// Keeps input, transport, service, response-shape, pagination, and Track
    /// mapping failures distinct without retaining Album or Track content.
    pub async fn album_tracks(
        &self,
        album_mid: &str,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicAlbumTrackPage, QqMusicAlbumTracksError<T::Error>> {
        if !safe_mid(album_mid) {
            return Err(QqMusicAlbumTracksError::InvalidAlbumMid);
        }
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicAlbumTracksError::InvalidPageSize { size });
        }
        let body = serde_json::to_vec(&AlbumTracksRequest::new(album_mid, offset, size))
            .map_err(|_| QqMusicAlbumTracksError::Serialize)?;
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
            .map_err(QqMusicAlbumTracksError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicAlbumTracksError::HttpStatus(response.status()));
        }
        let envelope: AlbumTracksResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicAlbumTracksError::InvalidJson)?;
        map_response(envelope, album_mid, offset)
    }
}

#[derive(Serialize)]
struct AlbumTracksRequest<'a> {
    comm: AlbumComm,
    #[serde(rename = "albumSongs")]
    album_songs: AlbumTracksRpc<'a>,
}

impl<'a> AlbumTracksRequest<'a> {
    const fn new(album_mid: &'a str, offset: u32, size: u32) -> Self {
        Self {
            comm: AlbumComm {
                client_type: "19",
                client_version: "1859",
                format: "json",
                input_charset: "utf-8",
                output_charset: "utf-8",
                platform: "yqq.json",
                need_new_code: 1,
            },
            album_songs: AlbumTracksRpc {
                module: "music.musichallAlbum.AlbumSongList",
                method: "GetAlbumSongList",
                param: AlbumTracksParam {
                    album_mid,
                    offset,
                    size,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct AlbumComm {
    #[serde(rename = "ct")]
    client_type: &'static str,
    #[serde(rename = "cv")]
    client_version: &'static str,
    format: &'static str,
    #[serde(rename = "inCharset")]
    input_charset: &'static str,
    #[serde(rename = "outCharset")]
    output_charset: &'static str,
    platform: &'static str,
    #[serde(rename = "needNewCode")]
    need_new_code: u8,
}

#[derive(Serialize)]
struct AlbumTracksRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: AlbumTracksParam<'a>,
}

#[derive(Serialize)]
struct AlbumTracksParam<'a> {
    #[serde(rename = "albumMid")]
    album_mid: &'a str,
    #[serde(rename = "begin")]
    offset: u32,
    #[serde(rename = "num")]
    size: u32,
}

#[derive(Deserialize)]
struct AlbumTracksResponse {
    code: Option<i64>,
    #[serde(rename = "albumSongs")]
    album_songs: Option<AlbumTracksResult>,
}

#[derive(Deserialize)]
struct AlbumTracksResult {
    code: Option<i64>,
    data: Option<AlbumTracksData>,
}

#[derive(Deserialize)]
struct AlbumTracksData {
    #[serde(rename = "albumMid")]
    album_mid: Option<String>,
    #[serde(rename = "curBegin")]
    offset: Option<u32>,
    #[serde(rename = "totalNum")]
    total: Option<u32>,
    #[serde(rename = "songList")]
    tracks: Option<Vec<RawAlbumTrackWrapper>>,
}

#[derive(Deserialize)]
struct RawAlbumTrackWrapper {
    #[serde(rename = "songInfo")]
    track: Option<RawAlbumTrack>,
}

#[derive(Deserialize)]
struct RawAlbumTrack {
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
    envelope: AlbumTracksResponse,
    requested_mid: &str,
    requested_offset: u32,
) -> Result<QqMusicAlbumTrackPage, QqMusicAlbumTracksError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicAlbumTracksError::MissingGlobalCode)?;
    let result_code = envelope.album_songs.as_ref().and_then(|result| result.code);
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicAlbumTracksError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .album_songs
        .ok_or(QqMusicAlbumTracksError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicAlbumTracksError::MissingResultCode)?;
    let data = result.data.ok_or(QqMusicAlbumTracksError::MissingData)?;
    let album_mid = data
        .album_mid
        .ok_or(QqMusicAlbumTracksError::MissingAlbumMid)?;
    if album_mid != requested_mid {
        return Err(QqMusicAlbumTracksError::MismatchedAlbumMid);
    }
    let offset = data.offset.ok_or(QqMusicAlbumTracksError::MissingOffset)?;
    let total = data.total.ok_or(QqMusicAlbumTracksError::MissingTotal)?;
    if offset != requested_offset || offset > total {
        return Err(QqMusicAlbumTracksError::InvalidPagination);
    }
    let raw_tracks = data.tracks.ok_or(QqMusicAlbumTracksError::MissingTracks)?;
    let count =
        u32::try_from(raw_tracks.len()).map_err(|_| QqMusicAlbumTracksError::InvalidPagination)?;
    let end = offset
        .checked_add(count)
        .ok_or(QqMusicAlbumTracksError::InvalidPagination)?;
    if end > total {
        return Err(QqMusicAlbumTracksError::InvalidPagination);
    }
    let has_more = end < total;
    if has_more && raw_tracks.is_empty() {
        return Err(QqMusicAlbumTracksError::InvalidPagination);
    }
    let tracks = raw_tracks
        .into_iter()
        .enumerate()
        .map(|(index, wrapper)| {
            let raw = wrapper.track.ok_or(QqMusicAlbumTracksError::InvalidTrack {
                index,
                field: AlbumTrackField::Wrapper,
            })?;
            map_track(raw, index)
        })
        .collect::<Result<Vec<_>, _>>()?;
    Ok(QqMusicAlbumTrackPage {
        offset,
        total,
        has_more,
        tracks,
    })
}

fn map_track<E>(
    raw: RawAlbumTrack,
    index: usize,
) -> Result<QqMusicTrackSummary, QqMusicAlbumTracksError<E>> {
    let track_id =
        raw.id
            .filter(|value| *value != 0)
            .ok_or(QqMusicAlbumTracksError::InvalidTrack {
                index,
                field: AlbumTrackField::TrackId,
            })?;
    let song_mid =
        raw.mid
            .filter(|value| safe_mid(value))
            .ok_or(QqMusicAlbumTracksError::InvalidTrack {
                index,
                field: AlbumTrackField::SongMid,
            })?;
    let file_media_mid = match raw.file.and_then(|file| file.media_mid) {
        Some(value) if value.trim().is_empty() => None,
        Some(value) if safe_mid(&value) => Some(value),
        Some(_) => {
            return Err(QqMusicAlbumTracksError::InvalidTrack {
                index,
                field: AlbumTrackField::FileMediaMid,
            });
        }
        None => None,
    };
    let title = nonblank(raw.title).or_else(|| nonblank(raw.name)).ok_or(
        QqMusicAlbumTracksError::InvalidTrack {
            index,
            field: AlbumTrackField::Title,
        },
    )?;
    let song_type = raw.song_type.ok_or(QqMusicAlbumTracksError::InvalidTrack {
        index,
        field: AlbumTrackField::SongType,
    })?;
    let raw_artists = raw.singer.ok_or(QqMusicAlbumTracksError::InvalidTrack {
        index,
        field: AlbumTrackField::Artists,
    })?;
    let artists = raw_artists
        .into_iter()
        .enumerate()
        .map(|(artist_index, artist)| {
            let name = nonblank(artist.name).ok_or(QqMusicAlbumTracksError::InvalidArtist {
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

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use crate::{HttpMethod, HttpRequest, HttpResponse, HttpTransport, QqMusicClient};

    use super::QqMusicAlbumTracksError;

    struct AlbumTransport {
        response: HttpResponse,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl AlbumTransport {
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

    impl HttpTransport for AlbumTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("request lock").push(request);
            Ok(self.response.clone())
        }
    }

    #[tokio::test]
    async fn serializes_evidenced_album_page_and_maps_tracks() {
        let client = QqMusicClient::new(AlbumTransport::new(&album_page_json(
            30,
            31,
            &synthetic_tracks(),
        )));
        let page = client
            .album_tracks("fixtureAlbumMid", 30, 5)
            .await
            .expect("Album page");

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
        assert_eq!(
            body["albumSongs"]["module"],
            "music.musichallAlbum.AlbumSongList"
        );
        assert_eq!(body["albumSongs"]["method"], "GetAlbumSongList");
        assert_eq!(body["albumSongs"]["param"]["albumMid"], "fixtureAlbumMid");
        assert_eq!(body["albumSongs"]["param"]["begin"], 30);
        assert_eq!(body["albumSongs"]["param"]["num"], 5);
        let debug = format!("{page:?} {:?}", requests[0]);
        assert!(!debug.contains("fixtureAlbumMid"));
        assert!(!debug.contains("Synthetic Track"));
    }

    #[tokio::test]
    async fn rejects_invalid_input_and_pagination_without_transport_or_content_leak() {
        let client = QqMusicClient::new(AlbumTransport::new(&album_page_json(0, 0, &json!([]))));
        assert!(matches!(
            client.album_tracks("unsafe/mid", 0, 5).await,
            Err(QqMusicAlbumTracksError::InvalidAlbumMid)
        ));
        assert!(matches!(
            client.album_tracks("safeMid", 0, 31).await,
            Err(QqMusicAlbumTracksError::InvalidPageSize { size: 31 })
        ));
        assert!(client.transport().requests().is_empty());

        let invalid = QqMusicClient::new(AlbumTransport::new(&album_page_json(
            5,
            1,
            &synthetic_tracks(),
        )))
        .album_tracks("fixtureAlbumMid", 0, 5)
        .await
        .expect_err("wrong pagination");
        assert!(matches!(
            invalid,
            QqMusicAlbumTracksError::InvalidPagination
        ));
        assert!(!format!("{invalid:?} {invalid}").contains("Synthetic Track"));
    }

    fn album_page_json(offset: u32, total: u32, tracks: &Value) -> Value {
        json!({
            "code": 0,
            "albumSongs": {
                "code": 0,
                "data": {
                    "albumMid": "fixtureAlbumMid",
                    "curBegin": offset,
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
            "singer": [{"id": 42001, "mid": "artistOneMid", "name": "Artist one"}],
            "album": {"id": 43001, "mid": "fixtureAlbumMid", "name": "Synthetic album"}
        }}])
    }
}
