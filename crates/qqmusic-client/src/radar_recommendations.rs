use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::credential::is_credential_rejection_code;
use crate::{
    Credential, HttpRequest, HttpTransport, QqMusicAlbumSummary, QqMusicArtistSummary,
    QqMusicClient, QqMusicTrackSummary,
};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RadarTrackField {
    Track,
    TrackId,
    SongMid,
    FileMediaMid,
    Title,
    SongType,
    Artists,
}

pub enum QqMusicRadarError<E> {
    InvalidPage {
        page: u32,
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
    Upstream {
        global_code: i64,
        result_code: Option<i64>,
    },
    MissingData,
    MissingTracks,
    MissingHasMore,
    InvalidPagination,
    InvalidTrack {
        index: usize,
        field: RadarTrackField,
    },
    InvalidArtist {
        track_index: usize,
        artist_index: usize,
    },
}

impl<E> fmt::Debug for QqMusicRadarError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidPage { page } => formatter
                .debug_struct("InvalidPage")
                .field("page", page)
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
            Self::Upstream {
                global_code,
                result_code,
            } => formatter
                .debug_struct("Upstream")
                .field("global_code", global_code)
                .field("result_code", result_code)
                .finish(),
            Self::MissingData => formatter.write_str("MissingData"),
            Self::MissingTracks => formatter.write_str("MissingTracks"),
            Self::MissingHasMore => formatter.write_str("MissingHasMore"),
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

impl<E> fmt::Display for QqMusicRadarError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidPage { page } => write!(formatter, "Radar page {page} is not positive"),
            Self::Transport(_) => formatter.write_str("QQ Music Radar request failed"),
            Self::Serialize => formatter.write_str("could not serialize Radar request"),
            Self::HttpStatus(status) => write!(formatter, "Radar request returned HTTP {status}"),
            Self::InvalidJson => formatter.write_str("Radar response was not valid JSON"),
            Self::MissingGlobalCode => formatter.write_str("Radar response has no global code"),
            Self::MissingResult => formatter.write_str("Radar result is missing"),
            Self::MissingResultCode => formatter.write_str("Radar result has no code"),
            Self::Rejected { code } => {
                write!(
                    formatter,
                    "QQ Music rejected the credential with code {code}"
                )
            }
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "Radar request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("Radar data is missing"),
            Self::MissingTracks => formatter.write_str("Radar Track array is missing"),
            Self::MissingHasMore => formatter.write_str("Radar continuation flag is missing"),
            Self::InvalidPagination => formatter.write_str("Radar pagination is invalid"),
            Self::InvalidTrack { index, field } => {
                write!(formatter, "Radar Track {index} has an invalid {field:?}")
            }
            Self::InvalidArtist {
                track_index,
                artist_index,
            } => write!(
                formatter,
                "Radar Track {track_index} has an invalid Artist at {artist_index}"
            ),
        }
    }
}

impl<E> std::error::Error for QqMusicRadarError<E>
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
pub struct QqMusicRadarTrackPage {
    page: u32,
    has_more: bool,
    tracks: Vec<QqMusicTrackSummary>,
}

impl QqMusicRadarTrackPage {
    #[must_use]
    pub const fn page(&self) -> u32 {
        self.page
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

impl fmt::Debug for QqMusicRadarTrackPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRadarTrackPage")
            .field("page", &self.page)
            .field("has_more", &self.has_more)
            .field("track_count", &self.tracks.len())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Loads one credential-bearing page of QQ Music Radar recommendations.
    ///
    /// # Errors
    ///
    /// Keeps rejection, transport, service, response-shape, continuation, and
    /// Track-mapping failures distinct without retaining credential or content.
    pub async fn radar_tracks(
        &self,
        credential: &Credential,
        page: u32,
    ) -> Result<QqMusicRadarTrackPage, QqMusicRadarError<T::Error>> {
        if page == 0 {
            return Err(QqMusicRadarError::InvalidPage { page });
        }
        let body = serde_json::to_vec(&RadarRequest::new(credential, page))
            .map_err(|_| QqMusicRadarError::Serialize)?;
        let response = self
            .transport()
            .execute(
                HttpRequest::post(MUSICU_URL)
                    .header("Content-Type", "application/json")
                    .header("Origin", "https://y.qq.com")
                    .header("Referer", "https://y.qq.com/")
                    .header("Cookie", credential.musicu_cookie_header())
                    .body(body)
                    .response_body_limit(MAX_RESPONSE_BYTES)
                    .timeout(REQUEST_TIMEOUT),
            )
            .await
            .map_err(QqMusicRadarError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicRadarError::HttpStatus(response.status()));
        }
        let envelope: RadarResponse =
            serde_json::from_slice(response.body()).map_err(|_| QqMusicRadarError::InvalidJson)?;
        map_response(envelope, page)
    }
}

