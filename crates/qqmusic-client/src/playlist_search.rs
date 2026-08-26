use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::{HttpRequest, HttpTransport, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const PLAYLIST_SEARCH_KEY: &str = "music.search.SearchCgiService";
const MAX_SEARCH_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const SEARCH_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_QUERY_BYTES: usize = 256;
const MAX_PAGE_SIZE: u32 = 30;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PlaylistSearchField {
    PlaylistId,
    Title,
    TrackCount,
}

pub enum QqMusicPlaylistSearchError<E> {
    InvalidQuery,
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
    MissingBody,
    MissingPlaylistResults,
    MissingPlaylists,
    MissingMeta,
    MissingCurrentPage,
    MissingNextPage,
    MissingTotal,
    MissingPageSize,
    InvalidPagination,
    InvalidPlaylist {
        index: usize,
        field: PlaylistSearchField,
    },
}

impl<E> fmt::Debug for QqMusicPlaylistSearchError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidQuery => formatter.write_str("InvalidQuery([REDACTED])"),
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
            Self::MissingBody => formatter.write_str("MissingBody"),
            Self::MissingPlaylistResults => formatter.write_str("MissingPlaylistResults"),
            Self::MissingPlaylists => formatter.write_str("MissingPlaylists"),
            Self::MissingMeta => formatter.write_str("MissingMeta"),
            Self::MissingCurrentPage => formatter.write_str("MissingCurrentPage"),
            Self::MissingNextPage => formatter.write_str("MissingNextPage"),
            Self::MissingTotal => formatter.write_str("MissingTotal"),
            Self::MissingPageSize => formatter.write_str("MissingPageSize"),
            Self::InvalidPagination => formatter.write_str("InvalidPagination"),
            Self::InvalidPlaylist { index, field } => formatter
                .debug_struct("InvalidPlaylist")
                .field("index", index)
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicPlaylistSearchError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidQuery => formatter.write_str("Playlist search query is invalid"),
            Self::InvalidPage { page } => {
                write!(formatter, "Playlist search page {page} must be positive")
            }
            Self::InvalidPageSize { size } => write!(
                formatter,
                "Playlist search page size {size} is outside 1..={MAX_PAGE_SIZE}"
            ),
            Self::Transport(_) => formatter.write_str("QQ Music Playlist search request failed"),
            Self::Serialize => formatter.write_str("could not serialize Playlist search request"),
            Self::HttpStatus(status) => {
                write!(formatter, "Playlist search request returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("Playlist search response was not valid JSON"),
            Self::MissingGlobalCode => {
                formatter.write_str("Playlist search response has no global code")
            }
            Self::MissingResult => formatter.write_str("Playlist search result is missing"),
            Self::MissingResultCode => formatter.write_str("Playlist search result has no code"),
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "Playlist search failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("Playlist search data is missing"),
            Self::MissingBody => formatter.write_str("Playlist search body is missing"),
            Self::MissingPlaylistResults => {
                formatter.write_str("Playlist search result container is missing")
            }
            Self::MissingPlaylists => formatter.write_str("Playlist search array is missing"),
            Self::MissingMeta => formatter.write_str("Playlist search pagination is missing"),
            Self::MissingCurrentPage => {
                formatter.write_str("Playlist search current page is missing")
            }
            Self::MissingNextPage => formatter.write_str("Playlist search next page is missing"),
            Self::MissingTotal => formatter.write_str("Playlist search total is missing"),
            Self::MissingPageSize => formatter.write_str("Playlist search page size is missing"),
            Self::InvalidPagination => formatter.write_str("Playlist search pagination is invalid"),
            Self::InvalidPlaylist { index, field } => {
                write!(
                    formatter,
                    "Playlist search row {index} has an invalid {field:?}"
                )
            }
        }
    }
}

impl<E> std::error::Error for QqMusicPlaylistSearchError<E>
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
pub struct QqMusicPlaylistSearchSummary {
    playlist_id: u64,
    title: String,
    artwork_uri: Option<String>,
    track_count: u32,
}

impl QqMusicPlaylistSearchSummary {
    #[must_use]
    pub const fn playlist_id(&self) -> u64 {
        self.playlist_id
    }

    #[must_use]
    pub fn title(&self) -> &str {
        &self.title
    }

    #[must_use]
    pub fn artwork_uri(&self) -> Option<&str> {
        self.artwork_uri.as_deref()
    }

    #[must_use]
    pub const fn track_count(&self) -> u32 {
        self.track_count
    }
}

