use crate::{
    Album, Artist, Error, KuGouClient, MAX_RESPONSE_BYTES, Request, SearchTrack, Transport,
    search::{
        MAX_ARTISTS, MAX_PAGE, MAX_SAFE_INTEGER, MAX_TEXT_BYTES, MAX_TOTAL, artwork,
        numeric_identity, text,
    },
};
use serde_json::{Map, Value};
use std::collections::HashSet;

const DETAIL_ENDPOINT: &str = "https://m.kugou.com/app/i/getSongInfo.php";
const RANKINGS_ENDPOINT: &str = "https://m.kugou.com/rank/list";
const RANKING_TRACKS_ENDPOINT: &str = "https://m.kugou.com/rank/info/";
const RANKING_PAGE_SIZE: u32 = 30;
const MAX_RANKINGS: usize = 1_000;

#[derive(Clone, Eq, PartialEq)]
pub struct TrackDetails {
    pub mix_song_id: String,
    pub standard_hash: String,
    pub audio_id: u64,
    pub album_id: Option<String>,
    pub title: String,
    pub artists: Vec<Artist>,
    pub album: Option<Album>,
    pub artwork: Option<String>,
    pub duration_seconds: u32,
}

impl std::fmt::Debug for TrackDetails {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("KuGouTrackDetails")
            .field("artist_count", &self.artists.len())
            .field("has_album", &self.album.is_some())
            .field("has_artwork", &self.artwork.is_some())
            .field("duration_seconds", &self.duration_seconds)
            .finish_non_exhaustive()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct Ranking {
    pub id: String,
    pub title: String,
    pub period: Option<String>,
    pub artwork: Option<String>,
}

impl std::fmt::Debug for Ranking {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("KuGouRanking")
            .field("id", &"[REDACTED]")
            .field("title", &"[REDACTED]")
            .field("has_period", &self.period.is_some())
            .field("has_artwork", &self.artwork.is_some())
            .finish()
    }
}

pub struct RankingCollection {
    pub items: Vec<Ranking>,
    pub omitted_item_count: u32,
}

impl std::fmt::Debug for RankingCollection {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("KuGouRankingCollection")
            .field("item_count", &self.items.len())
            .field("omitted_item_count", &self.omitted_item_count)
            .finish()
    }
}

pub struct RankingPage {
    pub ranking: Ranking,
    pub items: Vec<SearchTrack>,
    pub page: u32,
    pub total: u32,
    pub more: bool,
    pub omitted_item_count: u32,
}

impl std::fmt::Debug for RankingPage {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("KuGouRankingPage")
            .field("ranking", &self.ranking)
            .field("item_count", &self.items.len())
            .field("page", &self.page)
            .field("total", &self.total)
            .field("more", &self.more)
            .field("omitted_item_count", &self.omitted_item_count)
            .finish()
    }
}

impl<T: Transport> KuGouClient<T> {
    /// Loads the exact legacy public detail row for a standard `FileHash`. Live
    /// evidence shows successful rows with both `status=0` and `status=1`, so
    /// `errcode=0` plus strict identity fields is the success contract.
    ///
    /// # Errors
    /// Returns a bounded typed failure for invalid identity, transport,
    /// business response or a contradictory detail document.
    pub async fn track_details(&self, standard_hash: &str) -> Result<TrackDetails, Error> {
        validate_hash(standard_hash)?;
        let mut endpoint = url::Url::parse(DETAIL_ENDPOINT).map_err(|_| Error::InputBound)?;
        endpoint
            .query_pairs_mut()
            .append_pair("cmd", "playInfo")
            .append_pair("hash", standard_hash);
        let value = request_json(&self.transport, endpoint, true).await?;
        decode_detail(object(&value)?)
    }

    /// Loads the bounded unsigned ranking inventory exposed by the public
    /// mobile site. Editorial grouping is intentionally left to the Provider.
    ///
    /// # Errors
    /// Returns a bounded typed failure for transport, business response,
    /// duplicate identity or a malformed inventory.
    pub async fn rankings(&self) -> Result<RankingCollection, Error> {
        let mut endpoint = url::Url::parse(RANKINGS_ENDPOINT).map_err(|_| Error::InputBound)?;
        endpoint.query_pairs_mut().append_pair("json", "true");
        let value = request_json(&self.transport, endpoint, true).await?;
        decode_rankings(object(&value)?)
    }