#[derive(Serialize)]
struct RadarRequest<'a> {
    comm: RadarComm<'a>,
    radar: RadarRpc,
}

impl<'a> RadarRequest<'a> {
    fn new(credential: &'a Credential, page: u32) -> Self {
        Self {
            comm: RadarComm {
                account_id: credential.music_id(),
                format: "json",
                client_type: 19,
                client_version: 0,
                auth_key: credential.music_key(),
                login_type: credential.login_type().value(),
            },
            radar: RadarRpc {
                module: "music.recommend.TrackRelationServer",
                method: "GetRadarSong",
                param: RadarParam {
                    page,
                    request_type: 0,
                    favorite_songs: [],
                    entrance_songs: [],
                },
            },
        }
    }
}

#[derive(Serialize)]
struct RadarComm<'a> {
    #[serde(rename = "uin")]
    account_id: &'a str,
    format: &'static str,
    #[serde(rename = "ct")]
    client_type: u32,
    #[serde(rename = "cv")]
    client_version: u32,
    #[serde(rename = "authst")]
    auth_key: &'a str,
    #[serde(rename = "tmeLoginType")]
    login_type: u32,
}

#[derive(Serialize)]
struct RadarRpc {
    module: &'static str,
    method: &'static str,
    param: RadarParam,
}

#[derive(Serialize)]
struct RadarParam {
    #[serde(rename = "Page")]
    page: u32,
    #[serde(rename = "ReqType")]
    request_type: u32,
    #[serde(rename = "FavSongs")]
    favorite_songs: [u64; 0],
    #[serde(rename = "EntranceSongs")]
    entrance_songs: [u64; 0],
}

#[derive(Deserialize)]
struct RadarResponse {
    code: Option<i64>,
    radar: Option<RadarResult>,
}

#[derive(Deserialize)]
struct RadarResult {
    code: Option<i64>,
    data: Option<RadarData>,
}

#[derive(Deserialize)]
struct RadarData {
    #[serde(rename = "VecSongs")]
    tracks: Option<Vec<RawRadarTrackWrapper>>,
    #[serde(rename = "HasMore")]
    has_more: Option<bool>,
}

#[derive(Deserialize)]
struct RawRadarTrackWrapper {
    #[serde(rename = "Track")]
    track: Option<RawRadarTrack>,
}

#[derive(Deserialize)]
struct RawRadarTrack {
    id: Option<u64>,
    mid: Option<String>,
    name: Option<String>,
    title: Option<String>,
    subtitle: Option<String>,
    #[serde(rename = "type")]
    song_type: Option<u32>,
    interval: Option<u32>,
    singer: Option<Vec<RawRadarArtist>>,
    album: Option<RawRadarAlbum>,
    file: Option<RawRadarFile>,
}

#[derive(Deserialize)]
struct RawRadarFile {
    media_mid: Option<String>,
}

#[derive(Deserialize)]
struct RawRadarArtist {
    id: Option<u64>,
    mid: Option<String>,
    name: Option<String>,
}

#[derive(Deserialize)]
struct RawRadarAlbum {
    id: Option<u64>,
    mid: Option<String>,
    pmid: Option<String>,
    name: Option<String>,
    title: Option<String>,
}

