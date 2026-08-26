use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::{HttpRequest, HttpTransport, QqMusicAlbumSummary, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_PAGE_SIZE: u32 = 30;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ArtistAlbumField {
    AlbumId,
    AlbumMid,
    Title,
}

pub enum QqMusicArtistAlbumsError<E> {
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
    MissingAlbums,
    InvalidPagination,
    InvalidAlbum {
        index: usize,
        field: ArtistAlbumField,
    },
}

impl<E> fmt::Debug for QqMusicArtistAlbumsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
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
            Self::MissingAlbums => formatter.write_str("MissingAlbums"),
            Self::InvalidPagination => formatter.write_str("InvalidPagination"),
            Self::InvalidAlbum { index, field } => formatter
                .debug_struct("InvalidAlbum")
                .field("index", index)
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicArtistAlbumsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidArtistMid => formatter.write_str("artist MID is invalid"),
            Self::InvalidPageSize { size } => write!(
                formatter,
                "Artist Album page size {size} is outside 1..={MAX_PAGE_SIZE}"
            ),
            Self::Transport(_) => formatter.write_str("QQ Music Artist Album request failed"),
            Self::Serialize => formatter.write_str("could not serialize Artist Album request"),
            Self::HttpStatus(status) => {
                write!(formatter, "Artist Album request returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("Artist Album response was not valid JSON"),
            Self::MissingGlobalCode => {
                formatter.write_str("Artist Album response has no global code")
            }
            Self::MissingResult => formatter.write_str("Artist Album result is missing"),
            Self::MissingResultCode => formatter.write_str("Artist Album result has no code"),
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "Artist Album request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("Artist Album data is missing"),
            Self::MissingArtistMid => formatter.write_str("Artist Album Artist MID is missing"),
            Self::MismatchedArtistMid => {
                formatter.write_str("Artist Album Artist MID did not match the request")
            }
            Self::MissingTotal => formatter.write_str("Artist Album total is missing"),
            Self::MissingAlbums => formatter.write_str("Artist Album list is missing"),
            Self::InvalidPagination => formatter.write_str("Artist Album pagination is invalid"),
            Self::InvalidAlbum { index, field } => {
                write!(formatter, "Artist Album {index} has an invalid {field:?}")
            }
        }
    }
}

impl<E> std::error::Error for QqMusicArtistAlbumsError<E>
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
pub struct QqMusicArtistAlbumPage {
    offset: u32,
    total: u32,
    has_more: bool,
    albums: Vec<QqMusicAlbumSummary>,
}

impl QqMusicArtistAlbumPage {
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
    pub fn albums(&self) -> &[QqMusicAlbumSummary] {
        &self.albums
    }
}

impl fmt::Debug for QqMusicArtistAlbumPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicArtistAlbumPage")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("album_count", &self.albums.len())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Loads one public offset-paged Artist Album list without account material.
    ///
    /// # Errors
    ///
    /// Keeps input, transport, service, response-shape, pagination, and Album
    /// mapping failures distinct without retaining Artist or Album content.
    pub async fn artist_albums(
        &self,
        expected_mid: &str,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicArtistAlbumPage, QqMusicArtistAlbumsError<T::Error>> {
        if !safe_mid(expected_mid) {
            return Err(QqMusicArtistAlbumsError::InvalidArtistMid);
        }
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicArtistAlbumsError::InvalidPageSize { size });
        }
        let body = serde_json::to_vec(&ArtistAlbumsRequest::new(expected_mid, offset, size))
            .map_err(|_| QqMusicArtistAlbumsError::Serialize)?;
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
            .map_err(QqMusicArtistAlbumsError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicArtistAlbumsError::HttpStatus(response.status()));
        }
        let envelope: ArtistAlbumsResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicArtistAlbumsError::InvalidJson)?;
        map_response(envelope, expected_mid, offset, size)
    }
}

#[derive(Serialize)]
struct ArtistAlbumsRequest<'a> {
    comm: ArtistAlbumsComm,
    #[serde(rename = "artistAlbums")]
    artist_albums: ArtistAlbumsRpc<'a>,
}

