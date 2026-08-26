use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::{HttpRequest, HttpTransport, QqMusicAlbumSummary, QqMusicArtistSummary, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_PAGE_SIZE: u32 = 30;

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum QqMusicNewAlbumArea {
    MainlandChina,
    HongKongTaiwan,
    Western,
    Korea,
    Japan,
    Other,
}

impl QqMusicNewAlbumArea {
    const fn code(self) -> u8 {
        match self {
            Self::MainlandChina => 1,
            Self::HongKongTaiwan => 2,
            Self::Western => 3,
            Self::Korea => 4,
            Self::Japan => 5,
            Self::Other => 6,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NewAlbumField {
    AlbumId,
    AlbumMid,
    Title,
    ArtistId,
    ArtistMid,
    ArtistName,
}

pub enum QqMusicNewAlbumsError<E> {
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
    MissingTotal,
    MissingAlbums,
    InvalidPagination,
    InvalidAlbum {
        index: usize,
        field: NewAlbumField,
    },
    InvalidArtist {
        album_index: usize,
        artist_index: usize,
        field: NewAlbumField,
    },
}

impl<E> fmt::Debug for QqMusicNewAlbumsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
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
            Self::MissingTotal => formatter.write_str("MissingTotal"),
            Self::MissingAlbums => formatter.write_str("MissingAlbums"),
            Self::InvalidPagination => formatter.write_str("InvalidPagination"),
            Self::InvalidAlbum { index, field } => formatter
                .debug_struct("InvalidAlbum")
                .field("index", index)
                .field("field", field)
                .finish(),
            Self::InvalidArtist {
                album_index,
                artist_index,
                field,
            } => formatter
                .debug_struct("InvalidArtist")
                .field("album_index", album_index)
                .field("artist_index", artist_index)
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicNewAlbumsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidPageSize { size } => {
                write!(
                    formatter,
                    "new Album page size {size} is outside 1..={MAX_PAGE_SIZE}"
                )
            }
            Self::Transport(_) => formatter.write_str("QQ Music new Album request failed"),
            Self::Serialize => formatter.write_str("could not serialize new Album request"),
            Self::HttpStatus(status) => {
                write!(formatter, "new Album request returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("new Album response was not valid JSON"),
            Self::MissingGlobalCode => formatter.write_str("new Album response has no global code"),
            Self::MissingResult => formatter.write_str("new Album result is missing"),
            Self::MissingResultCode => formatter.write_str("new Album result has no code"),
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "new Album request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("new Album data is missing"),
            Self::MissingTotal => formatter.write_str("new Album total is missing"),
            Self::MissingAlbums => formatter.write_str("new Album list is missing"),
            Self::InvalidPagination => formatter.write_str("new Album pagination is invalid"),
            Self::InvalidAlbum { index, field } => {
                write!(formatter, "new Album {index} has an invalid {field:?}")
            }
            Self::InvalidArtist {
                album_index,
                artist_index,
                field,
            } => write!(
                formatter,
                "new Album {album_index} Artist {artist_index} has an invalid {field:?}"
            ),
        }
    }
}

impl<E> std::error::Error for QqMusicNewAlbumsError<E>
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
pub struct QqMusicNewAlbumRelease {
    album: QqMusicAlbumSummary,
    artists: Vec<QqMusicArtistSummary>,
    release_date: Option<String>,
}

impl QqMusicNewAlbumRelease {
    #[must_use]
    pub const fn album(&self) -> &QqMusicAlbumSummary {
        &self.album
    }

    #[must_use]
    pub fn artists(&self) -> &[QqMusicArtistSummary] {
        &self.artists
    }

    #[must_use]
    pub fn release_date(&self) -> Option<&str> {
        self.release_date.as_deref()
    }
}

impl fmt::Debug for QqMusicNewAlbumRelease {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicNewAlbumRelease")
            .field("album", &self.album)
            .field("artist_count", &self.artists.len())
            .field("has_release_date", &self.release_date.is_some())
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicNewAlbumPage {
    area: QqMusicNewAlbumArea,
    offset: u32,
    total: u32,
    has_more: bool,
    releases: Vec<QqMusicNewAlbumRelease>,
}

impl QqMusicNewAlbumPage {
    #[must_use]
    pub const fn area(&self) -> QqMusicNewAlbumArea {
        self.area
    }

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
    pub fn releases(&self) -> &[QqMusicNewAlbumRelease] {
        &self.releases
    }
}

impl fmt::Debug for QqMusicNewAlbumPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicNewAlbumPage")
            .field("area", &self.area)
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("release_count", &self.releases.len())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Loads one public regional new-Album page without account material.
    ///
    /// # Errors
    ///
    /// Keeps input, transport, service, response-shape, pagination, Album,
    /// and Artist failures distinct without retaining returned content.
    pub async fn new_album_releases(
        &self,
        area: QqMusicNewAlbumArea,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicNewAlbumPage, QqMusicNewAlbumsError<T::Error>> {
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicNewAlbumsError::InvalidPageSize { size });
        }
        let body = serde_json::to_vec(&NewAlbumsRequest::new(area, offset, size))
            .map_err(|_| QqMusicNewAlbumsError::Serialize)?;
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
            .map_err(QqMusicNewAlbumsError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicNewAlbumsError::HttpStatus(response.status()));
        }
        let envelope: NewAlbumsResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicNewAlbumsError::InvalidJson)?;
        map_response(envelope, area, offset, size)
    }
}