    /// Loads one native 30-row page. The public contract was observed with a
    /// real page number and fixed page size; callers must not invent a cursor.
    ///
    /// # Errors
    /// Returns a bounded typed failure for invalid input, transport,
    /// contradictory pagination or malformed Track rows.
    pub async fn ranking_tracks(&self, ranking_id: &str, page: u32) -> Result<RankingPage, Error> {
        numeric_identity(ranking_id)?;
        if page == 0 || page > MAX_PAGE {
            return Err(Error::InputBound);
        }
        let mut endpoint =
            url::Url::parse(RANKING_TRACKS_ENDPOINT).map_err(|_| Error::InputBound)?;
        endpoint
            .query_pairs_mut()
            .append_pair("rankid", ranking_id)
            .append_pair("page", &page.to_string())
            .append_pair("json", "true");
        let value = request_json(&self.transport, endpoint, true).await?;
        decode_ranking_page(object(&value)?, ranking_id, page)
    }
}

async fn request_json<T: Transport>(
    transport: &T,
    endpoint: url::Url,
    allow_html_json: bool,
) -> Result<Value, Error> {
    if endpoint.as_str().len() > MAX_TEXT_BYTES {
        return Err(Error::InputBound);
    }
    let response = transport
        .send(Request {
            url: endpoint.into(),
            profile: crate::profile::KuGouProtocolProfile::Public,
        })
        .await?;
    match response.status {
        200 => {}
        429 => return Err(Error::RateLimited),
        _ => return Err(Error::ProtocolUnavailable),
    }
    if response.body.len() > MAX_RESPONSE_BYTES {
        return Err(Error::ResponseBound);
    }
    let content_type = response
        .content_type
        .as_deref()
        .and_then(|value| value.split(';').next())
        .map(str::trim);
    let accepted = matches!(content_type, Some("application/json" | "text/plain"))
        || allow_html_json && content_type == Some("text/html");
    if !accepted {
        return Err(Error::ResponseShapeMismatch);
    }
    serde_json::from_slice(&response.body).map_err(|_| Error::ResponseShapeMismatch)
}

fn decode_detail(raw: &Map<String, Value>) -> Result<TrackDetails, Error> {
    if integer(raw.get("errcode"))? != 0 || !matches!(integer(raw.get("status"))?, 0 | 1) {
        return Err(Error::UpstreamUnknown);
    }
    let standard_hash = hash(raw.get("hash"))?;
    let mix_song_id = identity(raw.get("album_audio_id"))?;
    let audio_id = safe_integer(raw.get("audio_id"))?;
    let title = required_text(raw.get("songName"))?;
    let album_id = optional_identity(raw.get("albumid"))?;
    let duration_ms = unsigned(raw.get("timeLength"))?;
    if duration_ms > 86_400_000 {
        return Err(Error::ResponseShapeMismatch);
    }
    let duration_seconds =
        u32::try_from(duration_ms / 1_000).map_err(|_| Error::ResponseShapeMismatch)?;
    let artists = artists(
        raw.get("authors"),
        raw.get("singerId"),
        raw.get("singerName"),
    )?;
    let album_title = optional_text(raw.get("album_name").or_else(|| raw.get("albumName")))?;
    let album = match (album_id.as_ref(), album_title) {
        (Some(id), Some(title)) => Some(Album {
            id: id.clone(),
            title,
        }),
        _ => None,
    };
    Ok(TrackDetails {
        mix_song_id,
        standard_hash,
        audio_id,
        album_id,
        title,
        artists,
        album,
        artwork: artwork(optional_string(raw.get("album_img"))?)
            .ok()
            .flatten(),
        duration_seconds,
    })
}

fn decode_rankings(raw: &Map<String, Value>) -> Result<RankingCollection, Error> {
    let rank = object(raw.get("rank").ok_or(Error::ResponseShapeMismatch)?)?;
    let rows = array(rank.get("list").ok_or(Error::ResponseShapeMismatch)?)?;
    if rows.len() > MAX_RANKINGS {
        return Err(Error::ResponseBound);
    }
    let total = unsigned(rank.get("total"))?;
    if total > MAX_RANKINGS as u64 || total < rows.len() as u64 {
        return Err(Error::ResponseShapeMismatch);
    }
    let mut identities = HashSet::with_capacity(rows.len());
    let mut items = Vec::with_capacity(rows.len());
    let mut omitted_item_count = 0_u32;
    for row in rows {
        let decoded = object(row).and_then(decode_ranking);
        match decoded {
            Ok(item) => {
                if !identities.insert(item.id.clone()) {
                    return Err(Error::ResponseShapeMismatch);
                }
                items.push(item);
            }
            Err(Error::ResponseShapeMismatch | Error::ResponseBound) => {
                omitted_item_count = omitted_item_count
                    .checked_add(1)
                    .ok_or(Error::ResponseBound)?;
            }
            Err(error) => return Err(error),
        }
    }
    Ok(RankingCollection {
        items,
        omitted_item_count,
    })
}

