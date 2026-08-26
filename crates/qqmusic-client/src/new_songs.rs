use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::{
    HttpRequest, HttpTransport, QqMusicAlbumSummary, QqMusicArtistSummary, QqMusicClient,
    QqMusicTrackSummary,
};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const MAX_TRACKS: usize = 200;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicNewSongCategory {
    MainlandChina,
    Western,
    Japan,
    Korea,
    Latest,
    HongKongTaiwan,
}

impl QqMusicNewSongCategory {
    const fn code(self) -> u8 {
        match self {
            Self::MainlandChina => 1,
            Self::Western => 2,
            Self::Japan => 3,
            Self::Korea => 4,
            Self::Latest => 5,
            Self::HongKongTaiwan => 6,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NewSongTrackField {
    TrackId,
    SongMid,
    FileMediaMid,
    Title,
    SongType,
    Artists,
}

pub enum QqMusicNewSongsError<E> {
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
    MissingReturnedCategory,
    MismatchedCategory,
    MissingTracks,
    TooManyTracks {
        count: usize,
    },
    InvalidTrack {
        index: usize,
        field: NewSongTrackField,
    },
    InvalidArtist {
        track_index: usize,
        artist_index: usize,
    },
}

impl<E> fmt::Debug for QqMusicNewSongsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
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
            Self::MissingReturnedCategory => formatter.write_str("MissingReturnedCategory"),
            Self::MismatchedCategory => formatter.write_str("MismatchedCategory"),
            Self::MissingTracks => formatter.write_str("MissingTracks"),
            Self::TooManyTracks { count } => formatter
                .debug_struct("TooManyTracks")
                .field("count", count)
                .finish(),
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

impl<E> fmt::Display for QqMusicNewSongsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Transport(_) => formatter.write_str("QQ Music new-song request failed"),
            Self::Serialize => formatter.write_str("could not serialize new-song request"),
            Self::HttpStatus(status) => {
                write!(formatter, "new-song request returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("new-song response was not valid JSON"),
            Self::MissingGlobalCode => formatter.write_str("new-song response has no global code"),
            Self::MissingResult => formatter.write_str("new-song result is missing"),
            Self::MissingResultCode => formatter.write_str("new-song result has no code"),
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "new-song request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("new-song data is missing"),
            Self::MissingReturnedCategory => {
                formatter.write_str("new-song response has no returned category")
            }
            Self::MismatchedCategory => {
                formatter.write_str("new-song response returned a different category")
            }
            Self::MissingTracks => formatter.write_str("new-song Track array is missing"),
            Self::TooManyTracks { count } => {
                write!(
                    formatter,
                    "new-song response contains too many Tracks ({count})"
                )
            }
            Self::InvalidTrack { index, field } => {
                write!(formatter, "new-song Track {index} has an invalid {field:?}")
            }
            Self::InvalidArtist {
                track_index,
                artist_index,
            } => write!(
                formatter,
                "new-song Track {track_index} has an invalid Artist at {artist_index}"
            ),
        }
    }
}

impl<E> std::error::Error for QqMusicNewSongsError<E>
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
pub struct QqMusicNewSongCollection {
    category: QqMusicNewSongCategory,
    tracks: Vec<QqMusicTrackSummary>,
}

impl QqMusicNewSongCollection {
    #[must_use]
    pub const fn category(&self) -> QqMusicNewSongCategory {
        self.category
    }

    #[must_use]
    pub fn tracks(&self) -> &[QqMusicTrackSummary] {
        &self.tracks
    }
}

impl fmt::Debug for QqMusicNewSongCollection {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicNewSongCollection")
            .field("category", &self.category)
            .field("track_count", &self.tracks.len())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Loads one bounded, anonymous QQ Music new-song collection.
    ///
    /// # Errors
    ///
    /// Keeps transport, service, response-shape, returned-category, size, and
    /// Track-mapping failures distinct without retaining returned content.
    pub async fn new_songs(
        &self,
        category: QqMusicNewSongCategory,
    ) -> Result<QqMusicNewSongCollection, QqMusicNewSongsError<T::Error>> {
        let body = serde_json::to_vec(&NewSongsRequest::new(category))
            .map_err(|_| QqMusicNewSongsError::Serialize)?;
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
            .map_err(QqMusicNewSongsError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicNewSongsError::HttpStatus(response.status()));
        }
        let envelope: NewSongsResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicNewSongsError::InvalidJson)?;
        map_response(envelope, category)
    }
}