fn map_response<E>(
    envelope: RadarResponse,
    page: u32,
) -> Result<QqMusicRadarTrackPage, QqMusicRadarError<E>> {
    let global_code = envelope.code.ok_or(QqMusicRadarError::MissingGlobalCode)?;
    let result_code = envelope.radar.as_ref().and_then(|result| result.code);
    if is_credential_rejection_code(global_code)
        || result_code.is_some_and(is_credential_rejection_code)
    {
        return Err(QqMusicRadarError::Rejected {
            code: result_code
                .filter(|code| is_credential_rejection_code(*code))
                .unwrap_or(global_code),
        });
    }
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicRadarError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope.radar.ok_or(QqMusicRadarError::MissingResult)?;
    result.code.ok_or(QqMusicRadarError::MissingResultCode)?;
    let data = result.data.ok_or(QqMusicRadarError::MissingData)?;
    let raw_tracks = data.tracks.ok_or(QqMusicRadarError::MissingTracks)?;
    let has_more = data.has_more.ok_or(QqMusicRadarError::MissingHasMore)?;
    if has_more && raw_tracks.is_empty() {
        return Err(QqMusicRadarError::InvalidPagination);
    }
    let tracks = raw_tracks
        .into_iter()
        .enumerate()
        .map(|(index, wrapper)| {
            wrapper
                .track
                .ok_or(QqMusicRadarError::InvalidTrack {
                    index,
                    field: RadarTrackField::Track,
                })
                .and_then(|track| map_track(track, index))
        })
        .collect::<Result<Vec<_>, _>>()?;
    Ok(QqMusicRadarTrackPage {
        page,
        has_more,
        tracks,
    })
}