impl<'a> ArtistAlbumsRequest<'a> {
    const fn new(artist_mid: &'a str, offset: u32, size: u32) -> Self {
        Self {
            comm: ArtistAlbumsComm {
                client_type: 24,
                client_version: 0,
            },
            artist_albums: ArtistAlbumsRpc {
                module: "music.musichallAlbum.AlbumListServer",
                method: "GetAlbumList",
                param: ArtistAlbumsParam {
                    artist_mid,
                    order: 1,
                    offset,
                    size,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct ArtistAlbumsComm {
    #[serde(rename = "ct")]
    client_type: u32,
    #[serde(rename = "cv")]
    client_version: u32,
}

#[derive(Serialize)]
struct ArtistAlbumsRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: ArtistAlbumsParam<'a>,
}

#[derive(Serialize)]
struct ArtistAlbumsParam<'a> {
    #[serde(rename = "singerMid")]
    artist_mid: &'a str,
    order: u8,
    #[serde(rename = "begin")]
    offset: u32,
    #[serde(rename = "num")]
    size: u32,
}

#[derive(Deserialize)]
struct ArtistAlbumsResponse {
    code: Option<i64>,
    #[serde(rename = "artistAlbums")]
    artist_albums: Option<ArtistAlbumsResult>,
}

#[derive(Deserialize)]
struct ArtistAlbumsResult {
    code: Option<i64>,
    data: Option<ArtistAlbumsData>,
}

#[derive(Deserialize)]
struct ArtistAlbumsData {
    #[serde(rename = "singerMid")]
    artist_mid: Option<String>,
    total: Option<u32>,
    #[serde(rename = "albumList")]
    albums: Option<Vec<RawArtistAlbum>>,
}

#[derive(Deserialize)]
struct RawArtistAlbum {
    #[serde(rename = "albumID")]
    album_id: Option<u64>,
    #[serde(rename = "albumMid")]
    album_mid: Option<String>,
    #[serde(rename = "albumName")]
    title: Option<String>,
}

fn map_response<E>(
    envelope: ArtistAlbumsResponse,
    requested_mid: &str,
    requested_offset: u32,
    requested_size: u32,
) -> Result<QqMusicArtistAlbumPage, QqMusicArtistAlbumsError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicArtistAlbumsError::MissingGlobalCode)?;
    let result_code = envelope
        .artist_albums
        .as_ref()
        .and_then(|result| result.code);
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicArtistAlbumsError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .artist_albums
        .ok_or(QqMusicArtistAlbumsError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicArtistAlbumsError::MissingResultCode)?;
    let data = result.data.ok_or(QqMusicArtistAlbumsError::MissingData)?;
    let artist_mid = data
        .artist_mid
        .ok_or(QqMusicArtistAlbumsError::MissingArtistMid)?;
    if artist_mid != requested_mid {
        return Err(QqMusicArtistAlbumsError::MismatchedArtistMid);
    }
    let total = data.total.ok_or(QqMusicArtistAlbumsError::MissingTotal)?;
    if requested_offset > total {
        return Err(QqMusicArtistAlbumsError::InvalidPagination);
    }
    let raw_albums = data.albums.ok_or(QqMusicArtistAlbumsError::MissingAlbums)?;
    let count =
        u32::try_from(raw_albums.len()).map_err(|_| QqMusicArtistAlbumsError::InvalidPagination)?;
    if count > requested_size {
        return Err(QqMusicArtistAlbumsError::InvalidPagination);
    }
    let end = requested_offset
        .checked_add(count)
        .ok_or(QqMusicArtistAlbumsError::InvalidPagination)?;
    if end > total {
        return Err(QqMusicArtistAlbumsError::InvalidPagination);
    }
    let has_more = end < total;
    if has_more && raw_albums.is_empty() {
        return Err(QqMusicArtistAlbumsError::InvalidPagination);
    }
    let albums = raw_albums
        .into_iter()
        .enumerate()
        .map(|(index, raw)| map_album(raw, index))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(QqMusicArtistAlbumPage {
        offset: requested_offset,
        total,
        has_more,
        albums,
    })
}

fn map_album<E>(
    raw: RawArtistAlbum,
    index: usize,
) -> Result<QqMusicAlbumSummary, QqMusicArtistAlbumsError<E>> {
    let numeric_album_id =
        raw.album_id
            .filter(|value| *value != 0)
            .ok_or(QqMusicArtistAlbumsError::InvalidAlbum {
                index,
                field: ArtistAlbumField::AlbumId,
            })?;
    let catalog_mid =
        safe_media_mid(raw.album_mid).ok_or(QqMusicArtistAlbumsError::InvalidAlbum {
            index,
            field: ArtistAlbumField::AlbumMid,
        })?;
    let title = nonblank(raw.title).ok_or(QqMusicArtistAlbumsError::InvalidAlbum {
        index,
        field: ArtistAlbumField::Title,
    })?;
    Ok(QqMusicAlbumSummary::new(
        Some(numeric_album_id),
        Some(catalog_mid),
        Some(title),
    ))
}

fn nonblank(value: Option<String>) -> Option<String> {
    value.filter(|value| !value.trim().is_empty())
}

fn safe_mid(value: &str) -> bool {
    !value.is_empty() && value.len() <= 64 && value.bytes().all(|byte| byte.is_ascii_alphanumeric())
}

fn safe_media_mid(value: Option<String>) -> Option<String> {
    value.filter(|value| safe_mid(value))
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use crate::{HttpMethod, HttpRequest, HttpResponse, HttpTransport, QqMusicClient};

    use super::{ArtistAlbumField, QqMusicArtistAlbumsError};

    struct ArtistAlbumsTransport {
        response: HttpResponse,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl ArtistAlbumsTransport {
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

    impl HttpTransport for ArtistAlbumsTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("requests").push(request);
            Ok(self.response.clone())
        }
    }

    fn response(albums: &Value, total: u32, artist_mid: &str) -> Value {
        json!({
            "code": 0,
            "artistAlbums": {
                "code": 0,
                "data": {
                    "singerMid": artist_mid,
                    "total": total,
                    "albumList": albums
                }
            }
        })
    }

    fn synthetic_albums() -> Value {
        json!([{
            "albumID": 43001,
            "albumMid": "fixtureAlbumMid",
            "albumName": "Private Album Title"
        }])
    }

    #[tokio::test]
    async fn serializes_live_evidenced_num_field_and_maps_page() {
        let client = QqMusicClient::new(ArtistAlbumsTransport::new(&response(
            &synthetic_albums(),
            11,
            "fixtureArtistMid",
        )));

        let page = client
            .artist_albums("fixtureArtistMid", 5, 5)
            .await
            .expect("Artist Album page");

        assert_eq!(page.offset(), 5);
        assert_eq!(page.total(), 11);
        assert!(page.has_more());
        assert_eq!(page.albums().len(), 1);
        assert_eq!(page.albums()[0].album_id(), Some(43001));
        assert_eq!(page.albums()[0].media_mid(), Some("fixtureAlbumMid"));
        assert_eq!(page.albums()[0].name(), Some("Private Album Title"));

        let requests = client.transport().requests();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].method(), HttpMethod::Post);
        assert_eq!(requests[0].url(), "https://u.y.qq.com/cgi-bin/musicu.fcg");
        assert_eq!(requests[0].max_response_body_bytes(), 2 * 1024 * 1024);
        let body: Value =
            serde_json::from_slice(requests[0].body_bytes().expect("body")).expect("request JSON");
        assert_eq!(body["comm"]["ct"], 24);
        assert_eq!(
            body["artistAlbums"]["module"],
            "music.musichallAlbum.AlbumListServer"
        );
        assert_eq!(body["artistAlbums"]["method"], "GetAlbumList");
        assert_eq!(
            body["artistAlbums"]["param"]["singerMid"],
            "fixtureArtistMid"
        );
        assert_eq!(body["artistAlbums"]["param"]["begin"], 5);
        assert_eq!(body["artistAlbums"]["param"]["num"], 5);
        assert!(body["artistAlbums"]["param"].get("number").is_none());
        let debug = format!("{page:?} {:?}", requests[0]);
        assert!(!debug.contains("fixtureArtistMid"));
        assert!(!debug.contains("fixtureAlbumMid"));
        assert!(!debug.contains("Private Album Title"));
    }

    #[tokio::test]
    async fn rejects_invalid_input_before_transport() {
        let client = QqMusicClient::new(ArtistAlbumsTransport::new(&response(
            &json!([]),
            0,
            "fixtureArtistMid",
        )));

        assert!(matches!(
            client.artist_albums("unsafe/mid", 0, 5).await,
            Err(QqMusicArtistAlbumsError::InvalidArtistMid)
        ));
        assert!(matches!(
            client.artist_albums("fixtureArtistMid", 0, 0).await,
            Err(QqMusicArtistAlbumsError::InvalidPageSize { size: 0 })
        ));
        assert!(matches!(
            client.artist_albums("fixtureArtistMid", 0, 31).await,
            Err(QqMusicArtistAlbumsError::InvalidPageSize { size: 31 })
        ));
        assert!(client.transport().requests().is_empty());
    }

    #[tokio::test]
    async fn rejects_mismatched_identity_invalid_pagination_and_album_shape() {
        let mismatch = QqMusicClient::new(ArtistAlbumsTransport::new(&response(
            &json!([]),
            0,
            "anotherArtistMid",
        )));
        assert!(matches!(
            mismatch.artist_albums("fixtureArtistMid", 0, 5).await,
            Err(QqMusicArtistAlbumsError::MismatchedArtistMid)
        ));

        let oversized = QqMusicClient::new(ArtistAlbumsTransport::new(&response(
            &json!([
                {"albumID": 1, "albumMid": "albumMid1", "albumName": "one"},
                {"albumID": 2, "albumMid": "albumMid2", "albumName": "two"}
            ]),
            2,
            "fixtureArtistMid",
        )));
        assert!(matches!(
            oversized.artist_albums("fixtureArtistMid", 0, 1).await,
            Err(QqMusicArtistAlbumsError::InvalidPagination)
        ));

        let invalid_album = QqMusicClient::new(ArtistAlbumsTransport::new(&response(
            &json!([{"albumID": 43001, "albumMid": "unsafe/mid", "albumName": "private"}]),
            1,
            "fixtureArtistMid",
        )));
        let error = invalid_album
            .artist_albums("fixtureArtistMid", 0, 5)
            .await
            .expect_err("invalid Album");
        assert!(matches!(
            error,
            QqMusicArtistAlbumsError::InvalidAlbum {
                index: 0,
                field: ArtistAlbumField::AlbumMid
            }
        ));
        let debug = format!("{error:?}");
        assert!(!debug.contains("unsafe/mid"));
        assert!(!debug.contains("private"));
    }
}
