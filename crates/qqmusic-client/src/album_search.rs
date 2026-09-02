use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::protocol_strategy::{QqProtocolOutcome, classify_musicu_codes};
use crate::{HttpRequest, HttpTransport, QqMusicAlbumSummary, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const ALBUM_SEARCH_KEY: &str = "music.search.SearchCgiService";
const MAX_SEARCH_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const SEARCH_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_QUERY_BYTES: usize = 256;
const MAX_PAGE_SIZE: u32 = 30;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AlbumSearchField {
    AlbumId,
    AlbumMid,
    AlbumName,
}

pub enum QqMusicAlbumSearchError<E> {
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
    RateLimited {
        global_code: i64,
        result_code: Option<i64>,
    },
    MissingData,
    MissingBody,
    MissingAlbumResults,
    MissingAlbums,
    MissingMeta,
    MissingCurrentPage,
    MissingNextPage,
    MissingTotal,
    MissingPageSize,
    InvalidPagination,
    InvalidAlbum {
        index: usize,
        field: AlbumSearchField,
    },
}

impl<E> fmt::Debug for QqMusicAlbumSearchError<E> {
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
            Self::RateLimited {
                global_code,
                result_code,
            } => formatter
                .debug_struct("RateLimited")
                .field("global_code", global_code)
                .field("result_code", result_code)
                .finish(),
            Self::MissingData => formatter.write_str("MissingData"),
            Self::MissingBody => formatter.write_str("MissingBody"),
            Self::MissingAlbumResults => formatter.write_str("MissingAlbumResults"),
            Self::MissingAlbums => formatter.write_str("MissingAlbums"),
            Self::MissingMeta => formatter.write_str("MissingMeta"),
            Self::MissingCurrentPage => formatter.write_str("MissingCurrentPage"),
            Self::MissingNextPage => formatter.write_str("MissingNextPage"),
            Self::MissingTotal => formatter.write_str("MissingTotal"),
            Self::MissingPageSize => formatter.write_str("MissingPageSize"),
            Self::InvalidPagination => formatter.write_str("InvalidPagination"),
            Self::InvalidAlbum { index, field } => formatter
                .debug_struct("InvalidAlbum")
                .field("index", index)
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicAlbumSearchError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidQuery => formatter.write_str("Album search query is invalid"),
            Self::InvalidPage { page } => {
                write!(formatter, "Album search page {page} must be positive")
            }
            Self::InvalidPageSize { size } => write!(
                formatter,
                "Album search page size {size} is outside 1..={MAX_PAGE_SIZE}"
            ),
            Self::Transport(_) => formatter.write_str("QQ Music Album search request failed"),
            Self::Serialize => formatter.write_str("could not serialize Album search request"),
            Self::HttpStatus(status) => {
                write!(formatter, "Album search request returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("Album search response was not valid JSON"),
            Self::MissingGlobalCode => {
                formatter.write_str("Album search response has no global code")
            }
            Self::MissingResult => formatter.write_str("Album search result is missing"),
            Self::MissingResultCode => formatter.write_str("Album search result has no code"),
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "Album search failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::RateLimited {
                global_code,
                result_code,
            } => write!(
                formatter,
                "Album search was rate limited with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("Album search data is missing"),
            Self::MissingBody => formatter.write_str("Album search body is missing"),
            Self::MissingAlbumResults => {
                formatter.write_str("Album search result container is missing")
            }
            Self::MissingAlbums => formatter.write_str("Album search array is missing"),
            Self::MissingMeta => formatter.write_str("Album search pagination is missing"),
            Self::MissingCurrentPage => formatter.write_str("Album search current page is missing"),
            Self::MissingNextPage => formatter.write_str("Album search next page is missing"),
            Self::MissingTotal => formatter.write_str("Album search total is missing"),
            Self::MissingPageSize => formatter.write_str("Album search page size is missing"),
            Self::InvalidPagination => formatter.write_str("Album search pagination is invalid"),
            Self::InvalidAlbum { index, field } => {
                write!(
                    formatter,
                    "Album search row {index} has an invalid {field:?}"
                )
            }
        }
    }
}

impl<E> std::error::Error for QqMusicAlbumSearchError<E>
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
pub struct QqMusicAlbumSearchPage {
    page: u32,
    total: u32,
    has_more: bool,
    albums: Vec<QqMusicAlbumSummary>,
}

impl QqMusicAlbumSearchPage {
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
    pub fn albums(&self) -> &[QqMusicAlbumSummary] {
        &self.albums
    }
}

impl fmt::Debug for QqMusicAlbumSearchPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicAlbumSearchPage")
            .field("page", &self.page)
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
    /// Searches QQ Music's public Album catalog without account material.
    ///
    /// # Errors
    ///
    /// Keeps input, transport, service, response-shape, pagination, and Album
    /// mapping failures distinct without retaining query or result content.
    pub async fn search_albums(
        &self,
        query: &str,
        page: u32,
        size: u32,
    ) -> Result<QqMusicAlbumSearchPage, QqMusicAlbumSearchError<T::Error>> {
        let query = query.trim();
        if query.is_empty() || query.len() > MAX_QUERY_BYTES {
            return Err(QqMusicAlbumSearchError::InvalidQuery);
        }
        if page == 0 {
            return Err(QqMusicAlbumSearchError::InvalidPage { page });
        }
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicAlbumSearchError::InvalidPageSize { size });
        }
        let body = serde_json::to_vec(&AlbumSearchRequest::new(query, page, size))
            .map_err(|_| QqMusicAlbumSearchError::Serialize)?;
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
            .map_err(QqMusicAlbumSearchError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicAlbumSearchError::HttpStatus(response.status()));
        }
        let envelope: AlbumSearchResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicAlbumSearchError::InvalidJson)?;
        map_response(envelope, page, size)
    }
}

