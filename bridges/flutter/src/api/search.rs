use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use provider_api::{SearchError, TrackSearchProvider};
use tokio::sync::Notify;

use super::authentication::native_qq_music_provider;
use super::library::{LibraryTrackSummary, bridge_track_summary};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicTrackSearchPageLoadFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicTrackSearchPageLoad {
    pub page: u32,
    pub total: u32,
    pub has_more: bool,
    pub tracks: Vec<LibraryTrackSummary>,
    pub failure: Option<QqMusicTrackSearchPageLoadFailure>,
}

impl fmt::Debug for QqMusicTrackSearchPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicTrackSearchPageLoad")
            .field("page", &self.page)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("track_count", &self.tracks.len())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use Track search page. The query remains inside
/// this opaque handle and is always redacted from diagnostics.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicTrackSearchPageLoadHandle {
    query: String,
    page: u32,
    size: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicTrackSearchPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicTrackSearchPageLoadHandle")
            .field("query", &"[REDACTED]")
            .field("page", &self.page)
            .field("size", &self.size)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicTrackSearchPageLoadHandle {
    pub async fn run(&self) -> QqMusicTrackSearchPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_load(QqMusicTrackSearchPageLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_load(QqMusicTrackSearchPageLoadFailure::AlreadyRunning);
        }

        let outcome = match native_qq_music_provider() {
            Ok(provider) => {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_load(QqMusicTrackSearchPageLoadFailure::Cancelled)
                    }
                    result = provider.search_tracks(self.query.clone(), self.page, self.size) => {
                        if self.active.load(Ordering::SeqCst) {
                            map_load(result)
                        } else {
                            failed_load(QqMusicTrackSearchPageLoadFailure::Cancelled)
                        }
                    }
                }
            }
            Err(()) => failed_load(QqMusicTrackSearchPageLoadFailure::CoreUnavailable),
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
pub fn begin_qq_music_track_search_page_load(
    query: String,
    page: u32,
    size: u32,
) -> QqMusicTrackSearchPageLoadHandle {
    QqMusicTrackSearchPageLoadHandle {
        query,
        page,
        size,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_load(
    result: Result<music_domain::TrackSearchPage, SearchError>,
) -> QqMusicTrackSearchPageLoad {
    match result {
        Ok(page) => QqMusicTrackSearchPageLoad {
            page: page.page(),
            total: page.total(),
            has_more: page.has_more(),
            tracks: page.tracks().iter().map(bridge_track_summary).collect(),
            failure: None,
        },
        Err(error) => failed_load(map_error(error)),
    }
}

const fn failed_load(failure: QqMusicTrackSearchPageLoadFailure) -> QqMusicTrackSearchPageLoad {
    QqMusicTrackSearchPageLoad {
        page: 0,
        total: 0,
        has_more: false,
        tracks: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_error(error: SearchError) -> QqMusicTrackSearchPageLoadFailure {
    match error {
        SearchError::Network => QqMusicTrackSearchPageLoadFailure::Network,
        SearchError::ServiceUnavailable => QqMusicTrackSearchPageLoadFailure::ServiceUnavailable,
        SearchError::InvalidResponse => QqMusicTrackSearchPageLoadFailure::InvalidResponse,
    }
}

#[cfg(test)]
mod tests {
    use music_domain::{ProviderId, TrackId, TrackSearchPage, TrackSummary};
    use provider_api::SearchError;

    use super::{
        QqMusicTrackSearchPageLoadFailure, begin_qq_music_track_search_page_load, map_error,
        map_load,
    };

    #[test]
    fn maps_search_page_without_exposing_query_or_content() {
        let track = TrackSummary::new(
            TrackId::new(
                ProviderId::new("qq-music").expect("provider"),
                "track:41001:0:fixtureMid:-",
            )
            .expect("track ID"),
            "must-not-leak",
            vec!["private-artist".into()],
        )
        .expect("track summary");
        let mapped = map_load(Ok(TrackSearchPage::new(1, 31, true, vec![track])));

        assert_eq!(mapped.page, 1);
        assert_eq!(mapped.total, 31);
        assert!(mapped.has_more);
        assert_eq!(mapped.tracks.len(), 1);
        assert_eq!(mapped.tracks[0].provider_id, "qq-music");
        assert_eq!(mapped.tracks[0].title, "must-not-leak");
        let debug = format!("{mapped:?} {:?}", mapped.tracks[0]);
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("private-artist"));
        assert!(!debug.contains("41001"));
    }

    #[test]
    fn maps_provider_failures_precisely() {
        assert_eq!(
            map_error(SearchError::Network),
            QqMusicTrackSearchPageLoadFailure::Network
        );
        assert_eq!(
            map_error(SearchError::ServiceUnavailable),
            QqMusicTrackSearchPageLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_error(SearchError::InvalidResponse),
            QqMusicTrackSearchPageLoadFailure::InvalidResponse
        );
    }

    #[tokio::test]
    async fn cancellation_is_exact_terminal_and_query_is_redacted() {
        let handle = begin_qq_music_track_search_page_load("private search query".into(), 1, 30);

        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let result = handle.run().await;
        assert_eq!(
            result.failure,
            Some(QqMusicTrackSearchPageLoadFailure::Cancelled)
        );
        assert!(!format!("{handle:?}").contains("private search query"));
    }
}
