use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::{
    HttpRequest, HttpTransport, QqMusicAlbumSummary, QqMusicArtistSummary, QqMusicClient,
    QqMusicTrackSummary,
};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_PAGE_SIZE: u32 = 30;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RankingGroupField {
    Title,
    Rankings,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RankingField {
    Id,
    Title,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RankingTrackField {
    TrackId,
    SongMid,
    FileMediaMid,
    Title,
    SongType,
    Artists,
    ArtistName,
}

pub enum QqMusicRankingsError<E> {
    InvalidRankingId,
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
    MissingGroups,
    InvalidGroup {
        index: usize,
        field: RankingGroupField,
    },
    InvalidRanking {
        group_index: usize,
        ranking_index: usize,
        field: RankingField,
    },
    MismatchedRankingId,
    MissingTotal,
    MissingTracks,
    InvalidPagination,
    InvalidTrack {
        index: usize,
        field: RankingTrackField,
    },
    InvalidArtist {
        track_index: usize,
        artist_index: usize,
    },
}

impl<E> fmt::Debug for QqMusicRankingsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidRankingId => formatter.write_str("InvalidRankingId([REDACTED])"),
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
            Self::MissingGroups => formatter.write_str("MissingGroups"),
            Self::InvalidGroup { index, field } => formatter
                .debug_struct("InvalidGroup")
                .field("index", index)
                .field("field", field)
                .finish(),
            Self::InvalidRanking {
                group_index,
                ranking_index,
                field,
            } => formatter
                .debug_struct("InvalidRanking")
                .field("group_index", group_index)
                .field("ranking_index", ranking_index)
                .field("field", field)
                .finish(),
            Self::MismatchedRankingId => formatter.write_str("MismatchedRankingId([REDACTED])"),
            Self::MissingTotal => formatter.write_str("MissingTotal"),
            Self::MissingTracks => formatter.write_str("MissingTracks"),
            Self::InvalidPagination => formatter.write_str("InvalidPagination"),
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

impl<E> fmt::Display for QqMusicRankingsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidRankingId => formatter.write_str("ranking ID is invalid"),
            Self::InvalidPageSize { size } => {
                write!(
                    formatter,
                    "ranking page size {size} is outside 1..={MAX_PAGE_SIZE}"
                )
            }
            Self::Transport(_) => formatter.write_str("QQ Music ranking request failed"),
            Self::Serialize => formatter.write_str("could not serialize ranking request"),
            Self::HttpStatus(status) => write!(formatter, "ranking request returned HTTP {status}"),
            Self::InvalidJson => formatter.write_str("ranking response was not valid JSON"),
            Self::MissingGlobalCode => formatter.write_str("ranking response has no global code"),
            Self::MissingResult => formatter.write_str("ranking result is missing"),
            Self::MissingResultCode => formatter.write_str("ranking result has no code"),
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "ranking request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("ranking data is missing"),
            Self::MissingGroups => formatter.write_str("ranking groups are missing"),
            Self::InvalidGroup { index, field } => {
                write!(formatter, "ranking group {index} has an invalid {field:?}")
            }
            Self::InvalidRanking {
                group_index,
                ranking_index,
                field,
            } => write!(
                formatter,
                "ranking {ranking_index} in group {group_index} has an invalid {field:?}"
            ),
            Self::MismatchedRankingId => {
                formatter.write_str("ranking detail did not match the request")
            }
            Self::MissingTotal => formatter.write_str("ranking Track total is missing"),
            Self::MissingTracks => formatter.write_str("ranking Track list is missing"),
            Self::InvalidPagination => formatter.write_str("ranking pagination is invalid"),
            Self::InvalidTrack { index, field } => {
                write!(formatter, "ranking Track {index} has an invalid {field:?}")
            }
            Self::InvalidArtist {
                track_index,
                artist_index,
            } => write!(
                formatter,
                "ranking Track {track_index} artist {artist_index} is invalid"
            ),
        }
    }
}