#[derive(Serialize)]
struct AlbumSearchRequest<'a> {
    #[serde(rename = "music.search.SearchCgiService")]
    search: AlbumSearchRpc<'a>,
}

impl<'a> AlbumSearchRequest<'a> {
    const fn new(query: &'a str, page: u32, size: u32) -> Self {
        Self {
            search: AlbumSearchRpc {
                module: ALBUM_SEARCH_KEY,
                method: "DoSearchForQQMusicDesktop",
                param: AlbumSearchParam {
                    query,
                    page_size: size,
                    page,
                    search_type: 2,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct AlbumSearchRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: AlbumSearchParam<'a>,
}

#[derive(Serialize)]
struct AlbumSearchParam<'a> {
    query: &'a str,
    #[serde(rename = "num_per_page")]
    page_size: u32,
    #[serde(rename = "page_num")]
    page: u32,
    search_type: u8,
}

#[derive(Deserialize)]
struct AlbumSearchResponse {
    code: Option<i64>,
    #[serde(rename = "music.search.SearchCgiService")]
    search: Option<AlbumSearchResult>,
}

#[derive(Deserialize)]
struct AlbumSearchResult {
    code: Option<i64>,
    data: Option<AlbumSearchData>,
}

#[derive(Deserialize)]
struct AlbumSearchData {
    body: Option<AlbumSearchBody>,
    meta: Option<AlbumSearchMeta>,
}

#[derive(Deserialize)]
struct AlbumSearchBody {
    album: Option<AlbumSearchAlbums>,
}

#[derive(Deserialize)]
struct AlbumSearchAlbums {
    list: Option<Vec<RawSearchAlbum>>,
}

#[derive(Deserialize)]
struct AlbumSearchMeta {
    curpage: Option<u32>,
    nextpage: Option<i64>,
    sum: Option<u32>,
    perpage: Option<u32>,
}

#[derive(Deserialize)]
struct RawSearchAlbum {
    #[serde(rename = "albumID")]
    id: Option<u64>,
    #[serde(rename = "albumMID")]
    mid: Option<String>,
    #[serde(rename = "albumName")]
    name: Option<String>,
}

fn map_response<E>(
    envelope: AlbumSearchResponse,
    requested_page: u32,
    requested_size: u32,
) -> Result<QqMusicAlbumSearchPage, QqMusicAlbumSearchError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicAlbumSearchError::MissingGlobalCode)?;
    let result_code = envelope.search.as_ref().and_then(|result| result.code);
    match classify_musicu_codes(global_code, result_code) {
        Ok(()) => {}
        Err(QqProtocolOutcome::RateLimited) => {
            return Err(QqMusicAlbumSearchError::RateLimited {
                global_code,
                result_code,
            });
        }
        Err(_) => {
            return Err(QqMusicAlbumSearchError::Upstream {
                global_code,
                result_code,
            });
        }
    }
    let result = envelope
        .search
        .ok_or(QqMusicAlbumSearchError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicAlbumSearchError::MissingResultCode)?;
    let data = result.data.ok_or(QqMusicAlbumSearchError::MissingData)?;
    let body = data.body.ok_or(QqMusicAlbumSearchError::MissingBody)?;
    let album_results = body
        .album
        .ok_or(QqMusicAlbumSearchError::MissingAlbumResults)?;
    let raw_albums = album_results
        .list
        .ok_or(QqMusicAlbumSearchError::MissingAlbums)?;
    let meta = data.meta.ok_or(QqMusicAlbumSearchError::MissingMeta)?;
    let page = meta
        .curpage
        .ok_or(QqMusicAlbumSearchError::MissingCurrentPage)?;
    let next_page = meta
        .nextpage
        .ok_or(QqMusicAlbumSearchError::MissingNextPage)?;
    let total = meta.sum.ok_or(QqMusicAlbumSearchError::MissingTotal)?;
    let page_size = meta
        .perpage
        .ok_or(QqMusicAlbumSearchError::MissingPageSize)?;
    let raw_count =
        u32::try_from(raw_albums.len()).map_err(|_| QqMusicAlbumSearchError::InvalidPagination)?;
    let page_start = requested_page
        .checked_sub(1)
        .and_then(|value| value.checked_mul(requested_size))
        .ok_or(QqMusicAlbumSearchError::InvalidPagination)?;
    let page_end = page_start
        .checked_add(raw_count)
        .ok_or(QqMusicAlbumSearchError::InvalidPagination)?;
    if page != requested_page
        || page_size != requested_size
        || raw_count > requested_size
        || page_end > total
    {
        return Err(QqMusicAlbumSearchError::InvalidPagination);
    }
    let has_more = match next_page {
        -1 if page_end == total => false,
        value if value > i64::from(page) && raw_count != 0 && page_end < total => true,
        _ => return Err(QqMusicAlbumSearchError::InvalidPagination),
    };
    let albums = raw_albums
        .into_iter()
        .enumerate()
        .map(|(index, raw)| map_album(raw, index))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(QqMusicAlbumSearchPage {
        page,
        total,
        has_more,
        albums,
    })
}

fn map_album<E>(
    raw: RawSearchAlbum,
    index: usize,
) -> Result<QqMusicAlbumSummary, QqMusicAlbumSearchError<E>> {
    let id = raw
        .id
        .filter(|value| *value != 0)
        .ok_or(QqMusicAlbumSearchError::InvalidAlbum {
            index,
            field: AlbumSearchField::AlbumId,
        })?;
    let mid = safe_media_mid(raw.mid).ok_or(QqMusicAlbumSearchError::InvalidAlbum {
        index,
        field: AlbumSearchField::AlbumMid,
    })?;
    let name = nonblank(raw.name).ok_or(QqMusicAlbumSearchError::InvalidAlbum {
        index,
        field: AlbumSearchField::AlbumName,
    })?;
    Ok(QqMusicAlbumSummary::new(Some(id), Some(mid), Some(name)))
}

fn nonblank(value: Option<String>) -> Option<String> {
    value.filter(|value| !value.trim().is_empty())
}

fn safe_media_mid(value: Option<String>) -> Option<String> {
    nonblank(value)
        .filter(|value| value.len() <= 64 && value.bytes().all(|byte| byte.is_ascii_alphanumeric()))
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use crate::{HttpMethod, HttpRequest, HttpResponse, HttpTransport, QqMusicClient};

    use super::{MUSICU_URL, QqMusicAlbumSearchError};

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
    async fn serializes_evidenced_album_search_and_maps_page() {
        let client = QqMusicClient::new(SearchTransport::new(&album_search_page_json(
            &synthetic_albums(),
            1,
            2,
            25,
            5,
        )));

        let page = client
            .search_albums("  synthetic query  ", 1, 5)
            .await
            .expect("Album search page");

        assert_eq!(page.page(), 1);
        assert_eq!(page.total(), 25);
        assert!(page.has_more());
        assert_eq!(page.albums().len(), 1);
        assert_eq!(page.albums()[0].album_id(), Some(43_001));
        assert_eq!(page.albums()[0].media_mid(), Some("fixtureAlbumMid"));
        assert_eq!(page.albums()[0].name(), Some("Synthetic Album"));

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
        assert_eq!(search["param"]["search_type"], 2);
        assert_eq!(search["param"]["page_num"], 1);
        assert_eq!(search["param"]["num_per_page"], 5);
        let debug = format!("{page:?} {:?}", requests[0]);
        assert!(!debug.contains("synthetic query"));
        assert!(!debug.contains("Synthetic Album"));
        assert!(!debug.contains("fixtureAlbumMid"));
    }

    #[tokio::test]
    async fn classifies_rate_limit_without_fabricating_an_empty_page() {
        let client = QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "music.search.SearchCgiService": {"code": 2001}
        })));

        assert!(matches!(
            client.search_albums("query", 1, 5).await,
            Err(QqMusicAlbumSearchError::RateLimited {
                global_code: 0,
                result_code: Some(2001)
            })
        ));
        assert_eq!(client.transport().requests().len(), 1);
    }

    #[tokio::test]
    async fn maps_exact_terminal_page() {
        let client = QqMusicClient::new(SearchTransport::new(&album_search_page_json(
            &synthetic_albums(),
            5,
            -1,
            21,
            5,
        )));

        let page = client
            .search_albums("query", 5, 5)
            .await
            .expect("terminal page");

        assert!(!page.has_more());
        assert_eq!(page.total(), 21);
    }

    #[tokio::test]
    async fn rejects_invalid_input_before_transport() {
        let client = QqMusicClient::new(SearchTransport::new(&album_search_page_json(
            &json!([]),
            1,
            -1,
            0,
            10,
        )));

        assert!(matches!(
            client.search_albums("  ", 1, 10).await,
            Err(QqMusicAlbumSearchError::InvalidQuery)
        ));
        assert!(matches!(
            client.search_albums("query", 0, 10).await,
            Err(QqMusicAlbumSearchError::InvalidPage { page: 0 })
        ));
        assert!(matches!(
            client.search_albums("query", 1, 31).await,
            Err(QqMusicAlbumSearchError::InvalidPageSize { size: 31 })
        ));
        assert!(client.transport().requests().is_empty());
    }

    #[tokio::test]
    async fn rejects_invalid_pagination_and_album_without_leaking_content() {
        let pagination = QqMusicClient::new(SearchTransport::new(&album_search_page_json(
            &synthetic_albums(),
            1,
            2,
            1,
            30,
        )))
        .search_albums("private query", 1, 5)
        .await
        .expect_err("wrong page size");
        assert!(matches!(
            pagination,
            QqMusicAlbumSearchError::InvalidPagination
        ));

        let malformed = QqMusicClient::new(SearchTransport::new(&album_search_page_json(
            &json!([{
                "albumID": 43001,
                "albumMID": "bad/mid",
                "albumName": "must-not-leak"
            }]),
            1,
            -1,
            1,
            5,
        )))
        .search_albums("private query", 1, 5)
        .await
        .expect_err("invalid Album MID");
        assert!(matches!(
            malformed,
            QqMusicAlbumSearchError::InvalidAlbum { .. }
        ));
        let debug = format!("{malformed:?} {malformed}");
        assert!(!debug.contains("private query"));
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("bad/mid"));
    }

    fn album_search_page_json(
        albums: &Value,
        page: u32,
        next_page: i64,
        total: u32,
        page_size: u32,
    ) -> Value {
        json!({
            "code": 0,
            "music.search.SearchCgiService": {
                "code": 0,
                "data": {
                    "body": {"album": {"list": albums}},
                    "meta": {
                        "curpage": page,
                        "nextpage": next_page,
                        "sum": total,
                        "perpage": page_size
                    }
                }
            }
        })
    }

    fn synthetic_albums() -> Value {
        json!([{
            "albumID": 43001,
            "albumMID": "fixtureAlbumMid",
            "albumName": "Synthetic Album",
            "albumPic": "https://example.invalid/album.jpg",
            "publicTime": "2026-08-26",
            "song_count": 12,
            "singer_list": []
        }])
    }
}
