use std::collections::HashSet;
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
const PERSONAL_RADIO_ID: u32 = 99;
const REQUESTED_TRACKS: u32 = 5;
const MAX_TRACKS: usize = REQUESTED_TRACKS as usize;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PersonalizedTrackField {
    TrackId,
    SongMid,
    FileMediaMid,
    Title,
    SongType,
    Artists,
}

pub enum QqMusicPersonalizedTracksError<E> {
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
    TooManyTracks {
        count: usize,
    },
    DuplicateTrackIdentity,
    InvalidTrack {
        index: usize,
        field: PersonalizedTrackField,
    },
    InvalidArtist {
        track_index: usize,
        artist_index: usize,
    },
}

impl<E> fmt::Debug for QqMusicPersonalizedTracksError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
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
            Self::TooManyTracks { count } => formatter
                .debug_struct("TooManyTracks")
                .field("count", count)
                .finish(),
            Self::DuplicateTrackIdentity => {
                formatter.write_str("DuplicateTrackIdentity([REDACTED])")
            }
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

impl<E> fmt::Display for QqMusicPersonalizedTracksError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Transport(_) => formatter.write_str("QQ Music personalized-Track request failed"),
            Self::Serialize => {
                formatter.write_str("could not serialize personalized-Track request")
            }
            Self::HttpStatus(status) => {
                write!(
                    formatter,
                    "personalized-Track request returned HTTP {status}"
                )
            }
            Self::InvalidJson => {
                formatter.write_str("personalized-Track response was not valid JSON")
            }
            Self::MissingGlobalCode => {
                formatter.write_str("personalized-Track response has no global code")
            }
            Self::MissingResult => formatter.write_str("personalized-Track result is missing"),
            Self::MissingResultCode => formatter.write_str("personalized-Track result has no code"),
            Self::Rejected { code } => write!(
                formatter,
                "QQ Music rejected the credential with code {code}"
            ),
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "personalized-Track request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("personalized-Track data is missing"),
            Self::MissingTracks => formatter.write_str("personalized-Track array is missing"),
            Self::TooManyTracks { count } => {
                write!(
                    formatter,
                    "personalized-Track response contains too many Tracks ({count})"
                )
            }
            Self::DuplicateTrackIdentity => {
                formatter.write_str("personalized-Track response contains duplicate identity")
            }
            Self::InvalidTrack { index, field } => {
                write!(
                    formatter,
                    "personalized Track {index} has an invalid {field:?}"
                )
            }
            Self::InvalidArtist {
                track_index,
                artist_index,
            } => write!(
                formatter,
                "personalized Track {track_index} has an invalid Artist at {artist_index}"
            ),
        }
    }
}

impl<E> std::error::Error for QqMusicPersonalizedTracksError<E>
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
pub struct QqMusicPersonalizedTracks {
    tracks: Vec<QqMusicTrackSummary>,
}

impl QqMusicPersonalizedTracks {
    #[must_use]
    pub fn tracks(&self) -> &[QqMusicTrackSummary] {
        &self.tracks
    }
}

impl fmt::Debug for QqMusicPersonalizedTracks {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicPersonalizedTracks")
            .field("track_count", &self.tracks.len())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Loads one bounded authenticated QQ Music personal-radio Track set.
    ///
    /// # Errors
    ///
    /// Keeps rejection, transport, service, response-shape, size, identity,
    /// and Track-mapping failures distinct without retaining returned content.
    pub async fn personalized_tracks(
        &self,
        credential: &Credential,
    ) -> Result<QqMusicPersonalizedTracks, QqMusicPersonalizedTracksError<T::Error>> {
        let body = serde_json::to_vec(&PersonalizedTracksRequest::new(credential))
            .map_err(|_| QqMusicPersonalizedTracksError::Serialize)?;
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
            .map_err(QqMusicPersonalizedTracksError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicPersonalizedTracksError::HttpStatus(
                response.status(),
            ));
        }
        let envelope: PersonalizedTracksResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicPersonalizedTracksError::InvalidJson)?;
        map_response(envelope)
    }
}

