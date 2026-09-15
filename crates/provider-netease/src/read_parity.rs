use super::{NeteaseProvider, album, artist, provider_id, song};
use music_domain::{
    MusicVideo, MusicVideoId, MusicVideoQuality, MusicVideoSource, NewAlbumRegion, NewAlbumRelease,
    NewAlbumReleasesPage, NewSongCategory, NewSongCollection, RelatedTracksCollection,
    TrackComment, TrackCommentId, TrackCommentsPage, TrackId,
};
use netease_client::{Error, NewAlbumArea, NewSongArea, Transport};
use provider_api::{
    CatalogError, CommentsError, MusicVideoError, NewAlbumReleasesProvider, NewSongsProvider,
    RelatedTracksError, RelatedTracksProvider, TrackCommentsProvider, TrackMusicVideoProvider,
};

fn comments_error(error: Error) -> CommentsError {
    match error {
        Error::TemporaryNetworkFailure => CommentsError::Network,
        Error::InputBound | Error::ResponseBound | Error::ResponseShapeMismatch => {
            CommentsError::InvalidResponse
        }
        _ => CommentsError::ServiceUnavailable,
    }
}

fn related_error(error: Error) -> RelatedTracksError {
    match error {
        Error::InputBound => RelatedTracksError::InvalidTrack,
        Error::TemporaryNetworkFailure => RelatedTracksError::Network,
        Error::ResponseBound | Error::ResponseShapeMismatch => RelatedTracksError::InvalidResponse,
        _ => RelatedTracksError::ServiceUnavailable,
    }
}

fn video_error(error: Error) -> MusicVideoError {
    match error {
        Error::TemporaryNetworkFailure => MusicVideoError::Network,
        Error::TrackUnavailable | Error::EntitlementDenied => MusicVideoError::SourceUnavailable,
        Error::InputBound | Error::ResponseBound | Error::ResponseShapeMismatch => {
            MusicVideoError::InvalidResponse
        }
        _ => MusicVideoError::ServiceUnavailable,
    }
}

impl<T: Transport> TrackCommentsProvider for NeteaseProvider<T> {
    type Error = CommentsError;

    async fn track_comments(
        &self,
        track_id: TrackId,
        offset: u32,
        size: u32,
    ) -> Result<TrackCommentsPage, Self::Error> {
        let id = super::catalog::identity(track_id.provider(), track_id.opaque())
            .map_err(comments_error)?;
        let page = self
            .client
            .comments(id, offset, size)
            .await
            .map_err(comments_error)?;
        let map = |comment: netease_client::Comment| {
            let author_avatar_uri = netease_client::artwork(comment.user.avatar).ok().flatten();
            TrackComment::new(
                TrackCommentId::new(provider_id(), comment.id.to_string())
                    .map_err(|_| CommentsError::InvalidResponse)?,
                comment.user.nickname,
                comment.content,
                comment.time / 1000,
                comment.praise_count,
            )
            .map(|comment_domain| comment_domain.with_author_avatar_uri(author_avatar_uri))
            .map_err(|_| CommentsError::InvalidResponse)
        };
        let mut omitted_hot = page.omitted_hot;
        let mut hot = Vec::with_capacity(page.hot.len());
        for comment in page.hot {
            match map(comment) {
                Ok(comment) => hot.push(comment),
                Err(CommentsError::InvalidResponse) => {
                    omitted_hot = omitted_hot
                        .checked_add(1)
                        .ok_or(CommentsError::InvalidResponse)?;
                }
                Err(error) => return Err(error),
            }
        }
        let mut omitted_latest = page.omitted_latest;
        let mut latest = Vec::with_capacity(page.latest.len());
        for comment in page.latest {
            match map(comment) {
                Ok(comment) => latest.push(comment),
                Err(CommentsError::InvalidResponse) => {
                    omitted_latest = omitted_latest
                        .checked_add(1)
                        .ok_or(CommentsError::InvalidResponse)?;
                }
                Err(error) => return Err(error),
            }
        }
        Ok(
            TrackCommentsPage::new(page.offset, page.total, page.more, hot, latest).with_integrity(
                page.next,
                omitted_hot,
                omitted_latest,
            ),
        )
    }
}

impl<T: Transport> RelatedTracksProvider for NeteaseProvider<T> {
    type Error = RelatedTracksError;

    async fn related_tracks(&self, seed: TrackId) -> Result<RelatedTracksCollection, Self::Error> {
        let seed =
            super::catalog::identity(seed.provider(), seed.opaque()).map_err(related_error)?;
        let source = self
            .client
            .related_tracks(seed)
            .await
            .map_err(related_error)?;
        let mut omitted = source.omitted;
        let mut tracks = Vec::with_capacity(source.items.len());
        for item in source.items {
            match song(item) {
                Ok(track) => tracks.push(track),
                Err(Error::ResponseShapeMismatch | Error::ResponseBound) => {
                    omitted = omitted
                        .checked_add(1)
                        .ok_or(RelatedTracksError::InvalidResponse)?;
                }
                Err(error) => return Err(related_error(error)),
            }
        }
        Ok(RelatedTracksCollection::new(tracks, omitted))
    }
}

