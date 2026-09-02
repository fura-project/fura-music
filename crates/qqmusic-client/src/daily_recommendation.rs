use std::collections::HashSet;
use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::credential::is_credential_rejection_code;
use crate::{Credential, HttpRequest, HttpTransport, QqMusicClient, normalized_https_image_uri};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_TEXT_BYTES: usize = 4 * 1024;
const DAILY_PLAYLIST_JUMP_TYPE: u32 = 10_014;
const DAILY_MODULE_PREFIX: &str = "recforyou";
const DAILY_TRACE_MARKER: &str = "#daily30:";
const PERSONALIZED_PLAYLIST_MODULE_PREFIX: &str = "playlist";
const MAX_PERSONALIZED_PLAYLISTS: usize = 64;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DailyRecommendationField {
    PlaylistId,
    Title,
    ArtworkUri,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PersonalizedPlaylistField {
    PlaylistId,
    Title,
    ArtworkUri,
}

pub enum QqMusicDailyRecommendationError<E> {
    Transport(E),
    Serialize,
    HttpStatus(u16),
    InvalidJson,
    MissingGlobalCode,
    MissingResult,
    MissingResultCode,
    MissingData,
    MissingDataCode,
    MissingShelves,
    InvalidFeed,
    Rejected {
        code: i64,
    },
    Upstream {
        global_code: i64,
        result_code: Option<i64>,
        data_code: Option<i64>,
    },
    MultipleDailyPlaylists,
    InvalidDailyPlaylist {
        field: DailyRecommendationField,
    },
}

pub enum QqMusicPersonalizedPlaylistsError<E> {
    Transport(E),
    Serialize,
    HttpStatus(u16),
    InvalidJson,
    MissingGlobalCode,
    MissingResult,
    MissingResultCode,
    MissingData,
    MissingDataCode,
    MissingShelves,
    InvalidFeed,
    Rejected {
        code: i64,
    },
    Upstream {
        global_code: i64,
        result_code: Option<i64>,
        data_code: Option<i64>,
    },
    MultiplePlaylistShelves,
    TooManyPlaylists,
    DuplicatePlaylistId,
    InvalidPlaylist {
        field: PersonalizedPlaylistField,
    },
}

impl<E> fmt::Debug for QqMusicPersonalizedPlaylistsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Transport(_) => formatter.write_str("Transport([REDACTED])"),
            Self::Serialize => formatter.write_str("Serialize"),
            Self::HttpStatus(status) => formatter.debug_tuple("HttpStatus").field(status).finish(),
            Self::InvalidJson => formatter.write_str("InvalidJson([REDACTED])"),
            Self::MissingGlobalCode => formatter.write_str("MissingGlobalCode"),
            Self::MissingResult => formatter.write_str("MissingResult"),
            Self::MissingResultCode => formatter.write_str("MissingResultCode"),
            Self::MissingData => formatter.write_str("MissingData"),
            Self::MissingDataCode => formatter.write_str("MissingDataCode"),
            Self::MissingShelves => formatter.write_str("MissingShelves"),
            Self::InvalidFeed => formatter.write_str("InvalidFeed"),
            Self::Rejected { code } => formatter
                .debug_struct("Rejected")
                .field("code", code)
                .finish(),
            Self::Upstream {
                global_code,
                result_code,
                data_code,
            } => formatter
                .debug_struct("Upstream")
                .field("global_code", global_code)
                .field("result_code", result_code)
                .field("data_code", data_code)
                .finish(),
            Self::MultiplePlaylistShelves => formatter.write_str("MultiplePlaylistShelves"),
            Self::TooManyPlaylists => formatter.write_str("TooManyPlaylists"),
            Self::DuplicatePlaylistId => formatter.write_str("DuplicatePlaylistId([REDACTED])"),
            Self::InvalidPlaylist { field } => formatter
                .debug_struct("InvalidPlaylist")
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicPersonalizedPlaylistsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Transport(_) => {
                formatter.write_str("QQ Music personalized-playlist request failed")
            }
            Self::Serialize => {
                formatter.write_str("could not serialize personalized-playlist request")
            }
            Self::HttpStatus(status) => write!(
                formatter,
                "personalized-playlist request returned HTTP {status}"
            ),
            Self::InvalidJson => {
                formatter.write_str("personalized-playlist response was not valid JSON")
            }
            Self::MissingGlobalCode => {
                formatter.write_str("personalized-playlist response has no global code")
            }
            Self::MissingResult => formatter.write_str("personalized-playlist result is missing"),
            Self::MissingResultCode => {
                formatter.write_str("personalized-playlist result has no code")
            }
            Self::MissingData => formatter.write_str("personalized-playlist data is missing"),
            Self::MissingDataCode => {
                formatter.write_str("personalized-playlist data has no return code")
            }
            Self::MissingShelves => {
                formatter.write_str("personalized-playlist feed shelves are missing")
            }
            Self::InvalidFeed => {
                formatter.write_str("personalized-playlist feed structure is invalid")
            }
            Self::Rejected { code } => write!(
                formatter,
                "QQ Music rejected the credential with code {code}"
            ),
            Self::Upstream {
                global_code,
                result_code,
                data_code,
            } => write!(
                formatter,
                "personalized-playlist request failed with global code {global_code}, result code {result_code:?}, and data code {data_code:?}"
            ),
            Self::MultiplePlaylistShelves => {
                formatter.write_str("personalized-playlist feed returned multiple matching shelves")
            }
            Self::TooManyPlaylists => {
                formatter.write_str("personalized-playlist shelf exceeded the safety limit")
            }
            Self::DuplicatePlaylistId => {
                formatter.write_str("personalized-playlist shelf contains duplicate identity")
            }
            Self::InvalidPlaylist { field } => {
                write!(formatter, "personalized playlist has an invalid {field:?}")
            }
        }
    }
}

