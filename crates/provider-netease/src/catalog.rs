use super::{NeteaseProvider, album, artist, collection_song, playlist, provider_id, song};
use music_domain::{
    AlbumDetails, AlbumId, AlbumTracksPage, ArtistAlbumsPage, ArtistId, ArtistTracksPage,
    AudioFormat, AudioQuality, PlaylistId, PlaylistTracksPage, RankingGroup, RankingId,
    RankingSummary, RankingTracksPage, RecommendedPlaylistsPage, ResolvedMediaSource,
    SynchronizedLyricLine, SynchronizedLyrics, TrackId, TrackSummary,
};
use netease_client::{Error, MediaFormat, MediaQuality, Transport};
use provider_api::{
    AlbumDetailsProvider, AlbumTracksProvider, ArtistAlbumsProvider, ArtistTracksProvider,
    CatalogError, LyricsError, LyricsProvider, MediaResolutionError, MediaSourceResolver,
    PlaylistDetailsProvider, RankingsProvider, RecommendationError, RecommendedPlaylistsProvider,
    TrackDetailsProvider,
};

pub(super) fn catalog_error(error: Error) -> CatalogError {
    match error {
        Error::TemporaryNetworkFailure => CatalogError::Network,
        Error::InputBound | Error::ResponseBound | Error::ResponseShapeMismatch => {
            CatalogError::InvalidResponse
        }
        _ => CatalogError::ServiceUnavailable,
    }
}
pub(super) fn identity(provider: &music_domain::ProviderId, opaque: &str) -> Result<u64, Error> {
    if provider != &provider_id()
        || opaque.starts_with('0')
        || opaque.len() > 16
        || !opaque.bytes().all(|c| c.is_ascii_digit())
    {
        return Err(Error::InputBound);
    }
    let id = opaque.parse::<u64>().map_err(|_| Error::InputBound)?;
    if id == 0 || id > 9_007_199_254_740_991 {
        return Err(Error::InputBound);
    }
    Ok(id)
}
impl<T: Transport> TrackDetailsProvider for NeteaseProvider<T> {
    type Error = CatalogError;
    async fn track_details(&self, id: TrackId) -> Result<Option<TrackSummary>, Self::Error> {
        let id = identity(id.provider(), id.opaque()).map_err(catalog_error)?;
        self.client
            .songs(&[id])
            .await
            .map_err(catalog_error)?
            .into_iter()
            .next()
            .map(song)
            .transpose()
            .map_err(catalog_error)
    }
}
impl<T: Transport> PlaylistDetailsProvider for NeteaseProvider<T> {
    type Error = provider_api::UserLibraryError;
    async fn playlist_tracks_page(
        &self,
        id: PlaylistId,
        offset: u32,
        size: u32,
    ) -> Result<PlaylistTracksPage, Self::Error> {
        if id.provider() == &provider_id()
            && let Some(tail) = id.opaque().strip_prefix("liked:")
        {
            let (owner, playlist) = tail
                .split_once(':')
                .ok_or(provider_api::UserLibraryError::InvalidResponse)?;
            let owner = identity(id.provider(), owner)
                .map_err(|_| provider_api::UserLibraryError::InvalidResponse)?;
            let playlist = identity(id.provider(), playlist)
                .map_err(|_| provider_api::UserLibraryError::InvalidResponse)?;
            return self
                .liked_page(owner, playlist, offset, size)
                .await
                .map_err(super::auth::library_error);
        }
        let map = |e| super::auth::library_error(super::auth::Failure::Client(e));
        let id = identity(id.provider(), id.opaque()).map_err(map)?;
        let p = self
            .playlist_source(id, offset, size)
            .await
            .map_err(super::auth::library_error)?;
        let mut omitted = p.omitted;
        let mut tracks = Vec::with_capacity(p.tracks.len());
        for source in p.tracks {
            match collection_song(source) {
                Ok(track) => tracks.push(track),
                Err(Error::ResponseShapeMismatch | Error::ResponseBound) => {
                    omitted = omitted
                        .checked_add(1)
                        .ok_or(provider_api::UserLibraryError::InvalidResponse)?;
                }
                Err(error) => return Err(map(error)),
            }
        }
        Ok(PlaylistTracksPage::new_with_cursor(
            p.offset,
            p.next,
            p.total,
            p.next < p.total,
            omitted,
            tracks,
        ))
    }
}
impl<T: Transport> AlbumDetailsProvider for NeteaseProvider<T> {
    type Error = CatalogError;
    async fn album_details(&self, id: AlbumId) -> Result<AlbumDetails, Self::Error> {
        let id = identity(id.provider(), id.opaque()).map_err(catalog_error)?;
        let a = self.client.album(id).await.map_err(catalog_error)?.album;
        let artists = a
            .artists
            .clone()
            .into_iter()
            .filter(|a| a.id > 0)
            .map(artist)
            .collect::<Result<Vec<_>, _>>()
            .map_err(catalog_error)?;
        let description = a.description.clone();
        Ok(AlbumDetails::new(album(a).map_err(catalog_error)?, artists)
            .with_description(description))
    }
}
impl<T: Transport> AlbumTracksProvider for NeteaseProvider<T> {
    type Error = CatalogError;
    async fn album_tracks(
        &self,
        id: AlbumId,
        offset: u32,
        size: u32,
    ) -> Result<AlbumTracksPage, Self::Error> {
        if size == 0 || size > 100 || offset as usize > netease_client::MAX_ALBUM_TRACKS {
            return Err(CatalogError::InvalidResponse);
        }
        let id = identity(id.provider(), id.opaque()).map_err(catalog_error)?;
        let a = self.client.album(id).await.map_err(catalog_error)?;
        let total = u32::try_from(a.raw_songs.len()).map_err(|_| CatalogError::InvalidResponse)?;
        let window = a
            .raw_songs
            .into_iter()
            .skip(offset as usize)
            .take(size as usize)
            .collect::<Vec<_>>();
        let raw_count = u32::try_from(window.len()).map_err(|_| CatalogError::InvalidResponse)?;
        let next = offset
            .checked_add(raw_count)
            .ok_or(CatalogError::InvalidResponse)?;
        let mut songs = Vec::with_capacity(window.len());
        let mut omitted = 0_u32;
        for source in window {
            let Some(source) = source else {
                omitted = omitted
                    .checked_add(1)
                    .ok_or(CatalogError::InvalidResponse)?;
                continue;
            };
            match collection_song(source) {
                Ok(track) => songs.push(track),
                Err(Error::ResponseShapeMismatch | Error::ResponseBound) => {
                    omitted = omitted
                        .checked_add(1)
                        .ok_or(CatalogError::InvalidResponse)?;
                }
                Err(error) => return Err(catalog_error(error)),
            }
        }
        Ok(AlbumTracksPage::new(offset, total, next < total, songs).with_integrity(next, omitted))
    }
}
macro_rules! artist_page {
    ($contract:ident,$method:ident,$page:ident,$map:ident,$integrity:ident) => {
        impl<T: Transport> $contract for NeteaseProvider<T> {
            type Error = CatalogError;
            async fn $method(
                &self,
                id: ArtistId,
                offset: u32,
                size: u32,
            ) -> Result<$page, Self::Error> {
                let id = identity(id.provider(), id.opaque()).map_err(catalog_error)?;
                let p = self
                    .client
                    .$method(id, offset, size)
                    .await
                    .map_err(catalog_error)?;
                let mut omitted = p.omitted;
                let mut items = Vec::with_capacity(p.items.len());
                for source in p.items {
                    match $map(source) {
                        Ok(item) => items.push(item),
                        Err(Error::ResponseShapeMismatch | Error::ResponseBound) => {
                            omitted = omitted
                                .checked_add(1)
                                .ok_or(CatalogError::InvalidResponse)?;
                        }
                        Err(error) => return Err(catalog_error(error)),
                    }
                }
                Ok($page::new(p.offset, p.total, p.more, items).$integrity(p.next, omitted))
            }
        }
    };
}
artist_page!(
    ArtistTracksProvider,
    artist_tracks,
    ArtistTracksPage,
    collection_song,
    with_integrity
);
artist_page!(
    ArtistAlbumsProvider,
    artist_albums,
    ArtistAlbumsPage,
    album,
    with_integrity
);
impl<T: Transport> RecommendedPlaylistsProvider for NeteaseProvider<T> {
    type Error = RecommendationError;
    async fn recommended_playlists(
        &self,
        offset: u32,
        size: u32,
    ) -> Result<RecommendedPlaylistsPage, Self::Error> {
        if offset != 0 {
            return Err(RecommendationError::InvalidResponse);
        }
        let map = |e| match catalog_error(e) {
            CatalogError::Network => RecommendationError::Network,
            CatalogError::InvalidResponse => RecommendationError::InvalidResponse,
            CatalogError::ServiceUnavailable => RecommendationError::ServiceUnavailable,
        };
        let p = self
            .client
            .recommendations(size)
            .await
            .map_err(map)?
            .into_iter()
            .map(playlist)
            .collect::<Result<Vec<_>, _>>()
            .map_err(map)?;
        Ok(RecommendedPlaylistsPage::new(0, false, p))
    }
}
impl<T: Transport> RankingsProvider for NeteaseProvider<T> {
    type Error = CatalogError;
    async fn ranking_groups(&self) -> Result<Vec<RankingGroup>, Self::Error> {
        let rows = self.client.rankings().await.map_err(catalog_error)?;
        if rows.is_empty() {
            return Ok(vec![]);
        }
        let rankings = rows
            .into_iter()
            .map(|p| {
                let id = RankingId::new(provider_id(), p.id.to_string())
                    .map_err(|_| CatalogError::InvalidResponse)?;
                Ok(RankingSummary::new(id, p.name)
                    .map_err(|_| CatalogError::InvalidResponse)?
                    .with_artwork_uri(netease_client::artwork(p.artwork).map_err(catalog_error)?)
                    .with_track_count(Some(p.track_count)))
            })
            .collect::<Result<Vec<_>, CatalogError>>()?;
        Ok(vec![
            RankingGroup::new("NetEase Cloud Music", rankings)
                .map_err(|_| CatalogError::InvalidResponse)?,
        ])
    }
    async fn ranking_tracks(
        &self,
        id: RankingId,
        offset: u32,
        size: u32,
    ) -> Result<RankingTracksPage, Self::Error> {
        let id = identity(id.provider(), id.opaque()).map_err(catalog_error)?;
        let p = self
            .client
            .playlist_page(id, offset, size)
            .await
            .map_err(catalog_error)?;
        let ranking = RankingSummary::new(
            RankingId::new(provider_id(), id.to_string())
                .map_err(|_| CatalogError::InvalidResponse)?,
            p.playlist.name,
        )
        .map_err(|_| CatalogError::InvalidResponse)?
        .with_artwork_uri(netease_client::artwork(p.playlist.artwork).map_err(catalog_error)?)
        .with_track_count(Some(p.total));
        let mut omitted = p.omitted;
        let mut tracks = Vec::with_capacity(p.tracks.len());
        for source in p.tracks {
            match collection_song(source) {
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
            RankingTracksPage::new(ranking, p.offset, p.total, p.next < p.total, tracks)
                .with_raw_cursor(p.next, omitted),
        )
    }
}
impl<T: Transport> LyricsProvider for NeteaseProvider<T> {
    type Error = LyricsError;
    async fn lyrics(&self, id: TrackId) -> Result<SynchronizedLyrics, Self::Error> {
        let value =
            identity(id.provider(), id.opaque()).map_err(|_| LyricsError::InvalidResponse)?;
        let lyrics = self.client.lyrics(value).await.map_err(|e| match e {
            Error::AuthenticationRequired => LyricsError::AuthenticationRequired,
            Error::CredentialRejected => LyricsError::CredentialRejected,
            Error::TrackUnavailable => LyricsError::Unavailable,
            Error::TemporaryNetworkFailure => LyricsError::Network,
            Error::ResponseShapeMismatch | Error::ResponseBound | Error::InputBound => {
                LyricsError::InvalidResponse
            }
            _ => LyricsError::ServiceUnavailable,
        })?;
        let mut lines = Vec::new();
        for line in lyrics.lines {
            lines.push(
                SynchronizedLyricLine::new(line.text, line.start_ms, 0, vec![])
                    .map_err(|_| LyricsError::InvalidResponse)?
                    .with_translation(line.translation),
            );
        }
        SynchronizedLyrics::new(id, lines).map_err(|_| LyricsError::InvalidResponse)
    }
}
/// Borrowed resolver shares the exact Provider's client/session lifetime.
pub struct NeteaseMediaSourceResolver<'a, T> {
    provider: &'a NeteaseProvider<T>,
}
impl<T> NeteaseProvider<T> {
    #[must_use]
    pub const fn media_source_resolver(&self) -> NeteaseMediaSourceResolver<'_, T> {
        NeteaseMediaSourceResolver { provider: self }
    }
}
impl<T: Transport> MediaSourceResolver for NeteaseMediaSourceResolver<'_, T> {
    fn supports(&self, track: &TrackId) -> bool {
        track.provider() == &provider_id()
    }
    async fn resolve_media(
        &self,
        track: TrackId,
        preferred: AudioQuality,
    ) -> Result<ResolvedMediaSource, MediaResolutionError> {
        let id = identity(track.provider(), track.opaque())
            .map_err(|_| MediaResolutionError::Unavailable)?;
        let media = self
            .provider
            .resolve_source(
                id,
                match preferred {
                    AudioQuality::Low | AudioQuality::Standard => MediaQuality::Standard,
                    AudioQuality::High => MediaQuality::High,
                    AudioQuality::Lossless => MediaQuality::Lossless,
                },
            )
            .await
            .map_err(|failure| match failure {
                super::auth::Failure::Replaced => MediaResolutionError::Replaced,
                super::auth::Failure::Client(e) => match e {
                    Error::AuthenticationRequired => MediaResolutionError::AuthenticationRequired,
                    Error::CredentialRejected => MediaResolutionError::CredentialRejected,
                    Error::TrackUnavailable
                    | Error::EntitlementDenied
                    | Error::CopyrightRestricted
                    | Error::RegionRestricted => MediaResolutionError::Unavailable,
                    Error::TemporaryNetworkFailure => MediaResolutionError::Network,
                    Error::ResponseShapeMismatch | Error::ResponseBound | Error::InputBound => {
                        MediaResolutionError::InvalidResponse
                    }
                    _ => MediaResolutionError::ServiceUnavailable,
                },
            })?;
        ResolvedMediaSource::new(
            track,
            media.uri(),
            match media.format {
                MediaFormat::Mp3 => AudioFormat::Mp3,
                MediaFormat::M4a => AudioFormat::M4a,
                MediaFormat::Flac => AudioFormat::Flac,
            },
            match media.quality {
                MediaQuality::Standard => AudioQuality::Standard,
                MediaQuality::High => AudioQuality::High,
                MediaQuality::Lossless => AudioQuality::Lossless,
            },
            media.valid_for_seconds,
        )
        .map_err(|_| MediaResolutionError::InvalidResponse)
    }
}