fn decode_ranking(raw: &Map<String, Value>) -> Result<Ranking, Error> {
    Ok(Ranking {
        id: identity(raw.get("rankid"))?,
        title: required_text(raw.get("rankname"))?,
        period: optional_text(raw.get("issue"))?,
        artwork: artwork(optional_string(
            raw.get("imgurl")
                .or_else(|| raw.get("img_9"))
                .or_else(|| raw.get("bannerurl")),
        )?)
        .ok()
        .flatten(),
    })
}

fn decode_ranking_page(
    raw: &Map<String, Value>,
    requested_id: &str,
    requested_page: u32,
) -> Result<RankingPage, Error> {
    let ranking = decode_ranking(object(
        raw.get("info").ok_or(Error::ResponseShapeMismatch)?,
    )?)?;
    if ranking.id != requested_id {
        return Err(Error::ResponseShapeMismatch);
    }
    let songs = object(raw.get("songs").ok_or(Error::ResponseShapeMismatch)?)?;
    let page =
        u32::try_from(unsigned(songs.get("page"))?).map_err(|_| Error::ResponseShapeMismatch)?;
    let page_size = u32::try_from(unsigned(songs.get("pagesize"))?)
        .map_err(|_| Error::ResponseShapeMismatch)?;
    let total =
        u32::try_from(unsigned(songs.get("total"))?).map_err(|_| Error::ResponseShapeMismatch)?;
    let rows = array(songs.get("list").ok_or(Error::ResponseShapeMismatch)?)?;
    if page != requested_page
        || page_size != RANKING_PAGE_SIZE
        || rows.len() > RANKING_PAGE_SIZE as usize
        || total > MAX_TOTAL
    {
        return Err(Error::ResponseShapeMismatch);
    }
    let offset = page
        .checked_sub(1)
        .and_then(|value| value.checked_mul(RANKING_PAGE_SIZE))
        .ok_or(Error::ResponseShapeMismatch)?;
    let raw_count = u32::try_from(rows.len()).map_err(|_| Error::ResponseShapeMismatch)?;
    if (total == 0 && !rows.is_empty())
        || (!rows.is_empty() && offset >= total)
        || offset
            .checked_add(raw_count)
            .is_none_or(|next| next > total)
    {
        return Err(Error::ResponseShapeMismatch);
    }
    let more = offset
        .checked_add(RANKING_PAGE_SIZE)
        .is_some_and(|next| next < total);
    if (rows.is_empty() || raw_count != RANKING_PAGE_SIZE) && more {
        return Err(Error::ResponseShapeMismatch);
    }
    let mut identities = HashSet::with_capacity(rows.len());
    let mut items = Vec::with_capacity(rows.len());
    let mut omitted_item_count = 0_u32;
    for row in rows {
        let decoded = object(row).and_then(decode_ranking_track);
        match decoded {
            Ok(item) => {
                if !identities.insert(item.mix_song_id.clone()) {
                    return Err(Error::ResponseShapeMismatch);
                }
                items.push(item);
            }
            Err(Error::ResponseShapeMismatch | Error::ResponseBound) => {
                omitted_item_count = omitted_item_count
                    .checked_add(1)
                    .ok_or(Error::ResponseBound)?;
            }
            Err(error) => return Err(error),
        }
    }
    Ok(RankingPage {
        ranking,
        items,
        page,
        total,
        more,
        omitted_item_count,
    })
}

fn decode_ranking_track(raw: &Map<String, Value>) -> Result<SearchTrack, Error> {
    let mix_song_id = identity(raw.get("album_audio_id"))?;
    let standard_hash = hash(raw.get("hash"))?;
    let audio_id = safe_integer(raw.get("audio_id"))?;
    let title = required_text(raw.get("songname"))?;
    let album_id = optional_identity(raw.get("album_id"))?;
    let artists = artists(raw.get("authors"), None, None)?;
    let album_title = optional_text(raw.get("album_name"))?;
    let album = match (album_id.as_ref(), album_title) {
        (Some(id), Some(title)) => Some(Album {
            id: id.clone(),
            title,
        }),
        _ => None,
    };
    let raw_duration = unsigned(raw.get("duration"))?;
    let duration_seconds = if raw_duration <= 86_400 {
        raw_duration
    } else if raw_duration <= 86_400_000 {
        raw_duration / 1_000
    } else {
        return Err(Error::ResponseShapeMismatch);
    };
    Ok(SearchTrack {
        mix_song_id,
        standard_hash,
        audio_id,
        album_id,
        title,
        artists,
        album,
        artwork: artwork(optional_string(raw.get("album_sizable_cover"))?)
            .ok()
            .flatten(),
        duration_seconds: u32::try_from(duration_seconds)
            .map_err(|_| Error::ResponseShapeMismatch)?,
    })
}

