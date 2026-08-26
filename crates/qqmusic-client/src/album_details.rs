use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::{HttpRequest, HttpTransport, QqMusicAlbumSummary, QqMusicArtistSummary, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_SHORT_TEXT_BYTES: usize = 4 * 1024;
const MAX_DESCRIPTION_BYTES: usize = 128 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AlbumDetailField {
    AlbumId,
    AlbumMid,
    Title,
    ArtistId,
    ArtistMid,
    ArtistName,
    Subtitle,
    ReleaseDate,
    Description,
    Language,
    AlbumType,
    Genre,
    Company,
}

pub enum QqMusicAlbumDetailsError<E> {
    InvalidAlbumMid,
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
    MissingBasicInfo,
    MissingSingers,
    InvalidAlbum {
        field: AlbumDetailField,
    },
    MismatchedAlbumMid,
    InvalidArtist {
        index: usize,
        field: AlbumDetailField,
    },
    InvalidMetadata {
        field: AlbumDetailField,
    },
}

impl<E> fmt::Debug for QqMusicAlbumDetailsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidAlbumMid => formatter.write_str("InvalidAlbumMid([REDACTED])"),
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
            Self::MissingBasicInfo => formatter.write_str("MissingBasicInfo"),
            Self::MissingSingers => formatter.write_str("MissingSingers"),
            Self::InvalidAlbum { field } => formatter
                .debug_struct("InvalidAlbum")
                .field("field", field)
                .finish(),
            Self::MismatchedAlbumMid => formatter.write_str("MismatchedAlbumMid([REDACTED])"),
            Self::InvalidArtist { index, field } => formatter
                .debug_struct("InvalidArtist")
                .field("index", index)
                .field("field", field)
                .finish(),
            Self::InvalidMetadata { field } => formatter
                .debug_struct("InvalidMetadata")
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicAlbumDetailsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidAlbumMid => formatter.write_str("Album MID is invalid"),
            Self::Transport(_) => formatter.write_str("QQ Music Album detail request failed"),
            Self::Serialize => formatter.write_str("could not serialize Album detail request"),
            Self::HttpStatus(status) => {
                write!(formatter, "Album detail request returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("Album detail response was not valid JSON"),
            Self::MissingGlobalCode => {
                formatter.write_str("Album detail response has no global code")
            }
            Self::MissingResult => formatter.write_str("Album detail result is missing"),
            Self::MissingResultCode => formatter.write_str("Album detail result has no code"),
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "Album detail request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("Album detail data is missing"),
            Self::MissingBasicInfo => formatter.write_str("Album basic information is missing"),
            Self::MissingSingers => formatter.write_str("Album credited Artists are missing"),
            Self::InvalidAlbum { field } => {
                write!(formatter, "Album detail has an invalid {field:?}")
            }
            Self::MismatchedAlbumMid => {
                formatter.write_str("Album detail MID did not match the request")
            }
            Self::InvalidArtist { index, field } => {
                write!(
                    formatter,
                    "Album detail Artist {index} has an invalid {field:?}"
                )
            }
            Self::InvalidMetadata { field } => {
                write!(formatter, "Album detail metadata has an invalid {field:?}")
            }
        }
    }
}

impl<E> std::error::Error for QqMusicAlbumDetailsError<E>
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
pub struct QqMusicAlbumDetails {
    album: QqMusicAlbumSummary,
    artists: Vec<QqMusicArtistSummary>,
    subtitle: Option<String>,
    release_date: Option<String>,
    description: Option<String>,
    language: Option<String>,
    album_type: Option<String>,
    genre: Option<String>,
    company: Option<String>,
}

impl QqMusicAlbumDetails {
    #[must_use]
    pub const fn album(&self) -> &QqMusicAlbumSummary {
        &self.album
    }

    #[must_use]
    pub fn artists(&self) -> &[QqMusicArtistSummary] {
        &self.artists
    }

    #[must_use]
    pub fn subtitle(&self) -> Option<&str> {
        self.subtitle.as_deref()
    }

