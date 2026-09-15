//! `NetEase` catalog and session owner. Opaque identity parsing stays here.
mod auth;
mod catalog;
mod read_parity;
pub use auth::{NeteaseQrCancellation, NeteaseQrSession};
pub use catalog::NeteaseMediaSourceResolver;
use music_domain::{
    AlbumId, AlbumSearchPage, AlbumSummary, ArtistId, ArtistSearchPage, ArtistSummary, PlaylistId,
    PlaylistSearchPage, PlaylistSummary, ProviderId, TrackId, TrackSearchItem, TrackSearchPage,
    TrackSummary,
};
use netease_client::{Album, Artist, Error, NeteaseClient, Playlist, Song, Transport};
use provider_api::{
    AlbumSearchProvider, ArtistSearchProvider, MusicProvider, PlaylistSearchProvider,
    ProviderCapability, ProviderDescriptor, SearchError, TrackSearchProvider,
};
use std::sync::Arc;

pub struct NeteaseProvider<T> {
    client: Arc<NeteaseClient<T>>,
    auth: Arc<auth::AuthOwner>,
}
impl<T> NeteaseProvider<T> {
    #[must_use]
    pub fn new(client: NeteaseClient<T>) -> Self {
        Self {
            client: Arc::new(client),
            auth: Arc::new(auth::AuthOwner::new()),
        }
    }
}
#[must_use]
pub fn provider_id() -> ProviderId {
    provider_api::BuiltInProvider::NetEaseCloudMusic.id()
}
impl<T> MusicProvider for NeteaseProvider<T> {
    fn descriptor(&self) -> ProviderDescriptor {
        ProviderDescriptor {
            id: provider_id(),
            display_name: "NetEase Cloud Music".into(),
            capabilities: vec![
                ProviderCapability::Search,
                ProviderCapability::Catalog,
                ProviderCapability::Recommendations,
                ProviderCapability::Lyrics,
                ProviderCapability::Authentication,
                ProviderCapability::UserLibrary,
                ProviderCapability::Comments,
                ProviderCapability::MusicVideo,
            ],
        }
    }
}
fn artist(a: Artist) -> Result<ArtistSummary, Error> {
    let artwork = netease_client::artwork(a.artwork)?;
    ArtistSummary::new(
        ArtistId::new(provider_id(), a.id.to_string()).map_err(|_| Error::ResponseShapeMismatch)?,
        a.name,
    )
    .map(|s| s.with_artwork_uri(artwork))
    .map_err(|_| Error::ResponseShapeMismatch)
}
fn album(a: Album) -> Result<AlbumSummary, Error> {
    Ok(AlbumSummary::new(
        AlbumId::new(provider_id(), a.id.to_string()).map_err(|_| Error::ResponseShapeMismatch)?,
        a.name,
    )
    .map_err(|_| Error::ResponseShapeMismatch)?
    .with_artwork_uri(netease_client::artwork(a.artwork)?))
}
fn playlist(p: Playlist) -> Result<PlaylistSummary, Error> {
    Ok(PlaylistSummary::new(
        PlaylistId::new(provider_id(), p.id.to_string())
            .map_err(|_| Error::ResponseShapeMismatch)?,
        p.name,
    )
    .map_err(|_| Error::ResponseShapeMismatch)?
    .with_artwork_uri(netease_client::artwork(p.artwork)?)
    .with_track_count(Some(p.track_count)))
}
fn song(s: Song) -> Result<TrackSummary, Error> {
    let album = if s.album.has_catalog_identity() {
        Some(album(s.album)?)
    } else {
        None
    };
    let names = s.artists.iter().map(|a| a.name.clone()).collect();
    let artists = s
        .artists
        .into_iter()
        .filter(|a| a.id > 0)
        .map(artist)
        .collect::<Result<Vec<_>, _>>()?;
    let mut track = TrackSummary::new(
        TrackId::new(provider_id(), s.id.to_string()).map_err(|_| Error::ResponseShapeMismatch)?,
        s.name,
        names,
    )
    .map_err(|_| Error::ResponseShapeMismatch)?
    .with_artists(artists)
    .with_duration_seconds(Some(s.duration / 1000));
    if let Some(album) = album {
        track = track
            .with_album_title(Some(album.title().into()))
            .with_artwork_uri(album.artwork_uri().map(str::to_owned))
            .with_album(Some(album));
    }
    Ok(track)
}