impl<E> std::error::Error for QqMusicPersonalizedPlaylistsError<E>
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

impl<E> fmt::Debug for QqMusicDailyRecommendationError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Transport(_) => formatter.write_str("Transport([REDACTED])"),
            Self::Serialize => formatter.write_str("Serialize"),
            Self::HttpStatus(status) => formatter.debug_tuple("HttpStatus").field(status).finish(),
            Self::InvalidJson => formatter.write_str("InvalidJson([REDACTED])"),
            Self::MissingGlobalCode => formatter.write_str("MissingGlobalCode"),
            Self::MissingResult => formatter.write_str("MissingResult"),
            Self::MissingResultCode => formatter.write_str("MissingResultCode"),
            Self::MissingData => formatter.write_str("MissingData"),
            Self::MissingDataCode => formatter.write_str("MissingDataCode"),
            Self::MissingShelves => formatter.write_str("MissingShelves"),
            Self::InvalidFeed => formatter.write_str("InvalidFeed"),
            Self::Rejected { code } => formatter
                .debug_struct("Rejected")
                .field("code", code)
                .finish(),
            Self::Upstream {
                global_code,
                result_code,
                data_code,
            } => formatter
                .debug_struct("Upstream")
                .field("global_code", global_code)
                .field("result_code", result_code)
                .field("data_code", data_code)
                .finish(),
            Self::MultipleDailyPlaylists => formatter.write_str("MultipleDailyPlaylists"),
            Self::InvalidDailyPlaylist { field } => formatter
                .debug_struct("InvalidDailyPlaylist")
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicDailyRecommendationError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Transport(_) => formatter.write_str("QQ Music Daily 30 request failed"),
            Self::Serialize => formatter.write_str("could not serialize Daily 30 request"),
            Self::HttpStatus(status) => {
                write!(formatter, "Daily 30 request returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("Daily 30 response was not valid JSON"),
            Self::MissingGlobalCode => formatter.write_str("Daily 30 response has no global code"),
            Self::MissingResult => formatter.write_str("Daily 30 result is missing"),
            Self::MissingResultCode => formatter.write_str("Daily 30 result has no code"),
            Self::MissingData => formatter.write_str("Daily 30 data is missing"),
            Self::MissingDataCode => formatter.write_str("Daily 30 data has no return code"),
            Self::MissingShelves => formatter.write_str("Daily 30 feed shelves are missing"),
            Self::InvalidFeed => formatter.write_str("Daily 30 feed structure is invalid"),
            Self::Rejected { code } => write!(
                formatter,
                "QQ Music rejected the credential with code {code}"
            ),
            Self::Upstream {
                global_code,
                result_code,
                data_code,
            } => write!(
                formatter,
                "Daily 30 request failed with global code {global_code}, result code {result_code:?}, and data code {data_code:?}"
            ),
            Self::MultipleDailyPlaylists => {
                formatter.write_str("Daily 30 feed returned multiple matching playlists")
            }
            Self::InvalidDailyPlaylist { field } => {
                write!(formatter, "Daily 30 playlist has an invalid {field:?}")
            }
        }
    }
}

