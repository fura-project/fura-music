//! Provider-neutral mapping for the bounded `KuGou` public client.

use kugou_client::{Error, KuGouClient, SearchTrack, TrackDetails, Transport};
use music_domain::{
    AlbumId, AlbumSummary, ArtistId, ArtistSummary, ProviderId, RankingGroup,
    RankingGroupsCollection, RankingId, RankingSummary, RankingTracksPage, SynchronizedLyricLine,
    SynchronizedLyrics, TrackId, TrackSearchItem, TrackSearchPage, TrackSummary,
};
use provider_api::{
    CatalogError, LyricsError, LyricsProvider, MusicProvider, ProviderCapability,
    ProviderDescriptor, RankingsProvider, SearchError, TrackDetailsProvider, TrackSearchProvider,
};
use std::sync::Arc;

const TRACK_ID_VERSION: &str = "v1";
const RANKING_PAGE_SIZE: u32 = 30;

#[derive(Clone, Debug, Eq, PartialEq)]
struct TrackContext {
    mix_song_id: String,
    standard_hash: String,
    audio_id: u64,
    duration_seconds: u32,
    album_id: Option<String>,
}

pub struct KuGouProvider<T> {
    client: Arc<KuGouClient<T>>,
}

impl<T> KuGouProvider<T> {
    #[must_use]
    pub fn new(client: KuGouClient<T>) -> Self {
        Self {
            client: Arc::new(client),
        }
    }
}

#[must_use]
/// # Panics
/// Only if the compile-time `KuGou` Provider identifier violates Domain invariants.
pub fn provider_id() -> ProviderId {
    ProviderId::new("kugou-music").expect("static provider ID")
}

impl<T> MusicProvider for KuGouProvider<T> {
    fn descriptor(&self) -> ProviderDescriptor {
        ProviderDescriptor {
            id: provider_id(),
            display_name: "KuGou Music".into(),
            capabilities: vec![
                ProviderCapability::Search,
                ProviderCapability::Catalog,
                ProviderCapability::Lyrics,
            ],
        }
    }
}

fn map_error(error: Error) -> SearchError {
    match error {
        Error::TemporaryNetworkFailure => SearchError::Network,
        Error::InputBound | Error::ResponseBound | Error::ResponseShapeMismatch => {
            SearchError::InvalidResponse
        }
        Error::RateLimited
        | Error::SecurityVerificationRequired
        | Error::ProtocolUnavailable
        | Error::ContentUnavailable
        | Error::UpstreamUnknown => SearchError::ServiceUnavailable,
    }
}

fn map_track(source: SearchTrack) -> Result<TrackSearchItem, Error> {
    let track = map_track_summary(source)?;
    let album = track.album().cloned();
    let artists = track.artists().to_vec();
    Ok(TrackSearchItem::new(track, album, artists))
}

fn map_track_summary(source: SearchTrack) -> Result<TrackSummary, Error> {
    let context = TrackContext {
        mix_song_id: source.mix_song_id.clone(),
        standard_hash: source.standard_hash.clone(),
        audio_id: source.audio_id,
        duration_seconds: source.duration_seconds,
        album_id: source.album_id.clone(),
    };
    let album = source
        .album
        .map(|album| {
            AlbumSummary::new(
                AlbumId::new(provider_id(), album.id).map_err(|_| Error::ResponseShapeMismatch)?,
                album.title,
            )
            .map_err(|_| Error::ResponseShapeMismatch)
        })
        .transpose()?;
    let artist_names = source
        .artists
        .iter()
        .map(|artist| artist.name.clone())
        .collect::<Vec<_>>();
    let artists = source
        .artists
        .into_iter()
        .filter(|artist| artist.id > 0)
        .map(|artist| {
            ArtistSummary::new(
                ArtistId::new(provider_id(), artist.id.to_string())
                    .map_err(|_| Error::ResponseShapeMismatch)?,
                artist.name,
            )
            .map_err(|_| Error::ResponseShapeMismatch)
        })
        .collect::<Result<Vec<_>, _>>()?;
    let mut track = TrackSummary::new(
        TrackId::new(provider_id(), encode_track_context(&context))
            .map_err(|_| Error::ResponseShapeMismatch)?,
        source.title,
        artist_names,
    )
    .map_err(|_| Error::ResponseShapeMismatch)?
    .with_artists(artists.clone())
    .with_artwork_uri(source.artwork)
    .with_duration_seconds(Some(source.duration_seconds));
    if let Some(album) = &album {
        track = track
            .with_album_title(Some(album.title().into()))
            .with_album(Some(album.clone()));
    }
    Ok(track.with_membership_opaque_id(context.mix_song_id))
}

