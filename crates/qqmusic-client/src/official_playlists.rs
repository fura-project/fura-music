use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::{HttpRequest, HttpTransport, QqMusicClient, normalized_https_image_uri};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const OFFICIAL_PLAYLIST_CATEGORY_ID: u32 = 3317;
const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_PAGE_SIZE: u32 = 30;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OfficialPlaylistField {
    PlaylistId,
    Title,
}

pub enum QqMusicOfficialPlaylistsError<E> {
    InvalidPage {
        page: u32,
    },
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
    MissingPlaylists,
    InvalidPagination,
    InvalidPlaylist {
        index: usize,
        field: OfficialPlaylistField,
    },
}

impl<E> fmt::Debug for QqMusicOfficialPlaylistsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidPage { page } => formatter
                .debug_struct("InvalidPage")
                .field("page", page)
                .finish(),
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
            Self::MissingPlaylists => formatter.write_str("MissingPlaylists"),
            Self::InvalidPagination => formatter.write_str("InvalidPagination"),
            Self::InvalidPlaylist { index, field } => formatter
                .debug_struct("InvalidPlaylist")
                .field("index", index)
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicOfficialPlaylistsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidPage { page } => {
                write!(formatter, "official-playlist page {page} must be one-based")
            }
            Self::InvalidPageSize { size } => write!(
                formatter,
                "official-playlist page size {size} is outside 1..={MAX_PAGE_SIZE}"
            ),
            Self::Transport(_) => formatter.write_str("QQ Music official-playlist request failed"),
            Self::Serialize => formatter.write_str("could not serialize official-playlist request"),
            Self::HttpStatus(status) => {
                write!(
                    formatter,
                    "official-playlist request returned HTTP {status}"
                )
            }
            Self::InvalidJson => {
                formatter.write_str("official-playlist response was not valid JSON")
            }
            Self::MissingGlobalCode => {
                formatter.write_str("official-playlist response has no global code")
            }
            Self::MissingResult => formatter.write_str("official-playlist result is missing"),
            Self::MissingResultCode => formatter.write_str("official-playlist result has no code"),
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "official-playlist request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("official-playlist data is missing"),
            Self::MissingTotal => formatter.write_str("official-playlist total is missing"),
            Self::MissingPlaylists => formatter.write_str("official-playlist array is missing"),
            Self::InvalidPagination => {
                formatter.write_str("official-playlist pagination is invalid")
            }
            Self::InvalidPlaylist { index, field } => {
                write!(
                    formatter,
                    "official playlist {index} has an invalid {field:?}"
                )
            }
        }
    }
}

impl<E> std::error::Error for QqMusicOfficialPlaylistsError<E>
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
pub struct QqMusicOfficialPlaylist {
    playlist_id: u64,
    title: String,
    cover_url: Option<String>,
    creator: Option<String>,
    play_count: Option<u64>,
    categories: Vec<String>,
}

impl QqMusicOfficialPlaylist {
    #[must_use]
    pub const fn playlist_id(&self) -> u64 {
        self.playlist_id
    }

    #[must_use]
    pub fn title(&self) -> &str {
        &self.title
    }

    #[must_use]
    pub fn cover_url(&self) -> Option<&str> {
        self.cover_url.as_deref()
    }

    #[must_use]
    pub fn creator(&self) -> Option<&str> {
        self.creator.as_deref()
    }

    #[must_use]
    pub const fn play_count(&self) -> Option<u64> {
        self.play_count
    }

    #[must_use]
    pub fn categories(&self) -> &[String] {
        &self.categories
    }
}

impl fmt::Debug for QqMusicOfficialPlaylist {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicOfficialPlaylist")
            .field("playlist_id", &"[REDACTED]")
            .field("title", &"[REDACTED]")
            .field("has_cover", &self.cover_url.is_some())
            .field("has_creator", &self.creator.is_some())
            .field("play_count", &self.play_count)
            .field("category_count", &self.categories.len())
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicOfficialPlaylistsPage {
    page: u32,
    next_page: u32,
    total: u32,
    has_more: bool,
    omitted_playlist_count: u32,
    playlists: Vec<QqMusicOfficialPlaylist>,
}

impl QqMusicOfficialPlaylistsPage {
    #[must_use]
    pub const fn page(&self) -> u32 {
        self.page
    }

