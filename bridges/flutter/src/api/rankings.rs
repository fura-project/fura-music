use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use provider_api::{CatalogError, RankingsProvider};
use tokio::sync::Notify;

use super::authentication::native_qq_music_provider;
use super::library::{LibraryTrackSummary, bridge_track_summary};

#[derive(Clone, Eq, PartialEq)]
pub struct CatalogRankingSummary {
    pub provider_id: String,
    pub opaque_id: String,
    pub title: String,
    pub period: Option<String>,
    pub artwork_uri: Option<String>,
    pub track_count: Option<u32>,
}

impl fmt::Debug for CatalogRankingSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CatalogRankingSummary")
            .field("provider_id", &self.provider_id)
            .field("opaque_id", &"[REDACTED]")
            .field("title", &"[REDACTED]")
            .field("has_period", &self.period.is_some())
            .field("has_artwork", &self.artwork_uri.is_some())
            .field("track_count", &self.track_count)
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct CatalogRankingGroup {
    pub title: String,
    pub rankings: Vec<CatalogRankingSummary>,
}

impl fmt::Debug for CatalogRankingGroup {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CatalogRankingGroup")
            .field("title", &"[REDACTED]")
            .field("ranking_count", &self.rankings.len())
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicRankingLoadFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicRankingGroupLoad {
    pub groups: Vec<CatalogRankingGroup>,
    pub failure: Option<QqMusicRankingLoadFailure>,
}

impl fmt::Debug for QqMusicRankingGroupLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRankingGroupLoad")
            .field("group_count", &self.groups.len())
            .field("failure", &self.failure)
            .finish()
    }
}

#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicRankingGroupLoadHandle {
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicRankingGroupLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRankingGroupLoadHandle")
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicRankingGroupLoadHandle {
    pub async fn run(&self) -> QqMusicRankingGroupLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_group_load(QqMusicRankingLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_group_load(QqMusicRankingLoadFailure::AlreadyRunning);
        }
        let outcome = match native_qq_music_provider() {
            Ok(provider) => {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_group_load(QqMusicRankingLoadFailure::Cancelled)
                    }
                    result = provider.ranking_groups() => {
                        if self.active.load(Ordering::SeqCst) {
                            map_group_load(result)
                        } else {
                            failed_group_load(QqMusicRankingLoadFailure::Cancelled)
                        }
                    }
                }
            }
            Err(()) => failed_group_load(QqMusicRankingLoadFailure::CoreUnavailable),
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
pub fn begin_qq_music_ranking_group_load() -> QqMusicRankingGroupLoadHandle {
    QqMusicRankingGroupLoadHandle {
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicRankingTrackPageLoad {
    pub ranking: Option<CatalogRankingSummary>,
    pub offset: u32,
    pub total: u32,
    pub has_more: bool,
    pub tracks: Vec<LibraryTrackSummary>,
    pub failure: Option<QqMusicRankingLoadFailure>,
}

impl fmt::Debug for QqMusicRankingTrackPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRankingTrackPageLoad")
            .field("has_ranking", &self.ranking.is_some())
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("track_count", &self.tracks.len())
            .field("failure", &self.failure)
            .finish()
    }
}