impl<E> std::error::Error for QqMusicDailyRecommendationError<E>
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
pub struct QqMusicDailyRecommendation {
    playlist_id: u64,
    title: String,
    artwork_uri: Option<String>,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicPersonalizedPlaylist {
    playlist_id: u64,
    title: String,
    artwork_uri: Option<String>,
}

impl QqMusicPersonalizedPlaylist {
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
}

impl fmt::Debug for QqMusicPersonalizedPlaylist {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicPersonalizedPlaylist")
            .field("playlist_id", &"[REDACTED]")
            .field("title", &"[REDACTED]")
            .field("has_artwork", &self.artwork_uri.is_some())
            .finish()
    }
}

impl QqMusicDailyRecommendation {
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
}

impl fmt::Debug for QqMusicDailyRecommendation {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicDailyRecommendation")
            .field("playlist_id", &"[REDACTED]")
            .field("title", &"[REDACTED]")
            .field("has_artwork", &self.artwork_uri.is_some())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Loads the authenticated Daily 30 playlist summary from the QQ Music
    /// recommendation feed without exposing the heterogeneous feed upstream.
    ///
    /// # Errors
    ///
    /// Keeps credential rejection, transport, service, response-shape, and
    /// Daily-card mapping failures distinct without retaining feed content.
    pub async fn daily_recommendation(
        &self,
        credential: &Credential,
    ) -> Result<Option<QqMusicDailyRecommendation>, QqMusicDailyRecommendationError<T::Error>> {
        let body = serde_json::to_vec(&DailyRecommendationRequest::new(credential))
            .map_err(|_| QqMusicDailyRecommendationError::Serialize)?;
        let response = self
            .transport()
            .execute(
                HttpRequest::post(MUSICU_URL)
                    .header("Content-Type", "application/json")
                    .header("Origin", "https://y.qq.com")
                    .header("Referer", "https://y.qq.com/")
                    .header("Cookie", credential.musicu_cookie_header())
                    .body(body)
                    .response_body_limit(MAX_RESPONSE_BYTES)
                    .timeout(REQUEST_TIMEOUT),
            )
            .await
            .map_err(QqMusicDailyRecommendationError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicDailyRecommendationError::HttpStatus(
                response.status(),
            ));
        }
        let envelope: DailyRecommendationResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicDailyRecommendationError::InvalidJson)?;
        map_response(envelope)
    }

    /// Loads the authenticated personalized-playlist shelf without exposing
    /// the heterogeneous recommendation feed upstream.
    ///
    /// # Errors
    ///
    /// Keeps credential rejection, transport, service, response-shape, and
    /// playlist-card mapping failures distinct without retaining feed content.
    pub async fn personalized_playlists(
        &self,
        credential: &Credential,
    ) -> Result<Vec<QqMusicPersonalizedPlaylist>, QqMusicPersonalizedPlaylistsError<T::Error>> {
        let body = serde_json::to_vec(&DailyRecommendationRequest::new(credential))
            .map_err(|_| QqMusicPersonalizedPlaylistsError::Serialize)?;
        let response = self
            .transport()
            .execute(
                HttpRequest::post(MUSICU_URL)
                    .header("Content-Type", "application/json")
                    .header("Origin", "https://y.qq.com")
                    .header("Referer", "https://y.qq.com/")
                    .header("Cookie", credential.musicu_cookie_header())
                    .body(body)
                    .response_body_limit(MAX_RESPONSE_BYTES)
                    .timeout(REQUEST_TIMEOUT),
            )
            .await
            .map_err(QqMusicPersonalizedPlaylistsError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicPersonalizedPlaylistsError::HttpStatus(
                response.status(),
            ));
        }
        let envelope: DailyRecommendationResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicPersonalizedPlaylistsError::InvalidJson)?;
        map_personalized_response(envelope)
    }
}

#[derive(Serialize)]
struct DailyRecommendationRequest<'a> {
    comm: DailyRecommendationComm<'a>,
    feed: DailyRecommendationRpc,
}

impl<'a> DailyRecommendationRequest<'a> {
    fn new(credential: &'a Credential) -> Self {
        Self {
            comm: DailyRecommendationComm {
                account_id: credential.music_id(),
                format: "json",
                client_type: 20,
                client_version: 1770,
                csrf_token: 5381,
                input_charset: "utf-8",
                output_charset: "utf-8",
                platform: "wk_v17",
                user_id: "",
                guid: "",
            },
            feed: DailyRecommendationRpc {
                module: "music.recommend.RecommendFeed",
                method: "get_recommend_feed",
                param: DailyRecommendationParam {
                    direction: 0,
                    page: 1,
                    shelf_count: 0,
                    cache: [],
                    unique_items: [],
                },
            },
        }
    }
}