    #[must_use]
    pub const fn next_page(&self) -> u32 {
        self.next_page
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
    pub const fn omitted_playlist_count(&self) -> u32 {
        self.omitted_playlist_count
    }

    #[must_use]
    pub fn playlists(&self) -> &[QqMusicOfficialPlaylist] {
        &self.playlists
    }
}

impl fmt::Debug for QqMusicOfficialPlaylistsPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicOfficialPlaylistsPage")
            .field("page", &self.page)
            .field("next_page", &self.next_page)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("omitted_playlist_count", &self.omitted_playlist_count)
            .field("playlist_count", &self.playlists.len())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Loads one anonymous bounded page from QQ Music's evidenced official
    /// playlist category.
    ///
    /// # Errors
    ///
    /// Keeps transport, service, response-shape, pagination, and row-mapping
    /// failures distinct without retaining playlist content.
    pub async fn official_playlists(
        &self,
        page: u32,
        size: u32,
    ) -> Result<QqMusicOfficialPlaylistsPage, QqMusicOfficialPlaylistsError<T::Error>> {
        if page == 0 {
            return Err(QqMusicOfficialPlaylistsError::InvalidPage { page });
        }
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicOfficialPlaylistsError::InvalidPageSize { size });
        }
        let request = serde_json::to_string(&OfficialPlaylistsRequest::new(page, size))
            .map_err(|_| QqMusicOfficialPlaylistsError::Serialize)?;
        let response = self
            .transport()
            .execute(
                HttpRequest::get(MUSICU_URL)
                    .query("data", request)
                    .header("Origin", "https://y.qq.com")
                    .header("Referer", "https://y.qq.com/")
                    .response_body_limit(MAX_RESPONSE_BYTES)
                    .timeout(REQUEST_TIMEOUT),
            )
            .await
            .map_err(QqMusicOfficialPlaylistsError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicOfficialPlaylistsError::HttpStatus(response.status()));
        }
        let envelope: OfficialPlaylistsResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicOfficialPlaylistsError::InvalidJson)?;
        map_response(envelope, page, size)
    }
}

#[derive(Serialize)]
struct OfficialPlaylistsRequest {
    comm: OfficialPlaylistComm,
    playlist: OfficialPlaylistsRpc,
}

