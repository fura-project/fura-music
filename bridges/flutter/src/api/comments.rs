use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use music_domain::{TrackComment, TrackCommentsPage};
use provider_api::{CommentsError, TrackCommentsProvider};
use tokio::sync::Notify;

use super::authentication::native_qq_music_provider;
use super::domain_track_id;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicTrackCommentPageLoadFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct TrackCommentSummary {
    pub provider_id: String,
    pub opaque_id: String,
    pub author_display_name: String,
    pub content: String,
    pub published_at_unix_seconds: u32,
    pub praise_count: u32,
}

impl fmt::Debug for TrackCommentSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("TrackCommentSummary")
            .field("provider_id", &self.provider_id)
            .field("opaque_id", &"[REDACTED]")
            .field("author_display_name", &"[REDACTED]")
            .field("content", &"[REDACTED]")
            .field("published_at_unix_seconds", &self.published_at_unix_seconds)
            .field("praise_count", &self.praise_count)
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicTrackCommentPageLoad {
    pub offset: u32,
    pub total: u32,
    pub has_more: bool,
    pub hot_comments: Vec<TrackCommentSummary>,
    pub latest_comments: Vec<TrackCommentSummary>,
    pub failure: Option<QqMusicTrackCommentPageLoadFailure>,
}

impl fmt::Debug for QqMusicTrackCommentPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicTrackCommentPageLoad")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("hot_comment_count", &self.hot_comments.len())
            .field("latest_comment_count", &self.latest_comments.len())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use public Track-comment page load. Provider-owned