#[derive(Serialize)]
struct DailyRecommendationComm<'a> {
    #[serde(rename = "uin")]
    account_id: &'a str,
    format: &'static str,
    #[serde(rename = "ct")]
    client_type: u32,
    #[serde(rename = "cv")]
    client_version: u32,
    #[serde(rename = "g_tk")]
    csrf_token: u32,
    #[serde(rename = "inCharset")]
    input_charset: &'static str,
    #[serde(rename = "outCharset")]
    output_charset: &'static str,
    platform: &'static str,
    #[serde(rename = "uid")]
    user_id: &'static str,
    guid: &'static str,
}

#[derive(Serialize)]
struct DailyRecommendationRpc {
    module: &'static str,
    method: &'static str,
    param: DailyRecommendationParam,
}

#[derive(Serialize)]
struct DailyRecommendationParam {
    direction: u32,
    page: u32,
    #[serde(rename = "s_num")]
    shelf_count: u32,
    #[serde(rename = "v_cache")]
    cache: [&'static str; 0],
    #[serde(rename = "v_uniq")]
    unique_items: [&'static str; 0],
}

#[derive(Deserialize)]
struct DailyRecommendationResponse {
    code: Option<i64>,
    feed: Option<DailyRecommendationResult>,
}

#[derive(Deserialize)]
struct DailyRecommendationResult {
    code: Option<i64>,
    data: Option<DailyRecommendationData>,
}

#[derive(Deserialize)]
struct DailyRecommendationData {
    retcode: Option<i64>,
    #[serde(rename = "v_shelf")]
    shelves: Option<Vec<RawShelf>>,
}

#[derive(Deserialize)]
struct RawShelf {
    extra_info: Option<RawExtraInfo>,
    #[serde(rename = "v_niche")]
    niches: Option<Vec<RawNiche>>,
}

#[derive(Deserialize)]
struct RawNiche {
    #[serde(rename = "v_card")]
    cards: Option<Vec<RawCard>>,
}

#[derive(Deserialize)]
struct RawCard {
    id: Option<String>,
    title: Option<String>,
    cover: Option<String>,
    jumptype: Option<u32>,
    trace: Option<String>,
    extra_info: Option<RawExtraInfo>,
}

#[derive(Deserialize)]
struct RawExtraInfo {
    #[serde(rename = "moduleID")]
    module_id: Option<String>,
}

fn map_response<E>(
    envelope: DailyRecommendationResponse,
) -> Result<Option<QqMusicDailyRecommendation>, QqMusicDailyRecommendationError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicDailyRecommendationError::MissingGlobalCode)?;
    let result_code = envelope.feed.as_ref().and_then(|result| result.code);
    let data_code = envelope
        .feed
        .as_ref()
        .and_then(|result| result.data.as_ref())
        .and_then(|data| data.retcode);
    if let Some(code) = [Some(global_code), result_code, data_code]
        .into_iter()
        .flatten()
        .find(|code| is_credential_rejection_code(*code))
    {
        return Err(QqMusicDailyRecommendationError::Rejected { code });
    }
    if global_code != 0
        || result_code.is_some_and(|code| code != 0)
        || data_code.is_some_and(|code| code != 0)
    {
        return Err(QqMusicDailyRecommendationError::Upstream {
            global_code,
            result_code,
            data_code,
        });
    }
    let result = envelope
        .feed
        .ok_or(QqMusicDailyRecommendationError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicDailyRecommendationError::MissingResultCode)?;
    let data = result
        .data
        .ok_or(QqMusicDailyRecommendationError::MissingData)?;
    data.retcode
        .ok_or(QqMusicDailyRecommendationError::MissingDataCode)?;
    let shelves = data
        .shelves
        .ok_or(QqMusicDailyRecommendationError::MissingShelves)?;

    let mut candidate = None;
    for shelf in shelves {
        let niches = shelf
            .niches
            .ok_or(QqMusicDailyRecommendationError::InvalidFeed)?;
        for niche in niches {
            let cards = niche
                .cards
                .ok_or(QqMusicDailyRecommendationError::InvalidFeed)?;
            for card in cards {
                if !is_daily_playlist_card(&card) {
                    continue;
                }
                if candidate.is_some() {
                    return Err(QqMusicDailyRecommendationError::MultipleDailyPlaylists);
                }
                candidate = Some(map_daily_playlist(&card)?);
            }
        }
    }
    Ok(candidate)
}