impl OfficialPlaylistsRequest {
    const fn new(page: u32, size: u32) -> Self {
        Self {
            comm: OfficialPlaylistComm { client_type: 24 },
            playlist: OfficialPlaylistsRpc {
                module: "playlist.PlayListPlazaServer",
                method: "get_playlist_by_category",
                param: OfficialPlaylistsParam {
                    id: OFFICIAL_PLAYLIST_CATEGORY_ID,
                    page,
                    size,
                    order: 5,
                    title_id: OFFICIAL_PLAYLIST_CATEGORY_ID,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct OfficialPlaylistComm {
    #[serde(rename = "ct")]
    client_type: u32,
}

#[derive(Serialize)]
struct OfficialPlaylistsRpc {
    module: &'static str,
    method: &'static str,
    param: OfficialPlaylistsParam,
}

#[derive(Serialize)]
struct OfficialPlaylistsParam {
    id: u32,
    #[serde(rename = "curPage")]
    page: u32,
    size: u32,
    order: u32,
    #[serde(rename = "titleid")]
    title_id: u32,
}

#[derive(Deserialize)]
struct OfficialPlaylistsResponse {
    code: Option<i64>,
    playlist: Option<OfficialPlaylistsResult>,
}

#[derive(Deserialize)]
struct OfficialPlaylistsResult {
    code: Option<i64>,
    data: Option<OfficialPlaylistsData>,
}

#[derive(Deserialize)]
struct OfficialPlaylistsData {
    total: Option<u32>,
    v_playlist: Option<Vec<Value>>,
}

#[derive(Deserialize)]
struct RawOfficialPlaylist {
    tid: Option<u64>,
    title: Option<String>,
    cover_url_big: Option<String>,
    cover_url_medium: Option<String>,
    cover_url_small: Option<String>,
    creator_info: Option<RawOfficialCreator>,
    access_num: Option<u64>,
    tag_names: Option<Vec<String>>,
}

#[derive(Deserialize)]
struct RawOfficialCreator {
    nick: Option<String>,
}

fn map_response<E>(
    envelope: OfficialPlaylistsResponse,
    page: u32,
    requested_size: u32,
) -> Result<QqMusicOfficialPlaylistsPage, QqMusicOfficialPlaylistsError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicOfficialPlaylistsError::MissingGlobalCode)?;
    let result_code = envelope.playlist.as_ref().and_then(|result| result.code);
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicOfficialPlaylistsError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .playlist
        .ok_or(QqMusicOfficialPlaylistsError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicOfficialPlaylistsError::MissingResultCode)?;
    let data = result
        .data
        .ok_or(QqMusicOfficialPlaylistsError::MissingData)?;
    let total = data
        .total
        .ok_or(QqMusicOfficialPlaylistsError::MissingTotal)?;
    let raw_playlists = data
        .v_playlist
        .ok_or(QqMusicOfficialPlaylistsError::MissingPlaylists)?;
    let raw_count = u32::try_from(raw_playlists.len())
        .map_err(|_| QqMusicOfficialPlaylistsError::InvalidPagination)?;
    let consumed = page
        .checked_mul(requested_size)
        .ok_or(QqMusicOfficialPlaylistsError::InvalidPagination)?;
    let has_more = consumed < total;
    if raw_count > requested_size || (has_more && raw_count == 0) {
        return Err(QqMusicOfficialPlaylistsError::InvalidPagination);
    }
    let next_page = page
        .checked_add(1)
        .ok_or(QqMusicOfficialPlaylistsError::InvalidPagination)?;
    let mut playlists = Vec::with_capacity(raw_playlists.len());
    let mut omitted_playlist_count = 0_u32;
    for (index, value) in raw_playlists.into_iter().enumerate() {
        let mapped = serde_json::from_value::<RawOfficialPlaylist>(value)
            .map_err(|_| QqMusicOfficialPlaylistsError::InvalidPlaylist {
                index,
                field: OfficialPlaylistField::PlaylistId,
            })
            .and_then(|playlist| map_playlist(playlist, index));
        match mapped {
            Ok(playlist) => playlists.push(playlist),
            Err(QqMusicOfficialPlaylistsError::InvalidPlaylist { .. }) => {
                omitted_playlist_count = omitted_playlist_count
                    .checked_add(1)
                    .ok_or(QqMusicOfficialPlaylistsError::InvalidPagination)?;
            }
            Err(error) => return Err(error),
        }
    }
    Ok(QqMusicOfficialPlaylistsPage {
        page,
        next_page,
        total,
        has_more,
        omitted_playlist_count,
        playlists,
    })
}

fn map_playlist<E>(
    raw: RawOfficialPlaylist,
    index: usize,
) -> Result<QqMusicOfficialPlaylist, QqMusicOfficialPlaylistsError<E>> {
    let playlist_id = raw.tid.filter(|value| *value != 0).ok_or(
        QqMusicOfficialPlaylistsError::InvalidPlaylist {
            index,
            field: OfficialPlaylistField::PlaylistId,
        },
    )?;
    let title = raw.title.filter(|value| !value.trim().is_empty()).ok_or(
        QqMusicOfficialPlaylistsError::InvalidPlaylist {
            index,
            field: OfficialPlaylistField::Title,
        },
    )?;
    let cover_url = [raw.cover_url_big, raw.cover_url_medium, raw.cover_url_small]
        .into_iter()
        .flatten()
        .find_map(|value| normalized_https_image_uri(Some(value)));
    let creator = raw
        .creator_info
        .and_then(|creator| creator.nick)
        .filter(|value| !value.trim().is_empty());
    let categories = raw
        .tag_names
        .unwrap_or_default()
        .into_iter()
        .filter(|value| !value.trim().is_empty())
        .collect();
    Ok(QqMusicOfficialPlaylist {
        playlist_id,
        title,
        cover_url,
        creator,
        play_count: raw.access_num,
        categories,
    })
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use super::{MAX_RESPONSE_BYTES, QqMusicOfficialPlaylistsError, REQUEST_TIMEOUT};
    use crate::{HttpMethod, HttpRequest, HttpResponse, HttpTransport, QqMusicClient};

    struct OfficialPlaylistTransport {
        response: HttpResponse,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl OfficialPlaylistTransport {
        fn new(response: &Value) -> Self {
            Self {
                response: HttpResponse::new(
                    200,
                    serde_json::to_vec(response).expect("fixture JSON"),
                ),
                requests: Mutex::new(Vec::new()),
            }
        }
    }

    impl HttpTransport for OfficialPlaylistTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("request lock").push(request);
            Ok(self.response.clone())
        }
    }

    #[tokio::test]
    async fn serializes_evidenced_category_page_and_preserves_metadata() {
        let client = QqMusicClient::new(OfficialPlaylistTransport::new(&json!({
            "code": 0,
            "playlist": {
                "code": 0,
                "data": {
                    "total": 736,
                    "v_playlist": [{
                        "tid": 91001,
                        "title": "Fixture official playlist",
                        "cover_url_big": "https://example.invalid/official.jpg",
                        "creator_info": {"nick": "Fixture editor"},
                        "access_num": 123_456,
                        "tag_names": ["Fixture category"]
                    }]
                }
            }
        })));

        let page = client
            .official_playlists(1, 8)
            .await
            .expect("fixture official-playlist page");
        assert_eq!(page.page(), 1);
        assert_eq!(page.next_page(), 2);
        assert_eq!(page.total(), 736);
        assert!(page.has_more());
        assert_eq!(page.playlists().len(), 1);
        let playlist = &page.playlists()[0];
        assert_eq!(playlist.playlist_id(), 91001);
        assert_eq!(playlist.title(), "Fixture official playlist");
        assert_eq!(
            playlist.cover_url(),
            Some("https://example.invalid/official.jpg")
        );
        assert_eq!(playlist.creator(), Some("Fixture editor"));
        assert_eq!(playlist.play_count(), Some(123_456));
        assert_eq!(playlist.categories(), ["Fixture category"]);

        let request = &client.transport().requests.lock().expect("request lock")[0];
        assert_eq!(request.method(), HttpMethod::Get);
        assert_eq!(request.max_response_body_bytes(), MAX_RESPONSE_BYTES);
        assert_eq!(request.request_timeout(), Some(REQUEST_TIMEOUT));
        assert!(request.headers().iter().all(|(name, _)| name != "Cookie"));
        assert!(request.body_bytes().is_none());
        let request_json: Value = serde_json::from_str(
            request
                .query_pairs()
                .iter()
                .find(|(name, _)| name == "data")
                .map(|(_, value)| value.as_str())
                .expect("data query"),
        )
        .expect("request JSON");
        assert_eq!(request_json["comm"]["ct"], 24);
        assert_eq!(
            request_json["playlist"]["module"],
            "playlist.PlayListPlazaServer"
        );
        assert_eq!(
            request_json["playlist"]["method"],
            "get_playlist_by_category"
        );
        assert_eq!(request_json["playlist"]["param"]["id"], 3317);
        assert_eq!(request_json["playlist"]["param"]["titleid"], 3317);
        assert_eq!(request_json["playlist"]["param"]["curPage"], 1);
        assert_eq!(request_json["playlist"]["param"]["size"], 8);
        assert_eq!(request_json["playlist"]["param"]["order"], 5);
    }

    #[tokio::test]
    async fn rejects_invalid_input_and_omits_malformed_rows_without_leaking_content() {
        let client = QqMusicClient::new(OfficialPlaylistTransport::new(&json!({})));
        assert!(matches!(
            client.official_playlists(0, 8).await,
            Err(QqMusicOfficialPlaylistsError::InvalidPage { page: 0 })
        ));
        assert!(matches!(
            client.official_playlists(1, 0).await,
            Err(QqMusicOfficialPlaylistsError::InvalidPageSize { size: 0 })
        ));
        assert!(
            client
                .transport()
                .requests
                .lock()
                .expect("request lock")
                .is_empty()
        );

        let client = QqMusicClient::new(OfficialPlaylistTransport::new(&json!({
            "code": 0,
            "playlist": {"code": 0, "data": {
                "total": 1,
                "v_playlist": [{"tid": 0, "title": "must-not-leak"}]
            }}
        })));
        let page = client
            .official_playlists(1, 8)
            .await
            .expect("malformed row is isolated");
        assert!(page.playlists().is_empty());
        assert_eq!(page.omitted_playlist_count(), 1);
        assert!(!format!("{page:?}").contains("must-not-leak"));
    }

    #[tokio::test]
    async fn rejects_non_advancing_and_oversized_pages() {
        let client = QqMusicClient::new(OfficialPlaylistTransport::new(&json!({
            "code": 0,
            "playlist": {"code": 0, "data": {
                "total": 20,
                "v_playlist": []
            }}
        })));
        assert!(matches!(
            client.official_playlists(1, 8).await,
            Err(QqMusicOfficialPlaylistsError::InvalidPagination)
        ));

        let client = QqMusicClient::new(OfficialPlaylistTransport::new(&json!({
            "code": 0,
            "playlist": {"code": 0, "data": {
                "total": 2,
                "v_playlist": [
                    {"tid": 1, "title": "one"},
                    {"tid": 2, "title": "two"}
                ]
            }}
        })));
        assert!(matches!(
            client.official_playlists(1, 1).await,
            Err(QqMusicOfficialPlaylistsError::InvalidPagination)
        ));
    }
}