fn map_track_details(source: TrackDetails, context: &TrackContext) -> Result<TrackSummary, Error> {
    if source.mix_song_id != context.mix_song_id
        || source.standard_hash != context.standard_hash
        || source.audio_id != context.audio_id
        || source.duration_seconds != context.duration_seconds
        || context
            .album_id
            .as_ref()
            .is_some_and(|expected| source.album_id.as_ref() != Some(expected))
    {
        return Err(Error::ResponseShapeMismatch);
    }
    let album = source
        .album
        .map(|album| {
            AlbumSummary::new(
                AlbumId::new(provider_id(), album.id).map_err(|_| Error::ResponseShapeMismatch)?,
                album.title,
            )
            .map_err(|_| Error::ResponseShapeMismatch)
        })
        .transpose()?;
    let artist_names = source
        .artists
        .iter()
        .map(|artist| artist.name.clone())
        .collect::<Vec<_>>();
    let artists = source
        .artists
        .into_iter()
        .filter(|artist| artist.id > 0)
        .map(|artist| {
            ArtistSummary::new(
                ArtistId::new(provider_id(), artist.id.to_string())
                    .map_err(|_| Error::ResponseShapeMismatch)?,
                artist.name,
            )
            .map_err(|_| Error::ResponseShapeMismatch)
        })
        .collect::<Result<Vec<_>, _>>()?;
    let mut track = TrackSummary::new(
        TrackId::new(provider_id(), encode_track_context(context))
            .map_err(|_| Error::ResponseShapeMismatch)?,
        source.title,
        artist_names,
    )
    .map_err(|_| Error::ResponseShapeMismatch)?
    .with_artists(artists)
    .with_artwork_uri(source.artwork)
    .with_duration_seconds(Some(source.duration_seconds))
    .with_membership_opaque_id(context.mix_song_id.clone());
    if let Some(album) = album {
        track = track
            .with_album_title(Some(album.title().to_owned()))
            .with_album(Some(album));
    }
    Ok(track)
}

fn encode_track_context(context: &TrackContext) -> String {
    format!(
        "{TRACK_ID_VERSION}:{}:{}:{}:{}:{}",
        context.mix_song_id,
        context.standard_hash,
        context.audio_id,
        context.duration_seconds,
        context.album_id.as_deref().unwrap_or("-")
    )
}

fn decode_track_context(id: &TrackId) -> Result<TrackContext, Error> {
    if id.provider() != &provider_id() {
        return Err(Error::InputBound);
    }
    let mut fields = id.opaque().split(':');
    let version = fields.next();
    let mix_song_id = fields.next();
    let standard_hash = fields.next();
    let audio_id = fields.next();
    let duration_seconds = fields.next();
    let album_id = fields.next();
    if fields.next().is_some() || version != Some(TRACK_ID_VERSION) {
        return Err(Error::InputBound);
    }
    let mix_song_id = numeric_identity(mix_song_id.ok_or(Error::InputBound)?)?;
    let standard_hash = standard_hash.ok_or(Error::InputBound)?.to_ascii_uppercase();
    if standard_hash.len() != 32 || !standard_hash.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(Error::InputBound);
    }
    let audio_id = numeric_identity(audio_id.ok_or(Error::InputBound)?)?
        .parse::<u64>()
        .map_err(|_| Error::InputBound)?;
    let duration_seconds = duration_seconds
        .ok_or(Error::InputBound)?
        .parse::<u32>()
        .map_err(|_| Error::InputBound)?;
    if duration_seconds > 86_400 {
        return Err(Error::InputBound);
    }
    let album_id = match album_id.ok_or(Error::InputBound)? {
        "-" => None,
        value => Some(numeric_identity(value)?),
    };
    Ok(TrackContext {
        mix_song_id,
        standard_hash,
        audio_id,
        duration_seconds,
        album_id,
    })
}

