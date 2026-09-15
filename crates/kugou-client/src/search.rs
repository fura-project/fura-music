use crate::{Error, KuGouClient, MAX_RESPONSE_BYTES, Request, Transport};
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashSet;

const SEARCH_ENDPOINT: &str = "https://songsearch.kugou.com/song_search_v2";
const MAX_QUERY_BYTES: usize = 256;
const MAX_PAGE: u32 = 100_000;
const MAX_PAGE_SIZE: u32 = 30;
const MAX_TOTAL: u32 = 100_000_000;
const MAX_TEXT_BYTES: usize = 4096;
const MAX_ARTISTS: usize = 32;
const MAX_SAFE_INTEGER: u64 = 9_007_199_254_740_991;

#[derive(Clone, Eq, PartialEq)]
pub struct Artist {
    pub id: u64,
    pub name: String,
}

#[derive(Clone, Eq, PartialEq)]
pub struct Album {
    pub id: String,
    pub title: String,
}

#[derive(Clone, Eq, PartialEq)]
pub struct SearchTrack {
    pub mix_song_id: String,
    pub standard_hash: String,
    pub audio_id: u64,
    pub title: String,
    pub artists: Vec<Artist>,
    pub album: Option<Album>,
    pub artwork: Option<String>,
    pub duration_seconds: u32,
}

impl std::fmt::Debug for SearchTrack {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("KuGouSearchTrack")
            .field("artist_count", &self.artists.len())
            .field("has_album", &self.album.is_some())
            .field("has_artwork", &self.artwork.is_some())
            .field("duration_seconds", &self.duration_seconds)
            .finish_non_exhaustive()
    }
}

pub struct SearchPage {
    pub items: Vec<SearchTrack>,
    pub page: u32,
    pub total: u32,
    pub more: bool,
    pub omitted_item_count: u32,
}

impl std::fmt::Debug for SearchPage {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("KuGouSearchPage")
            .field("item_count", &self.items.len())
            .field("page", &self.page)
            .field("total", &self.total)
            .field("more", &self.more)
            .field("omitted_item_count", &self.omitted_item_count)
            .finish_non_exhaustive()
    }
}

#[derive(Deserialize)]
struct Envelope {
    status: i64,
    error_code: i64,
    data: SearchData,
}

#[derive(Deserialize)]
struct SearchData {
    page: u32,
    pagesize: u32,
    size: u32,
    total: u32,
    lists: Vec<Value>,
}

#[derive(Deserialize)]
struct RawTrack {
    #[serde(rename = "MixSongID")]
    mix_song_id: String,
    #[serde(rename = "FileHash")]
    standard_hash: String,
    #[serde(rename = "Audioid")]
    audio_id: u64,
    #[serde(default, rename = "OriSongName")]
    original_title: Option<String>,
    #[serde(default, rename = "SongName")]
    song_title: Option<String>,
    #[serde(default, rename = "Suffix")]
    suffix: Option<String>,
    #[serde(default, rename = "Singers")]
    artists: Vec<RawArtist>,
    #[serde(default, rename = "SingerName")]
    artist_display: Option<String>,
    #[serde(default, rename = "AlbumID")]
    album_id: Option<String>,
    #[serde(default, rename = "AlbumName")]
    album_title: Option<String>,
    #[serde(default, rename = "Image")]
    artwork: Option<String>,
    #[serde(rename = "Duration")]
    duration_seconds: u32,
}

#[derive(Deserialize)]
struct RawArtist {
    id: u64,
    name: String,
}