/// Collection-context Track mapping. Canonical Track identity and title stay
/// strict while optional Album/Artist navigation and artwork may be absent.
fn collection_song(s: Song) -> Result<TrackSummary, Error> {
    let names = s.artists.iter().map(|artist| artist.name.clone()).collect();
    let artists = s
        .artists
        .iter()
        .filter(|artist| artist.id > 0)
        .filter_map(|source| {
            let id = ArtistId::new(provider_id(), source.id.to_string()).ok()?;
            let summary = ArtistSummary::new(id, source.name.clone()).ok()?;
            Some(summary.with_artwork_uri(netease_client::artwork(source.artwork.clone()).ok()?))
        })
        .collect::<Vec<_>>();
    let album = if s.album.has_catalog_identity() {
        AlbumId::new(provider_id(), s.album.id.to_string())
            .ok()
            .and_then(|id| AlbumSummary::new(id, s.album.name.clone()).ok())
            .map(|summary| {
                summary.with_artwork_uri(
                    netease_client::artwork(s.album.artwork.clone())
                        .ok()
                        .flatten(),
                )
            })
    } else {
        None
    };
    let mut track = TrackSummary::new(
        TrackId::new(provider_id(), s.id.to_string()).map_err(|_| Error::ResponseShapeMismatch)?,
        s.name,
        names,
    )
    .map_err(|_| Error::ResponseShapeMismatch)?
    .with_artists(artists)
    .with_duration_seconds((s.duration > 0).then_some(s.duration / 1000));
    if let Some(title) = (!s.album.name.trim().is_empty()).then_some(s.album.name) {
        track = track.with_album_title(Some(title));
    }
    if let Some(album) = album {
        track = track
            .with_artwork_uri(album.artwork_uri().map(str::to_owned))
            .with_album(Some(album));
    }
    Ok(track)
}
fn search_error(e: Error) -> SearchError {
    match e {
        Error::TemporaryNetworkFailure => SearchError::Network,
        Error::ResponseShapeMismatch | Error::InputBound | Error::ResponseBound => {
            SearchError::InvalidResponse
        }
        _ => SearchError::ServiceUnavailable,
    }
}
fn offset(page: u32, size: u32) -> Result<u32, SearchError> {
    page.checked_sub(1)
        .and_then(|p| p.checked_mul(size))
        .ok_or(SearchError::InvalidResponse)
}
impl<T: Transport> TrackSearchProvider for NeteaseProvider<T> {
    type Error = SearchError;
    async fn search_tracks(
        &self,
        query: String,
        page: u32,
        size: u32,
    ) -> Result<TrackSearchPage, SearchError> {
        let p = self
            .client
            .search_tracks(&query, offset(page, size)?, size)
            .await
            .map_err(search_error)?;
        let mut omitted = p.omitted;
        let mut tracks = Vec::with_capacity(p.items.len());
        for source in p.items {
            match collection_song(source) {
                Ok(track) => tracks.push(TrackSearchItem::new(
                    track.clone(),
                    track.album().cloned(),
                    track.artists().to_vec(),
                )),
                Err(Error::ResponseShapeMismatch | Error::ResponseBound) => {
                    omitted = omitted.checked_add(1).ok_or(SearchError::InvalidResponse)?;
                }
                Err(error) => return Err(search_error(error)),
            }
        }
        Ok(TrackSearchPage::new(page, p.total, p.more, tracks).with_omitted_item_count(omitted))
    }
}
macro_rules! search {
    ($contract:ident,$method:ident,$page:ident,$map:ident,$integrity:ident) => {
        impl<T: Transport> $contract for NeteaseProvider<T> {
            type Error = SearchError;
            async fn $method(
                &self,
                query: String,
                page: u32,
                size: u32,
            ) -> Result<$page, SearchError> {
                let p = self
                    .client
                    .$method(&query, offset(page, size)?, size)
                    .await
                    .map_err(search_error)?;
                let mut omitted = p.omitted;
                let mut items = Vec::with_capacity(p.items.len());
                for source in p.items {
                    match $map(source) {
                        Ok(item) => items.push(item),
                        Err(Error::ResponseShapeMismatch | Error::ResponseBound) => {
                            omitted = omitted.checked_add(1).ok_or(SearchError::InvalidResponse)?;
                        }
                        Err(error) => return Err(search_error(error)),
                    }
                }
                Ok($page::new(page, p.total, p.more, items).$integrity(omitted))
            }
        }
    };
}
search!(
    ArtistSearchProvider,
    search_artists,
    ArtistSearchPage,
    artist,
    with_omitted_artist_count
);
search!(
    AlbumSearchProvider,
    search_albums,
    AlbumSearchPage,
    album,
    with_omitted_album_count
);
search!(
    PlaylistSearchProvider,
    search_playlists,
    PlaylistSearchPage,
    playlist,
    with_omitted_playlist_count
);
