use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::{HttpRequest, HttpTransport, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_PAGE_SIZE: u32 = 30;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RecommendedPlaylistField {
    Wrapper,
    Basic,
    PlaylistId,
    Title,
}

pub enum QqMusicRecommendedPlaylistsError<E> {
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
    MissingPlaylists,
    MissingHasMore,
    InvalidPagination,
    InvalidPlaylist {
        index: usize,
        field: RecommendedPlaylistField,
    },
}

impl<E> fmt::Debug for QqMusicRecommendedPlaylistsError<E> {
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
            Self::MissingPlaylists => formatter.write_str("MissingPlaylists"),
            Self::MissingHasMore => formatter.write_str("MissingHasMore"),
            Self::InvalidPagination => formatter.write_str("InvalidPagination"),
            Self::InvalidPlaylist { index, field } => formatter
                .debug_struct("InvalidPlaylist")
                .field("index", index)
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicRecommendedPlaylistsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidPageSize { size } => write!(
                formatter,
                "recommended-playlist page size {size} is outside 1..={MAX_PAGE_SIZE}"
            ),
            Self::Transport(_) => formatter.write_str("QQ Music recommendation request failed"),
            Self::Serialize => formatter.write_str("could not serialize recommendation request"),
            Self::HttpStatus(status) => {
                write!(formatter, "recommendation request returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("recommendation response was not valid JSON"),
            Self::MissingGlobalCode => {
                formatter.write_str("recommendation response has no global code")
            }
            Self::MissingResult => formatter.write_str("recommendation result is missing"),
            Self::MissingResultCode => formatter.write_str("recommendation result has no code"),
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "recommendation request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("recommendation data is missing"),
            Self::MissingPlaylists => formatter.write_str("recommended-playlist array is missing"),
            Self::MissingHasMore => {
                formatter.write_str("recommendation continuation flag is missing")
            }
            Self::InvalidPagination => formatter.write_str("recommendation pagination is invalid"),
            Self::InvalidPlaylist { index, field } => {
                write!(
                    formatter,
                    "recommended playlist {index} has an invalid {field:?}"
                )
            }
        }
    }
}

impl<E> std::error::Error for QqMusicRecommendedPlaylistsError<E>
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
pub struct QqMusicRecommendedPlaylist {
    playlist_id: u64,
    title: String,
    cover_url: Option<String>,
    track_count: Option<u32>,
}

impl QqMusicRecommendedPlaylist {
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
    pub const fn track_count(&self) -> Option<u32> {
        self.track_count
    }
}

impl fmt::Debug for QqMusicRecommendedPlaylist {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRecommendedPlaylist")
            .field("playlist_id", &"[REDACTED]")
            .field("title", &"[REDACTED]")
            .field("has_cover", &self.cover_url.is_some())
            .field("track_count", &self.track_count)
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicRecommendedPlaylistsPage {
    offset: u32,
    has_more: bool,
    playlists: Vec<QqMusicRecommendedPlaylist>,
}

impl QqMusicRecommendedPlaylistsPage {
    #[must_use]
    pub const fn offset(&self) -> u32 {
        self.offset
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn playlists(&self) -> &[QqMusicRecommendedPlaylist] {
        &self.playlists
    }
}

impl fmt::Debug for QqMusicRecommendedPlaylistsPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRecommendedPlaylistsPage")
            .field("offset", &self.offset)
            .field("has_more", &self.has_more)
            .field("playlist_count", &self.playlists.len())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Loads one anonymous bounded page of QQ Music playlist recommendations.
    ///
    /// # Errors
    ///
    /// Keeps transport, service, response-shape, pagination, and row-mapping
    /// failures distinct without retaining recommendation content.
    pub async fn recommended_playlists(
        &self,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicRecommendedPlaylistsPage, QqMusicRecommendedPlaylistsError<T::Error>> {
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicRecommendedPlaylistsError::InvalidPageSize { size });
        }
        let body = serde_json::to_vec(&RecommendedPlaylistsRequest::new(offset, size))
            .map_err(|_| QqMusicRecommendedPlaylistsError::Serialize)?;
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
            .map_err(QqMusicRecommendedPlaylistsError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicRecommendedPlaylistsError::HttpStatus(
                response.status(),
            ));
        }
        let envelope: RecommendedPlaylistsResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicRecommendedPlaylistsError::InvalidJson)?;
        map_response(envelope, offset, size)
    }
}

#[derive(Serialize)]
struct RecommendedPlaylistsRequest {
    comm: RecommendationComm,
    recommend: RecommendedPlaylistsRpc,
}