#[derive(Serialize)]
struct NewSongsRequest {
    comm: NewSongsComm,
    #[serde(rename = "new_song")]
    new_song: NewSongsRpc,
}

impl NewSongsRequest {
    const fn new(category: QqMusicNewSongCategory) -> Self {
        Self {
            comm: NewSongsComm {
                client_type: 24,
                client_version: 4_747_474,
                format: "json",
            },
            new_song: NewSongsRpc {
                module: "newsong.NewSongServer",
                method: "get_new_song_info",
                param: NewSongsParam {
                    category: category.code(),
                },
            },
        }
    }
}

#[derive(Serialize)]
struct NewSongsComm {
    #[serde(rename = "ct")]
    client_type: u32,
    #[serde(rename = "cv")]
    client_version: u32,
    format: &'static str,
}

#[derive(Serialize)]
struct NewSongsRpc {
    module: &'static str,
    method: &'static str,
    param: NewSongsParam,
}

#[derive(Serialize)]
struct NewSongsParam {
    #[serde(rename = "type")]
    category: u8,
}

#[derive(Deserialize)]
struct NewSongsResponse {
    code: Option<i64>,
    #[serde(rename = "new_song")]
    new_song: Option<NewSongsResult>,
}

#[derive(Deserialize)]
struct NewSongsResult {
    code: Option<i64>,
    data: Option<NewSongsData>,
}

#[derive(Deserialize)]
struct NewSongsData {
    #[serde(rename = "type")]
    category: Option<u8>,
    songlist: Option<Vec<RawNewSongTrack>>,
}

#[derive(Deserialize)]
struct RawNewSongTrack {
    id: Option<u64>,
    mid: Option<String>,
    name: Option<String>,
    title: Option<String>,
    subtitle: Option<String>,
    #[serde(rename = "type")]
    song_type: Option<u32>,
    interval: Option<u32>,
    singer: Option<Vec<RawNewSongArtist>>,
    album: Option<RawNewSongAlbum>,
    file: Option<RawNewSongFile>,
}

#[derive(Deserialize)]
struct RawNewSongFile {
    media_mid: Option<String>,
}

#[derive(Deserialize)]
struct RawNewSongArtist {
    id: Option<u64>,
    mid: Option<String>,
    name: Option<String>,
}

#[derive(Deserialize)]
struct RawNewSongAlbum {
    id: Option<u64>,
    mid: Option<String>,
    pmid: Option<String>,
    name: Option<String>,
    title: Option<String>,
}

fn map_response<E>(
    envelope: NewSongsResponse,
    requested_category: QqMusicNewSongCategory,
) -> Result<QqMusicNewSongCollection, QqMusicNewSongsError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicNewSongsError::MissingGlobalCode)?;
    let result_code = envelope.new_song.as_ref().and_then(|result| result.code);
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicNewSongsError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .new_song
        .ok_or(QqMusicNewSongsError::MissingResult)?;
    result.code.ok_or(QqMusicNewSongsError::MissingResultCode)?;
    let data = result.data.ok_or(QqMusicNewSongsError::MissingData)?;
    let returned_category = data
        .category
        .ok_or(QqMusicNewSongsError::MissingReturnedCategory)?;
    if returned_category != requested_category.code() {
        return Err(QqMusicNewSongsError::MismatchedCategory);
    }
    let raw_tracks = data.songlist.ok_or(QqMusicNewSongsError::MissingTracks)?;
    if raw_tracks.len() > MAX_TRACKS {
        return Err(QqMusicNewSongsError::TooManyTracks {
            count: raw_tracks.len(),
        });
    }
    let tracks = raw_tracks
        .into_iter()
        .enumerate()
        .map(|(index, track)| map_track(track, index))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(QqMusicNewSongCollection {
        category: requested_category,
        tracks,
    })
}

