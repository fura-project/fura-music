use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::{
    HttpRequest, HttpTransport, QqMusicAlbumSummary, QqMusicArtistSummary, QqMusicClient,
    QqMusicTrackSummary,
};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_SEARCH_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const SEARCH_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_QUERY_BYTES: usize = 256;
const MAX_PAGE_SIZE: u32 = 30;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SearchTrackField {
    TrackId,
    SongMid,
    FileMediaMid,
    Title,
    SongType,
    Artists,
    ArtistName,
}

pub enum QqMusicSearchError<E> {
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
    MissingSongResults,
    MissingTracks,
    MissingMeta,
    MissingCurrentPage,
    MissingNextPage,
    MissingTotal,
    InvalidPagination,
    InvalidTrack {
        index: usize,
        field: SearchTrackField,
    },
    InvalidArtist {
        track_index: usize,
        artist_index: usize,
        field: SearchTrackField,
    },
}

impl<E> fmt::Debug for QqMusicSearchError<E> {
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
            Self::MissingSongResults => formatter.write_str("MissingSongResults"),
            Self::MissingTracks => formatter.write_str("MissingTracks"),
            Self::MissingMeta => formatter.write_str("MissingMeta"),
            Self::MissingCurrentPage => formatter.write_str("MissingCurrentPage"),
            Self::MissingNextPage => formatter.write_str("MissingNextPage"),
            Self::MissingTotal => formatter.write_str("MissingTotal"),
            Self::InvalidPagination => formatter.write_str("InvalidPagination"),
            Self::InvalidTrack { index, field } => formatter
                .debug_struct("InvalidTrack")
                .field("index", index)
                .field("field", field)
                .finish(),
            Self::InvalidArtist {
                track_index,
                artist_index,
                field,
            } => formatter
                .debug_struct("InvalidArtist")
                .field("track_index", track_index)
                .field("artist_index", artist_index)
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicSearchError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidQuery => formatter.write_str("search query is invalid"),
            Self::InvalidPage { page } => write!(formatter, "search page {page} must be positive"),
            Self::InvalidPageSize { size } => write!(
                formatter,
                "search page size {size} is outside 1..={MAX_PAGE_SIZE}"
            ),
            Self::Transport(_) => formatter.write_str("QQ Music search request failed"),
            Self::Serialize => formatter.write_str("could not serialize search request"),
            Self::HttpStatus(status) => write!(formatter, "search request returned HTTP {status}"),
            Self::InvalidJson => formatter.write_str("search response was not valid JSON"),
            Self::MissingGlobalCode => formatter.write_str("search response has no global code"),
            Self::MissingResult => formatter.write_str("search result is missing"),
            Self::MissingResultCode => formatter.write_str("search result has no code"),
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "search request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("search data is missing"),
            Self::MissingBody => formatter.write_str("search body is missing"),
            Self::MissingSongResults => formatter.write_str("search song result is missing"),
            Self::MissingTracks => formatter.write_str("search Track array is missing"),
            Self::MissingMeta => formatter.write_str("search pagination metadata is missing"),
            Self::MissingCurrentPage => formatter.write_str("search current page is missing"),
            Self::MissingNextPage => formatter.write_str("search next page is missing"),
            Self::MissingTotal => formatter.write_str("search total is missing"),
            Self::InvalidPagination => formatter.write_str("search pagination is invalid"),
            Self::InvalidTrack { index, field } => {
                write!(formatter, "search Track {index} has an invalid {field:?}")
            }
            Self::InvalidArtist {
                track_index,
                artist_index,
                field,
            } => write!(
                formatter,
                "search Track {track_index} artist {artist_index} has an invalid {field:?}"
            ),
        }
    }
}

impl<E> std::error::Error for QqMusicSearchError<E>
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
pub struct QqMusicTrackSearchPage {
    page: u32,
    total: u32,
    has_more: bool,
    tracks: Vec<QqMusicTrackSummary>,
}

impl QqMusicTrackSearchPage {
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
    pub fn tracks(&self) -> &[QqMusicTrackSummary] {
        &self.tracks
    }
}