#[derive(Serialize)]
struct PersonalizedTracksRequest<'a> {
    comm: PersonalizedTracksComm<'a>,
    radio: PersonalizedTracksRpc,
}

impl<'a> PersonalizedTracksRequest<'a> {
    fn new(credential: &'a Credential) -> Self {
        Self {
            comm: PersonalizedTracksComm {
                account_id: credential.music_id(),
                format: "json",
                client_type: 19,
                client_version: 0,
                auth_key: credential.music_key(),
                login_type: credential.login_type().value(),
            },
            radio: PersonalizedTracksRpc {
                module: "music.radioProxy.MbTrackRadioSvr",
                method: "get_radio_track",
                param: PersonalizedTracksParam {
                    id: PERSONAL_RADIO_ID,
                    count: REQUESTED_TRACKS,
                    offset: 0,
                    scene: 0,
                    song_ids: [],
                },
            },
        }
    }
}

#[derive(Serialize)]
struct PersonalizedTracksComm<'a> {
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
struct PersonalizedTracksRpc {
    module: &'static str,
    method: &'static str,
    param: PersonalizedTracksParam,
}

#[derive(Serialize)]
struct PersonalizedTracksParam {
    id: u32,
    #[serde(rename = "num")]
    count: u32,
    #[serde(rename = "from")]
    offset: u32,
    scene: u32,
    song_ids: [u64; 0],
}

#[derive(Deserialize)]
struct PersonalizedTracksResponse {
    code: Option<i64>,
    radio: Option<PersonalizedTracksResult>,
}

#[derive(Deserialize)]
struct PersonalizedTracksResult {
    code: Option<i64>,
    data: Option<PersonalizedTracksData>,
}

#[derive(Deserialize)]
struct PersonalizedTracksData {
    tracks: Option<Vec<RawPersonalizedTrack>>,
}

#[derive(Deserialize)]
struct RawPersonalizedTrack {
    id: Option<u64>,
    mid: Option<String>,
    name: Option<String>,
    title: Option<String>,
    subtitle: Option<String>,
    #[serde(rename = "type")]
    song_type: Option<u32>,
    interval: Option<u32>,
    singer: Option<Vec<RawPersonalizedArtist>>,
    album: Option<RawPersonalizedAlbum>,
    file: Option<RawPersonalizedFile>,
}

#[derive(Deserialize)]
struct RawPersonalizedFile {
    media_mid: Option<String>,
}

#[derive(Deserialize)]
struct RawPersonalizedArtist {
    id: Option<u64>,
    mid: Option<String>,
    name: Option<String>,
}

#[derive(Deserialize)]
struct RawPersonalizedAlbum {
    id: Option<u64>,
    mid: Option<String>,
    pmid: Option<String>,
    name: Option<String>,
    title: Option<String>,
}

fn map_response<E>(
    envelope: PersonalizedTracksResponse,
) -> Result<QqMusicPersonalizedTracks, QqMusicPersonalizedTracksError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicPersonalizedTracksError::MissingGlobalCode)?;
    let result_code = envelope.radio.as_ref().and_then(|result| result.code);
    if is_credential_rejection_code(global_code)
        || result_code.is_some_and(is_credential_rejection_code)
    {
        return Err(QqMusicPersonalizedTracksError::Rejected {
            code: result_code
                .filter(|code| is_credential_rejection_code(*code))
                .unwrap_or(global_code),
        });
    }
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicPersonalizedTracksError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .radio
        .ok_or(QqMusicPersonalizedTracksError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicPersonalizedTracksError::MissingResultCode)?;
    let data = result
        .data
        .ok_or(QqMusicPersonalizedTracksError::MissingData)?;
    let raw_tracks = data
        .tracks
        .ok_or(QqMusicPersonalizedTracksError::MissingTracks)?;
    if raw_tracks.len() > MAX_TRACKS {
        return Err(QqMusicPersonalizedTracksError::TooManyTracks {
            count: raw_tracks.len(),
        });
    }
    let tracks = raw_tracks
        .into_iter()
        .enumerate()
        .map(|(index, track)| map_track(track, index))
        .collect::<Result<Vec<_>, _>>()?;
    let mut track_ids = HashSet::new();
    let mut song_mids = HashSet::new();
    for track in &tracks {
        if !track_ids.insert(track.track_id()) || !song_mids.insert(track.song_mid()) {
            return Err(QqMusicPersonalizedTracksError::DuplicateTrackIdentity);
        }
    }
    Ok(QqMusicPersonalizedTracks { tracks })
}