impl RecommendedPlaylistsRequest {
    const fn new(offset: u32, size: u32) -> Self {
        Self {
            comm: RecommendationComm {
                client_type: 20,
                client_version: 1770,
                token: 5381,
                uin: "0",
                format: "json",
                input_charset: "utf-8",
                output_charset: "utf-8",
                platform: "wk_v17",
                uid: "",
                guid: "",
            },
            recommend: RecommendedPlaylistsRpc {
                module: "music.playlist.PlaylistSquare",
                method: "GetRecommendFeed",
                param: RecommendedPlaylistsParam { offset, size },
            },
        }
    }
}

#[derive(Serialize)]
struct RecommendationComm {
    #[serde(rename = "ct")]
    client_type: u32,
    #[serde(rename = "cv")]
    client_version: u32,
    #[serde(rename = "g_tk")]
    token: u32,
    uin: &'static str,
    format: &'static str,
    #[serde(rename = "inCharset")]
    input_charset: &'static str,
    #[serde(rename = "outCharset")]
    output_charset: &'static str,
    platform: &'static str,
    uid: &'static str,
    guid: &'static str,
}

#[derive(Serialize)]
struct RecommendedPlaylistsRpc {
    module: &'static str,
    method: &'static str,
    param: RecommendedPlaylistsParam,
}

#[derive(Serialize)]
struct RecommendedPlaylistsParam {
    #[serde(rename = "From")]
    offset: u32,
    #[serde(rename = "Size")]
    size: u32,
}

#[derive(Deserialize)]
struct RecommendedPlaylistsResponse {
    code: Option<i64>,
    recommend: Option<RecommendedPlaylistsResult>,
}

#[derive(Deserialize)]
struct RecommendedPlaylistsResult {
    code: Option<i64>,
    data: Option<RecommendedPlaylistsData>,
}

#[derive(Deserialize)]
struct RecommendedPlaylistsData {
    #[serde(rename = "List")]
    playlists: Option<Vec<RawRecommendedItem>>,
    #[serde(rename = "HasMore")]
    has_more: Option<bool>,
}

#[derive(Deserialize)]
struct RawRecommendedItem {
    #[serde(rename = "Playlist")]
    playlist: Option<RawRecommendedPlaylist>,
}

#[derive(Deserialize)]
struct RawRecommendedPlaylist {
    basic: Option<RawRecommendedPlaylistBasic>,
}

#[derive(Deserialize)]
struct RawRecommendedPlaylistBasic {
    tid: Option<u64>,
    title: Option<String>,
    cover: Option<RawRecommendedCover>,
    song_cnt: Option<u32>,
}

#[derive(Deserialize)]
struct RawRecommendedCover {
    #[serde(rename = "medium_url")]
    medium: Option<String>,
    #[serde(rename = "big_url")]
    big: Option<String>,
    #[serde(rename = "default_url")]
    default: Option<String>,
    #[serde(rename = "small_url")]
    small: Option<String>,
}

impl RawRecommendedCover {
    fn best(self) -> Option<String> {
        [self.medium, self.big, self.default, self.small]
            .into_iter()
            .flatten()
            .find(|value| !value.trim().is_empty())
    }
}

fn map_response<E>(
    envelope: RecommendedPlaylistsResponse,
    offset: u32,
    requested_size: u32,
) -> Result<QqMusicRecommendedPlaylistsPage, QqMusicRecommendedPlaylistsError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicRecommendedPlaylistsError::MissingGlobalCode)?;
    let result_code = envelope.recommend.as_ref().and_then(|result| result.code);
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicRecommendedPlaylistsError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .recommend
        .ok_or(QqMusicRecommendedPlaylistsError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicRecommendedPlaylistsError::MissingResultCode)?;
    let data = result
        .data
        .ok_or(QqMusicRecommendedPlaylistsError::MissingData)?;
    let raw_playlists = data
        .playlists
        .ok_or(QqMusicRecommendedPlaylistsError::MissingPlaylists)?;
    let has_more = data
        .has_more
        .ok_or(QqMusicRecommendedPlaylistsError::MissingHasMore)?;
    let count = u32::try_from(raw_playlists.len())
        .map_err(|_| QqMusicRecommendedPlaylistsError::InvalidPagination)?;
    if count > requested_size || (has_more && count == 0) || offset.checked_add(count).is_none() {
        return Err(QqMusicRecommendedPlaylistsError::InvalidPagination);
    }
    let playlists = raw_playlists
        .into_iter()
        .enumerate()
        .map(|(index, item)| map_playlist(item, index))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(QqMusicRecommendedPlaylistsPage {
        offset,
        has_more,
        playlists,
    })
}