    #[must_use]
    pub fn release_date(&self) -> Option<&str> {
        self.release_date.as_deref()
    }

    #[must_use]
    pub fn description(&self) -> Option<&str> {
        self.description.as_deref()
    }

    #[must_use]
    pub fn language(&self) -> Option<&str> {
        self.language.as_deref()
    }

    #[must_use]
    pub fn album_type(&self) -> Option<&str> {
        self.album_type.as_deref()
    }

    #[must_use]
    pub fn genre(&self) -> Option<&str> {
        self.genre.as_deref()
    }

    #[must_use]
    pub fn company(&self) -> Option<&str> {
        self.company.as_deref()
    }
}

impl fmt::Debug for QqMusicAlbumDetails {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicAlbumDetails")
            .field("album", &self.album)
            .field("artist_count", &self.artists.len())
            .field("has_subtitle", &self.subtitle.is_some())
            .field("has_release_date", &self.release_date.is_some())
            .field("has_description", &self.description.is_some())
            .field("has_language", &self.language.is_some())
            .field("has_album_type", &self.album_type.is_some())
            .field("has_genre", &self.genre.is_some())
            .field("has_company", &self.company.is_some())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Loads public canonical Album metadata without account material.
    ///
    /// # Errors
    ///
    /// Keeps input, transport, service, identity, Artist, and bounded text
    /// failures distinct without retaining returned content in diagnostics.
    pub async fn album_details(
        &self,
        album_mid: &str,
    ) -> Result<QqMusicAlbumDetails, QqMusicAlbumDetailsError<T::Error>> {
        if !safe_mid(album_mid) {
            return Err(QqMusicAlbumDetailsError::InvalidAlbumMid);
        }
        let body = serde_json::to_vec(&AlbumDetailsRequest::new(album_mid))
            .map_err(|_| QqMusicAlbumDetailsError::Serialize)?;
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
            .map_err(QqMusicAlbumDetailsError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicAlbumDetailsError::HttpStatus(response.status()));
        }
        let envelope: AlbumDetailsResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicAlbumDetailsError::InvalidJson)?;
        map_response(envelope, album_mid)
    }
}

#[derive(Serialize)]
struct AlbumDetailsRequest<'a> {
    comm: AlbumDetailsComm,
    album: AlbumDetailsRpc<'a>,
}

impl<'a> AlbumDetailsRequest<'a> {
    const fn new(album_mid: &'a str) -> Self {
        Self {
            comm: AlbumDetailsComm {
                client_type: 24,
                client_version: 0,
                format: "json",
            },
            album: AlbumDetailsRpc {
                module: "music.musichallAlbum.AlbumInfoServer",
                method: "GetAlbumDetail",
                param: AlbumDetailsParam { album_mid },
            },
        }
    }
}

#[derive(Serialize)]
struct AlbumDetailsComm {
    #[serde(rename = "ct")]
    client_type: u32,
    #[serde(rename = "cv")]
    client_version: u32,
    format: &'static str,
}

#[derive(Serialize)]
struct AlbumDetailsRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: AlbumDetailsParam<'a>,
}

#[derive(Serialize)]
struct AlbumDetailsParam<'a> {
    #[serde(rename = "albumMId")]
    album_mid: &'a str,
}

#[derive(Deserialize)]
struct AlbumDetailsResponse {
    code: Option<i64>,
    album: Option<AlbumDetailsResult>,
}

#[derive(Deserialize)]
struct AlbumDetailsResult {
    code: Option<i64>,
    data: Option<RawAlbumDetailsData>,
}

#[derive(Deserialize)]
struct RawAlbumDetailsData {
    #[serde(rename = "basicInfo")]
    basic_info: Option<RawAlbumBasicInfo>,
    company: Option<RawAlbumCompany>,
    singer: Option<RawAlbumSingerGroup>,
}