impl<T: Transport> KuGouClient<T> {
    /// Loads one direct anonymous page from the current unsigned public Search
    /// surface. No signature, Cookie, dfid or persistent device identity is
    /// sent.
    ///
    /// # Errors
    /// Returns a bounded typed failure for invalid input, transport, business
    /// response or malformed content.
    pub async fn search_tracks(
        &self,
        query: &str,
        page: u32,
        size: u32,
    ) -> Result<SearchPage, Error> {
        validate_input(query, page, size)?;
        let mut endpoint = url::Url::parse(SEARCH_ENDPOINT).map_err(|_| Error::InputBound)?;
        endpoint
            .query_pairs_mut()
            .append_pair("platform", "AndroidFilter")
            .append_pair("iscorrection", "1")
            .append_pair("keyword", query)
            .append_pair("page", &page.to_string())
            .append_pair("pagesize", &size.to_string());
        if endpoint.as_str().len() > MAX_TEXT_BYTES {
            return Err(Error::InputBound);
        }
        let response = self
            .transport
            .send(Request {
                url: endpoint.into(),
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
        if !matches!(content_type, Some("application/json" | "text/plain")) {
            return Err(Error::ResponseShapeMismatch);
        }
        let envelope: Envelope =
            serde_json::from_slice(&response.body).map_err(|_| Error::ResponseShapeMismatch)?;
        if envelope.status != 1 || envelope.error_code != 0 {
            return Err(Error::UpstreamUnknown);
        }
        decode_page(envelope.data, page, size)
    }
}

fn validate_input(query: &str, page: u32, size: u32) -> Result<(), Error> {
    if query.trim().is_empty()
        || query.len() > MAX_QUERY_BYTES
        || query.chars().any(char::is_control)
        || page == 0
        || page > MAX_PAGE
        || size == 0
        || size > MAX_PAGE_SIZE
    {
        Err(Error::InputBound)
    } else {
        Ok(())
    }
}

fn decode_page(
    data: SearchData,
    requested_page: u32,
    requested_size: u32,
) -> Result<SearchPage, Error> {
    if data.page != requested_page
        || data.pagesize != requested_size
        || data.size as usize != data.lists.len()
        || data.size > requested_size
        || data.total > MAX_TOTAL
    {
        return Err(Error::ResponseShapeMismatch);
    }
    let start = requested_page
        .checked_sub(1)
        .and_then(|value| value.checked_mul(requested_size))
        .ok_or(Error::ResponseShapeMismatch)?;
    if (data.total == 0 && !data.lists.is_empty())
        || (!data.lists.is_empty() && start >= data.total)
        || start
            .checked_add(data.size)
            .is_none_or(|end| end > data.total)
    {
        return Err(Error::ResponseShapeMismatch);
    }
    let more = start
        .checked_add(requested_size)
        .is_some_and(|end| end < data.total);
    if data.lists.is_empty() && more {
        return Err(Error::ResponseShapeMismatch);
    }

    let mut identities = HashSet::with_capacity(data.lists.len());
    let mut items = Vec::with_capacity(data.lists.len());
    let mut omitted_item_count = 0_u32;
    for value in data.lists {
        let item = serde_json::from_value::<RawTrack>(value)
            .map_err(|_| Error::ResponseShapeMismatch)
            .and_then(decode_track);
        match item {
            Ok(item) => {
                if !identities.insert(item.mix_song_id.clone()) {
                    return Err(Error::ResponseShapeMismatch);
                }
                items.push(item);
            }
            Err(Error::ResponseShapeMismatch | Error::ResponseBound) => {
                omitted_item_count = omitted_item_count.saturating_add(1);
            }
            Err(error) => return Err(error),
        }
    }
    Ok(SearchPage {
        items,
        page: requested_page,
        total: data.total,
        more,
        omitted_item_count,
    })
}

fn decode_track(raw: RawTrack) -> Result<SearchTrack, Error> {
    numeric_identity(&raw.mix_song_id)?;
    if raw.standard_hash.len() != 32
        || !raw
            .standard_hash
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit())
        || raw.audio_id == 0
        || raw.audio_id > MAX_SAFE_INTEGER
        || raw.duration_seconds > 86_400
        || raw.artists.len() > MAX_ARTISTS
    {
        return Err(Error::ResponseShapeMismatch);
    }

    let mut title = raw
        .original_title
        .filter(|value| !value.trim().is_empty())
        .or_else(|| raw.song_title.filter(|value| !value.trim().is_empty()))
        .ok_or(Error::ResponseShapeMismatch)?;
    text(&title)?;
    if let Some(suffix) = raw.suffix.filter(|value| !value.trim().is_empty()) {
        text(&suffix)?;
        title.push(' ');
        title.push_str(suffix.trim());
        text(&title)?;
    }

    let mut artists = Vec::with_capacity(raw.artists.len().max(1));
    for artist in raw.artists {
        text(&artist.name)?;
        if artist.id > MAX_SAFE_INTEGER {
            return Err(Error::ResponseShapeMismatch);
        }
        artists.push(Artist {
            id: artist.id,
            name: artist.name,
        });
    }
    if artists.is_empty()
        && let Some(display) = raw.artist_display.filter(|value| !value.trim().is_empty())
    {
        text(&display)?;
        artists.push(Artist {
            id: 0,
            name: display,
        });
    }

    let album_id = raw.album_id.unwrap_or_default();
    let album_title = raw.album_title.unwrap_or_default();
    let album = if album_id.is_empty() && album_title.trim().is_empty()
        || album_id == "0" && album_title.trim().is_empty()
    {
        None
    } else {
        numeric_identity(&album_id)
            .and_then(|()| text(&album_title))
            .ok()
            .map(|()| Album {
                id: album_id,
                title: album_title,
            })
    };

    Ok(SearchTrack {
        mix_song_id: raw.mix_song_id,
        standard_hash: raw.standard_hash.to_ascii_uppercase(),
        audio_id: raw.audio_id,
        title,
        artists,
        album,
        artwork: artwork(raw.artwork).ok().flatten(),
        duration_seconds: raw.duration_seconds,
    })
}

fn numeric_identity(value: &str) -> Result<(), Error> {
    if value.is_empty()
        || value.starts_with('0')
        || value.len() > 20
        || !value.bytes().all(|byte| byte.is_ascii_digit())
        || value.parse::<u64>().ok().as_ref().is_none_or(|id| *id == 0)
    {
        Err(Error::ResponseShapeMismatch)
    } else {
        Ok(())
    }
}

fn text(value: &str) -> Result<(), Error> {
    if value.trim().is_empty()
        || value.len() > MAX_TEXT_BYTES
        || value.chars().any(char::is_control)
    {
        Err(Error::ResponseShapeMismatch)
    } else {
        Ok(())
    }
}

/// Normalizes only the exact current Search artwork host whose same-path HTTP
/// and HTTPS bodies were independently observed as byte-identical.
pub fn artwork(value: Option<String>) -> Result<Option<String>, Error> {
    value
        .filter(|value| !value.trim().is_empty())
        .map(|value| {
            let value = value.replace("{size}", "400");
            if value.len() > MAX_TEXT_BYTES {
                return Err(Error::ResponseShapeMismatch);
            }
            let mut uri = url::Url::parse(&value).map_err(|_| Error::ResponseShapeMismatch)?;
            if uri.scheme() == "http" && uri.host_str() == Some("imge.kugou.com") {
                uri.set_scheme("https")
                    .map_err(|()| Error::ResponseShapeMismatch)?;
            }
            if uri.scheme() != "https"
                || uri.host_str() != Some("imge.kugou.com")
                || !uri.username().is_empty()
                || uri.password().is_some()
                || uri.port().is_some()
                || uri.fragment().is_some()
            {
                return Err(Error::ResponseShapeMismatch);
            }
            Ok(uri.into())
        })
        .transpose()
}