impl<E> std::error::Error for QqMusicRankingsError<E>
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
pub struct QqMusicRankingSummary {
    top_id: u64,
    title: String,
    period: Option<String>,
    artwork_uri: Option<String>,
    total: Option<u32>,
}

impl QqMusicRankingSummary {
    #[must_use]
    pub const fn top_id(&self) -> u64 {
        self.top_id
    }

    #[must_use]
    pub fn title(&self) -> &str {
        &self.title
    }

    #[must_use]
    pub fn period(&self) -> Option<&str> {
        self.period.as_deref()
    }

    #[must_use]
    pub fn artwork_uri(&self) -> Option<&str> {
        self.artwork_uri.as_deref()
    }

    #[must_use]
    pub const fn total(&self) -> Option<u32> {
        self.total
    }
}

impl fmt::Debug for QqMusicRankingSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRankingSummary")
            .field("top_id", &"[REDACTED]")
            .field("title", &"[REDACTED]")
            .field("has_period", &self.period.is_some())
            .field("has_artwork", &self.artwork_uri.is_some())
            .field("total", &self.total)
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicRankingGroup {
    title: String,
    rankings: Vec<QqMusicRankingSummary>,
}

impl QqMusicRankingGroup {
    #[must_use]
    pub fn title(&self) -> &str {
        &self.title
    }

    #[must_use]
    pub fn rankings(&self) -> &[QqMusicRankingSummary] {
        &self.rankings
    }
}

impl fmt::Debug for QqMusicRankingGroup {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRankingGroup")
            .field("title", &"[REDACTED]")
            .field("ranking_count", &self.rankings.len())
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicRankingTrackPage {
    ranking: QqMusicRankingSummary,
    offset: u32,
    total: u32,
    has_more: bool,
    tracks: Vec<QqMusicTrackSummary>,
}

impl QqMusicRankingTrackPage {
    #[must_use]
    pub const fn ranking(&self) -> &QqMusicRankingSummary {
        &self.ranking
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
    pub fn tracks(&self) -> &[QqMusicTrackSummary] {
        &self.tracks
    }
}

impl fmt::Debug for QqMusicRankingTrackPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRankingTrackPage")
            .field("ranking", &self.ranking)
            .field("offset", &self.offset)
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
    /// Loads QQ Music's current public ranking groups without account data.
    ///
    /// # Errors
    ///
    /// Keeps transport, service, response-shape, group, and ranking mapping
    /// failures distinct without retaining editorial content.
    pub async fn ranking_groups(
        &self,
    ) -> Result<Vec<QqMusicRankingGroup>, QqMusicRankingsError<T::Error>> {
        let body = serde_json::to_vec(&RankingListRequest::new())
            .map_err(|_| QqMusicRankingsError::Serialize)?;
        let response = self
            .transport()
            .execute(ranking_request(body))
            .await
            .map_err(QqMusicRankingsError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicRankingsError::HttpStatus(response.status()));
        }
        let envelope: RankingListResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicRankingsError::InvalidJson)?;
        map_list_response(envelope)
    }

    /// Loads one bounded page from the service-selected current period.
    ///
    /// # Errors
    ///
    /// Keeps input, transport, service, response-shape, pagination, and Track
    /// mapping failures distinct without retaining ranking or Track content.
    pub async fn ranking_tracks(
        &self,
        top_id: u64,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicRankingTrackPage, QqMusicRankingsError<T::Error>> {
        if top_id == 0 {
            return Err(QqMusicRankingsError::InvalidRankingId);
        }
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicRankingsError::InvalidPageSize { size });
        }
        let body = serde_json::to_vec(&RankingDetailRequest::new(top_id, offset, size))
            .map_err(|_| QqMusicRankingsError::Serialize)?;
        let response = self
            .transport()
            .execute(ranking_request(body))
            .await
            .map_err(QqMusicRankingsError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicRankingsError::HttpStatus(response.status()));
        }
        let envelope: RankingDetailResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicRankingsError::InvalidJson)?;
        map_detail_response(envelope, top_id, offset, size)
    }
}