fn map_track<E>(
    raw: RawPersonalizedTrack,
    index: usize,
) -> Result<QqMusicTrackSummary, QqMusicPersonalizedTracksError<E>> {
    let track_id =
        raw.id
            .filter(|value| *value != 0)
            .ok_or(QqMusicPersonalizedTracksError::InvalidTrack {
                index,
                field: PersonalizedTrackField::TrackId,
            })?;
    let song_mid = safe_mid(raw.mid).ok_or(QqMusicPersonalizedTracksError::InvalidTrack {
        index,
        field: PersonalizedTrackField::SongMid,
    })?;
    let file_media_mid = match raw.file.and_then(|file| file.media_mid) {
        Some(value) if value.trim().is_empty() => None,
        Some(value) => Some(safe_mid(Some(value)).ok_or(
            QqMusicPersonalizedTracksError::InvalidTrack {
                index,
                field: PersonalizedTrackField::FileMediaMid,
            },
        )?),
        None => None,
    };
    let title = nonblank(raw.title).or_else(|| nonblank(raw.name)).ok_or(
        QqMusicPersonalizedTracksError::InvalidTrack {
            index,
            field: PersonalizedTrackField::Title,
        },
    )?;
    let song_type = raw
        .song_type
        .ok_or(QqMusicPersonalizedTracksError::InvalidTrack {
            index,
            field: PersonalizedTrackField::SongType,
        })?;
    let raw_artists = raw
        .singer
        .ok_or(QqMusicPersonalizedTracksError::InvalidTrack {
            index,
            field: PersonalizedTrackField::Artists,
        })?;
    let artists = raw_artists
        .into_iter()
        .enumerate()
        .map(|(artist_index, artist)| {
            let name =
                nonblank(artist.name).ok_or(QqMusicPersonalizedTracksError::InvalidArtist {
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

    use crate::{
        Credential, HttpMethod, HttpRequest, HttpResponse, HttpTransport, LoginType, QqMusicClient,
    };

    use super::{
        MUSICU_URL, PersonalizedTrackField, QqMusicPersonalizedTracksError, REQUESTED_TRACKS,
    };

    struct PersonalizedTracksTransport {
        response: HttpResponse,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl PersonalizedTracksTransport {
        fn new(body: &Value) -> Self {
            Self {
                response: HttpResponse::new(200, body.to_string().into_bytes()),
                requests: Mutex::new(Vec::new()),
            }
        }
    }

    impl HttpTransport for PersonalizedTracksTransport {
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
    async fn serializes_evidenced_personal_radio_and_maps_bounded_tracks() {
        let client = QqMusicClient::new(PersonalizedTracksTransport::new(&response_json(&[
            track_json(41_001, "fixtureTrackMid", "Synthetic recommendation"),
        ])));

        let recommendations = client
            .personalized_tracks(&credential())
            .await
            .expect("personalized Tracks");
        assert_eq!(recommendations.tracks().len(), 1);
        assert_eq!(recommendations.tracks()[0].track_id(), 41_001);
        assert_eq!(recommendations.tracks()[0].song_mid(), "fixtureTrackMid");
        assert_eq!(
            recommendations.tracks()[0].title(),
            "Synthetic recommendation"
        );

        let requests = client.transport().requests.lock().expect("requests");
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].method(), HttpMethod::Post);
        assert_eq!(requests[0].url(), MUSICU_URL);
        let body: Value =
            serde_json::from_slice(requests[0].body_bytes().expect("body")).expect("request JSON");
        assert_eq!(body["radio"]["module"], "music.radioProxy.MbTrackRadioSvr");
        assert_eq!(body["radio"]["method"], "get_radio_track");
        assert_eq!(body["radio"]["param"]["id"], 99);
        assert_eq!(body["radio"]["param"]["num"], REQUESTED_TRACKS);
        assert_eq!(body["radio"]["param"]["from"], 0);
        assert_eq!(body["radio"]["param"]["scene"], 0);
        assert_eq!(body["radio"]["param"]["song_ids"], json!([]));
        assert_eq!(body["comm"]["uin"], "123456");
        assert_eq!(body["comm"]["authst"], "W_X_private-key");
        let debug = format!("{recommendations:?} {:?}", requests[0]);
        assert!(!debug.contains("W_X_private-key"));
        assert!(!debug.contains("fixtureTrackMid"));
        assert!(!debug.contains("Synthetic recommendation"));
    }

    #[tokio::test]
    async fn accepts_empty_and_rejects_oversized_or_duplicate_track_sets() {
        let empty = QqMusicClient::new(PersonalizedTracksTransport::new(&response_json(&[])))
            .personalized_tracks(&credential())
            .await
            .expect("empty recommendations");
        assert!(empty.tracks().is_empty());

        let too_many = (1..=6)
            .map(|id| track_json(id, &format!("fixtureMid{id}"), "Private title"))
            .collect::<Vec<_>>();
        let oversized =
            QqMusicClient::new(PersonalizedTracksTransport::new(&response_json(&too_many)))
                .personalized_tracks(&credential())
                .await;
        assert!(matches!(
            oversized,
            Err(QqMusicPersonalizedTracksError::TooManyTracks { count: 6 })
        ));

        let duplicate = QqMusicClient::new(PersonalizedTracksTransport::new(&response_json(&[
            track_json(41_001, "fixtureTrackMid", "Private one"),
            track_json(41_001, "fixtureTrackMidTwo", "Private duplicate"),
        ])))
        .personalized_tracks(&credential())
        .await;
        assert!(matches!(
            duplicate,
            Err(QqMusicPersonalizedTracksError::DuplicateTrackIdentity)
        ));
        assert!(!format!("{duplicate:?}").contains("Private duplicate"));
    }

    #[tokio::test]
    async fn keeps_rejection_service_and_identity_failures_distinct() {
        let rejected = QqMusicClient::new(PersonalizedTracksTransport::new(&json!({
            "code": 0,
            "radio": {"code": 104_401}
        })))
        .personalized_tracks(&credential())
        .await;
        assert!(matches!(
            rejected,
            Err(QqMusicPersonalizedTracksError::Rejected { code: 104_401 })
        ));

        let upstream = QqMusicClient::new(PersonalizedTracksTransport::new(&json!({
            "code": 0,
            "radio": {"code": 50_006, "data": {"tracks": []}}
        })))
        .personalized_tracks(&credential())
        .await;
        assert!(matches!(
            upstream,
            Err(QqMusicPersonalizedTracksError::Upstream {
                global_code: 0,
                result_code: Some(50_006)
            })
        ));

        let invalid = QqMusicClient::new(PersonalizedTracksTransport::new(&response_json(&[
            track_json(0, "privateMid", "must-not-leak"),
        ])))
        .personalized_tracks(&credential())
        .await;
        assert!(matches!(
            invalid,
            Err(QqMusicPersonalizedTracksError::InvalidTrack {
                index: 0,
                field: PersonalizedTrackField::TrackId
            })
        ));
        let debug = format!("{invalid:?}");
        assert!(!debug.contains("privateMid"));
        assert!(!debug.contains("must-not-leak"));
    }

    fn response_json(tracks: &[Value]) -> Value {
        json!({
            "code": 0,
            "radio": {"code": 0, "data": {"tracks": tracks}}
        })
    }

    fn track_json(id: u64, mid: &str, title: &str) -> Value {
        json!({
            "id": id,
            "mid": mid,
            "title": title,
            "subtitle": "",
            "type": 0,
            "interval": 245,
            "file": {"media_mid": mid},
            "singer": [{"id": 42001, "mid": "fixtureArtistMid", "name": "Artist"}],
            "album": {"id": 43001, "mid": "fixtureAlbumMid", "name": "Album"}
        })
    }
}