fn map_playlist<E>(
    item: RawRecommendedItem,
    index: usize,
) -> Result<QqMusicRecommendedPlaylist, QqMusicRecommendedPlaylistsError<E>> {
    let playlist = item
        .playlist
        .ok_or(QqMusicRecommendedPlaylistsError::InvalidPlaylist {
            index,
            field: RecommendedPlaylistField::Wrapper,
        })?;
    let basic = playlist
        .basic
        .ok_or(QqMusicRecommendedPlaylistsError::InvalidPlaylist {
            index,
            field: RecommendedPlaylistField::Basic,
        })?;
    let playlist_id = basic.tid.filter(|value| *value != 0).ok_or(
        QqMusicRecommendedPlaylistsError::InvalidPlaylist {
            index,
            field: RecommendedPlaylistField::PlaylistId,
        },
    )?;
    let title = basic.title.filter(|value| !value.trim().is_empty()).ok_or(
        QqMusicRecommendedPlaylistsError::InvalidPlaylist {
            index,
            field: RecommendedPlaylistField::Title,
        },
    )?;
    Ok(QqMusicRecommendedPlaylist {
        playlist_id,
        title,
        cover_url: basic.cover.and_then(RawRecommendedCover::best),
        track_count: basic.song_cnt,
    })
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use super::{MAX_RESPONSE_BYTES, QqMusicRecommendedPlaylistsError, REQUEST_TIMEOUT};
    use crate::{HttpMethod, HttpRequest, HttpResponse, HttpTransport, QqMusicClient};

    struct RecommendationTransport {
        response: HttpResponse,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl RecommendationTransport {
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

    impl HttpTransport for RecommendationTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("request lock").push(request);
            Ok(self.response.clone())
        }
    }

    #[tokio::test]
    async fn serializes_evidenced_page_and_maps_playlists() {
        let client = QqMusicClient::new(RecommendationTransport::new(&json!({
            "code": 0,
            "recommend": {
                "code": 0,
                "data": {
                    "List": [{
                        "Playlist": {"basic": {
                            "tid": 8001,
                            "title": "Fixture discovery",
                            "cover": {"medium_url": "https://example.invalid/cover.jpg"},
                            "song_cnt": 31
                        }}
                    }],
                    "HasMore": true,
                    "FromLimit": 400
                }
            }
        })));

        let page = client
            .recommended_playlists(30, 10)
            .await
            .expect("fixture recommendation page");
        assert_eq!(page.offset(), 30);
        assert!(page.has_more());
        assert_eq!(page.playlists().len(), 1);
        assert_eq!(page.playlists()[0].playlist_id(), 8001);
        assert_eq!(page.playlists()[0].title(), "Fixture discovery");
        assert_eq!(page.playlists()[0].track_count(), Some(31));

        let request = &client.transport().requests.lock().expect("request lock")[0];
        assert_eq!(request.method(), HttpMethod::Post);
        assert_eq!(request.max_response_body_bytes(), MAX_RESPONSE_BYTES);
        assert_eq!(request.request_timeout(), Some(REQUEST_TIMEOUT));
        assert!(request.headers().iter().all(|(name, _)| name != "Cookie"));
        let body: Value = serde_json::from_slice(
            request
                .body_bytes()
                .expect("recommended-playlist request body"),
        )
        .expect("request JSON");
        assert_eq!(body["recommend"]["module"], "music.playlist.PlaylistSquare");
        assert_eq!(body["recommend"]["method"], "GetRecommendFeed");
        assert_eq!(body["recommend"]["param"]["From"], 30);
        assert_eq!(body["recommend"]["param"]["Size"], 10);
    }

    #[tokio::test]
    async fn rejects_invalid_input_pagination_and_rows_without_content_leak() {
        let transport = RecommendationTransport::new(&json!({}));
        let client = QqMusicClient::new(transport);
        assert!(matches!(
            client.recommended_playlists(0, 0).await,
            Err(QqMusicRecommendedPlaylistsError::InvalidPageSize { size: 0 })
        ));
        assert!(
            client
                .transport()
                .requests
                .lock()
                .expect("request lock")
                .is_empty()
        );

        let client = QqMusicClient::new(RecommendationTransport::new(&json!({
            "code": 0,
            "recommend": {"code": 0, "data": {
                "List": [{"Playlist": {"basic": {"tid": 0, "title": "must-not-leak"}}}],
                "HasMore": false
            }}
        })));
        let error = client
            .recommended_playlists(0, 10)
            .await
            .expect_err("invalid playlist");
        assert!(!format!("{error:?} {error}").contains("must-not-leak"));

        let client = QqMusicClient::new(RecommendationTransport::new(&json!({
            "code": 0,
            "recommend": {"code": 0, "data": {
                "List": [{"Playlist": {"basic": {
                    "tid": 8002,
                    "title": "overflow fixture"
                }}}],
                "HasMore": true
            }}
        })));
        assert!(matches!(
            client.recommended_playlists(u32::MAX, 10).await,
            Err(QqMusicRecommendedPlaylistsError::InvalidPagination)
        ));
    }
}