#[derive(Deserialize)]
struct RawAlbumBasicInfo {
    #[serde(rename = "albumID")]
    album_id: Option<u64>,
    #[serde(rename = "albumMid")]
    album_mid: Option<String>,
    #[serde(rename = "albumName")]
    album_name: Option<String>,
    #[serde(rename = "tranName")]
    subtitle: Option<String>,
    #[serde(rename = "publishDate")]
    release_date: Option<String>,
    desc: Option<String>,
    language: Option<String>,
    #[serde(rename = "albumType")]
    album_type: Option<String>,
    genre: Option<String>,
}

#[derive(Deserialize)]
struct RawAlbumCompany {
    name: Option<String>,
}

#[derive(Deserialize)]
struct RawAlbumSingerGroup {
    #[serde(rename = "singerList")]
    singer_list: Option<Vec<RawAlbumArtist>>,
}

#[derive(Deserialize)]
struct RawAlbumArtist {
    #[serde(rename = "singerID")]
    artist_id: Option<u64>,
    mid: Option<String>,
    name: Option<String>,
}

fn map_response<E>(
    envelope: AlbumDetailsResponse,
    requested_mid: &str,
) -> Result<QqMusicAlbumDetails, QqMusicAlbumDetailsError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicAlbumDetailsError::MissingGlobalCode)?;
    let result_code = envelope.album.as_ref().and_then(|result| result.code);
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicAlbumDetailsError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .album
        .ok_or(QqMusicAlbumDetailsError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicAlbumDetailsError::MissingResultCode)?;
    let data = result.data.ok_or(QqMusicAlbumDetailsError::MissingData)?;
    let basic = data
        .basic_info
        .ok_or(QqMusicAlbumDetailsError::MissingBasicInfo)?;
    let numeric_album_id = basic.album_id.filter(|value| *value != 0).ok_or(
        QqMusicAlbumDetailsError::InvalidAlbum {
            field: AlbumDetailField::AlbumId,
        },
    )?;
    let response_mid = basic.album_mid.filter(|value| safe_mid(value)).ok_or(
        QqMusicAlbumDetailsError::InvalidAlbum {
            field: AlbumDetailField::AlbumMid,
        },
    )?;
    if response_mid != requested_mid {
        return Err(QqMusicAlbumDetailsError::MismatchedAlbumMid);
    }
    let title = required_text(
        basic.album_name,
        MAX_SHORT_TEXT_BYTES,
        AlbumDetailField::Title,
    )?;
    let singer_group = data
        .singer
        .ok_or(QqMusicAlbumDetailsError::MissingSingers)?;
    let raw_artists = singer_group
        .singer_list
        .ok_or(QqMusicAlbumDetailsError::MissingSingers)?;
    let artists = raw_artists
        .into_iter()
        .enumerate()
        .map(|(index, artist)| map_artist(artist, index))
        .collect::<Result<Vec<_>, _>>()?;
    let company = data.company.and_then(|value| value.name);
    Ok(QqMusicAlbumDetails {
        album: QqMusicAlbumSummary::new(Some(numeric_album_id), Some(response_mid), Some(title)),
        artists,
        subtitle: optional_text(
            basic.subtitle,
            MAX_SHORT_TEXT_BYTES,
            AlbumDetailField::Subtitle,
        )?,
        release_date: optional_text(
            basic.release_date,
            MAX_SHORT_TEXT_BYTES,
            AlbumDetailField::ReleaseDate,
        )?,
        description: optional_text(
            basic.desc,
            MAX_DESCRIPTION_BYTES,
            AlbumDetailField::Description,
        )?,
        language: optional_text(
            basic.language,
            MAX_SHORT_TEXT_BYTES,
            AlbumDetailField::Language,
        )?,
        album_type: optional_text(
            basic.album_type,
            MAX_SHORT_TEXT_BYTES,
            AlbumDetailField::AlbumType,
        )?,
        genre: optional_text(basic.genre, MAX_SHORT_TEXT_BYTES, AlbumDetailField::Genre)?,
        company: optional_text(company, MAX_SHORT_TEXT_BYTES, AlbumDetailField::Company)?,
    })
}