fn artists(
    value: Option<&Value>,
    fallback_id: Option<&Value>,
    fallback_name: Option<&Value>,
) -> Result<Vec<Artist>, Error> {
    let mut result = Vec::new();
    if let Some(value) = value {
        for row in array(value)? {
            if result.len() >= MAX_ARTISTS {
                return Err(Error::ResponseBound);
            }
            let row = object(row)?;
            let id = unsigned(row.get("author_id").or_else(|| row.get("id")))?;
            if id > MAX_SAFE_INTEGER {
                return Err(Error::ResponseShapeMismatch);
            }
            let name = required_text(row.get("author_name").or_else(|| row.get("name")))?;
            result.push(Artist { id, name });
        }
    }
    if result.is_empty()
        && let Some(name) = optional_text(fallback_name)?
    {
        let id = match fallback_id {
            Some(value) => {
                let id = unsigned(Some(value))?;
                if id > MAX_SAFE_INTEGER {
                    return Err(Error::ResponseShapeMismatch);
                }
                id
            }
            None => 0,
        };
        result.push(Artist { id, name });
    }
    Ok(result)
}

fn validate_hash(value: &str) -> Result<(), Error> {
    if value.len() == 32 && value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        Ok(())
    } else {
        Err(Error::InputBound)
    }
}

fn object(value: &Value) -> Result<&Map<String, Value>, Error> {
    value.as_object().ok_or(Error::ResponseShapeMismatch)
}

fn array(value: &Value) -> Result<&Vec<Value>, Error> {
    value.as_array().ok_or(Error::ResponseShapeMismatch)
}

fn integer(value: Option<&Value>) -> Result<i64, Error> {
    let value = value.ok_or(Error::ResponseShapeMismatch)?;
    value
        .as_i64()
        .or_else(|| value.as_str()?.parse().ok())
        .ok_or(Error::ResponseShapeMismatch)
}

fn unsigned(value: Option<&Value>) -> Result<u64, Error> {
    let value = value.ok_or(Error::ResponseShapeMismatch)?;
    value
        .as_u64()
        .or_else(|| value.as_str()?.parse().ok())
        .ok_or(Error::ResponseShapeMismatch)
}

fn safe_integer(value: Option<&Value>) -> Result<u64, Error> {
    let value = unsigned(value)?;
    if value == 0 || value > MAX_SAFE_INTEGER {
        Err(Error::ResponseShapeMismatch)
    } else {
        Ok(value)
    }
}

fn identity(value: Option<&Value>) -> Result<String, Error> {
    let value = match value.ok_or(Error::ResponseShapeMismatch)? {
        Value::String(value) => value.clone(),
        Value::Number(value) => value.to_string(),
        _ => return Err(Error::ResponseShapeMismatch),
    };
    numeric_identity(&value)?;
    Ok(value)
}

fn optional_identity(value: Option<&Value>) -> Result<Option<String>, Error> {
    match value {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(value)) if value.is_empty() || value == "0" => Ok(None),
        Some(Value::Number(value)) if value.as_u64() == Some(0) => Ok(None),
        Some(value) => identity(Some(value)).map(Some),
    }
}

fn hash(value: Option<&Value>) -> Result<String, Error> {
    let value = required_text(value)?;
    validate_hash(&value).map_err(|_| Error::ResponseShapeMismatch)?;
    Ok(value.to_ascii_uppercase())
}

fn required_text(value: Option<&Value>) -> Result<String, Error> {
    let value = value
        .and_then(Value::as_str)
        .ok_or(Error::ResponseShapeMismatch)?
        .to_owned();
    text(&value)?;
    Ok(value)
}

fn optional_text(value: Option<&Value>) -> Result<Option<String>, Error> {
    match optional_string(value)? {
        Some(value) if !value.trim().is_empty() => {
            text(&value)?;
            Ok(Some(value))
        }
        _ => Ok(None),
    }
}

fn optional_string(value: Option<&Value>) -> Result<Option<String>, Error> {
    match value {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(value)) => {
            if value.len() > MAX_TEXT_BYTES || value.chars().any(char::is_control) {
                Err(Error::ResponseBound)
            } else {
                Ok(Some(value.clone()))
            }
        }
        _ => Err(Error::ResponseShapeMismatch),
    }
}
