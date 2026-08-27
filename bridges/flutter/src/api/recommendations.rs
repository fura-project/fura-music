use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use provider_api::{
    DailyRecommendationError, DailyRecommendationProvider, RadarRecommendationError,
    RadarRecommendationsProvider, RecommendationError, RecommendedPlaylistsProvider,
};
use tokio::sync::Notify;

use super::authentication::native_qq_music_provider;
use super::library::{
    LibraryPlaylistSummary, LibraryTrackSummary, bridge_playlist_summary, bridge_track_summary,
};

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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicDailyRecommendationLoadFailure {
    CoreUnavailable,
    AuthenticationRequired,
    CredentialRejected,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Replaced,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicDailyRecommendationLoad {
    pub playlist: Option<LibraryPlaylistSummary>,
    pub failure: Option<QqMusicDailyRecommendationLoadFailure>,
}

impl fmt::Debug for QqMusicDailyRecommendationLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicDailyRecommendationLoad")
            .field("has_playlist", &self.playlist.is_some())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use authenticated Daily 30 summary load. QQ feed
/// selection and credentials remain inside the Rust Provider stack.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicDailyRecommendationLoadHandle {
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicDailyRecommendationLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicDailyRecommendationLoadHandle")
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicDailyRecommendationLoadHandle {
    pub async fn run(&self) -> QqMusicDailyRecommendationLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_daily_load(QqMusicDailyRecommendationLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_daily_load(QqMusicDailyRecommendationLoadFailure::AlreadyRunning);
        }
        let outcome = match native_qq_music_provider() {
            Ok(provider) => {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_daily_load(QqMusicDailyRecommendationLoadFailure::Cancelled)
                    }
                    result = provider.daily_recommendation() => {
                        if self.active.load(Ordering::SeqCst) {
                            map_daily_load(result)
                        } else {
                            failed_daily_load(QqMusicDailyRecommendationLoadFailure::Cancelled)
                        }
                    }
                }
            }
            Err(()) => failed_daily_load(QqMusicDailyRecommendationLoadFailure::CoreUnavailable),
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
pub fn begin_qq_music_daily_recommendation_load() -> QqMusicDailyRecommendationLoadHandle {
    QqMusicDailyRecommendationLoadHandle {
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_daily_load(
    result: Result<Option<music_domain::PlaylistSummary>, DailyRecommendationError>,
) -> QqMusicDailyRecommendationLoad {
    match result {
        Ok(playlist) => QqMusicDailyRecommendationLoad {
            playlist: playlist.as_ref().map(bridge_playlist_summary),
            failure: None,
        },
        Err(error) => failed_daily_load(map_daily_error(error)),
    }
}

const fn failed_daily_load(
    failure: QqMusicDailyRecommendationLoadFailure,
) -> QqMusicDailyRecommendationLoad {
    QqMusicDailyRecommendationLoad {
        playlist: None,
        failure: Some(failure),
    }
}

const fn map_daily_error(error: DailyRecommendationError) -> QqMusicDailyRecommendationLoadFailure {
    match error {
        DailyRecommendationError::AuthenticationRequired => {
            QqMusicDailyRecommendationLoadFailure::AuthenticationRequired
        }
        DailyRecommendationError::CredentialRejected => {
            QqMusicDailyRecommendationLoadFailure::CredentialRejected
        }
        DailyRecommendationError::Network => QqMusicDailyRecommendationLoadFailure::Network,
        DailyRecommendationError::ServiceUnavailable => {
            QqMusicDailyRecommendationLoadFailure::ServiceUnavailable
        }
        DailyRecommendationError::InvalidResponse => {
            QqMusicDailyRecommendationLoadFailure::InvalidResponse
        }
        DailyRecommendationError::Replaced => QqMusicDailyRecommendationLoadFailure::Replaced,
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicRadarTrackPageLoadFailure {
    CoreUnavailable,
    AuthenticationRequired,
    CredentialRejected,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Replaced,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicRadarTrackPageLoad {
    pub page: u32,
    pub has_more: bool,
    pub tracks: Vec<LibraryTrackSummary>,
    pub failure: Option<QqMusicRadarTrackPageLoadFailure>,
}

impl fmt::Debug for QqMusicRadarTrackPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRadarTrackPageLoad")
            .field("page", &self.page)
            .field("has_more", &self.has_more)
            .field("track_count", &self.tracks.len())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use authenticated Radar Track page load. QQ
/// request fields, credentials, and continuation rules remain in Rust Core.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicRadarTrackPageLoadHandle {
    page: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicRadarTrackPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRadarTrackPageLoadHandle")
            .field("page", &self.page)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicRadarTrackPageLoadHandle {
    pub async fn run(&self) -> QqMusicRadarTrackPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_radar_load(QqMusicRadarTrackPageLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_radar_load(QqMusicRadarTrackPageLoadFailure::AlreadyRunning);
        }
        let outcome = match native_qq_music_provider() {
            Ok(provider) => {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_radar_load(QqMusicRadarTrackPageLoadFailure::Cancelled)
                    }
                    result = provider.radar_tracks(self.page) => {
                        if self.active.load(Ordering::SeqCst) {
                            map_radar_load(result)
                        } else {
                            failed_radar_load(QqMusicRadarTrackPageLoadFailure::Cancelled)
                        }
                    }
                }
            }
            Err(()) => failed_radar_load(QqMusicRadarTrackPageLoadFailure::CoreUnavailable),
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
pub fn begin_qq_music_radar_track_page_load(page: u32) -> QqMusicRadarTrackPageLoadHandle {
    QqMusicRadarTrackPageLoadHandle {
        page,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_radar_load(
    result: Result<music_domain::RadarTrackPage, RadarRecommendationError>,
) -> QqMusicRadarTrackPageLoad {
    match result {
        Ok(page) => QqMusicRadarTrackPageLoad {
            page: page.page(),
            has_more: page.has_more(),
            tracks: page.tracks().iter().map(bridge_track_summary).collect(),
            failure: None,
        },
        Err(error) => failed_radar_load(map_radar_error(error)),
    }
}

const fn failed_radar_load(failure: QqMusicRadarTrackPageLoadFailure) -> QqMusicRadarTrackPageLoad {
    QqMusicRadarTrackPageLoad {
        page: 0,
        has_more: false,
        tracks: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_radar_error(error: RadarRecommendationError) -> QqMusicRadarTrackPageLoadFailure {
    match error {
        RadarRecommendationError::AuthenticationRequired => {
            QqMusicRadarTrackPageLoadFailure::AuthenticationRequired
        }
        RadarRecommendationError::CredentialRejected => {
            QqMusicRadarTrackPageLoadFailure::CredentialRejected
        }
        RadarRecommendationError::Network => QqMusicRadarTrackPageLoadFailure::Network,
        RadarRecommendationError::ServiceUnavailable => {
            QqMusicRadarTrackPageLoadFailure::ServiceUnavailable
        }
        RadarRecommendationError::InvalidResponse => {
            QqMusicRadarTrackPageLoadFailure::InvalidResponse
        }
        RadarRecommendationError::Replaced => QqMusicRadarTrackPageLoadFailure::Replaced,
    }
}

#[cfg(test)]
mod tests {
    use music_domain::{
        PlaylistId, PlaylistSummary, ProviderId, RadarTrackPage, RecommendedPlaylistsPage, TrackId,
        TrackSummary,
    };
    use provider_api::{DailyRecommendationError, RadarRecommendationError, RecommendationError};

    use super::{
        QqMusicDailyRecommendationLoadFailure, QqMusicRadarTrackPageLoadFailure,
        QqMusicRecommendedPlaylistPageLoadFailure, begin_qq_music_daily_recommendation_load,
        begin_qq_music_radar_track_page_load, begin_qq_music_recommended_playlist_page_load,
        map_daily_error, map_daily_load, map_error, map_load, map_radar_error, map_radar_load,
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

        let cases = [
            (
                RadarRecommendationError::AuthenticationRequired,
                QqMusicRadarTrackPageLoadFailure::AuthenticationRequired,
            ),
            (
                RadarRecommendationError::CredentialRejected,
                QqMusicRadarTrackPageLoadFailure::CredentialRejected,
            ),
            (
                RadarRecommendationError::Network,
                QqMusicRadarTrackPageLoadFailure::Network,
            ),
            (
                RadarRecommendationError::ServiceUnavailable,
                QqMusicRadarTrackPageLoadFailure::ServiceUnavailable,
            ),
            (
                RadarRecommendationError::InvalidResponse,
                QqMusicRadarTrackPageLoadFailure::InvalidResponse,
            ),
            (
                RadarRecommendationError::Replaced,
                QqMusicRadarTrackPageLoadFailure::Replaced,
            ),
        ];
        for (source, expected) in cases {
            assert_eq!(map_radar_error(source), expected);
        }

        let daily_cases = [
            (
                DailyRecommendationError::AuthenticationRequired,
                QqMusicDailyRecommendationLoadFailure::AuthenticationRequired,
            ),
            (
                DailyRecommendationError::CredentialRejected,
                QqMusicDailyRecommendationLoadFailure::CredentialRejected,
            ),
            (
                DailyRecommendationError::Network,
                QqMusicDailyRecommendationLoadFailure::Network,
            ),
            (
                DailyRecommendationError::ServiceUnavailable,
                QqMusicDailyRecommendationLoadFailure::ServiceUnavailable,
            ),
            (
                DailyRecommendationError::InvalidResponse,
                QqMusicDailyRecommendationLoadFailure::InvalidResponse,
            ),
            (
                DailyRecommendationError::Replaced,
                QqMusicDailyRecommendationLoadFailure::Replaced,
            ),
        ];
        for (source, expected) in daily_cases {
            assert_eq!(map_daily_error(source), expected);
        }
    }

    #[test]
    fn maps_optional_daily_playlist_without_exposing_content() {
        let playlist = PlaylistSummary::new(
            PlaylistId::new(
                ProviderId::new("qq-music").expect("provider"),
                "catalog:7251579717",
            )
            .expect("Playlist ID"),
            "must-not-leak-daily",
        )
        .expect("Playlist summary");
        let mapped = map_daily_load(Ok(Some(playlist)));
        assert!(mapped.failure.is_none());
        assert!(mapped.playlist.is_some());
        let debug = format!(
            "{mapped:?} {:?}",
            mapped.playlist.as_ref().expect("playlist")
        );
        assert!(!debug.contains("must-not-leak-daily"));
        assert!(!debug.contains("7251579717"));

        let absent = map_daily_load(Ok(None));
        assert!(absent.playlist.is_none());
        assert!(absent.failure.is_none());
    }

    #[test]
    fn maps_radar_page_without_exposing_identity_or_content() {
        let track = TrackSummary::new(
            TrackId::new(
                ProviderId::new("qq-music").expect("provider"),
                "track:41001:0:private-mid:-",
            )
            .expect("Track ID"),
            "must-not-leak-track",
            vec!["private-artist".into()],
        )
        .expect("Track");
        let mapped = map_radar_load(Ok(RadarTrackPage::new(2, true, vec![track])));

        assert_eq!(mapped.page, 2);
        assert!(mapped.has_more);
        assert_eq!(mapped.tracks.len(), 1);
        let debug = format!("{mapped:?} {:?}", mapped.tracks[0]);
        for private in [
            "must-not-leak-track",
            "private-artist",
            "private-mid",
            "41001",
        ] {
            assert!(!debug.contains(private));
        }
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

        let radar = begin_qq_music_radar_track_page_load(2);
        assert!(radar.is_active());
        assert!(radar.cancel());
        assert!(!radar.cancel());
        assert_eq!(
            radar.run().await.failure,
            Some(QqMusicRadarTrackPageLoadFailure::Cancelled)
        );

        let daily = begin_qq_music_daily_recommendation_load();
        assert!(daily.is_active());
        assert!(daily.cancel());
        assert!(!daily.cancel());
        assert_eq!(
            daily.run().await.failure,
            Some(QqMusicDailyRecommendationLoadFailure::Cancelled)
        );
    }
}