/// Track parsing and source-specific hot/latest pagination remain in Rust.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicTrackCommentPageLoadHandle {
    provider_id: String,
    opaque_track_id: String,
    offset: u32,
    size: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicTrackCommentPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicTrackCommentPageLoadHandle")
            .field("provider_id", &self.provider_id)
            .field("opaque_track_id", &"[REDACTED]")
            .field("offset", &self.offset)
            .field("size", &self.size)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicTrackCommentPageLoadHandle {
    pub async fn run(&self) -> QqMusicTrackCommentPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_load(QqMusicTrackCommentPageLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_load(QqMusicTrackCommentPageLoadFailure::AlreadyRunning);
        }
        let outcome = match (
            native_qq_music_provider(),
            domain_track_id(&self.provider_id, &self.opaque_track_id),
        ) {
            (Ok(provider), Ok(track_id)) => {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_load(QqMusicTrackCommentPageLoadFailure::Cancelled)
                    }
                    result = provider.track_comments(track_id, self.offset, self.size) => {
                        if self.active.load(Ordering::SeqCst) {
                            map_load(result)
                        } else {
                            failed_load(QqMusicTrackCommentPageLoadFailure::Cancelled)
                        }
                    }
                }
            }
            (Err(()), _) => failed_load(QqMusicTrackCommentPageLoadFailure::CoreUnavailable),
            (_, Err(())) => failed_load(QqMusicTrackCommentPageLoadFailure::InvalidResponse),
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
pub fn begin_qq_music_track_comment_page_load(
    provider_id: String,
    opaque_track_id: String,
    offset: u32,
    size: u32,
) -> QqMusicTrackCommentPageLoadHandle {
    QqMusicTrackCommentPageLoadHandle {
        provider_id,
        opaque_track_id,
        offset,
        size,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_load(result: Result<TrackCommentsPage, CommentsError>) -> QqMusicTrackCommentPageLoad {
    let page = match result {
        Ok(page) => page,
        Err(error) => return failed_load(map_error(error)),
    };
    let hot_comments = match page
        .hot_comments()
        .iter()
        .map(bridge_comment)
        .collect::<Result<Vec<_>, _>>()
    {
        Ok(comments) => comments,
        Err(()) => return failed_load(QqMusicTrackCommentPageLoadFailure::InvalidResponse),
    };
    let latest_comments = match page
        .latest_comments()
        .iter()
        .map(bridge_comment)
        .collect::<Result<Vec<_>, _>>()
    {
        Ok(comments) => comments,
        Err(()) => return failed_load(QqMusicTrackCommentPageLoadFailure::InvalidResponse),
    };
    QqMusicTrackCommentPageLoad {
        offset: page.offset(),
        total: page.total(),
        has_more: page.has_more(),
        hot_comments,
        latest_comments,
        failure: None,
    }
}

fn bridge_comment(comment: &TrackComment) -> Result<TrackCommentSummary, ()> {
    Ok(TrackCommentSummary {
        provider_id: comment.id().provider().as_str().to_owned(),
        opaque_id: comment.id().opaque().to_owned(),
        author_display_name: comment.author_display_name().to_owned(),
        content: comment.content().to_owned(),
        published_at_unix_seconds: u32::try_from(comment.published_at_unix_seconds())
            .map_err(|_| ())?,
        praise_count: u32::try_from(comment.praise_count()).map_err(|_| ())?,
    })
}

const fn failed_load(failure: QqMusicTrackCommentPageLoadFailure) -> QqMusicTrackCommentPageLoad {
    QqMusicTrackCommentPageLoad {
        offset: 0,
        total: 0,
        has_more: false,
        hot_comments: Vec::new(),
        latest_comments: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_error(error: CommentsError) -> QqMusicTrackCommentPageLoadFailure {
    match error {
        CommentsError::Network => QqMusicTrackCommentPageLoadFailure::Network,
        CommentsError::ServiceUnavailable => QqMusicTrackCommentPageLoadFailure::ServiceUnavailable,
        CommentsError::InvalidResponse => QqMusicTrackCommentPageLoadFailure::InvalidResponse,
    }
}

#[cfg(test)]
mod tests {
    use music_domain::{ProviderId, TrackComment, TrackCommentId, TrackCommentsPage};
    use provider_api::CommentsError;

    use super::{
        QqMusicTrackCommentPageLoadFailure, begin_qq_music_track_comment_page_load, map_error,
        map_load,
    };

    fn comment(id: &str, author: &str, content: &str, time: u64, praise: u64) -> TrackComment {
        TrackComment::new(
            TrackCommentId::new(
                ProviderId::new("qq-music").expect("provider"),
                format!("comment:{id}"),
            )
            .expect("comment ID"),
            author,
            content,
            time,
            praise,
        )
        .expect("comment")
    }

    #[test]
    fn maps_comment_page_without_exposing_identity_or_content() {
        let mapped = map_load(Ok(TrackCommentsPage::new(
            0,
            2,
            true,
            vec![comment(
                "91001",
                "must-not-leak-hot",
                "private-hot",
                1_700_000_001,
                41,
            )],
            vec![comment(
                "92001",
                "must-not-leak-latest",
                "private-latest",
                1_700_000_002,
                7,
            )],
        )));

        assert_eq!(mapped.total, 2);
        assert!(mapped.has_more);
        assert_eq!(mapped.hot_comments[0].opaque_id, "comment:91001");
        assert_eq!(mapped.latest_comments[0].praise_count, 7);
        let debug = format!("{mapped:?} {:?}", mapped.latest_comments[0]);
        for private in ["must-not-leak", "private-", "91001", "92001"] {
            assert!(!debug.contains(private));
        }
    }

    #[test]
    fn rejects_values_that_cannot_cross_the_narrow_bridge_contract() {
        let mapped = map_load(Ok(TrackCommentsPage::new(
            0,
            1,
            false,
            Vec::new(),
            vec![comment("92001", "author", "content", u64::MAX, 0)],
        )));
        assert_eq!(
            mapped.failure,
            Some(QqMusicTrackCommentPageLoadFailure::InvalidResponse)
        );
    }

    #[test]
    fn maps_comment_failures_precisely() {
        assert_eq!(
            map_error(CommentsError::Network),
            QqMusicTrackCommentPageLoadFailure::Network
        );
        assert_eq!(
            map_error(CommentsError::ServiceUnavailable),
            QqMusicTrackCommentPageLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_error(CommentsError::InvalidResponse),
            QqMusicTrackCommentPageLoadFailure::InvalidResponse
        );
    }

    #[tokio::test]
    async fn cancellation_is_exact_and_terminal() {
        let handle = begin_qq_music_track_comment_page_load(
            "qq-music".into(),
            "track:41001:0:fixtureTrackMid:fixtureFileMid".into(),
            0,
            20,
        );

        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let result = handle.run().await;
        assert_eq!(
            result.failure,
            Some(QqMusicTrackCommentPageLoadFailure::Cancelled)
        );
    }
}