#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicRankingTrackPageLoadHandle {
    provider_id: String,
    opaque_ranking_id: String,
    offset: u32,
    size: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicRankingTrackPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRankingTrackPageLoadHandle")
            .field("provider_id", &self.provider_id)
            .field("opaque_ranking_id", &"[REDACTED]")
            .field("offset", &self.offset)
            .field("size", &self.size)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicRankingTrackPageLoadHandle {
    pub async fn run(&self) -> QqMusicRankingTrackPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_track_load(QqMusicRankingLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_track_load(QqMusicRankingLoadFailure::AlreadyRunning);
        }
        let outcome = match ranking_id(&self.provider_id, &self.opaque_ranking_id) {
            Ok(ranking_id) => match native_qq_music_provider() {
                Ok(provider) => {
                    tokio::select! {
                        () = self.cancelled.notified() => {
                            failed_track_load(QqMusicRankingLoadFailure::Cancelled)
                        }
                        result = provider.ranking_tracks(ranking_id, self.offset, self.size) => {
                            if self.active.load(Ordering::SeqCst) {
                                map_track_load(result)
                            } else {
                                failed_track_load(QqMusicRankingLoadFailure::Cancelled)
                            }
                        }
                    }
                }
                Err(()) => failed_track_load(QqMusicRankingLoadFailure::CoreUnavailable),
            },
            Err(()) => failed_track_load(QqMusicRankingLoadFailure::InvalidResponse),
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
pub fn begin_qq_music_ranking_track_page_load(
    provider_id: String,
    opaque_ranking_id: String,
    offset: u32,
    size: u32,
) -> QqMusicRankingTrackPageLoadHandle {
    QqMusicRankingTrackPageLoadHandle {
        provider_id,
        opaque_ranking_id,
        offset,
        size,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn ranking_id(provider_id: &str, opaque_id: &str) -> Result<music_domain::RankingId, ()> {
    let provider = music_domain::ProviderId::new(provider_id).map_err(|_| ())?;
    music_domain::RankingId::new(provider, opaque_id).map_err(|_| ())
}

fn bridge_ranking_summary(ranking: &music_domain::RankingSummary) -> CatalogRankingSummary {
    CatalogRankingSummary {
        provider_id: ranking.id().provider().to_string(),
        opaque_id: ranking.id().opaque().to_owned(),
        title: ranking.title().to_owned(),
        period: ranking.period().map(str::to_owned),
        artwork_uri: ranking.artwork_uri().map(str::to_owned),
        track_count: ranking.track_count(),
    }
}

fn map_group_load(
    result: Result<Vec<music_domain::RankingGroup>, CatalogError>,
) -> QqMusicRankingGroupLoad {
    match result {
        Ok(groups) => QqMusicRankingGroupLoad {
            groups: groups
                .iter()
                .map(|group| CatalogRankingGroup {
                    title: group.title().to_owned(),
                    rankings: group
                        .rankings()
                        .iter()
                        .map(bridge_ranking_summary)
                        .collect(),
                })
                .collect(),
            failure: None,
        },
        Err(error) => failed_group_load(map_error(error)),
    }
}

fn map_track_load(
    result: Result<music_domain::RankingTracksPage, CatalogError>,
) -> QqMusicRankingTrackPageLoad {
    match result {
        Ok(page) => QqMusicRankingTrackPageLoad {
            ranking: Some(bridge_ranking_summary(page.ranking())),
            offset: page.offset(),
            total: page.total(),
            has_more: page.has_more(),
            tracks: page.tracks().iter().map(bridge_track_summary).collect(),
            failure: None,
        },
        Err(error) => failed_track_load(map_error(error)),
    }
}

const fn failed_group_load(failure: QqMusicRankingLoadFailure) -> QqMusicRankingGroupLoad {
    QqMusicRankingGroupLoad {
        groups: Vec::new(),
        failure: Some(failure),
    }
}

const fn failed_track_load(failure: QqMusicRankingLoadFailure) -> QqMusicRankingTrackPageLoad {
    QqMusicRankingTrackPageLoad {
        ranking: None,
        offset: 0,
        total: 0,
        has_more: false,
        tracks: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_error(error: CatalogError) -> QqMusicRankingLoadFailure {
    match error {
        CatalogError::Network => QqMusicRankingLoadFailure::Network,
        CatalogError::ServiceUnavailable => QqMusicRankingLoadFailure::ServiceUnavailable,
        CatalogError::InvalidResponse => QqMusicRankingLoadFailure::InvalidResponse,
    }
}

#[cfg(test)]
mod tests {
    use music_domain::{
        ProviderId, RankingGroup, RankingId, RankingSummary, RankingTracksPage, TrackId,
        TrackSummary,
    };
    use provider_api::CatalogError;

    use super::{
        QqMusicRankingLoadFailure, begin_qq_music_ranking_group_load,
        begin_qq_music_ranking_track_page_load, map_error, map_group_load, map_track_load,
    };

    fn ranking() -> RankingSummary {
        RankingSummary::new(
            RankingId::new(
                ProviderId::new("qq-music").expect("provider"),
                "ranking:62001",
            )
            .expect("ranking ID"),
            "must-not-leak-ranking",
        )
        .expect("ranking")
        .with_period(Some("private-period".into()))
        .with_track_count(Some(100))
    }

    #[test]
    fn maps_groups_and_track_pages_without_exposing_content() {
        let groups = map_group_load(Ok(vec![
            RankingGroup::new("must-not-leak-group", vec![ranking()]).expect("group"),
        ]));
        assert!(groups.failure.is_none());
        assert_eq!(groups.groups.len(), 1);
        assert_eq!(groups.groups[0].rankings.len(), 1);

        let track = TrackSummary::new(
            TrackId::new(
                ProviderId::new("qq-music").expect("provider"),
                "track:41001:0:fixtureMid:-",
            )
            .expect("Track ID"),
            "must-not-leak-track",
            vec!["private-artist".into()],
        )
        .expect("Track");
        let page = map_track_load(Ok(RankingTracksPage::new(
            ranking(),
            30,
            100,
            true,
            vec![track],
        )));
        assert!(page.failure.is_none());
        assert_eq!(page.offset, 30);
        assert_eq!(page.total, 100);
        assert!(page.has_more);
        assert_eq!(page.tracks.len(), 1);
        let debug = format!("{groups:?} {page:?}");
        for private in [
            "must-not-leak-group",
            "must-not-leak-ranking",
            "must-not-leak-track",
            "private-period",
            "private-artist",
            "62001",
            "41001",
        ] {
            assert!(!debug.contains(private));
        }
    }

    #[test]
    fn maps_failures_precisely() {
        assert_eq!(
            map_error(CatalogError::Network),
            QqMusicRankingLoadFailure::Network
        );
        assert_eq!(
            map_error(CatalogError::ServiceUnavailable),
            QqMusicRankingLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_error(CatalogError::InvalidResponse),
            QqMusicRankingLoadFailure::InvalidResponse
        );
    }

    #[tokio::test]
    async fn cancellation_is_exact_terminal_and_identity_is_redacted() {
        let groups = begin_qq_music_ranking_group_load();
        assert!(groups.is_active());
        assert!(groups.cancel());
        assert!(!groups.cancel());
        assert_eq!(
            groups.run().await.failure,
            Some(QqMusicRankingLoadFailure::Cancelled)
        );

        let tracks = begin_qq_music_ranking_track_page_load(
            "qq-music".into(),
            "ranking:62001".into(),
            0,
            30,
        );
        let debug = format!("{tracks:?}");
        assert!(!debug.contains("62001"));
        assert!(tracks.cancel());
        assert!(!tracks.cancel());
        assert_eq!(
            tracks.run().await.failure,
            Some(QqMusicRankingLoadFailure::Cancelled)
        );
    }
}
