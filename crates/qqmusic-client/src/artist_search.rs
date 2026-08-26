use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::{HttpRequest, HttpTransport, QqMusicArtistSummary, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const ARTIST_SEARCH_KEY: &str = "music.search.SearchCgiService";
const MAX_SEARCH_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const SEARCH_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_QUERY_BYTES: usize = 256;
const MAX_PAGE_SIZE: u32 = 30;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ArtistSearchField {
    ArtistId,
    ArtistMid,
    ArtistName,
}

pub enum QqMusicArtistSearchError<E> {
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
    MissingArtistResults,
    MissingArtists,
    MissingMeta,
    MissingCurrentPage,
    MissingNextPage,
    MissingTotal,
    MissingPageSize,
    InvalidPagination,
    InvalidArtist {
        index: usize,
        field: ArtistSearchField,
    },
}

impl<E> fmt::Debug for QqMusicArtistSearchError<E> {
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
            Self::MissingArtistResults => formatter.write_str("MissingArtistResults"),
            Self::MissingArtists => formatter.write_str("MissingArtists"),
            Self::MissingMeta => formatter.write_str("MissingMeta"),
            Self::MissingCurrentPage => formatter.write_str("MissingCurrentPage"),
            Self::MissingNextPage => formatter.write_str("MissingNextPage"),
            Self::MissingTotal => formatter.write_str("MissingTotal"),
            Self::MissingPageSize => formatter.write_str("MissingPageSize"),
            Self::InvalidPagination => formatter.write_str("InvalidPagination"),
            Self::InvalidArtist { index, field } => formatter
                .debug_struct("InvalidArtist")
                .field("index", index)
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicArtistSearchError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidQuery => formatter.write_str("Artist search query is invalid"),
            Self::InvalidPage { page } => {
                write!(formatter, "Artist search page {page} must be positive")
            }
            Self::InvalidPageSize { size } => write!(
                formatter,
                "Artist search page size {size} is outside 1..={MAX_PAGE_SIZE}"
            ),
            Self::Transport(_) => formatter.write_str("QQ Music Artist search request failed"),
            Self::Serialize => formatter.write_str("could not serialize Artist search request"),
            Self::HttpStatus(status) => {
                write!(formatter, "Artist search request returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("Artist search response was not valid JSON"),
            Self::MissingGlobalCode => {
                formatter.write_str("Artist search response has no global code")
            }
            Self::MissingResult => formatter.write_str("Artist search result is missing"),
            Self::MissingResultCode => formatter.write_str("Artist search result has no code"),
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "Artist search failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("Artist search data is missing"),
            Self::MissingBody => formatter.write_str("Artist search body is missing"),
            Self::MissingArtistResults => {
                formatter.write_str("Artist search result container is missing")
            }
            Self::MissingArtists => formatter.write_str("Artist search array is missing"),
            Self::MissingMeta => formatter.write_str("Artist search pagination is missing"),
            Self::MissingCurrentPage => {
                formatter.write_str("Artist search current page is missing")
            }
            Self::MissingNextPage => formatter.write_str("Artist search next page is missing"),
            Self::MissingTotal => formatter.write_str("Artist search total is missing"),
            Self::MissingPageSize => formatter.write_str("Artist search page size is missing"),
            Self::InvalidPagination => formatter.write_str("Artist search pagination is invalid"),
            Self::InvalidArtist { index, field } => {
                write!(
                    formatter,
                    "Artist search row {index} has an invalid {field:?}"
                )
            }
        }
    }
}

impl<E> std::error::Error for QqMusicArtistSearchError<E>
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
pub struct QqMusicArtistSearchPage {
    page: u32,
    total: u32,
    has_more: bool,
    artists: Vec<QqMusicArtistSummary>,
}

impl QqMusicArtistSearchPage {
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
    pub fn artists(&self) -> &[QqMusicArtistSummary] {
        &self.artists
    }
}

impl fmt::Debug for QqMusicArtistSearchPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicArtistSearchPage")
            .field("page", &self.page)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("artist_count", &self.artists.len())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Searches QQ Music's public Artist catalog without account material.
    ///
    /// # Errors
    ///
    /// Keeps input, transport, service, response-shape, pagination, and Artist
    /// mapping failures distinct without retaining query or result content.
    pub async fn search_artists(
        &self,
        query: &str,
        page: u32,
        size: u32,
    ) -> Result<QqMusicArtistSearchPage, QqMusicArtistSearchError<T::Error>> {
        let query = query.trim();
        if query.is_empty() || query.len() > MAX_QUERY_BYTES {
            return Err(QqMusicArtistSearchError::InvalidQuery);
        }
        if page == 0 {
            return Err(QqMusicArtistSearchError::InvalidPage { page });
        }
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicArtistSearchError::InvalidPageSize { size });
        }
        let body = serde_json::to_vec(&ArtistSearchRequest::new(query, page, size))
            .map_err(|_| QqMusicArtistSearchError::Serialize)?;
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
            .map_err(QqMusicArtistSearchError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicArtistSearchError::HttpStatus(response.status()));
        }
        let envelope: ArtistSearchResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicArtistSearchError::InvalidJson)?;
        map_response(envelope, page, size)
    }
}