impl fmt::Debug for QqMusicTrackSearchPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicTrackSearchPage")
            .field("page", &self.page)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("track_count", &self.tracks.len())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Searches QQ Music's public Track catalog without account material.
    ///
    /// # Errors
    ///
    /// Keeps input, transport, service, response-shape, pagination, and Track
    /// mapping failures distinct without retaining query or result content.
    pub async fn search_tracks(
        &self,
        query: &str,
        page: u32,
        size: u32,
    ) -> Result<QqMusicTrackSearchPage, QqMusicSearchError<T::Error>> {
        let query = query.trim();
        if query.is_empty() || query.len() > MAX_QUERY_BYTES {
            return Err(QqMusicSearchError::InvalidQuery);
        }
        if page == 0 {
            return Err(QqMusicSearchError::InvalidPage { page });
        }
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicSearchError::InvalidPageSize { size });
        }
        let body = serde_json::to_vec(&TrackSearchRequest::new(query, page, size))
            .map_err(|_| QqMusicSearchError::Serialize)?;
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
            .map_err(QqMusicSearchError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicSearchError::HttpStatus(response.status()));
        }
        let envelope: TrackSearchResponse =
            serde_json::from_slice(response.body()).map_err(|_| QqMusicSearchError::InvalidJson)?;
        map_response(envelope, page)
    }
}

#[derive(Serialize)]
struct TrackSearchRequest<'a> {
    comm: TrackSearchComm,
    search: TrackSearchRpc<'a>,
}