fn numeric_identity(value: &str) -> Result<String, Error> {
    if value.is_empty()
        || value.starts_with('0')
        || value.len() > 20
        || !value.bytes().all(|byte| byte.is_ascii_digit())
        || value
            .parse::<u64>()
            .ok()
            .as_ref()
            .is_none_or(|value| *value == 0)
    {
        Err(Error::InputBound)
    } else {
        Ok(value.to_owned())
    }
}

fn catalog_error(error: Error) -> CatalogError {
    match error {
        Error::TemporaryNetworkFailure => CatalogError::Network,
        Error::InputBound | Error::ResponseBound | Error::ResponseShapeMismatch => {
            CatalogError::InvalidResponse
        }
        Error::RateLimited
        | Error::SecurityVerificationRequired
        | Error::ProtocolUnavailable
        | Error::ContentUnavailable
        | Error::UpstreamUnknown => CatalogError::ServiceUnavailable,
    }
}

fn lyrics_error(error: Error) -> LyricsError {
    match error {
        Error::ContentUnavailable => LyricsError::Unavailable,
        Error::TemporaryNetworkFailure => LyricsError::Network,
        Error::InputBound | Error::ResponseBound | Error::ResponseShapeMismatch => {
            LyricsError::InvalidResponse
        }
        Error::RateLimited
        | Error::SecurityVerificationRequired
        | Error::ProtocolUnavailable
        | Error::UpstreamUnknown => LyricsError::ServiceUnavailable,
    }
}

impl<T: Transport> TrackSearchProvider for KuGouProvider<T> {
    type Error = SearchError;

    async fn search_tracks(
        &self,
        query: String,
        page: u32,
        size: u32,
    ) -> Result<TrackSearchPage, Self::Error> {
        let page_result = self
            .client
            .search_tracks(&query, page, size)
            .await
            .map_err(map_error)?;
        let mut omitted = page_result.omitted_item_count;
        let mut items = Vec::with_capacity(page_result.items.len());
        for source in page_result.items {
            match map_track(source) {
                Ok(item) => items.push(item),
                Err(Error::ResponseShapeMismatch | Error::ResponseBound) => {
                    omitted = omitted.checked_add(1).ok_or(SearchError::InvalidResponse)?;
                }
                Err(error) => return Err(map_error(error)),
            }
        }
        Ok(
            TrackSearchPage::new(page_result.page, page_result.total, page_result.more, items)
                .with_omitted_item_count(omitted),
        )
    }
}

impl<T: Transport> TrackDetailsProvider for KuGouProvider<T> {
    type Error = CatalogError;

    async fn track_details(&self, id: TrackId) -> Result<Option<TrackSummary>, Self::Error> {
        let context = decode_track_context(&id).map_err(catalog_error)?;
        self.client
            .track_details(&context.standard_hash)
            .await
            .and_then(|source| map_track_details(source, &context))
            .map(Some)
            .map_err(catalog_error)
    }
}

impl<T: Transport> RankingsProvider for KuGouProvider<T> {
    type Error = CatalogError;

