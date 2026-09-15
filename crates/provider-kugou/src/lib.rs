//! Provider-neutral mapping for the bounded `KuGou` public client.

use kugou_client::{Error, KuGouClient, SearchTrack, Transport};
use music_domain::{
    AlbumId, AlbumSummary, ArtistId, ArtistSummary, ProviderId, TrackId, TrackSearchItem,
    TrackSearchPage, TrackSummary,
};
use provider_api::{
    MusicProvider, ProviderCapability, ProviderDescriptor, SearchError, TrackSearchProvider,
};
use std::sync::Arc;

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
            capabilities: vec![ProviderCapability::Search],
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
        | Error::UpstreamUnknown => SearchError::ServiceUnavailable,
    }
}

fn map_track(source: SearchTrack) -> Result<TrackSearchItem, Error> {
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
        TrackId::new(provider_id(), source.mix_song_id)
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
    Ok(TrackSearchItem::new(track, album, artists))
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
