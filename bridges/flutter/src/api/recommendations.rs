use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use provider_api::{RecommendationError, RecommendedPlaylistsProvider};
use tokio::sync::Notify;

use super::authentication::native_qq_music_provider;
use super::library::{LibraryPlaylistSummary, bridge_playlist_summary};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicRecommendedPlaylistPageLoadFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicRecommendedPlaylistPageLoad {
    pub offset: u32,
    pub has_more: bool,
    pub playlists: Vec<LibraryPlaylistSummary>,
    pub failure: Option<QqMusicRecommendedPlaylistPageLoadFailure>,
}

impl fmt::Debug for QqMusicRecommendedPlaylistPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRecommendedPlaylistPageLoad")
            .field("offset", &self.offset)
            .field("has_more", &self.has_more)
            .field("playlist_count", &self.playlists.len())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use public recommendation-page load. Ranking and
/// source-specific request fields remain inside the Rust Provider stack.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicRecommendedPlaylistPageLoadHandle {
    offset: u32,
    size: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicRecommendedPlaylistPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRecommendedPlaylistPageLoadHandle")
            .field("offset", &self.offset)
            .field("size", &self.size)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicRecommendedPlaylistPageLoadHandle {
    pub async fn run(&self) -> QqMusicRecommendedPlaylistPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_load(QqMusicRecommendedPlaylistPageLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_load(QqMusicRecommendedPlaylistPageLoadFailure::AlreadyRunning);
        }
        let outcome = match native_qq_music_provider() {
            Ok(provider) => {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_load(QqMusicRecommendedPlaylistPageLoadFailure::Cancelled)
                    }
                    result = provider.recommended_playlists(self.offset, self.size) => {
                        if self.active.load(Ordering::SeqCst) {
                            map_load(result)
                        } else {
                            failed_load(QqMusicRecommendedPlaylistPageLoadFailure::Cancelled)
                        }
                    }
                }
            }
            Err(()) => failed_load(QqMusicRecommendedPlaylistPageLoadFailure::CoreUnavailable),
        };
        self.running.store(false, Ordering::SeqCst);
        self.active.store(false, Ordering::SeqCst);
        outcome
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) -> bool {
        let was_active = self.active.swap(false, Ordering::SeqCst);
        if was_active {
            self.cancelled.notify_one();
        }
        was_active
    }

    #[flutter_rust_bridge::frb(sync, getter)]
    pub fn is_active(&self) -> bool {
        self.active.load(Ordering::SeqCst)
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn begin_qq_music_recommended_playlist_page_load(
    offset: u32,
    size: u32,
) -> QqMusicRecommendedPlaylistPageLoadHandle {
    QqMusicRecommendedPlaylistPageLoadHandle {
        offset,
        size,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_load(
    result: Result<music_domain::RecommendedPlaylistsPage, RecommendationError>,
) -> QqMusicRecommendedPlaylistPageLoad {
    match result {
        Ok(page) => QqMusicRecommendedPlaylistPageLoad {
            offset: page.offset(),
            has_more: page.has_more(),
            playlists: page
                .playlists()
                .iter()
                .map(bridge_playlist_summary)
                .collect(),
            failure: None,
        },
        Err(error) => failed_load(map_error(error)),
    }
}

const fn failed_load(
    failure: QqMusicRecommendedPlaylistPageLoadFailure,
) -> QqMusicRecommendedPlaylistPageLoad {
    QqMusicRecommendedPlaylistPageLoad {
        offset: 0,
        has_more: false,
        playlists: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_error(error: RecommendationError) -> QqMusicRecommendedPlaylistPageLoadFailure {
    match error {
        RecommendationError::Network => QqMusicRecommendedPlaylistPageLoadFailure::Network,
        RecommendationError::ServiceUnavailable => {
            QqMusicRecommendedPlaylistPageLoadFailure::ServiceUnavailable
        }
        RecommendationError::InvalidResponse => {
            QqMusicRecommendedPlaylistPageLoadFailure::InvalidResponse
        }
    }
}

#[cfg(test)]
mod tests {
    use music_domain::{PlaylistId, PlaylistSummary, ProviderId, RecommendedPlaylistsPage};
    use provider_api::RecommendationError;

    use super::{
        QqMusicRecommendedPlaylistPageLoadFailure, begin_qq_music_recommended_playlist_page_load,
        map_error, map_load,
    };

    #[test]
    fn maps_recommendation_page_without_exposing_identity_or_content() {
        let playlist = PlaylistSummary::new(
            PlaylistId::new(
                ProviderId::new("qq-music").expect("provider"),
                "catalog:81001",
            )
            .expect("Playlist ID"),
            "must-not-leak",
        )
        .expect("Playlist summary")
        .with_track_count(Some(29));
        let mapped = map_load(Ok(RecommendedPlaylistsPage::new(20, true, vec![playlist])));

        assert_eq!(mapped.offset, 20);
        assert!(mapped.has_more);
        assert_eq!(mapped.playlists.len(), 1);
        assert_eq!(mapped.playlists[0].track_count, Some(29));
        let debug = format!("{mapped:?} {:?}", mapped.playlists[0]);
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("81001"));
    }

    #[test]
    fn maps_recommendation_failures_precisely() {
        assert_eq!(
            map_error(RecommendationError::Network),
            QqMusicRecommendedPlaylistPageLoadFailure::Network
        );
        assert_eq!(
            map_error(RecommendationError::ServiceUnavailable),
            QqMusicRecommendedPlaylistPageLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_error(RecommendationError::InvalidResponse),
            QqMusicRecommendedPlaylistPageLoadFailure::InvalidResponse
        );
    }

    #[tokio::test]
    async fn cancellation_is_exact_and_terminal() {
        let handle = begin_qq_music_recommended_playlist_page_load(0, 20);
        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let result = handle.run().await;
        assert_eq!(
            result.failure,
            Some(QqMusicRecommendedPlaylistPageLoadFailure::Cancelled)
        );
    }
}