fn map_personalized_response<E>(
    envelope: DailyRecommendationResponse,
) -> Result<Vec<QqMusicPersonalizedPlaylist>, QqMusicPersonalizedPlaylistsError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicPersonalizedPlaylistsError::MissingGlobalCode)?;
    let result_code = envelope.feed.as_ref().and_then(|result| result.code);
    let data_code = envelope
        .feed
        .as_ref()
        .and_then(|result| result.data.as_ref())
        .and_then(|data| data.retcode);
    if let Some(code) = [Some(global_code), result_code, data_code]
        .into_iter()
        .flatten()
        .find(|code| is_credential_rejection_code(*code))
    {
        return Err(QqMusicPersonalizedPlaylistsError::Rejected { code });
    }
    if global_code != 0
        || result_code.is_some_and(|code| code != 0)
        || data_code.is_some_and(|code| code != 0)
    {
        return Err(QqMusicPersonalizedPlaylistsError::Upstream {
            global_code,
            result_code,
            data_code,
        });
    }
    let result = envelope
        .feed
        .ok_or(QqMusicPersonalizedPlaylistsError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicPersonalizedPlaylistsError::MissingResultCode)?;
    let data = result
        .data
        .ok_or(QqMusicPersonalizedPlaylistsError::MissingData)?;
    data.retcode
        .ok_or(QqMusicPersonalizedPlaylistsError::MissingDataCode)?;
    let shelves = data
        .shelves
        .ok_or(QqMusicPersonalizedPlaylistsError::MissingShelves)?;

    let mut matching_shelf = None;
    for shelf in shelves {
        if shelf
            .extra_info
            .as_ref()
            .and_then(|extra| extra.module_id.as_deref())
            .is_some_and(|module| module.starts_with(PERSONALIZED_PLAYLIST_MODULE_PREFIX))
        {
            if matching_shelf.is_some() {
                return Err(QqMusicPersonalizedPlaylistsError::MultiplePlaylistShelves);
            }
            matching_shelf = Some(shelf);
        }
    }
    let Some(shelf) = matching_shelf else {
        return Ok(Vec::new());
    };
    let niches = shelf
        .niches
        .ok_or(QqMusicPersonalizedPlaylistsError::InvalidFeed)?;
    let mut playlist_ids = HashSet::new();
    let mut playlists = Vec::new();
    for niche in niches {
        let cards = niche
            .cards
            .ok_or(QqMusicPersonalizedPlaylistsError::InvalidFeed)?;
        for card in cards {
            if card.jumptype != Some(DAILY_PLAYLIST_JUMP_TYPE) {
                continue;
            }
            if playlists.len() == MAX_PERSONALIZED_PLAYLISTS {
                return Err(QqMusicPersonalizedPlaylistsError::TooManyPlaylists);
            }
            let playlist = map_personalized_playlist(&card)?;
            if !playlist_ids.insert(playlist.playlist_id()) {
                return Err(QqMusicPersonalizedPlaylistsError::DuplicatePlaylistId);
            }
            playlists.push(playlist);
        }
    }
    Ok(playlists)
}

fn is_daily_playlist_card(card: &RawCard) -> bool {
    card.jumptype == Some(DAILY_PLAYLIST_JUMP_TYPE)
        && card
            .extra_info
            .as_ref()
            .and_then(|extra| extra.module_id.as_deref())
            .is_some_and(|module| module.starts_with(DAILY_MODULE_PREFIX))
        && card
            .trace
            .as_deref()
            .is_some_and(|trace| trace.contains(DAILY_TRACE_MARKER))
}

fn map_daily_playlist<E>(
    card: &RawCard,
) -> Result<QqMusicDailyRecommendation, QqMusicDailyRecommendationError<E>> {
    let playlist_id = card
        .id
        .as_deref()
        .and_then(|value| value.trim().parse::<u64>().ok())
        .filter(|value| *value != 0)
        .ok_or(QqMusicDailyRecommendationError::InvalidDailyPlaylist {
            field: DailyRecommendationField::PlaylistId,
        })?;
    let title = bounded_nonblank(card.title.as_deref()).ok_or(
        QqMusicDailyRecommendationError::InvalidDailyPlaylist {
            field: DailyRecommendationField::Title,
        },
    )?;
    let artwork_uri = normalized_https_image_uri(card.cover.clone());
    Ok(QqMusicDailyRecommendation {
        playlist_id,
        title,
        artwork_uri,
    })
}