fn map_track<E>(
    raw: RawRadarTrack,
    index: usize,
) -> Result<QqMusicTrackSummary, QqMusicRadarError<E>> {
    let track_id = raw
        .id
        .filter(|value| *value != 0)
        .ok_or(QqMusicRadarError::InvalidTrack {
            index,
            field: RadarTrackField::TrackId,
        })?;
    let song_mid = safe_mid(raw.mid).ok_or(QqMusicRadarError::InvalidTrack {
        index,
        field: RadarTrackField::SongMid,
    })?;
    let file_media_mid = match raw.file.and_then(|file| file.media_mid) {
        Some(value) if value.trim().is_empty() => None,
        Some(value) => Some(
            safe_mid(Some(value)).ok_or(QqMusicRadarError::InvalidTrack {
                index,
                field: RadarTrackField::FileMediaMid,
            })?,
        ),
        None => None,
    };
    let title = nonblank(raw.title).or_else(|| nonblank(raw.name)).ok_or(
        QqMusicRadarError::InvalidTrack {
            index,
            field: RadarTrackField::Title,
        },
    )?;
    let song_type = raw.song_type.ok_or(QqMusicRadarError::InvalidTrack {
        index,
        field: RadarTrackField::SongType,
    })?;
    let raw_artists = raw.singer.ok_or(QqMusicRadarError::InvalidTrack {
        index,
        field: RadarTrackField::Artists,
    })?;
    let artists = raw_artists
        .into_iter()
        .enumerate()
        .map(|(artist_index, artist)| {
            let name = nonblank(artist.name).ok_or(QqMusicRadarError::InvalidArtist {
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

fn safe_mid(value: Option<String>) -> Option<String> {
    nonblank(value)
        .filter(|value| value.len() <= 64 && value.bytes().all(|byte| byte.is_ascii_alphanumeric()))
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use crate::{
        Credential, HttpMethod, HttpRequest, HttpResponse, HttpTransport, LoginType, QqMusicClient,
    };

    use super::{MUSICU_URL, QqMusicRadarError, RadarTrackField};

    struct RadarTransport {
        response: HttpResponse,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl RadarTransport {
        fn new(body: &Value) -> Self {
            Self {
                response: HttpResponse::new(200, body.to_string().into_bytes()),
                requests: Mutex::new(Vec::new()),
            }
        }
    }

    impl HttpTransport for RadarTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("requests").push(request);
            Ok(self.response.clone())
        }
    }

    fn credential() -> Credential {
        Credential::new("123456", "W_X_private-key", LoginType::WECHAT).expect("credential")
    }

    #[tokio::test]
    async fn serializes_authenticated_request_and_maps_overlapping_page_shape() {
        let client = QqMusicClient::new(RadarTransport::new(&radar_json(
            &[track_json(41001, "fixtureMidOne", "First")],
            true,
        )));

        let page = client
            .radar_tracks(&credential(), 2)
            .await
            .expect("Radar page");

        assert_eq!(page.page(), 2);
        assert!(page.has_more());
        assert_eq!(page.tracks().len(), 1);
        assert_eq!(page.tracks()[0].track_id(), 41001);
        assert_eq!(page.tracks()[0].song_mid(), "fixtureMidOne");
        assert_eq!(page.tracks()[0].title(), "First");
        assert_eq!(page.tracks()[0].artists()[0].name(), "Artist");

        let requests = client.transport().requests.lock().expect("requests");
        assert_eq!(requests.len(), 1);
        let request = &requests[0];
        assert_eq!(request.method(), HttpMethod::Post);
        assert_eq!(request.url(), MUSICU_URL);
        assert_eq!(request.max_response_body_bytes(), 2 * 1024 * 1024);
        let body: Value = serde_json::from_slice(request.body_bytes().expect("request body"))
            .expect("request JSON");
        assert_eq!(
            body["radar"]["module"],
            "music.recommend.TrackRelationServer"
        );
        assert_eq!(body["radar"]["method"], "GetRadarSong");
        assert_eq!(body["radar"]["param"]["Page"], 2);
        assert_eq!(body["radar"]["param"]["ReqType"], 0);
        assert_eq!(body["radar"]["param"]["FavSongs"], json!([]));
        assert_eq!(body["radar"]["param"]["EntranceSongs"], json!([]));
        assert_eq!(body["comm"]["ct"], 19);
        assert_eq!(body["comm"]["uin"], "123456");
        assert_eq!(body["comm"]["authst"], "W_X_private-key");
        let cookie = request
            .headers()
            .iter()
            .find(|(name, _)| name == "Cookie")
            .map(|(_, value)| value)
            .expect("credential cookie");
        assert!(cookie.contains("qm_keyst=W_X_private-key"));
        let debug = format!("{page:?} {request:?}");
        assert!(!debug.contains("W_X_private-key"));
        assert!(!debug.contains("fixtureMidOne"));
        assert!(!debug.contains("First"));
    }

    #[tokio::test]
    async fn maps_empty_terminal_page_and_rejects_invalid_page_before_transport() {
        let client = QqMusicClient::new(RadarTransport::new(&radar_json(&[], false)));
        let page = client
            .radar_tracks(&credential(), 1)
            .await
            .expect("empty terminal page");
        assert!(!page.has_more());
        assert!(page.tracks().is_empty());

        let invalid = QqMusicClient::new(RadarTransport::new(&json!({})))
            .radar_tracks(&credential(), 0)
            .await;
        assert!(matches!(
            invalid,
            Err(QqMusicRadarError::InvalidPage { page: 0 })
        ));
    }

    #[tokio::test]
    async fn keeps_rejection_pagination_and_identity_failures_distinct_and_redacted() {
        let rejected = QqMusicClient::new(RadarTransport::new(&json!({
            "code": 0,
            "radar": {"code": 104_401}
        })))
        .radar_tracks(&credential(), 1)
        .await;
        assert!(matches!(
            rejected,
            Err(QqMusicRadarError::Rejected { code: 104_401 })
        ));

        let pagination = QqMusicClient::new(RadarTransport::new(&radar_json(&[], true)))
            .radar_tracks(&credential(), 1)
            .await;
        assert!(matches!(
            pagination,
            Err(QqMusicRadarError::InvalidPagination)
        ));

        let invalid = QqMusicClient::new(RadarTransport::new(&radar_json(
            &[track_json(0, "privateMid", "private title")],
            false,
        )))
        .radar_tracks(&credential(), 1)
        .await;
        assert!(matches!(
            invalid,
            Err(QqMusicRadarError::InvalidTrack {
                index: 0,
                field: RadarTrackField::TrackId
            })
        ));
        let debug = format!("{invalid:?}");
        assert!(!debug.contains("privateMid"));
        assert!(!debug.contains("private title"));
    }

    fn radar_json(tracks: &[Value], has_more: bool) -> Value {
        json!({
            "code": 0,
            "radar": {
                "code": 0,
                "data": {"VecSongs": tracks, "HasMore": has_more}
            }
        })
    }

    fn track_json(id: u64, mid: &str, title: &str) -> Value {
        json!({"Track": {
            "id": id,
            "mid": mid,
            "title": title,
            "subtitle": "",
            "type": 0,
            "interval": 245,
            "file": {"media_mid": mid},
            "singer": [{"id": 42001, "mid": "fixtureArtistMid", "name": "Artist"}],
            "album": {"id": 43001, "mid": "fixtureAlbumMid", "name": "Album"}
        }})
    }
}