impl fmt::Debug for QqMusicPlaylistSearchSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicPlaylistSearchSummary")
            .field("playlist_id", &"[REDACTED]")
            .field("title", &"[REDACTED]")
            .field("has_artwork", &self.artwork_uri.is_some())
            .field("track_count", &self.track_count)
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicPlaylistSearchPage {
    page: u32,
    total: u32,
    has_more: bool,
    playlists: Vec<QqMusicPlaylistSearchSummary>,
}

impl QqMusicPlaylistSearchPage {
    #[must_use]
    pub const fn page(&self) -> u32 {
        self.page
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
    pub fn playlists(&self) -> &[QqMusicPlaylistSearchSummary] {
        &self.playlists
    }
}

impl fmt::Debug for QqMusicPlaylistSearchPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicPlaylistSearchPage")
            .field("page", &self.page)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("playlist_count", &self.playlists.len())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Searches QQ Music's public Playlist catalog without account material.
    ///
    /// # Errors
    ///
    /// Keeps input, transport, service, response-shape, pagination, and
    /// Playlist mapping failures distinct without retaining content.
    pub async fn search_playlists(
        &self,
        query: &str,
        page: u32,
        size: u32,
    ) -> Result<QqMusicPlaylistSearchPage, QqMusicPlaylistSearchError<T::Error>> {
        let query = query.trim();
        if query.is_empty() || query.len() > MAX_QUERY_BYTES {
            return Err(QqMusicPlaylistSearchError::InvalidQuery);
        }
        if page == 0 {
            return Err(QqMusicPlaylistSearchError::InvalidPage { page });
        }
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicPlaylistSearchError::InvalidPageSize { size });
        }
        let body = serde_json::to_vec(&PlaylistSearchRequest::new(query, page, size))
            .map_err(|_| QqMusicPlaylistSearchError::Serialize)?;
        let response = self
            .transport()
            .execute(
                HttpRequest::post(MUSICU_URL)
                    .header("Content-Type", "application/json")
                    .header("Origin", "https://y.qq.com")
                    .header("Referer", "https://y.qq.com/")
                    .body(body)
                    .response_body_limit(MAX_SEARCH_RESPONSE_BYTES)
                    .timeout(SEARCH_TIMEOUT),
            )
            .await
            .map_err(QqMusicPlaylistSearchError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicPlaylistSearchError::HttpStatus(response.status()));
        }
        let envelope: PlaylistSearchResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicPlaylistSearchError::InvalidJson)?;
        map_response(envelope, page, size)
    }
}

#[derive(Serialize)]
struct PlaylistSearchRequest<'a> {
    #[serde(rename = "music.search.SearchCgiService")]
    search: PlaylistSearchRpc<'a>,
}