#[derive(Serialize)]
struct ArtistSearchRequest<'a> {
    #[serde(rename = "music.search.SearchCgiService")]
    search: ArtistSearchRpc<'a>,
}

impl<'a> ArtistSearchRequest<'a> {
    const fn new(query: &'a str, page: u32, size: u32) -> Self {
        Self {
            search: ArtistSearchRpc {
                module: ARTIST_SEARCH_KEY,
                method: "DoSearchForQQMusicDesktop",
                param: ArtistSearchParam {
                    query,
                    page_size: size,
                    page,
                    search_type: 1,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct ArtistSearchRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: ArtistSearchParam<'a>,
}

#[derive(Serialize)]
struct ArtistSearchParam<'a> {
    query: &'a str,
    #[serde(rename = "num_per_page")]
    page_size: u32,
    #[serde(rename = "page_num")]
    page: u32,
    search_type: u8,
}

#[derive(Deserialize)]
struct ArtistSearchResponse {
    code: Option<i64>,
    #[serde(rename = "music.search.SearchCgiService")]
    search: Option<ArtistSearchResult>,
}

#[derive(Deserialize)]
struct ArtistSearchResult {
    code: Option<i64>,
    data: Option<ArtistSearchData>,
}

#[derive(Deserialize)]
struct ArtistSearchData {
    body: Option<ArtistSearchBody>,
    meta: Option<ArtistSearchMeta>,
}

#[derive(Deserialize)]
struct ArtistSearchBody {
    singer: Option<ArtistSearchArtists>,
}

#[derive(Deserialize)]
struct ArtistSearchArtists {
    list: Option<Vec<RawSearchArtist>>,
}

#[derive(Deserialize)]
struct ArtistSearchMeta {
    curpage: Option<u32>,
    nextpage: Option<i64>,
    sum: Option<u32>,
    perpage: Option<u32>,
}

#[derive(Deserialize)]
struct RawSearchArtist {
    #[serde(rename = "singerID")]
    id: Option<u64>,
    #[serde(rename = "singerMID")]
    mid: Option<String>,
    #[serde(rename = "singerName")]
    name: Option<String>,
}

fn map_response<E>(
    envelope: ArtistSearchResponse,
    requested_page: u32,
    requested_size: u32,
) -> Result<QqMusicArtistSearchPage, QqMusicArtistSearchError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicArtistSearchError::MissingGlobalCode)?;
    let result_code = envelope.search.as_ref().and_then(|result| result.code);
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicArtistSearchError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .search
        .ok_or(QqMusicArtistSearchError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicArtistSearchError::MissingResultCode)?;
    let data = result.data.ok_or(QqMusicArtistSearchError::MissingData)?;
    let body = data.body.ok_or(QqMusicArtistSearchError::MissingBody)?;
    let artist_results = body
        .singer
        .ok_or(QqMusicArtistSearchError::MissingArtistResults)?;
    let raw_artists = artist_results
        .list
        .ok_or(QqMusicArtistSearchError::MissingArtists)?;
    let meta = data.meta.ok_or(QqMusicArtistSearchError::MissingMeta)?;
    let page = meta
        .curpage
        .ok_or(QqMusicArtistSearchError::MissingCurrentPage)?;
    let next_page = meta
        .nextpage
        .ok_or(QqMusicArtistSearchError::MissingNextPage)?;
    let total = meta.sum.ok_or(QqMusicArtistSearchError::MissingTotal)?;
    let page_size = meta
        .perpage
        .ok_or(QqMusicArtistSearchError::MissingPageSize)?;
    let raw_count = u32::try_from(raw_artists.len())
        .map_err(|_| QqMusicArtistSearchError::InvalidPagination)?;
    let page_start = requested_page
        .checked_sub(1)
        .and_then(|value| value.checked_mul(requested_size))
        .ok_or(QqMusicArtistSearchError::InvalidPagination)?;
    let page_end = page_start
        .checked_add(raw_count)
        .ok_or(QqMusicArtistSearchError::InvalidPagination)?;
    if page != requested_page
        || page_size != requested_size
        || raw_count > requested_size
        || page_end > total
    {
        return Err(QqMusicArtistSearchError::InvalidPagination);
    }
    let has_more = match next_page {
        -1 if page_end == total => false,
        value if value > i64::from(page) && raw_count != 0 && page_end < total => true,
        _ => return Err(QqMusicArtistSearchError::InvalidPagination),
    };
    let artists = raw_artists
        .into_iter()
        .enumerate()
        .map(|(index, raw)| map_artist(raw, index))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(QqMusicArtistSearchPage {
        page,
        total,
        has_more,
        artists,
    })
}

fn map_artist<E>(
    raw: RawSearchArtist,
    index: usize,
) -> Result<QqMusicArtistSummary, QqMusicArtistSearchError<E>> {
    let id = raw
        .id
        .filter(|value| *value != 0)
        .ok_or(QqMusicArtistSearchError::InvalidArtist {
            index,
            field: ArtistSearchField::ArtistId,
        })?;
    let mid = safe_media_mid(raw.mid).ok_or(QqMusicArtistSearchError::InvalidArtist {
        index,
        field: ArtistSearchField::ArtistMid,
    })?;
    let name = nonblank(raw.name).ok_or(QqMusicArtistSearchError::InvalidArtist {
        index,
        field: ArtistSearchField::ArtistName,
    })?;
    Ok(QqMusicArtistSummary::new(Some(id), Some(mid), name))
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

    use super::QqMusicArtistSearchError;

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
    async fn serializes_evidenced_artist_search_and_maps_page() {
        let client = QqMusicClient::new(SearchTransport::new(&artist_search_page_json(
            &synthetic_artists(),
            1,
            2,
            8,
            5,
        )));

        let page = client
            .search_artists("  synthetic query  ", 1, 5)
            .await
            .expect("Artist search page");

        assert_eq!(page.page(), 1);
        assert_eq!(page.total(), 8);
        assert!(page.has_more());
        assert_eq!(page.artists().len(), 1);
        assert_eq!(page.artists()[0].artist_id(), Some(42_001));
        assert_eq!(page.artists()[0].media_mid(), Some("fixtureArtistMid"));
        assert_eq!(page.artists()[0].name(), "Synthetic Artist");

        let requests = client.transport().requests();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].method(), HttpMethod::Post);
        assert_eq!(requests[0].url(), "https://u.y.qq.com/cgi-bin/musicu.fcg");
        assert_eq!(requests[0].max_response_body_bytes(), 2 * 1024 * 1024);
        let body: Value = serde_json::from_slice(requests[0].body_bytes().expect("request body"))
            .expect("request JSON");
        assert!(body.get("comm").is_none());
        assert_eq!(body.as_object().expect("object").len(), 1);
        let search = &body["music.search.SearchCgiService"];
        assert_eq!(search["module"], "music.search.SearchCgiService");
        assert_eq!(search["method"], "DoSearchForQQMusicDesktop");
        assert_eq!(search["param"]["query"], "synthetic query");
        assert_eq!(search["param"]["search_type"], 1);
        assert_eq!(search["param"]["page_num"], 1);
        assert_eq!(search["param"]["num_per_page"], 5);
        let debug = format!("{page:?} {:?}", requests[0]);
        assert!(!debug.contains("synthetic query"));
        assert!(!debug.contains("Synthetic Artist"));
        assert!(!debug.contains("fixtureArtistMid"));
    }

    #[tokio::test]
    async fn maps_exact_terminal_page() {
        let client = QqMusicClient::new(SearchTransport::new(&artist_search_page_json(
            &synthetic_artists(),
            2,
            -1,
            6,
            5,
        )));

        let page = client
            .search_artists("query", 2, 5)
            .await
            .expect("terminal page");

        assert!(!page.has_more());
        assert_eq!(page.total(), 6);
    }

    #[tokio::test]
    async fn rejects_invalid_input_before_transport() {
        let client = QqMusicClient::new(SearchTransport::new(&artist_search_page_json(
            &json!([]),
            1,
            -1,
            0,
            10,
        )));

        assert!(matches!(
            client.search_artists("  ", 1, 10).await,
            Err(QqMusicArtistSearchError::InvalidQuery)
        ));
        assert!(matches!(
            client.search_artists("query", 0, 10).await,
            Err(QqMusicArtistSearchError::InvalidPage { page: 0 })
        ));
        assert!(matches!(
            client.search_artists("query", 1, 31).await,
            Err(QqMusicArtistSearchError::InvalidPageSize { size: 31 })
        ));
        assert!(client.transport().requests().is_empty());
    }

    #[tokio::test]
    async fn rejects_invalid_pagination_and_artist_without_leaking_content() {
        let pagination = QqMusicClient::new(SearchTransport::new(&artist_search_page_json(
            &synthetic_artists(),
            1,
            2,
            1,
            30,
        )))
        .search_artists("private query", 1, 5)
        .await
        .expect_err("wrong page size");
        assert!(matches!(
            pagination,
            QqMusicArtistSearchError::InvalidPagination
        ));

        let invalid = QqMusicClient::new(SearchTransport::new(&artist_search_page_json(
            &json!([{
                "singerID": 42001,
                "singerMID": "fixtureArtistMid",
                "singerName": "must-not-leak"
            }]),
            1,
            -1,
            1,
            5,
        )))
        .search_artists("private query", 1, 5)
        .await
        .expect("valid Artist");
        assert!(!format!("{invalid:?}").contains("must-not-leak"));

        let malformed = QqMusicClient::new(SearchTransport::new(&artist_search_page_json(
            &json!([{
                "singerID": 42001,
                "singerMID": "bad/mid",
                "singerName": "must-not-leak"
            }]),
            1,
            -1,
            1,
            5,
        )))
        .search_artists("private query", 1, 5)
        .await
        .expect_err("invalid Artist MID");
        assert!(matches!(
            malformed,
            QqMusicArtistSearchError::InvalidArtist { .. }
        ));
        let debug = format!("{malformed:?} {malformed}");
        assert!(!debug.contains("private query"));
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("bad/mid"));
    }

    fn artist_search_page_json(
        artists: &Value,
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
                    "body": {"singer": {"list": artists}},
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

    fn synthetic_artists() -> Value {
        json!([{
            "singerID": 42001,
            "singerMID": "fixtureArtistMid",
            "singerName": "Synthetic Artist",
            "singerPic": "https://example.invalid/artist.jpg",
            "songNum": 12,
            "albumNum": 3
        }])
    }
}