impl<'a> TrackSearchRequest<'a> {
    const fn new(query: &'a str, page: u32, size: u32) -> Self {
        Self {
            comm: TrackSearchComm {
                client_type: "19",
                client_version: "1859",
                format: "json",
                input_charset: "utf-8",
                output_charset: "utf-8",
                platform: "yqq.json",
                need_new_code: 1,
            },
            search: TrackSearchRpc {
                module: "music.search.SearchCgiService",
                method: "DoSearchForQQMusicDesktop",
                param: TrackSearchParam {
                    query,
                    page_size: size,
                    page,
                    search_type: 0,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct TrackSearchComm {
    #[serde(rename = "ct")]
    client_type: &'static str,
    #[serde(rename = "cv")]
    client_version: &'static str,
    format: &'static str,
    #[serde(rename = "inCharset")]
    input_charset: &'static str,
    #[serde(rename = "outCharset")]
    output_charset: &'static str,
    platform: &'static str,
    #[serde(rename = "needNewCode")]
    need_new_code: u8,
}

#[derive(Serialize)]
struct TrackSearchRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: TrackSearchParam<'a>,
}

#[derive(Serialize)]
struct TrackSearchParam<'a> {
    query: &'a str,
    #[serde(rename = "num_per_page")]
    page_size: u32,
    #[serde(rename = "page_num")]
    page: u32,
    search_type: u8,
}

#[derive(Deserialize)]
struct TrackSearchResponse {
    code: Option<i64>,
    search: Option<TrackSearchResult>,
}

#[derive(Deserialize)]
struct TrackSearchResult {
    code: Option<i64>,
    data: Option<TrackSearchData>,
}

#[derive(Deserialize)]
struct TrackSearchData {
    body: Option<TrackSearchBody>,
    meta: Option<TrackSearchMeta>,
}

#[derive(Deserialize)]
struct TrackSearchBody {
    song: Option<TrackSearchSongs>,
}

#[derive(Deserialize)]
struct TrackSearchSongs {
    list: Option<Vec<RawSearchTrack>>,
}

#[derive(Deserialize)]
struct TrackSearchMeta {
    curpage: Option<u32>,
    nextpage: Option<i64>,
    sum: Option<u32>,
}

#[derive(Deserialize)]
struct RawSearchTrack {
    id: Option<u64>,
    mid: Option<String>,
    name: Option<String>,
    title: Option<String>,
    subtitle: Option<String>,
    #[serde(rename = "type")]
    song_type: Option<u32>,
    interval: Option<u32>,
    singer: Option<Vec<RawSearchArtist>>,
    album: Option<RawSearchAlbum>,
    file: Option<RawSearchFile>,
}

#[derive(Deserialize)]
struct RawSearchFile {
    media_mid: Option<String>,
}

#[derive(Deserialize)]
struct RawSearchArtist {
    id: Option<u64>,
    mid: Option<String>,
    name: Option<String>,
}

#[derive(Deserialize)]
struct RawSearchAlbum {
    id: Option<u64>,
    mid: Option<String>,
    pmid: Option<String>,
    name: Option<String>,
    title: Option<String>,
}

fn map_response<E>(
    envelope: TrackSearchResponse,
    requested_page: u32,
) -> Result<QqMusicTrackSearchPage, QqMusicSearchError<E>> {
    let global_code = envelope.code.ok_or(QqMusicSearchError::MissingGlobalCode)?;
    let result_code = envelope.search.as_ref().and_then(|result| result.code);
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicSearchError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope.search.ok_or(QqMusicSearchError::MissingResult)?;
    result.code.ok_or(QqMusicSearchError::MissingResultCode)?;
    let data = result.data.ok_or(QqMusicSearchError::MissingData)?;
    let body = data.body.ok_or(QqMusicSearchError::MissingBody)?;
    let song = body.song.ok_or(QqMusicSearchError::MissingSongResults)?;
    let raw_tracks = song.list.ok_or(QqMusicSearchError::MissingTracks)?;
    let meta = data.meta.ok_or(QqMusicSearchError::MissingMeta)?;
    let page = meta.curpage.ok_or(QqMusicSearchError::MissingCurrentPage)?;
    let next_page = meta.nextpage.ok_or(QqMusicSearchError::MissingNextPage)?;
    let total = meta.sum.ok_or(QqMusicSearchError::MissingTotal)?;
    if page != requested_page {
        return Err(QqMusicSearchError::InvalidPagination);
    }
    let has_more = match next_page {
        -1 => false,
        value if value > i64::from(page) => true,
        _ => return Err(QqMusicSearchError::InvalidPagination),
    };
    let tracks = raw_tracks
        .into_iter()
        .enumerate()
        .map(|(index, raw)| map_track(raw, index))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(QqMusicTrackSearchPage {
        page,
        total,
        has_more,
        tracks,
    })
}

fn map_track<E>(
    raw: RawSearchTrack,
    index: usize,
) -> Result<QqMusicTrackSummary, QqMusicSearchError<E>> {
    let track_id = raw
        .id
        .filter(|value| *value != 0)
        .ok_or(QqMusicSearchError::InvalidTrack {
            index,
            field: SearchTrackField::TrackId,
        })?;
    let song_mid = safe_media_mid(raw.mid).ok_or(QqMusicSearchError::InvalidTrack {
        index,
        field: SearchTrackField::SongMid,
    })?;
    let file_media_mid = match raw.file.and_then(|file| file.media_mid) {
        Some(value) if value.trim().is_empty() => None,
        Some(value) => Some(safe_media_mid(Some(value)).ok_or(
            QqMusicSearchError::InvalidTrack {
                index,
                field: SearchTrackField::FileMediaMid,
            },
        )?),
        None => None,
    };
    let title = nonblank(raw.title).or_else(|| nonblank(raw.name)).ok_or(
        QqMusicSearchError::InvalidTrack {
            index,
            field: SearchTrackField::Title,
        },
    )?;
    let song_type = raw.song_type.ok_or(QqMusicSearchError::InvalidTrack {
        index,
        field: SearchTrackField::SongType,
    })?;
    let raw_artists = raw.singer.ok_or(QqMusicSearchError::InvalidTrack {
        index,
        field: SearchTrackField::Artists,
    })?;
    let artists = raw_artists
        .into_iter()
        .enumerate()
        .map(|(artist_index, artist)| {
            let name = nonblank(artist.name).ok_or(QqMusicSearchError::InvalidArtist {
                track_index: index,
                artist_index,
                field: SearchTrackField::ArtistName,
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

    use super::QqMusicSearchError;

    struct SearchTransport {
        response: HttpResponse,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl SearchTransport {
        fn new(response: &Value) -> Self {
            Self {
                response: HttpResponse::new(
                    200,
                    serde_json::to_vec(&response).expect("fixture JSON"),
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
    async fn serializes_evidenced_track_search_and_maps_page() {
        let client = QqMusicClient::new(SearchTransport::new(&search_page_json(
            &synthetic_tracks(),
            2,
            3,
            45,
        )));

        let page = client
            .search_tracks("  synthetic query  ", 2, 5)
            .await
            .expect("search page");

        assert_eq!(page.page(), 2);
        assert_eq!(page.total(), 45);
        assert!(page.has_more());
        assert_eq!(page.tracks().len(), 1);
        assert_eq!(page.tracks()[0].track_id(), 41_001);
        assert_eq!(page.tracks()[0].song_mid(), "fixtureTrackMid1");
        assert_eq!(page.tracks()[0].file_media_mid(), Some("fixtureFileMid1"));
        assert_eq!(page.tracks()[0].title(), "Synthetic track");
        assert_eq!(page.tracks()[0].artists()[0].name(), "Artist one");

        let requests = client.transport().requests();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].method(), HttpMethod::Post);
        assert_eq!(requests[0].url(), "https://u.y.qq.com/cgi-bin/musicu.fcg");
        assert_eq!(requests[0].max_response_body_bytes(), 2 * 1024 * 1024);
        let body: Value = serde_json::from_slice(requests[0].body_bytes().expect("request body"))
            .expect("request JSON");
        assert_eq!(body["comm"]["ct"], "19");
        assert_eq!(body["search"]["module"], "music.search.SearchCgiService");
        assert_eq!(body["search"]["method"], "DoSearchForQQMusicDesktop");
        assert_eq!(body["search"]["param"]["query"], "synthetic query");
        assert_eq!(body["search"]["param"]["page_num"], 2);
        assert_eq!(body["search"]["param"]["num_per_page"], 5);
        let debug = format!("{page:?} {:?}", requests[0]);
        assert!(!debug.contains("synthetic query"));
        assert!(!debug.contains("Synthetic track"));
        assert!(!debug.contains("fixtureTrackMid1"));
    }

    #[tokio::test]
    async fn rejects_invalid_input_before_transport() {
        let client = QqMusicClient::new(SearchTransport::new(&search_page_json(
            &json!([]),
            1,
            -1,
            0,
        )));

        assert!(matches!(
            client.search_tracks("  ", 1, 10).await,
            Err(QqMusicSearchError::InvalidQuery)
        ));
        assert!(matches!(
            client.search_tracks("query", 0, 10).await,
            Err(QqMusicSearchError::InvalidPage { page: 0 })
        ));
        assert!(matches!(
            client.search_tracks("query", 1, 31).await,
            Err(QqMusicSearchError::InvalidPageSize { size: 31 })
        ));
        assert!(client.transport().requests().is_empty());
    }

    #[tokio::test]
    async fn rejects_invalid_pagination_and_track_without_leaking_content() {
        let client = QqMusicClient::new(SearchTransport::new(&search_page_json(
            &synthetic_tracks(),
            3,
            4,
            45,
        )));
        let pagination = client
            .search_tracks("private query", 2, 5)
            .await
            .expect_err("wrong current page");
        assert!(matches!(pagination, QqMusicSearchError::InvalidPagination));

        let invalid = QqMusicClient::new(SearchTransport::new(&search_page_json(
            &json!([{
                "id": 41001,
                "mid": "fixtureTrackMid1",
                "type": 0,
                "title": "must-not-leak",
                "singer": [{"name": " "}]
            }]),
            1,
            -1,
            1,
        )))
        .search_tracks("private query", 1, 5)
        .await
        .expect_err("blank artist");
        assert!(matches!(invalid, QqMusicSearchError::InvalidArtist { .. }));
        let debug = format!("{invalid:?} {invalid}");
        assert!(!debug.contains("private query"));
        assert!(!debug.contains("must-not-leak"));
    }

    fn search_page_json(tracks: &Value, page: u32, next_page: i64, total: u32) -> Value {
        json!({
            "code": 0,
            "search": {
                "code": 0,
                "data": {
                    "body": {"song": {"list": tracks}},
                    "meta": {"curpage": page, "nextpage": next_page, "sum": total}
                }
            }
        })
    }

    fn synthetic_tracks() -> Value {
        json!([{
            "id": 41001,
            "mid": "fixtureTrackMid1",
            "name": "Fallback title",
            "title": "Synthetic track",
            "subtitle": "Synthetic subtitle",
            "type": 0,
            "interval": 245,
            "file": {"media_mid": "fixtureFileMid1"},
            "singer": [{"id": 42001, "mid": "artistOneMid", "name": "Artist one"}],
            "album": {
                "id": 43001,
                "mid": "fixtureAlbumMid",
                "name": "Synthetic album"
            }
        }])
    }
}