impl<'a> PlaylistSearchRequest<'a> {
    const fn new(query: &'a str, page: u32, size: u32) -> Self {
        Self {
            search: PlaylistSearchRpc {
                module: PLAYLIST_SEARCH_KEY,
                method: "DoSearchForQQMusicDesktop",
                param: PlaylistSearchParam {
                    query,
                    page_size: size,
                    page,
                    search_type: 3,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct PlaylistSearchRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: PlaylistSearchParam<'a>,
}

#[derive(Serialize)]
struct PlaylistSearchParam<'a> {
    query: &'a str,
    #[serde(rename = "num_per_page")]
    page_size: u32,
    #[serde(rename = "page_num")]
    page: u32,
    search_type: u8,
}

#[derive(Deserialize)]
struct PlaylistSearchResponse {
    code: Option<i64>,
    #[serde(rename = "music.search.SearchCgiService")]
    search: Option<PlaylistSearchResult>,
}

#[derive(Deserialize)]
struct PlaylistSearchResult {
    code: Option<i64>,
    data: Option<PlaylistSearchData>,
}

#[derive(Deserialize)]
struct PlaylistSearchData {
    body: Option<PlaylistSearchBody>,
    meta: Option<PlaylistSearchMeta>,
}

#[derive(Deserialize)]
struct PlaylistSearchBody {
    songlist: Option<PlaylistSearchRows>,
}

#[derive(Deserialize)]
struct PlaylistSearchRows {
    list: Option<Vec<RawSearchPlaylist>>,
}

#[derive(Deserialize)]
struct PlaylistSearchMeta {
    curpage: Option<u32>,
    nextpage: Option<i64>,
    sum: Option<u32>,
    perpage: Option<u32>,
}

#[derive(Deserialize)]
struct RawSearchPlaylist {
    dissid: Option<String>,
    dissname: Option<String>,
    imgurl: Option<String>,
    song_count: Option<u32>,
}

fn map_response<E>(
    envelope: PlaylistSearchResponse,
    requested_page: u32,
    requested_size: u32,
) -> Result<QqMusicPlaylistSearchPage, QqMusicPlaylistSearchError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicPlaylistSearchError::MissingGlobalCode)?;
    let result_code = envelope.search.as_ref().and_then(|result| result.code);
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicPlaylistSearchError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .search
        .ok_or(QqMusicPlaylistSearchError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicPlaylistSearchError::MissingResultCode)?;
    let data = result.data.ok_or(QqMusicPlaylistSearchError::MissingData)?;
    let body = data.body.ok_or(QqMusicPlaylistSearchError::MissingBody)?;
    let rows = body
        .songlist
        .ok_or(QqMusicPlaylistSearchError::MissingPlaylistResults)?;
    let raw_playlists = rows
        .list
        .ok_or(QqMusicPlaylistSearchError::MissingPlaylists)?;
    let meta = data.meta.ok_or(QqMusicPlaylistSearchError::MissingMeta)?;
    let page = meta
        .curpage
        .ok_or(QqMusicPlaylistSearchError::MissingCurrentPage)?;
    let next_page = meta
        .nextpage
        .ok_or(QqMusicPlaylistSearchError::MissingNextPage)?;
    let total = meta.sum.ok_or(QqMusicPlaylistSearchError::MissingTotal)?;
    let page_size = meta
        .perpage
        .ok_or(QqMusicPlaylistSearchError::MissingPageSize)?;
    let raw_count = u32::try_from(raw_playlists.len())
        .map_err(|_| QqMusicPlaylistSearchError::InvalidPagination)?;
    if page != requested_page
        || page_size != requested_size
        || raw_count > requested_size
        || raw_count > total
    {
        return Err(QqMusicPlaylistSearchError::InvalidPagination);
    }
    let has_more = match next_page {
        -1 => false,
        value if value > i64::from(page) && raw_count != 0 => true,
        _ => return Err(QqMusicPlaylistSearchError::InvalidPagination),
    };
    let playlists = raw_playlists
        .into_iter()
        .enumerate()
        .map(|(index, playlist)| map_playlist(playlist, index))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(QqMusicPlaylistSearchPage {
        page,
        total,
        has_more,
        playlists,
    })
}

fn map_playlist<E>(
    raw: RawSearchPlaylist,
    index: usize,
) -> Result<QqMusicPlaylistSearchSummary, QqMusicPlaylistSearchError<E>> {
    let playlist_id = raw
        .dissid
        .as_deref()
        .and_then(|value| value.parse::<u64>().ok())
        .filter(|value| *value != 0)
        .ok_or(QqMusicPlaylistSearchError::InvalidPlaylist {
            index,
            field: PlaylistSearchField::PlaylistId,
        })?;
    let title = nonblank(raw.dissname).ok_or(QqMusicPlaylistSearchError::InvalidPlaylist {
        index,
        field: PlaylistSearchField::Title,
    })?;
    let track_count = raw
        .song_count
        .ok_or(QqMusicPlaylistSearchError::InvalidPlaylist {
            index,
            field: PlaylistSearchField::TrackCount,
        })?;
    Ok(QqMusicPlaylistSearchSummary {
        playlist_id,
        title,
        artwork_uri: nonblank(raw.imgurl),
        track_count,
    })
}

fn nonblank(value: Option<String>) -> Option<String> {
    value.filter(|value| !value.trim().is_empty())
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use crate::{HttpMethod, HttpRequest, HttpResponse, HttpTransport, QqMusicClient};

    use super::{MUSICU_URL, PlaylistSearchField, QqMusicPlaylistSearchError};

    struct SearchTransport {
        response: HttpResponse,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl SearchTransport {
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

    impl HttpTransport for SearchTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("request lock").push(request);
            Ok(self.response.clone())
        }
    }

    #[tokio::test]
    async fn serializes_evidenced_short_playlist_page_and_maps_results() {
        let client = QqMusicClient::new(SearchTransport::new(&playlist_search_page_json(
            &synthetic_playlists(),
            1,
            2,
            25,
            5,
        )));

        let page = client
            .search_playlists("  synthetic query  ", 1, 5)
            .await
            .expect("Playlist search page");

        assert_eq!(page.page(), 1);
        assert_eq!(page.total(), 25);
        assert!(page.has_more());
        assert_eq!(page.playlists().len(), 1);
        assert_eq!(page.playlists()[0].playlist_id(), 44_001);
        assert_eq!(page.playlists()[0].title(), "Synthetic Playlist");
        assert_eq!(page.playlists()[0].track_count(), 42);

        let requests = client.transport().requests();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].method(), HttpMethod::Post);
        assert_eq!(requests[0].url(), MUSICU_URL);
        assert_eq!(requests[0].max_response_body_bytes(), 2 * 1024 * 1024);
        let body: Value = serde_json::from_slice(requests[0].body_bytes().expect("request body"))
            .expect("request JSON");
        assert!(body.get("comm").is_none());
        assert_eq!(body.as_object().expect("object").len(), 1);
        let search = &body["music.search.SearchCgiService"];
        assert_eq!(search["module"], "music.search.SearchCgiService");
        assert_eq!(search["method"], "DoSearchForQQMusicDesktop");
        assert_eq!(search["param"]["query"], "synthetic query");
        assert_eq!(search["param"]["search_type"], 3);
        assert_eq!(search["param"]["page_num"], 1);
        assert_eq!(search["param"]["num_per_page"], 5);
        let debug = format!("{page:?} {:?}", requests[0]);
        assert!(!debug.contains("synthetic query"));
        assert!(!debug.contains("Synthetic Playlist"));
        assert!(!debug.contains("44001"));
    }

    #[tokio::test]
    async fn maps_empty_terminal_page() {
        let client = QqMusicClient::new(SearchTransport::new(&playlist_search_page_json(
            &json!([]),
            1,
            -1,
            0,
            5,
        )));

        let page = client
            .search_playlists("query", 1, 5)
            .await
            .expect("empty terminal page");

        assert!(!page.has_more());
        assert_eq!(page.total(), 0);
        assert!(page.playlists().is_empty());
    }

    #[tokio::test]
    async fn rejects_invalid_input_before_transport() {
        let client = QqMusicClient::new(SearchTransport::new(&playlist_search_page_json(
            &json!([]),
            1,
            -1,
            0,
            5,
        )));

        assert!(matches!(
            client.search_playlists("  ", 1, 5).await,
            Err(QqMusicPlaylistSearchError::InvalidQuery)
        ));
        assert!(matches!(
            client.search_playlists("query", 0, 5).await,
            Err(QqMusicPlaylistSearchError::InvalidPage { page: 0 })
        ));
        assert!(matches!(
            client.search_playlists("query", 1, 31).await,
            Err(QqMusicPlaylistSearchError::InvalidPageSize { size: 31 })
        ));
        assert!(client.transport().requests().is_empty());
    }

    #[tokio::test]
    async fn rejects_invalid_pagination_and_identity_without_leaks() {
        let pagination = QqMusicClient::new(SearchTransport::new(&playlist_search_page_json(
            &synthetic_playlists(),
            2,
            2,
            25,
            5,
        )))
        .search_playlists("private query", 1, 5)
        .await
        .expect_err("wrong current page");
        assert!(matches!(
            pagination,
            QqMusicPlaylistSearchError::InvalidPagination
        ));

        let invalid = json!([{
            "dissid": "not-a-number",
            "dissname": "must-not-leak",
            "imgurl": "https://example.invalid/private.jpg",
            "song_count": 1
        }]);
        let error = QqMusicClient::new(SearchTransport::new(&playlist_search_page_json(
            &invalid, 1, -1, 1, 5,
        )))
        .search_playlists("private query", 1, 5)
        .await
        .expect_err("invalid playlist identity");
        assert!(matches!(
            error,
            QqMusicPlaylistSearchError::InvalidPlaylist {
                field: PlaylistSearchField::PlaylistId,
                ..
            }
        ));
        let debug = format!("{pagination:?} {pagination} {error:?} {error}");
        assert!(!debug.contains("private query"));
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("not-a-number"));
    }

    fn playlist_search_page_json(
        playlists: &Value,
        page: u32,
        next_page: i64,
        total: u32,
        page_size: u32,
    ) -> Value {
        json!({
            "code": 0,
            "music.search.SearchCgiService": {"code": 0, "data": {
                "body": {"songlist": {"list": playlists}},
                "meta": {
                    "curpage": page,
                    "nextpage": next_page,
                    "sum": total,
                    "perpage": page_size
                }
            }}
        })
    }

    fn synthetic_playlists() -> Value {
        json!([{
            "dissid": "44001",
            "dissname": "Synthetic Playlist",
            "imgurl": "https://example.invalid/playlist.jpg",
            "song_count": 42,
            "creator": {"name": "Synthetic creator"}
        }])
    }
}