#[derive(Serialize)]
struct NewAlbumsRequest {
    comm: NewAlbumsComm,
    #[serde(rename = "newAlbum")]
    new_album: NewAlbumsRpc,
}

impl NewAlbumsRequest {
    const fn new(area: QqMusicNewAlbumArea, offset: u32, size: u32) -> Self {
        Self {
            comm: NewAlbumsComm {
                client_type: 24,
                client_version: 0,
                format: "json",
            },
            new_album: NewAlbumsRpc {
                module: "newalbum.NewAlbumServer",
                method: "get_new_album_info",
                param: NewAlbumsParam {
                    area: area.code(),
                    size,
                    offset,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct NewAlbumsComm {
    #[serde(rename = "ct")]
    client_type: u32,
    #[serde(rename = "cv")]
    client_version: u32,
    format: &'static str,
}

#[derive(Serialize)]
struct NewAlbumsRpc {
    module: &'static str,
    method: &'static str,
    param: NewAlbumsParam,
}

#[derive(Serialize)]
struct NewAlbumsParam {
    area: u8,
    #[serde(rename = "num")]
    size: u32,
    #[serde(rename = "start")]
    offset: u32,
}

#[derive(Deserialize)]
struct NewAlbumsResponse {
    code: Option<i64>,
    #[serde(rename = "newAlbum")]
    new_album: Option<NewAlbumsResult>,
}

#[derive(Deserialize)]
struct NewAlbumsResult {
    code: Option<i64>,
    data: Option<NewAlbumsData>,
}

#[derive(Deserialize)]
struct NewAlbumsData {
    total: Option<u32>,
    albums: Option<Vec<RawNewAlbum>>,
}

#[derive(Deserialize)]
struct RawNewAlbum {
    id: Option<u64>,
    mid: Option<String>,
    #[serde(alias = "title")]
    name: Option<String>,
    singers: Option<Vec<RawNewAlbumArtist>>,
    release_time: Option<String>,
}

#[derive(Deserialize)]
struct RawNewAlbumArtist {
    id: Option<u64>,
    mid: Option<String>,
    name: Option<String>,
}

fn map_response<E>(
    envelope: NewAlbumsResponse,
    area: QqMusicNewAlbumArea,
    requested_offset: u32,
    requested_size: u32,
) -> Result<QqMusicNewAlbumPage, QqMusicNewAlbumsError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicNewAlbumsError::MissingGlobalCode)?;
    let result_code = envelope.new_album.as_ref().and_then(|result| result.code);
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicNewAlbumsError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .new_album
        .ok_or(QqMusicNewAlbumsError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicNewAlbumsError::MissingResultCode)?;
    let data = result.data.ok_or(QqMusicNewAlbumsError::MissingData)?;
    let total = data.total.ok_or(QqMusicNewAlbumsError::MissingTotal)?;
    if requested_offset > total {
        return Err(QqMusicNewAlbumsError::InvalidPagination);
    }
    let raw_albums = data.albums.ok_or(QqMusicNewAlbumsError::MissingAlbums)?;
    let count =
        u32::try_from(raw_albums.len()).map_err(|_| QqMusicNewAlbumsError::InvalidPagination)?;
    if count > requested_size {
        return Err(QqMusicNewAlbumsError::InvalidPagination);
    }
    let end = requested_offset
        .checked_add(count)
        .ok_or(QqMusicNewAlbumsError::InvalidPagination)?;
    if end > total {
        return Err(QqMusicNewAlbumsError::InvalidPagination);
    }
    let has_more = end < total;
    if has_more && raw_albums.is_empty() {
        return Err(QqMusicNewAlbumsError::InvalidPagination);
    }
    let releases = raw_albums
        .into_iter()
        .enumerate()
        .map(|(index, raw)| map_release(raw, index))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(QqMusicNewAlbumPage {
        area,
        offset: requested_offset,
        total,
        has_more,
        releases,
    })
}

fn map_release<E>(
    raw: RawNewAlbum,
    album_index: usize,
) -> Result<QqMusicNewAlbumRelease, QqMusicNewAlbumsError<E>> {
    let numeric_album_id =
        raw.id
            .filter(|value| *value != 0)
            .ok_or(QqMusicNewAlbumsError::InvalidAlbum {
                index: album_index,
                field: NewAlbumField::AlbumId,
            })?;
    let opaque_album_mid = safe_media_mid(raw.mid).ok_or(QqMusicNewAlbumsError::InvalidAlbum {
        index: album_index,
        field: NewAlbumField::AlbumMid,
    })?;
    let title = nonblank(raw.name).ok_or(QqMusicNewAlbumsError::InvalidAlbum {
        index: album_index,
        field: NewAlbumField::Title,
    })?;
    let artists = raw
        .singers
        .unwrap_or_default()
        .into_iter()
        .enumerate()
        .map(|(artist_index, artist)| map_artist(artist, album_index, artist_index))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(QqMusicNewAlbumRelease {
        album: QqMusicAlbumSummary::new(
            Some(numeric_album_id),
            Some(opaque_album_mid),
            Some(title),
        ),
        artists,
        release_date: nonblank(raw.release_time),
    })
}

fn map_artist<E>(
    raw: RawNewAlbumArtist,
    album_index: usize,
    artist_index: usize,
) -> Result<QqMusicArtistSummary, QqMusicNewAlbumsError<E>> {
    let numeric_artist_id =
        raw.id
            .filter(|value| *value != 0)
            .ok_or(QqMusicNewAlbumsError::InvalidArtist {
                album_index,
                artist_index,
                field: NewAlbumField::ArtistId,
            })?;
    let opaque_artist_mid =
        safe_media_mid(raw.mid).ok_or(QqMusicNewAlbumsError::InvalidArtist {
            album_index,
            artist_index,
            field: NewAlbumField::ArtistMid,
        })?;
    let name = nonblank(raw.name).ok_or(QqMusicNewAlbumsError::InvalidArtist {
        album_index,
        artist_index,
        field: NewAlbumField::ArtistName,
    })?;
    Ok(QqMusicArtistSummary::new(
        Some(numeric_artist_id),
        Some(opaque_artist_mid),
        name,
    ))
}

fn nonblank(value: Option<String>) -> Option<String> {
    value.filter(|value| !value.trim().is_empty())
}

fn safe_media_mid(value: Option<String>) -> Option<String> {
    value.filter(|value| {
        !value.is_empty()
            && value.len() <= 64
            && value.bytes().all(|byte| byte.is_ascii_alphanumeric())
    })
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use crate::{HttpMethod, HttpRequest, HttpResponse, HttpTransport, QqMusicClient};

    use super::{NewAlbumField, QqMusicNewAlbumArea, QqMusicNewAlbumsError};

    struct NewAlbumsTransport {
        response: HttpResponse,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl NewAlbumsTransport {
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

    impl HttpTransport for NewAlbumsTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("requests").push(request);
            Ok(self.response.clone())
        }
    }

    fn response(albums: &Value, total: u32) -> Value {
        json!({
            "code": 0,
            "newAlbum": {
                "code": 0,
                "data": {"total": total, "albums": albums}
            }
        })
    }

    fn synthetic_albums() -> Value {
        json!([{
            "id": 43001,
            "mid": "fixtureAlbumMid",
            "name": "Private Album Title",
            "release_time": "2026-08-26",
            "singers": [{
                "id": 42001,
                "mid": "fixtureArtistMid",
                "name": "Private Artist"
            }]
        }])
    }

    #[tokio::test]
    async fn serializes_evidenced_area_pagination_and_maps_release() {
        let client =
            QqMusicClient::new(NewAlbumsTransport::new(&response(&synthetic_albums(), 11)));

        let page = client
            .new_album_releases(QqMusicNewAlbumArea::Japan, 5, 5)
            .await
            .expect("new Album page");

        assert_eq!(page.area(), QqMusicNewAlbumArea::Japan);
        assert_eq!(page.offset(), 5);
        assert_eq!(page.total(), 11);
        assert!(page.has_more());
        assert_eq!(page.releases().len(), 1);
        let release = &page.releases()[0];
        assert_eq!(release.album().album_id(), Some(43001));
        assert_eq!(release.album().media_mid(), Some("fixtureAlbumMid"));
        assert_eq!(release.artists()[0].artist_id(), Some(42001));
        assert_eq!(release.release_date(), Some("2026-08-26"));

        let requests = client.transport().requests();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].method(), HttpMethod::Post);
        assert_eq!(requests[0].url(), "https://u.y.qq.com/cgi-bin/musicu.fcg");
        assert_eq!(requests[0].max_response_body_bytes(), 2 * 1024 * 1024);
        assert!(
            requests[0]
                .headers()
                .iter()
                .all(|(name, _)| name != "Cookie")
        );
        let body: Value =
            serde_json::from_slice(requests[0].body_bytes().expect("body")).expect("request JSON");
        assert_eq!(body["comm"], json!({"ct": 24, "cv": 0, "format": "json"}));
        assert_eq!(body["newAlbum"]["module"], "newalbum.NewAlbumServer");
        assert_eq!(body["newAlbum"]["method"], "get_new_album_info");
        assert_eq!(
            body["newAlbum"]["param"],
            json!({"area": 5, "num": 5, "start": 5})
        );
        let debug = format!("{page:?} {:?}", requests[0]);
        assert!(!debug.contains("fixtureAlbumMid"));
        assert!(!debug.contains("Private Album Title"));
        assert!(!debug.contains("fixtureArtistMid"));
        assert!(!debug.contains("2026-08-26"));
    }

    #[tokio::test]
    async fn rejects_invalid_size_and_pagination_before_or_after_transport() {
        let client = QqMusicClient::new(NewAlbumsTransport::new(&response(&json!([]), 0)));
        assert!(matches!(
            client
                .new_album_releases(QqMusicNewAlbumArea::MainlandChina, 0, 0)
                .await,
            Err(QqMusicNewAlbumsError::InvalidPageSize { size: 0 })
        ));
        assert!(matches!(
            client
                .new_album_releases(QqMusicNewAlbumArea::Other, 0, 31)
                .await,
            Err(QqMusicNewAlbumsError::InvalidPageSize { size: 31 })
        ));
        assert!(client.transport().requests().is_empty());

        let empty_more = QqMusicClient::new(NewAlbumsTransport::new(&response(&json!([]), 2)));
        assert!(matches!(
            empty_more
                .new_album_releases(QqMusicNewAlbumArea::Western, 0, 5)
                .await,
            Err(QqMusicNewAlbumsError::InvalidPagination)
        ));
        let oversized = QqMusicClient::new(NewAlbumsTransport::new(&response(
            &json!([
                {"id": 1, "mid": "albumMidOne", "name": "one", "singers": []},
                {"id": 2, "mid": "albumMidTwo", "name": "two", "singers": []}
            ]),
            2,
        )));
        assert!(matches!(
            oversized
                .new_album_releases(QqMusicNewAlbumArea::Korea, 0, 1)
                .await,
            Err(QqMusicNewAlbumsError::InvalidPagination)
        ));
    }

    #[tokio::test]
    async fn rejects_invalid_album_and_artist_without_content_diagnostics() {
        let invalid_album = QqMusicClient::new(NewAlbumsTransport::new(&response(
            &json!([{"id": 43001, "mid": "unsafe/mid", "name": "private", "singers": []}]),
            1,
        )));
        let error = invalid_album
            .new_album_releases(QqMusicNewAlbumArea::HongKongTaiwan, 0, 5)
            .await
            .expect_err("invalid Album");
        assert!(matches!(
            error,
            QqMusicNewAlbumsError::InvalidAlbum {
                index: 0,
                field: NewAlbumField::AlbumMid
            }
        ));
        assert!(!format!("{error:?}").contains("unsafe/mid"));

        let invalid_artist = QqMusicClient::new(NewAlbumsTransport::new(&response(
            &json!([{
                "id": 43001,
                "mid": "fixtureAlbumMid",
                "name": "private album",
                "singers": [{"id": 0, "mid": "fixtureArtistMid", "name": "private artist"}]
            }]),
            1,
        )));
        let error = invalid_artist
            .new_album_releases(QqMusicNewAlbumArea::MainlandChina, 0, 5)
            .await
            .expect_err("invalid Artist");
        assert!(matches!(
            error,
            QqMusicNewAlbumsError::InvalidArtist {
                album_index: 0,
                artist_index: 0,
                field: NewAlbumField::ArtistId
            }
        ));
        let debug = format!("{error:?}");
        assert!(!debug.contains("private album"));
        assert!(!debug.contains("private artist"));
    }
}