impl<T: Transport> NewSongsProvider for NeteaseProvider<T> {
    type Error = CatalogError;

    async fn new_songs(&self, category: NewSongCategory) -> Result<NewSongCollection, Self::Error> {
        let area = match category {
            NewSongCategory::Latest => NewSongArea::All,
            NewSongCategory::Western => NewSongArea::Western,
            NewSongCategory::Japan => NewSongArea::Japan,
            NewSongCategory::Korea => NewSongArea::Korea,
            // NetEase's `ZH`/area 7 means the broader Chinese-language market;
            // it is not an exact Mainland or Hong Kong/Taiwan category.
            NewSongCategory::MainlandChina | NewSongCategory::HongKongTaiwan => {
                return Err(CatalogError::InvalidResponse);
            }
        };
        let source = self
            .client
            .new_songs(area)
            .await
            .map_err(super::catalog::catalog_error)?;
        let mut omitted = source.omitted;
        let mut tracks = Vec::with_capacity(source.items.len());
        for item in source.items {
            match song(item) {
                Ok(track) => tracks.push(track),
                Err(Error::ResponseShapeMismatch | Error::ResponseBound) => {
                    omitted = omitted
                        .checked_add(1)
                        .ok_or(CatalogError::InvalidResponse)?;
                }
                Err(error) => return Err(super::catalog::catalog_error(error)),
            }
        }
        Ok(NewSongCollection::new(category, tracks).with_omitted_track_count(omitted))
    }
}

impl<T: Transport> NewAlbumReleasesProvider for NeteaseProvider<T> {
    type Error = CatalogError;

    async fn new_album_releases(
        &self,
        region: NewAlbumRegion,
        offset: u32,
        size: u32,
    ) -> Result<NewAlbumReleasesPage, Self::Error> {
        let area = match region {
            NewAlbumRegion::Western => NewAlbumArea::Western,
            NewAlbumRegion::Korea => NewAlbumArea::Korea,
            NewAlbumRegion::Japan => NewAlbumArea::Japan,
            // `ZH` is not an exact match for either QQ-derived region, and the
            // NetEase `ALL` catalog has no provider-neutral enum value here.
            NewAlbumRegion::MainlandChina
            | NewAlbumRegion::HongKongTaiwan
            | NewAlbumRegion::Other => return Err(CatalogError::InvalidResponse),
        };
        let page = self
            .client
            .new_albums(area, offset, size)
            .await
            .map_err(super::catalog::catalog_error)?;
        let mut omitted = page.omitted;
        let mut releases = Vec::with_capacity(page.items.len());
        for release in page.items {
            let mapped = (|| {
                let artists = release
                    .album
                    .artists
                    .clone()
                    .into_iter()
                    .filter(|artist| artist.id > 0)
                    .map(artist)
                    .collect::<Result<Vec<_>, _>>()?;
                // `publishTime` is retained by the protocol client. Domain
                // display-date conversion is deliberately omitted until its
                // service timezone semantics are evidenced.
                Ok(NewAlbumRelease::new(album(release.album)?, artists, None))
            })();
            match mapped {
                Ok(item) => releases.push(item),
                Err(Error::ResponseShapeMismatch | Error::ResponseBound) => {
                    omitted = omitted
                        .checked_add(1)
                        .ok_or(CatalogError::InvalidResponse)?;
                }
                Err(error) => return Err(super::catalog::catalog_error(error)),
            }
        }
        Ok(
            NewAlbumReleasesPage::new(region, page.offset, page.total, page.more, releases)
                .with_integrity(page.next, omitted),
        )
    }
}

impl<T: Transport> TrackMusicVideoProvider for NeteaseProvider<T> {
    type Error = MusicVideoError;

    async fn track_music_video(
        &self,
        track_id: TrackId,
    ) -> Result<Option<MusicVideo>, Self::Error> {
        let id = super::catalog::identity(track_id.provider(), track_id.opaque())
            .map_err(video_error)?;
        let Some(video) = self.client.music_video(id).await.map_err(video_error)? else {
            return Ok(None);
        };
        let quality = match video.source.resolution {
            1080 => MusicVideoQuality::FullHd,
            720 => MusicVideoQuality::Hd,
            480 => MusicVideoQuality::Sd,
            240 | 360 => MusicVideoQuality::Low,
            _ => return Err(MusicVideoError::InvalidResponse),
        };
        let source = MusicVideoSource::new(video.source.uri(), quality)
            .map_err(|_| MusicVideoError::InvalidResponse)?;
        Ok(Some(
            MusicVideo::new(
                MusicVideoId::new(provider_id(), video.id.to_string())
                    .map_err(|_| MusicVideoError::InvalidResponse)?,
                video.title,
                video.artist_names,
                source,
            )
            .map_err(|_| MusicVideoError::InvalidResponse)?
            .with_artwork_uri(video.artwork)
            .with_duration_seconds(Some(video.duration_millis / 1000)),
        ))
    }
}