fn map_artist<E>(
    raw: RawAlbumArtist,
    index: usize,
) -> Result<QqMusicArtistSummary, QqMusicAlbumDetailsError<E>> {
    let numeric_artist_id = raw.artist_id.filter(|value| *value != 0).ok_or(
        QqMusicAlbumDetailsError::InvalidArtist {
            index,
            field: AlbumDetailField::ArtistId,
        },
    )?;
    let opaque_artist_mid =
        raw.mid
            .filter(|value| safe_mid(value))
            .ok_or(QqMusicAlbumDetailsError::InvalidArtist {
                index,
                field: AlbumDetailField::ArtistMid,
            })?;
    let name = required_artist_text(raw.name, index)?;
    Ok(QqMusicArtistSummary::new(
        Some(numeric_artist_id),
        Some(opaque_artist_mid),
        name,
    ))
}

fn required_artist_text<E>(
    value: Option<String>,
    index: usize,
) -> Result<String, QqMusicAlbumDetailsError<E>> {
    value
        .filter(|value| !value.trim().is_empty() && value.len() <= MAX_SHORT_TEXT_BYTES)
        .ok_or(QqMusicAlbumDetailsError::InvalidArtist {
            index,
            field: AlbumDetailField::ArtistName,
        })
}

fn required_text<E>(
    value: Option<String>,
    max_bytes: usize,
    field: AlbumDetailField,
) -> Result<String, QqMusicAlbumDetailsError<E>> {
    value
        .filter(|value| !value.trim().is_empty() && value.len() <= max_bytes)
        .ok_or(QqMusicAlbumDetailsError::InvalidAlbum { field })
}