    async fn ranking_groups(&self) -> Result<RankingGroupsCollection, Self::Error> {
        let source = self.client.rankings().await.map_err(catalog_error)?;
        let mut omitted = source.omitted_item_count;
        let mut rankings = Vec::with_capacity(source.items.len());
        for source in source.items {
            let mapped = (|| {
                let id = RankingId::new(provider_id(), source.id)
                    .map_err(|_| CatalogError::InvalidResponse)?;
                Ok(RankingSummary::new(id, source.title)
                    .map_err(|_| CatalogError::InvalidResponse)?
                    .with_period(source.period)
                    .with_artwork_uri(source.artwork))
            })();
            match mapped {
                Ok(ranking) => rankings.push(ranking),
                Err(CatalogError::InvalidResponse) => {
                    omitted = omitted
                        .checked_add(1)
                        .ok_or(CatalogError::InvalidResponse)?;
                }
                Err(error) => return Err(error),
            }
        }
        if rankings.is_empty() {
            return if omitted == 0 {
                Ok(RankingGroupsCollection::new(Vec::new(), 0))
            } else {
                Err(CatalogError::InvalidResponse)
            };
        }
        let group = RankingGroup::new("KuGou Music", rankings)
            .map_err(|_| CatalogError::InvalidResponse)?;
        Ok(RankingGroupsCollection::new(vec![group], omitted))
    }

    async fn ranking_tracks(
        &self,
        id: RankingId,
        offset: u32,
        size: u32,
    ) -> Result<RankingTracksPage, Self::Error> {
        if id.provider() != &provider_id()
            || size != RANKING_PAGE_SIZE
            || !offset.is_multiple_of(RANKING_PAGE_SIZE)
        {
            return Err(CatalogError::InvalidResponse);
        }
        let ranking_id = numeric_identity(id.opaque()).map_err(catalog_error)?;
        let page = offset
            .checked_div(RANKING_PAGE_SIZE)
            .and_then(|value| value.checked_add(1))
            .ok_or(CatalogError::InvalidResponse)?;
        let source = self
            .client
            .ranking_tracks(&ranking_id, page)
            .await
            .map_err(catalog_error)?;
        let ranking = RankingSummary::new(
            RankingId::new(provider_id(), source.ranking.id)
                .map_err(|_| CatalogError::InvalidResponse)?,
            source.ranking.title,
        )
        .map_err(|_| CatalogError::InvalidResponse)?
        .with_period(source.ranking.period)
        .with_artwork_uri(source.ranking.artwork)
        .with_track_count(Some(source.total));
        let raw_count = u32::try_from(source.items.len())
            .ok()
            .and_then(|count| count.checked_add(source.omitted_item_count))
            .ok_or(CatalogError::InvalidResponse)?;
        let next_offset = offset
            .checked_add(raw_count)
            .ok_or(CatalogError::InvalidResponse)?;
        let mut omitted = source.omitted_item_count;
        let mut tracks = Vec::with_capacity(source.items.len());
        for source in source.items {
            match map_track_summary(source) {
                Ok(track) => tracks.push(track),
                Err(Error::ResponseShapeMismatch | Error::ResponseBound) => {
                    omitted = omitted
                        .checked_add(1)
                        .ok_or(CatalogError::InvalidResponse)?;
                }
                Err(error) => return Err(catalog_error(error)),
            }
        }
        Ok(
            RankingTracksPage::new(ranking, offset, source.total, source.more, tracks)
                .with_raw_cursor(next_offset, omitted),
        )
    }
}

impl<T: Transport> LyricsProvider for KuGouProvider<T> {
    type Error = LyricsError;

    async fn lyrics(&self, id: TrackId) -> Result<SynchronizedLyrics, Self::Error> {
        let context = decode_track_context(&id).map_err(lyrics_error)?;
        let source = self
            .client
            .lyrics(&context.standard_hash, context.duration_seconds)
            .await
            .map_err(lyrics_error)?;
        let mut lines = Vec::with_capacity(source.lines.len());
        for line in source.lines {
            lines.push(
                SynchronizedLyricLine::new(line.text, line.start_ms, 0, Vec::new())
                    .map_err(|_| LyricsError::InvalidResponse)?,
            );
        }
        SynchronizedLyrics::new(id, lines)
            .map(|lyrics| lyrics.with_omitted_line_count(source.omitted_line_count))
            .map_err(|_| LyricsError::InvalidResponse)
    }
}