fn ranking_request(body: Vec<u8>) -> HttpRequest {
    HttpRequest::post(MUSICU_URL)
        .header("Content-Type", "application/json")
        .header("Origin", "https://y.qq.com")
        .header("Referer", "https://y.qq.com/")
        .body(body)
        .response_body_limit(MAX_RESPONSE_BYTES)
        .timeout(REQUEST_TIMEOUT)
}

#[derive(Serialize)]
struct RankingListRequest {
    #[serde(rename = "music.musicToplist.Toplist.GetAll")]
    request: RankingListRpc,
}

impl RankingListRequest {
    const fn new() -> Self {
        Self {
            request: RankingListRpc {
                module: "music.musicToplist.Toplist",
                method: "GetAll",
                param: EmptyParam {},
            },
        }
    }
}

#[derive(Serialize)]
struct RankingListRpc {
    module: &'static str,
    method: &'static str,
    param: EmptyParam,
}

#[derive(Serialize)]
struct EmptyParam {}

#[derive(Serialize)]
struct RankingDetailRequest {
    #[serde(rename = "music.musicToplist.Toplist.GetDetail")]
    request: RankingDetailRpc,
}

impl RankingDetailRequest {
    const fn new(top_id: u64, offset: u32, size: u32) -> Self {
        Self {
            request: RankingDetailRpc {
                module: "music.musicToplist.Toplist",
                method: "GetDetail",
                param: RankingDetailParam {
                    top_id,
                    offset,
                    size,
                    with_tags: false,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct RankingDetailRpc {
    module: &'static str,
    method: &'static str,
    param: RankingDetailParam,
}

#[derive(Serialize)]
struct RankingDetailParam {
    #[serde(rename = "topId")]
    top_id: u64,
    offset: u32,
    #[serde(rename = "num")]
    size: u32,
    #[serde(rename = "withTags")]
    with_tags: bool,
}

#[derive(Deserialize)]
struct RankingListResponse {
    code: Option<i64>,
    #[serde(rename = "music.musicToplist.Toplist.GetAll")]
    result: Option<RankingListResult>,
}

#[derive(Deserialize)]
struct RankingListResult {
    code: Option<i64>,
    data: Option<RankingListData>,
}

#[derive(Deserialize)]
struct RankingListData {
    group: Option<Vec<RawRankingGroup>>,
}

#[derive(Deserialize)]
struct RawRankingGroup {
    #[serde(rename = "groupName")]
    title: Option<String>,
    toplist: Option<Vec<RawRankingSummary>>,
}

#[derive(Deserialize)]
struct RankingDetailResponse {
    code: Option<i64>,
    #[serde(rename = "music.musicToplist.Toplist.GetDetail")]
    result: Option<RankingDetailResult>,
}

#[derive(Deserialize)]
struct RankingDetailResult {
    code: Option<i64>,
    data: Option<RankingDetailData>,
}

#[derive(Deserialize)]
struct RankingDetailData {
    data: Option<RawRankingSummary>,
    #[serde(rename = "songInfoList")]
    tracks: Option<Vec<RawRankingTrack>>,
}

#[derive(Deserialize)]
struct RawRankingSummary {
    #[serde(rename = "topId")]
    top_id: Option<u64>,
    title: Option<String>,
    period: Option<String>,
    #[serde(rename = "frontPicUrl")]
    front_pic_url: Option<String>,
    #[serde(rename = "headPicUrl")]
    head_pic_url: Option<String>,
    #[serde(rename = "totalNum")]
    total: Option<u32>,
}

#[derive(Deserialize)]
struct RawRankingTrack {
    id: Option<u64>,
    mid: Option<String>,
    name: Option<String>,
    title: Option<String>,
    subtitle: Option<String>,
    #[serde(rename = "type")]
    song_type: Option<u32>,
    interval: Option<u32>,
    singer: Option<Vec<RawArtist>>,
    album: Option<RawAlbum>,
    file: Option<RawFile>,
}

#[derive(Deserialize)]
struct RawFile {
    media_mid: Option<String>,
}

#[derive(Deserialize)]
struct RawArtist {
    id: Option<u64>,
    mid: Option<String>,
    name: Option<String>,
}

#[derive(Deserialize)]
struct RawAlbum {
    id: Option<u64>,
    mid: Option<String>,
    pmid: Option<String>,
    name: Option<String>,
    title: Option<String>,
}

fn map_list_response<E>(
    envelope: RankingListResponse,
) -> Result<Vec<QqMusicRankingGroup>, QqMusicRankingsError<E>> {
    let data = checked_list_data(envelope)?;
    data.group
        .ok_or(QqMusicRankingsError::MissingGroups)?
        .into_iter()
        .enumerate()
        .map(|(group_index, raw)| {
            let title = nonblank(raw.title).ok_or(QqMusicRankingsError::InvalidGroup {
                index: group_index,
                field: RankingGroupField::Title,
            })?;
            let raw_rankings = raw.toplist.ok_or(QqMusicRankingsError::InvalidGroup {
                index: group_index,
                field: RankingGroupField::Rankings,
            })?;
            if raw_rankings.is_empty() {
                return Err(QqMusicRankingsError::InvalidGroup {
                    index: group_index,
                    field: RankingGroupField::Rankings,
                });
            }
            let rankings = raw_rankings
                .into_iter()
                .enumerate()
                .map(|(ranking_index, ranking)| {
                    map_ranking_summary(ranking).map_err(|field| {
                        QqMusicRankingsError::InvalidRanking {
                            group_index,
                            ranking_index,
                            field,
                        }
                    })
                })
                .collect::<Result<Vec<_>, _>>()?;
            Ok(QqMusicRankingGroup { title, rankings })
        })
        .collect()
}

fn checked_list_data<E>(
    envelope: RankingListResponse,
) -> Result<RankingListData, QqMusicRankingsError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicRankingsError::MissingGlobalCode)?;
    let result_code = envelope.result.as_ref().and_then(|result| result.code);
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicRankingsError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope.result.ok_or(QqMusicRankingsError::MissingResult)?;
    result.code.ok_or(QqMusicRankingsError::MissingResultCode)?;
    result.data.ok_or(QqMusicRankingsError::MissingData)
}

fn map_detail_response<E>(
    envelope: RankingDetailResponse,
    requested_id: u64,
    requested_offset: u32,
    requested_size: u32,
) -> Result<QqMusicRankingTrackPage, QqMusicRankingsError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicRankingsError::MissingGlobalCode)?;
    let result_code = envelope.result.as_ref().and_then(|result| result.code);
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicRankingsError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope.result.ok_or(QqMusicRankingsError::MissingResult)?;
    result.code.ok_or(QqMusicRankingsError::MissingResultCode)?;
    let data = result.data.ok_or(QqMusicRankingsError::MissingData)?;
    let ranking = map_ranking_summary(data.data.ok_or(QqMusicRankingsError::MissingData)?)
        .map_err(|field| QqMusicRankingsError::InvalidRanking {
            group_index: 0,
            ranking_index: 0,
            field,
        })?;
    if ranking.top_id != requested_id {
        return Err(QqMusicRankingsError::MismatchedRankingId);
    }
    let total = ranking.total.ok_or(QqMusicRankingsError::MissingTotal)?;
    if requested_offset > total {
        return Err(QqMusicRankingsError::InvalidPagination);
    }
    let raw_tracks = data.tracks.ok_or(QqMusicRankingsError::MissingTracks)?;
    let count =
        u32::try_from(raw_tracks.len()).map_err(|_| QqMusicRankingsError::InvalidPagination)?;
    if count > requested_size {
        return Err(QqMusicRankingsError::InvalidPagination);
    }
    let end = requested_offset
        .checked_add(count)
        .ok_or(QqMusicRankingsError::InvalidPagination)?;
    if end > total {
        return Err(QqMusicRankingsError::InvalidPagination);
    }
    let has_more = end < total;
    if has_more && raw_tracks.is_empty() {
        return Err(QqMusicRankingsError::InvalidPagination);
    }
    let tracks = raw_tracks
        .into_iter()
        .enumerate()
        .map(|(index, track)| map_track(track, index))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(QqMusicRankingTrackPage {
        ranking,
        offset: requested_offset,
        total,
        has_more,
        tracks,
    })
}

fn map_ranking_summary(raw: RawRankingSummary) -> Result<QqMusicRankingSummary, RankingField> {
    let top_id = raw
        .top_id
        .filter(|value| *value != 0)
        .ok_or(RankingField::Id)?;
    let title = nonblank(raw.title).ok_or(RankingField::Title)?;
    Ok(QqMusicRankingSummary {
        top_id,
        title,
        period: nonblank(raw.period),
        artwork_uri: nonblank(raw.front_pic_url).or_else(|| nonblank(raw.head_pic_url)),
        total: raw.total,
    })
}

fn map_track<E>(
    raw: RawRankingTrack,
    index: usize,
) -> Result<QqMusicTrackSummary, QqMusicRankingsError<E>> {
    let track_id =
        raw.id
            .filter(|value| *value != 0)
            .ok_or(QqMusicRankingsError::InvalidTrack {
                index,
                field: RankingTrackField::TrackId,
            })?;
    let song_mid = safe_mid(raw.mid).ok_or(QqMusicRankingsError::InvalidTrack {
        index,
        field: RankingTrackField::SongMid,
    })?;
    let file_media_mid = match raw.file.and_then(|file| file.media_mid) {
        Some(value) if value.trim().is_empty() => None,
        Some(value) => Some(
            safe_mid(Some(value)).ok_or(QqMusicRankingsError::InvalidTrack {
                index,
                field: RankingTrackField::FileMediaMid,
            })?,
        ),
        None => None,
    };
    let title = nonblank(raw.title).or_else(|| nonblank(raw.name)).ok_or(
        QqMusicRankingsError::InvalidTrack {
            index,
            field: RankingTrackField::Title,
        },
    )?;
    let song_type = raw.song_type.ok_or(QqMusicRankingsError::InvalidTrack {
        index,
        field: RankingTrackField::SongType,
    })?;
    let raw_artists = raw.singer.ok_or(QqMusicRankingsError::InvalidTrack {
        index,
        field: RankingTrackField::Artists,
    })?;
    let artists = raw_artists
        .into_iter()
        .enumerate()
        .map(|(artist_index, artist)| {
            let name = nonblank(artist.name).ok_or(QqMusicRankingsError::InvalidArtist {
                track_index: index,
                artist_index,
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

fn safe_mid(value: Option<String>) -> Option<String> {
    nonblank(value)
        .filter(|value| value.len() <= 64 && value.bytes().all(|byte| byte.is_ascii_alphanumeric()))
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use crate::{HttpMethod, HttpResponse};

    use super::*;

    struct RankingTransport {
        response: HttpResponse,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl RankingTransport {
        fn new(response: &Value) -> Self {
            Self {
                response: HttpResponse::new(
                    200,
                    serde_json::to_vec(response).expect("response JSON"),
                ),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn requests(&self) -> Vec<HttpRequest> {
            self.requests.lock().expect("request lock").clone()
        }
    }

    impl HttpTransport for RankingTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("request lock").push(request);
            Ok(self.response.clone())
        }
    }

    #[tokio::test]
    async fn serializes_exact_anonymous_list_and_maps_groups() {
        let client = QqMusicClient::new(RankingTransport::new(&ranking_list_json()));
        let groups = client.ranking_groups().await.expect("ranking groups");

        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].title(), "Synthetic group");
        assert_eq!(groups[0].rankings().len(), 2);
        assert_eq!(groups[0].rankings()[0].top_id(), 62001);
        assert_eq!(groups[0].rankings()[0].period(), Some("fixture-period"));
        assert_eq!(groups[0].rankings()[1].period(), None);
        let requests = client.transport().requests();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].method(), HttpMethod::Post);
        assert_eq!(requests[0].url(), MUSICU_URL);
        assert_eq!(requests[0].max_response_body_bytes(), MAX_RESPONSE_BYTES);
        assert_eq!(requests[0].request_timeout(), Some(REQUEST_TIMEOUT));
        let body: Value =
            serde_json::from_slice(requests[0].body_bytes().expect("body")).expect("request JSON");
        assert_eq!(body.as_object().expect("object").len(), 1);
        assert!(body.get("comm").is_none());
        assert_eq!(
            body["music.musicToplist.Toplist.GetAll"]["module"],
            "music.musicToplist.Toplist"
        );
        assert_eq!(
            body["music.musicToplist.Toplist.GetAll"]["method"],
            "GetAll"
        );
        assert_eq!(
            body["music.musicToplist.Toplist.GetAll"]["param"],
            json!({})
        );
        let debug = format!("{groups:?} {:?}", requests[0]);
        assert!(!debug.contains("Synthetic group"));
        assert!(!debug.contains("62001"));
    }

    #[tokio::test]
    async fn serializes_exact_detail_and_maps_bounded_tracks() {
        let client = QqMusicClient::new(RankingTransport::new(&ranking_detail_json(
            62001,
            31,
            &synthetic_tracks(),
        )));
        let page = client
            .ranking_tracks(62001, 30, 5)
            .await
            .expect("ranking Tracks");

        assert_eq!(page.ranking().top_id(), 62001);
        assert_eq!(page.ranking().period(), Some("fixture-period"));
        assert_eq!(page.offset(), 30);
        assert_eq!(page.total(), 31);
        assert!(!page.has_more());
        assert_eq!(page.tracks().len(), 1);
        assert_eq!(page.tracks()[0].song_mid(), "fixtureTrackMid1");
        let requests = client.transport().requests();
        let body: Value =
            serde_json::from_slice(requests[0].body_bytes().expect("body")).expect("request JSON");
        assert_eq!(body.as_object().expect("object").len(), 1);
        assert!(body.get("comm").is_none());
        assert_eq!(
            body["music.musicToplist.Toplist.GetDetail"]["module"],
            "music.musicToplist.Toplist"
        );
        assert_eq!(
            body["music.musicToplist.Toplist.GetDetail"]["method"],
            "GetDetail"
        );
        assert_eq!(
            body["music.musicToplist.Toplist.GetDetail"]["param"]["topId"],
            62001
        );
        assert_eq!(
            body["music.musicToplist.Toplist.GetDetail"]["param"]["offset"],
            30
        );
        assert_eq!(
            body["music.musicToplist.Toplist.GetDetail"]["param"]["num"],
            5
        );
        assert_eq!(
            body["music.musicToplist.Toplist.GetDetail"]["param"]["withTags"],
            false
        );
        let debug = format!("{page:?} {:?}", requests[0]);
        assert!(!debug.contains("Synthetic ranking"));
        assert!(!debug.contains("Synthetic Track"));
        assert!(!debug.contains("62001"));
    }

    #[tokio::test]
    async fn rejects_invalid_inputs_and_structural_mismatches_without_leaks() {
        let client = QqMusicClient::new(RankingTransport::new(&ranking_detail_json(
            62002,
            31,
            &synthetic_tracks(),
        )));
        assert!(matches!(
            client.ranking_tracks(0, 0, 5).await,
            Err(QqMusicRankingsError::InvalidRankingId)
        ));
        assert!(matches!(
            client.ranking_tracks(62001, 0, 31).await,
            Err(QqMusicRankingsError::InvalidPageSize { size: 31 })
        ));
        assert!(client.transport().requests().is_empty());

        let error = client
            .ranking_tracks(62001, 0, 5)
            .await
            .expect_err("mismatched ranking ID");
        assert!(matches!(error, QqMusicRankingsError::MismatchedRankingId));
        assert!(!format!("{error:?} {error}").contains("62001"));

        let invalid = QqMusicClient::new(RankingTransport::new(&ranking_detail_json(
            62001,
            1,
            &synthetic_tracks(),
        )))
        .ranking_tracks(62001, 1, 5)
        .await
        .expect_err("page extends beyond total");
        assert!(matches!(invalid, QqMusicRankingsError::InvalidPagination));
        assert!(!format!("{invalid:?} {invalid}").contains("Synthetic Track"));
    }

    #[tokio::test]
    async fn rejects_invalid_group_and_track_identity() {
        let invalid_group = json!({
            "code": 0,
            "music.musicToplist.Toplist.GetAll": {"code": 0, "data": {"group": [{
                "groupName": "Synthetic group",
                "toplist": []
            }]}}
        });
        assert!(matches!(
            QqMusicClient::new(RankingTransport::new(&invalid_group))
                .ranking_groups()
                .await,
            Err(QqMusicRankingsError::InvalidGroup {
                field: RankingGroupField::Rankings,
                ..
            })
        ));

        let invalid_track = json!([{
            "id": 41001,
            "mid": "unsafe/mid",
            "title": "must-not-leak",
            "type": 0,
            "singer": []
        }]);
        let error = QqMusicClient::new(RankingTransport::new(&ranking_detail_json(
            62001,
            1,
            &invalid_track,
        )))
        .ranking_tracks(62001, 0, 5)
        .await
        .expect_err("invalid Track MID");
        assert!(matches!(
            error,
            QqMusicRankingsError::InvalidTrack {
                field: RankingTrackField::SongMid,
                ..
            }
        ));
        assert!(!format!("{error:?} {error}").contains("must-not-leak"));
    }

    fn ranking_list_json() -> Value {
        json!({
            "code": 0,
            "music.musicToplist.Toplist.GetAll": {"code": 0, "data": {"group": [{
                "groupName": "Synthetic group",
                "toplist": [
                    {
                        "topId": 62001,
                        "title": "Synthetic ranking one",
                        "period": "fixture-period",
                        "frontPicUrl": "https://example.invalid/ranking.jpg",
                        "totalNum": 100
                    },
                    {"topId": 62002, "title": "Synthetic ranking two"}
                ]
            }]}}
        })
    }

    fn ranking_detail_json(top_id: u64, total: u32, tracks: &Value) -> Value {
        json!({
            "code": 0,
            "music.musicToplist.Toplist.GetDetail": {"code": 0, "data": {
                "data": {
                    "topId": top_id,
                    "title": "Synthetic ranking",
                    "period": "fixture-period",
                    "frontPicUrl": "https://example.invalid/ranking.jpg",
                    "totalNum": total
                },
                "songInfoList": tracks,
                "songTagInfoList": []
            }}
        })
    }

    fn synthetic_tracks() -> Value {
        json!([{
            "id": 41001,
            "mid": "fixtureTrackMid1",
            "title": "Synthetic Track",
            "subtitle": "Synthetic subtitle",
            "type": 0,
            "interval": 245,
            "file": {"media_mid": "fixtureFileMid1"},
            "singer": [{"id": 42001, "mid": "artistOneMid", "name": "Artist one"}],
            "album": {"id": 43001, "mid": "fixtureAlbumMid", "name": "Synthetic album"}
        }])
    }
}