fn optional_text<E>(
    value: Option<String>,
    max_bytes: usize,
    field: AlbumDetailField,
) -> Result<Option<String>, QqMusicAlbumDetailsError<E>> {
    match value {
        None => Ok(None),
        Some(value) if value.trim().is_empty() => Ok(None),
        Some(value) if value.len() <= max_bytes => Ok(Some(value)),
        Some(_) => Err(QqMusicAlbumDetailsError::InvalidMetadata { field }),
    }
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

    use super::{AlbumDetailField, QqMusicAlbumDetailsError};

    struct AlbumDetailsTransport {
        response: HttpResponse,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl AlbumDetailsTransport {
        fn new(body: &Value) -> Self {
            Self {
                response: HttpResponse::new(200, serde_json::to_vec(body).expect("JSON")),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn requests(&self) -> Vec<HttpRequest> {
            self.requests.lock().expect("requests").clone()
        }
    }

    impl HttpTransport for AlbumDetailsTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("requests").push(request);
            Ok(self.response.clone())
        }
    }

    fn response(basic: &Value, singers: &Value) -> Value {
        json!({
            "code": 0,
            "album": {
                "code": 0,
                "data": {
                    "basicInfo": basic,
                    "company": {"name": "Private Company"},
                    "singer": {"singerList": singers}
                }
            }
        })
    }

    fn basic() -> Value {
        json!({
            "albumID": 43001,
            "albumMid": "fixtureAlbumMid",
            "albumName": "Private Album",
            "tranName": "Private Subtitle",
            "publishDate": "2026-08-26",
            "desc": "Private Description",
            "language": "Private Language",
            "albumType": "Private Type",
            "genre": "Private Genre"
        })
    }

    fn singers() -> Value {
        json!([{
            "singerID": 42001,
            "mid": "fixtureArtistMid",
            "name": "Private Artist"
        }])
    }

    #[tokio::test]
    async fn serializes_exact_mid_request_and_maps_bounded_metadata() {
        let client =
            QqMusicClient::new(AlbumDetailsTransport::new(&response(&basic(), &singers())));

        let details = client
            .album_details("fixtureAlbumMid")
            .await
            .expect("Album details");

        assert_eq!(details.album().album_id(), Some(43001));
        assert_eq!(details.album().media_mid(), Some("fixtureAlbumMid"));
        assert_eq!(details.album().name(), Some("Private Album"));
        assert_eq!(details.artists()[0].artist_id(), Some(42001));
        assert_eq!(details.subtitle(), Some("Private Subtitle"));
        assert_eq!(details.release_date(), Some("2026-08-26"));
        assert_eq!(details.description(), Some("Private Description"));
        assert_eq!(details.language(), Some("Private Language"));
        assert_eq!(details.album_type(), Some("Private Type"));
        assert_eq!(details.genre(), Some("Private Genre"));
        assert_eq!(details.company(), Some("Private Company"));

        let requests = client.transport().requests();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].method(), HttpMethod::Post);
        assert_eq!(requests[0].max_response_body_bytes(), 2 * 1024 * 1024);
        assert!(
            requests[0]
                .headers()
                .iter()
                .all(|(name, _)| name != "Cookie")
        );
        let body: Value =
            serde_json::from_slice(requests[0].body_bytes().expect("body")).expect("JSON");
        assert_eq!(body["comm"], json!({"ct": 24, "cv": 0, "format": "json"}));
        assert_eq!(
            body["album"]["module"],
            "music.musichallAlbum.AlbumInfoServer"
        );
        assert_eq!(body["album"]["method"], "GetAlbumDetail");
        assert_eq!(
            body["album"]["param"],
            json!({"albumMId": "fixtureAlbumMid"})
        );
        let debug = format!("{details:?} {:?}", requests[0]);
        for private in [
            "fixtureAlbumMid",
            "Private Album",
            "Private Artist",
            "Private Description",
            "2026-08-26",
            "43001",
            "42001",
        ] {
            assert!(!debug.contains(private));
        }
    }

    #[tokio::test]
    async fn rejects_invalid_or_mismatched_identity_without_content_diagnostics() {
        let client =
            QqMusicClient::new(AlbumDetailsTransport::new(&response(&basic(), &singers())));
        assert!(matches!(
            client.album_details("unsafe/mid").await,
            Err(QqMusicAlbumDetailsError::InvalidAlbumMid)
        ));
        assert!(client.transport().requests().is_empty());

        let mismatched =
            QqMusicClient::new(AlbumDetailsTransport::new(&response(&basic(), &singers())));
        let error = mismatched
            .album_details("differentSafeMid")
            .await
            .expect_err("mismatched MID");
        assert!(matches!(
            error,
            QqMusicAlbumDetailsError::MismatchedAlbumMid
        ));
        assert!(!format!("{error:?}").contains("fixtureAlbumMid"));

        let invalid_artist = QqMusicClient::new(AlbumDetailsTransport::new(&response(
            &basic(),
            &json!([{"singerID": 0, "mid": "fixtureArtistMid", "name": "Private Artist"}]),
        )));
        assert!(matches!(
            invalid_artist.album_details("fixtureAlbumMid").await,
            Err(QqMusicAlbumDetailsError::InvalidArtist {
                index: 0,
                field: AlbumDetailField::ArtistId
            })
        ));
    }

    #[tokio::test]
    async fn normalizes_empty_optional_fields_and_rejects_oversized_text() {
        let mut empty = basic();
        empty["tranName"] = json!("   ");
        empty["desc"] = Value::Null;
        let client = QqMusicClient::new(AlbumDetailsTransport::new(&response(&empty, &json!([]))));
        let details = client
            .album_details("fixtureAlbumMid")
            .await
            .expect("optional metadata");
        assert_eq!(details.subtitle(), None);
        assert_eq!(details.description(), None);
        assert!(details.artists().is_empty());

        let mut oversized = basic();
        oversized["desc"] = json!("x".repeat(128 * 1024 + 1));
        let client = QqMusicClient::new(AlbumDetailsTransport::new(&response(
            &oversized,
            &singers(),
        )));
        assert!(matches!(
            client.album_details("fixtureAlbumMid").await,
            Err(QqMusicAlbumDetailsError::InvalidMetadata {
                field: AlbumDetailField::Description
            })
        ));
    }
}