fn map_track<E>(
    raw: RawNewSongTrack,
    index: usize,
) -> Result<QqMusicTrackSummary, QqMusicNewSongsError<E>> {
    let track_id =
        raw.id
            .filter(|value| *value != 0)
            .ok_or(QqMusicNewSongsError::InvalidTrack {
                index,
                field: NewSongTrackField::TrackId,
            })?;
    let song_mid = safe_mid(raw.mid).ok_or(QqMusicNewSongsError::InvalidTrack {
        index,
        field: NewSongTrackField::SongMid,
    })?;
    let file_media_mid = match raw.file.and_then(|file| file.media_mid) {
        Some(value) if value.trim().is_empty() => None,
        Some(value) => Some(
            safe_mid(Some(value)).ok_or(QqMusicNewSongsError::InvalidTrack {
                index,
                field: NewSongTrackField::FileMediaMid,
            })?,
        ),
        None => None,
    };
    let title = nonblank(raw.title).or_else(|| nonblank(raw.name)).ok_or(
        QqMusicNewSongsError::InvalidTrack {
            index,
            field: NewSongTrackField::Title,
        },
    )?;
    let song_type = raw.song_type.ok_or(QqMusicNewSongsError::InvalidTrack {
        index,
        field: NewSongTrackField::SongType,
    })?;
    let raw_artists = raw.singer.ok_or(QqMusicNewSongsError::InvalidTrack {
        index,
        field: NewSongTrackField::Artists,
    })?;
    let artists = raw_artists
        .into_iter()
        .enumerate()
        .map(|(artist_index, artist)| {
            let name = nonblank(artist.name).ok_or(QqMusicNewSongsError::InvalidArtist {
                track_index: index,
                artist_index,
            })?;
            Ok(QqMusicArtistSummary::new(
                artist.id.filter(|value| *value != 0),
                safe_mid(artist.mid),
                name,
            ))
        })
        .collect::<Result<Vec<_>, _>>()?;
    let album = raw.album.map(|album| {
        QqMusicAlbumSummary::new(
            album.id.filter(|value| *value != 0),
            safe_mid(album.mid).or_else(|| safe_mid(album.pmid)),
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

fn safe_mid(value: Option<String>) -> Option<String> {
    nonblank(value)
        .filter(|value| value.len() <= 64 && value.bytes().all(|byte| byte.is_ascii_alphanumeric()))
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use crate::{HttpMethod, HttpRequest, HttpResponse, HttpTransport, QqMusicClient};

    use super::{MUSICU_URL, NewSongTrackField, QqMusicNewSongCategory, QqMusicNewSongsError};

    struct NewSongsTransport {
        response: HttpResponse,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl NewSongsTransport {
        fn new(body: &Value) -> Self {
            Self {
                response: HttpResponse::new(200, body.to_string().into_bytes()),
                requests: Mutex::new(Vec::new()),
            }
        }
    }

    impl HttpTransport for NewSongsTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("requests").push(request);
            Ok(self.response.clone())
        }
    }

    #[tokio::test]
    async fn serializes_category_and_maps_bounded_track_collection() {
        let client = QqMusicClient::new(NewSongsTransport::new(&response_json(
            3,
            &[track_json(41_001, "fixtureTrackMid", "Synthetic Track")],
        )));

        let collection = client
            .new_songs(QqMusicNewSongCategory::Japan)
            .await
            .expect("new songs");

        assert_eq!(collection.category(), QqMusicNewSongCategory::Japan);
        assert_eq!(collection.tracks().len(), 1);
        assert_eq!(collection.tracks()[0].song_mid(), "fixtureTrackMid");
        assert_eq!(
            collection.tracks()[0].artists()[0].name(),
            "Synthetic Artist"
        );
        let requests = client.transport().requests.lock().expect("requests");
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].method(), HttpMethod::Post);
        assert_eq!(requests[0].url(), MUSICU_URL);
        assert_eq!(requests[0].max_response_body_bytes(), 2 * 1024 * 1024);
        let body: Value =
            serde_json::from_slice(requests[0].body_bytes().expect("body")).expect("request JSON");
        assert_eq!(body["comm"]["ct"], 24);
        assert_eq!(body["new_song"]["module"], "newsong.NewSongServer");
        assert_eq!(body["new_song"]["method"], "get_new_song_info");
        assert_eq!(body["new_song"]["param"]["type"], 3);
        let debug = format!("{collection:?} {:?}", requests[0]);
        assert!(!debug.contains("fixtureTrackMid"));
        assert!(!debug.contains("Synthetic Track"));
        assert!(!debug.contains("Synthetic Artist"));
    }

    #[tokio::test]
    async fn accepts_empty_collection_and_rejects_mismatched_or_oversized_response() {
        let empty = QqMusicClient::new(NewSongsTransport::new(&response_json(5, &[])))
            .new_songs(QqMusicNewSongCategory::Latest)
            .await
            .expect("empty collection");
        assert!(empty.tracks().is_empty());

        let mismatched = QqMusicClient::new(NewSongsTransport::new(&response_json(2, &[])))
            .new_songs(QqMusicNewSongCategory::Latest)
            .await;
        assert!(matches!(
            mismatched,
            Err(QqMusicNewSongsError::MismatchedCategory)
        ));

        let too_many = vec![track_json(41_001, "fixtureTrackMid", "private"); 201];
        let oversized = QqMusicClient::new(NewSongsTransport::new(&response_json(5, &too_many)))
            .new_songs(QqMusicNewSongCategory::Latest)
            .await;
        assert!(matches!(
            oversized,
            Err(QqMusicNewSongsError::TooManyTracks { count: 201 })
        ));
    }

    #[tokio::test]
    async fn keeps_service_and_identity_failures_distinct_and_redacted() {
        let upstream = QqMusicClient::new(NewSongsTransport::new(&json!({
            "code": 0,
            "new_song": {"code": 500_001}
        })))
        .new_songs(QqMusicNewSongCategory::Latest)
        .await;
        assert!(matches!(
            upstream,
            Err(QqMusicNewSongsError::Upstream {
                global_code: 0,
                result_code: Some(500_001)
            })
        ));

        let invalid = QqMusicClient::new(NewSongsTransport::new(&response_json(
            5,
            &[track_json(0, "privateMid", "must-not-leak")],
        )))
        .new_songs(QqMusicNewSongCategory::Latest)
        .await
        .expect_err("invalid Track");
        assert!(matches!(
            invalid,
            QqMusicNewSongsError::InvalidTrack {
                index: 0,
                field: NewSongTrackField::TrackId
            }
        ));
        let debug = format!("{invalid:?} {invalid}");
        assert!(!debug.contains("privateMid"));
        assert!(!debug.contains("must-not-leak"));
    }

    fn response_json(category: u8, tracks: &[Value]) -> Value {
        json!({
            "code": 0,
            "new_song": {
                "code": 0,
                "data": {"type": category, "songlist": tracks}
            }
        })
    }

    fn track_json(id: u64, mid: &str, title: &str) -> Value {
        json!({
            "id": id,
            "mid": mid,
            "title": title,
            "subtitle": "Synthetic subtitle",
            "type": 0,
            "interval": 245,
            "file": {"media_mid": mid},
            "singer": [
                {"id": 42001, "mid": "fixtureArtistMid", "name": "Synthetic Artist"}
            ],
            "album": {"id": 43001, "mid": "fixtureAlbumMid", "name": "Synthetic Album"}
        })
    }
}