fn map_personalized_playlist<E>(
    card: &RawCard,
) -> Result<QqMusicPersonalizedPlaylist, QqMusicPersonalizedPlaylistsError<E>> {
    let playlist_id = card
        .id
        .as_deref()
        .and_then(|value| value.trim().parse::<u64>().ok())
        .filter(|value| *value != 0)
        .ok_or(QqMusicPersonalizedPlaylistsError::InvalidPlaylist {
            field: PersonalizedPlaylistField::PlaylistId,
        })?;
    let title = bounded_nonblank(card.title.as_deref()).ok_or(
        QqMusicPersonalizedPlaylistsError::InvalidPlaylist {
            field: PersonalizedPlaylistField::Title,
        },
    )?;
    let artwork_uri = normalized_https_image_uri(card.cover.clone());
    Ok(QqMusicPersonalizedPlaylist {
        playlist_id,
        title,
        artwork_uri,
    })
}

fn bounded_nonblank(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty() && value.len() <= MAX_TEXT_BYTES)
        .map(str::to_owned)
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use super::{
        DailyRecommendationField, PersonalizedPlaylistField, QqMusicDailyRecommendationError,
        QqMusicPersonalizedPlaylistsError,
    };
    use crate::{
        Credential, HttpMethod, HttpRequest, HttpResponse, HttpTransport, LoginType, QqMusicClient,
    };

    struct DailyTransport {
        response: HttpResponse,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl DailyTransport {
        fn new(response: &Value) -> Self {
            Self {
                response: HttpResponse::new(200, response.to_string().into_bytes()),
                requests: Mutex::new(Vec::new()),
            }
        }
    }

    impl HttpTransport for DailyTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("requests").push(request);
            Ok(self.response.clone())
        }
    }

    fn credential() -> Credential {
        Credential::new("123456", "W_X_private-key", LoginType::WECHAT).expect("credential")
    }

    #[tokio::test]
    async fn serializes_evidenced_feed_and_maps_one_strict_daily_playlist() {
        let client = QqMusicClient::new(DailyTransport::new(&feed_json(&[daily_card(
            "7251579717",
            "Daily fixture",
        )])));

        let daily = client
            .daily_recommendation(&credential())
            .await
            .expect("daily response")
            .expect("daily playlist");
        assert_eq!(daily.playlist_id(), 7_251_579_717);
        assert_eq!(daily.title(), "Daily fixture");
        assert_eq!(
            daily.artwork_uri(),
            Some("https://example.invalid/daily.jpg")
        );

        let requests = client.transport().requests.lock().expect("requests");
        assert_eq!(requests.len(), 1);
        let request = &requests[0];
        assert_eq!(request.method(), HttpMethod::Post);
        let body: Value =
            serde_json::from_slice(request.body_bytes().expect("body")).expect("request JSON");
        assert_eq!(body["feed"]["module"], "music.recommend.RecommendFeed");
        assert_eq!(body["feed"]["method"], "get_recommend_feed");
        assert_eq!(body["feed"]["param"]["direction"], 0);
        assert_eq!(body["feed"]["param"]["page"], 1);
        assert_eq!(body["feed"]["param"]["s_num"], 0);
        assert_eq!(body["feed"]["param"]["v_cache"], json!([]));
        assert_eq!(body["feed"]["param"]["v_uniq"], json!([]));
        assert_eq!(body["comm"]["uin"], "123456");
        assert_eq!(body["comm"]["ct"], 20);
        assert_eq!(body["comm"]["cv"], 1770);
        assert_eq!(body["comm"]["g_tk"], 5381);
        assert_eq!(body["comm"]["platform"], "wk_v17");
        assert_eq!(body["comm"]["inCharset"], "utf-8");
        assert_eq!(body["comm"]["outCharset"], "utf-8");
        assert_eq!(body["comm"]["uid"], "");
        assert_eq!(body["comm"]["guid"], "");
        assert!(body["comm"].get("authst").is_none());
        assert!(body["comm"].get("tmeLoginType").is_none());
        let cookie = request
            .headers()
            .iter()
            .find(|(name, _)| name == "Cookie")
            .map(|(_, value)| value)
            .expect("credential cookie");
        assert!(cookie.contains("qm_keyst=W_X_private-key"));
        let debug = format!("{daily:?} {request:?}");
        assert!(!debug.contains("W_X_private-key"));
        assert!(!debug.contains("Daily fixture"));
        assert!(!debug.contains("7251579717"));
    }

    #[tokio::test]
    async fn distinguishes_absence_from_ambiguous_or_invalid_daily_cards() {
        let absent = QqMusicClient::new(DailyTransport::new(&feed_json(&[json!({
            "id": "9001",
            "title": "Public playlist",
            "jumptype": 10014,
            "trace": "public",
            "extra_info": {"moduleID": "playlist"}
        })])))
        .daily_recommendation(&credential())
        .await
        .expect("valid feed without Daily 30");
        assert!(absent.is_none());

        let mut cleartext_qq_artwork = daily_card("9002", "Daily QQ artwork");
        cleartext_qq_artwork["cover"] = json!("http://qpic.y.qq.com/music_cover/fixture/300?n=1");
        let normalized =
            QqMusicClient::new(DailyTransport::new(&feed_json(&[cleartext_qq_artwork])))
                .daily_recommendation(&credential())
                .await
                .expect("daily response")
                .expect("daily playlist");
        assert_eq!(
            normalized.artwork_uri(),
            Some("https://qpic.y.qq.com/music_cover/fixture/300?n=1")
        );

        let mut unusable_artwork = daily_card("9002", "Daily unusable artwork");
        unusable_artwork["cover"] = json!("http://example.invalid/daily.jpg");
        let without_artwork =
            QqMusicClient::new(DailyTransport::new(&feed_json(&[unusable_artwork])))
                .daily_recommendation(&credential())
                .await
                .expect("optional artwork does not invalidate Daily")
                .expect("daily playlist");
        assert_eq!(without_artwork.artwork_uri(), None);

        let duplicate = QqMusicClient::new(DailyTransport::new(&feed_json(&[
            daily_card("9002", "First private title"),
            daily_card("9003", "Second private title"),
        ])))
        .daily_recommendation(&credential())
        .await;
        assert!(matches!(
            duplicate,
            Err(QqMusicDailyRecommendationError::MultipleDailyPlaylists)
        ));
        let debug = format!("{duplicate:?}");
        assert!(!debug.contains("First private title"));
        assert!(!debug.contains("Second private title"));

        let invalid = QqMusicClient::new(DailyTransport::new(&feed_json(&[daily_card(
            "not-a-number",
            "Private daily title",
        )])))
        .daily_recommendation(&credential())
        .await;
        assert!(matches!(
            invalid,
            Err(QqMusicDailyRecommendationError::InvalidDailyPlaylist {
                field: DailyRecommendationField::PlaylistId
            })
        ));
        assert!(!format!("{invalid:?}").contains("Private daily title"));
    }

    #[tokio::test]
    async fn keeps_rejection_and_feed_shape_failures_distinct() {
        let rejected = QqMusicClient::new(DailyTransport::new(&json!({
            "code": 0,
            "feed": {"code": 104_401}
        })))
        .daily_recommendation(&credential())
        .await;
        assert!(matches!(
            rejected,
            Err(QqMusicDailyRecommendationError::Rejected { code: 104_401 })
        ));

        let invalid_feed = QqMusicClient::new(DailyTransport::new(&json!({
            "code": 0,
            "feed": {"code": 0, "data": {"retcode": 0, "v_shelf": [{}]}}
        })))
        .daily_recommendation(&credential())
        .await;
        assert!(matches!(
            invalid_feed,
            Err(QqMusicDailyRecommendationError::InvalidFeed)
        ));
    }

    #[tokio::test]
    async fn maps_only_the_evidenced_personalized_playlist_shelf() {
        let client = QqMusicClient::new(DailyTransport::new(&personalized_feed_json(&[
            personalized_card("9001", "First private playlist"),
            personalized_card("9002", "Second private playlist"),
            json!({"id": "ignored", "title": "Non-playlist", "jumptype": 10002}),
        ])));

        let playlists = client
            .personalized_playlists(&credential())
            .await
            .expect("personalized playlists");
        assert_eq!(playlists.len(), 2);
        assert_eq!(playlists[0].playlist_id(), 9001);
        assert_eq!(playlists[0].title(), "First private playlist");
        assert_eq!(
            playlists[0].artwork_uri(),
            Some("https://example.invalid/personalized.jpg")
        );

        let requests = client.transport().requests.lock().expect("requests");
        let body: Value =
            serde_json::from_slice(requests[0].body_bytes().expect("body")).expect("request JSON");
        assert_eq!(body["feed"]["module"], "music.recommend.RecommendFeed");
        assert_eq!(body["feed"]["method"], "get_recommend_feed");
        assert_eq!(body["feed"]["param"]["v_uniq"], json!([]));
        assert_eq!(body["comm"]["ct"], 20);
        assert_eq!(body["comm"]["cv"], 1770);
        assert_eq!(body["comm"]["platform"], "wk_v17");
        let debug = format!("{playlists:?} {:?}", requests[0]);
        assert!(!debug.contains("W_X_private-key"));
        assert!(!debug.contains("First private playlist"));
        assert!(!debug.contains("9001"));
    }

    #[tokio::test]
    async fn distinguishes_absence_ambiguity_and_invalid_personalized_cards() {
        let absent = QqMusicClient::new(DailyTransport::new(&feed_json(&[])))
            .personalized_playlists(&credential())
            .await
            .expect("feed without personalized shelf");
        assert!(absent.is_empty());

        let multiple = QqMusicClient::new(DailyTransport::new(&json!({
            "code": 0,
            "feed": {"code": 0, "data": {"retcode": 0, "v_shelf": [
                {"extra_info": {"moduleID": "playlist@1"}, "v_niche": []},
                {"extra_info": {"moduleID": "playlist@2"}, "v_niche": []}
            ]}}
        })))
        .personalized_playlists(&credential())
        .await;
        assert!(matches!(
            multiple,
            Err(QqMusicPersonalizedPlaylistsError::MultiplePlaylistShelves)
        ));

        let duplicate = QqMusicClient::new(DailyTransport::new(&personalized_feed_json(&[
            personalized_card("9001", "Private one"),
            personalized_card("9001", "Private duplicate"),
        ])))
        .personalized_playlists(&credential())
        .await;
        assert!(matches!(
            duplicate,
            Err(QqMusicPersonalizedPlaylistsError::DuplicatePlaylistId)
        ));
        assert!(!format!("{duplicate:?}").contains("Private duplicate"));

        let mut cleartext_qq_artwork = personalized_card("9002", "Private QQ artwork");
        cleartext_qq_artwork["cover"] = json!("http://qpic.y.qq.com/music_cover/fixture/300?n=1");
        let mut insecure_artwork = personalized_card("9003", "Private insecure artwork");
        insecure_artwork["cover"] = json!("http://example.invalid/personalized.jpg");
        let with_insecure_artwork =
            QqMusicClient::new(DailyTransport::new(&personalized_feed_json(&[
                personalized_card("9001", "Private secure artwork"),
                cleartext_qq_artwork,
                insecure_artwork,
            ])))
            .personalized_playlists(&credential())
            .await
            .expect("playlist data survives unusable optional artwork");
        assert_eq!(with_insecure_artwork.len(), 3);
        assert_eq!(
            with_insecure_artwork[0].artwork_uri(),
            Some("https://example.invalid/personalized.jpg")
        );
        assert_eq!(
            with_insecure_artwork[1].artwork_uri(),
            Some("https://qpic.y.qq.com/music_cover/fixture/300?n=1")
        );
        assert_eq!(with_insecure_artwork[2].artwork_uri(), None);

        let invalid = QqMusicClient::new(DailyTransport::new(&personalized_feed_json(&[
            personalized_card("not-a-number", "Private invalid"),
        ])))
        .personalized_playlists(&credential())
        .await;
        assert!(matches!(
            invalid,
            Err(QqMusicPersonalizedPlaylistsError::InvalidPlaylist {
                field: PersonalizedPlaylistField::PlaylistId
            })
        ));
    }

    #[tokio::test]
    async fn bounds_personalized_playlist_output() {
        let cards = (1..=65)
            .map(|id| personalized_card(&id.to_string(), "Private playlist"))
            .collect::<Vec<_>>();
        let result = QqMusicClient::new(DailyTransport::new(&personalized_feed_json(&cards)))
            .personalized_playlists(&credential())
            .await;
        assert!(matches!(
            result,
            Err(QqMusicPersonalizedPlaylistsError::TooManyPlaylists)
        ));
    }

    fn feed_json(cards: &[Value]) -> Value {
        json!({
            "code": 0,
            "feed": {
                "code": 0,
                "data": {
                    "retcode": 0,
                    "v_shelf": [{"v_niche": [{"v_card": cards}]}]
                }
            }
        })
    }

    fn daily_card(id: &str, title: &str) -> Value {
        json!({
            "id": id,
            "title": title,
            "cover": "https://example.invalid/daily.jpg",
            "jumptype": 10014,
            "trace": "fixture#daily30:8#private",
            "extra_info": {"moduleID": "recforyou@0@0"}
        })
    }

    fn personalized_feed_json(cards: &[Value]) -> Value {
        json!({
            "code": 0,
            "feed": {
                "code": 0,
                "data": {
                    "retcode": 0,
                    "v_shelf": [{
                        "extra_info": {"moduleID": "playlist@135@0"},
                        "v_niche": [{"v_card": cards}]
                    }]
                }
            }
        })
    }

    fn personalized_card(id: &str, title: &str) -> Value {
        json!({
            "id": id,
            "title": title,
            "cover": "https://example.invalid/personalized.jpg",
            "jumptype": 10014
        })
    }
}
