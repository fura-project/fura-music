use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use provider_api::{
    BuiltInProvider, DailyRecommendationError, DailyRecommendationProvider, DailyTracksProvider,
    PersonalizedPlaylistsError, PersonalizedPlaylistsProvider, PersonalizedTracksError,
    PersonalizedTracksProvider, RadarRecommendationError, RadarRecommendationsProvider,
    RecommendationError, RecommendedPlaylistsProvider, RelatedTracksError, RelatedTracksProvider,
};
use tokio::sync::Notify;

use super::library::{
    LibraryPlaylistSummary, LibraryTrackSummary, bridge_playlist_summary, bridge_track_summary,
};
use super::{authentication::native_qq_music_provider, built_in_provider, with_native_provider};

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
    pub next_offset: u32,
    pub has_more: bool,
    pub omitted_playlist_count: u32,
    pub playlists: Vec<LibraryPlaylistSummary>,
    pub failure: Option<QqMusicRecommendedPlaylistPageLoadFailure>,
}

impl fmt::Debug for QqMusicRecommendedPlaylistPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRecommendedPlaylistPageLoad")
            .field("offset", &self.offset)
            .field("next_offset", &self.next_offset)
            .field("has_more", &self.has_more)
            .field("omitted_playlist_count", &self.omitted_playlist_count)
            .field("playlist_count", &self.playlists.len())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use public recommendation-page load. Ranking and
/// source-specific request fields remain inside the Rust Provider stack.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicRecommendedPlaylistPageLoadHandle {
    provider_id: String,
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
        let outcome = with_native_provider!(
            &self.provider_id,
            |provider| {
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
            },
            failed_load(QqMusicRecommendedPlaylistPageLoadFailure::CoreUnavailable)
        );
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
    provider_id: String,
    offset: u32,
    size: u32,
) -> QqMusicRecommendedPlaylistPageLoadHandle {
    QqMusicRecommendedPlaylistPageLoadHandle {
        provider_id,
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
            next_offset: page.next_offset(),
            has_more: page.has_more(),
            omitted_playlist_count: page.omitted_playlist_count(),
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
        next_offset: 0,
        has_more: false,
        omitted_playlist_count: 0,
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
    pub tracks: Vec<LibraryTrackSummary>,
    pub omitted_track_count: u32,
    pub failure: Option<QqMusicDailyRecommendationLoadFailure>,
}

impl fmt::Debug for QqMusicDailyRecommendationLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicDailyRecommendationLoad")
            .field("has_playlist", &self.playlist.is_some())
            .field("track_count", &self.tracks.len())
            .field("omitted_track_count", &self.omitted_track_count)
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use authenticated Daily 30 summary load. QQ feed
/// selection and credentials remain inside the Rust Provider stack.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicDailyRecommendationLoadHandle {
    provider_id: String,
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
        let outcome = match built_in_provider(&self.provider_id) {
            Ok(BuiltInProvider::QQMusic) => match native_qq_music_provider() {
                Ok(provider) => tokio::select! {
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
                },
                Err(()) => {
                    failed_daily_load(QqMusicDailyRecommendationLoadFailure::CoreUnavailable)
                }
            },
            Ok(BuiltInProvider::NetEaseCloudMusic) => {
                match crate::native_netease::native_netease_provider() {
                    Ok(provider) => tokio::select! {
                        () = self.cancelled.notified() => {
                            failed_daily_load(QqMusicDailyRecommendationLoadFailure::Cancelled)
                        }
                        result = provider.daily_tracks() => {
                            if self.active.load(Ordering::SeqCst) {
                                map_daily_tracks_load(result)
                            } else {
                                failed_daily_load(QqMusicDailyRecommendationLoadFailure::Cancelled)
                            }
                        }
                    },
                    Err(()) => {
                        failed_daily_load(QqMusicDailyRecommendationLoadFailure::CoreUnavailable)
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
pub fn begin_qq_music_daily_recommendation_load(
    provider_id: String,
) -> QqMusicDailyRecommendationLoadHandle {
    QqMusicDailyRecommendationLoadHandle {
        provider_id,
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
            tracks: Vec::new(),
            omitted_track_count: 0,
            failure: None,
        },
        Err(error) => failed_daily_load(map_daily_error(error)),
    }
}

fn map_daily_tracks_load(
    result: Result<music_domain::DailyTracksCollection, DailyRecommendationError>,
) -> QqMusicDailyRecommendationLoad {
    match result {
        Ok(collection) => QqMusicDailyRecommendationLoad {
            playlist: None,
            tracks: collection
                .tracks()
                .iter()
                .map(bridge_track_summary)
                .collect(),
            omitted_track_count: collection.omitted_track_count(),
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
        tracks: Vec::new(),
        omitted_track_count: 0,
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
pub enum QqMusicPersonalizedPlaylistsLoadFailure {
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
pub struct QqMusicPersonalizedPlaylistsLoad {
    pub playlists: Vec<LibraryPlaylistSummary>,
    pub omitted_playlist_count: u32,
    pub failure: Option<QqMusicPersonalizedPlaylistsLoadFailure>,
}

impl fmt::Debug for QqMusicPersonalizedPlaylistsLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicPersonalizedPlaylistsLoad")
            .field("playlist_count", &self.playlists.len())
            .field("omitted_playlist_count", &self.omitted_playlist_count)
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use authenticated personalized-playlist summary
/// load. QQ feed structure and credentials remain in the Rust Provider stack.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicPersonalizedPlaylistsLoadHandle {
    provider_id: String,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicPersonalizedPlaylistsLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicPersonalizedPlaylistsLoadHandle")
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicPersonalizedPlaylistsLoadHandle {
    pub async fn run(&self) -> QqMusicPersonalizedPlaylistsLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_personalized_playlists_load(
                QqMusicPersonalizedPlaylistsLoadFailure::Cancelled,
            );
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_personalized_playlists_load(
                QqMusicPersonalizedPlaylistsLoadFailure::AlreadyRunning,
            );
        }
        let outcome = with_native_provider!(
            &self.provider_id,
            |provider| {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_personalized_playlists_load(
                            QqMusicPersonalizedPlaylistsLoadFailure::Cancelled,
                        )
                    }
                    result = provider.personalized_playlists() => {
                        if self.active.load(Ordering::SeqCst) {
                            map_personalized_playlists_load(result)
                        } else {
                            failed_personalized_playlists_load(
                                QqMusicPersonalizedPlaylistsLoadFailure::Cancelled,
                            )
                        }
                    }
                }
            },
            failed_personalized_playlists_load(
                QqMusicPersonalizedPlaylistsLoadFailure::CoreUnavailable,
            )
        );
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
pub fn begin_qq_music_personalized_playlists_load(
    provider_id: String,
) -> QqMusicPersonalizedPlaylistsLoadHandle {
    QqMusicPersonalizedPlaylistsLoadHandle {
        provider_id,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_personalized_playlists_load(
    result: Result<music_domain::PersonalizedPlaylistsCollection, PersonalizedPlaylistsError>,
) -> QqMusicPersonalizedPlaylistsLoad {
    match result {
        Ok(collection) => QqMusicPersonalizedPlaylistsLoad {
            playlists: collection
                .playlists()
                .iter()
                .map(bridge_playlist_summary)
                .collect(),
            omitted_playlist_count: collection.omitted_playlist_count(),
            failure: None,
        },
        Err(error) => failed_personalized_playlists_load(map_personalized_playlists_error(error)),
    }
}

const fn failed_personalized_playlists_load(
    failure: QqMusicPersonalizedPlaylistsLoadFailure,
) -> QqMusicPersonalizedPlaylistsLoad {
    QqMusicPersonalizedPlaylistsLoad {
        playlists: Vec::new(),
        omitted_playlist_count: 0,
        failure: Some(failure),
    }
}

const fn map_personalized_playlists_error(
    error: PersonalizedPlaylistsError,
) -> QqMusicPersonalizedPlaylistsLoadFailure {
    match error {
        PersonalizedPlaylistsError::AuthenticationRequired => {
            QqMusicPersonalizedPlaylistsLoadFailure::AuthenticationRequired
        }
        PersonalizedPlaylistsError::CredentialRejected => {
            QqMusicPersonalizedPlaylistsLoadFailure::CredentialRejected
        }
        PersonalizedPlaylistsError::Network => QqMusicPersonalizedPlaylistsLoadFailure::Network,
        PersonalizedPlaylistsError::ServiceUnavailable => {
            QqMusicPersonalizedPlaylistsLoadFailure::ServiceUnavailable
        }
        PersonalizedPlaylistsError::InvalidResponse => {
            QqMusicPersonalizedPlaylistsLoadFailure::InvalidResponse
        }
        PersonalizedPlaylistsError::Replaced => QqMusicPersonalizedPlaylistsLoadFailure::Replaced,
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicPersonalizedTracksLoadFailure {
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
pub struct QqMusicPersonalizedTracksLoad {
    pub tracks: Vec<LibraryTrackSummary>,
    pub omitted_track_count: u32,
    pub failure: Option<QqMusicPersonalizedTracksLoadFailure>,
}

impl fmt::Debug for QqMusicPersonalizedTracksLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicPersonalizedTracksLoad")
            .field("track_count", &self.tracks.len())
            .field("omitted_track_count", &self.omitted_track_count)
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use authenticated personalized-Track summary load.
/// QQ radio identity, request fields, and credentials remain in Rust Core.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicPersonalizedTracksLoadHandle {
    provider_id: String,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicPersonalizedTracksLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicPersonalizedTracksLoadHandle")
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicPersonalizedTracksLoadHandle {
    pub async fn run(&self) -> QqMusicPersonalizedTracksLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_personalized_tracks_load(
                QqMusicPersonalizedTracksLoadFailure::Cancelled,
            );
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_personalized_tracks_load(
                QqMusicPersonalizedTracksLoadFailure::AlreadyRunning,
            );
        }
        let outcome = with_native_provider!(
            &self.provider_id,
            |provider| {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_personalized_tracks_load(
                            QqMusicPersonalizedTracksLoadFailure::Cancelled,
                        )
                    }
                    result = provider.personalized_tracks() => {
                        if self.active.load(Ordering::SeqCst) {
                            map_personalized_tracks_load(result)
                        } else {
                            failed_personalized_tracks_load(
                                QqMusicPersonalizedTracksLoadFailure::Cancelled,
                            )
                        }
                    }
                }
            },
            failed_personalized_tracks_load(QqMusicPersonalizedTracksLoadFailure::CoreUnavailable,)
        );
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
pub fn begin_qq_music_personalized_tracks_load(
    provider_id: String,
) -> QqMusicPersonalizedTracksLoadHandle {
    QqMusicPersonalizedTracksLoadHandle {
        provider_id,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_personalized_tracks_load(
    result: Result<music_domain::PersonalizedTracksCollection, PersonalizedTracksError>,
) -> QqMusicPersonalizedTracksLoad {
    match result {
        Ok(collection) => QqMusicPersonalizedTracksLoad {
            tracks: collection
                .tracks()
                .iter()
                .map(bridge_track_summary)
                .collect(),
            omitted_track_count: collection.omitted_track_count(),
            failure: None,
        },
        Err(error) => failed_personalized_tracks_load(map_personalized_tracks_error(error)),
    }
}

const fn failed_personalized_tracks_load(
    failure: QqMusicPersonalizedTracksLoadFailure,
) -> QqMusicPersonalizedTracksLoad {
    QqMusicPersonalizedTracksLoad {
        tracks: Vec::new(),
        omitted_track_count: 0,
        failure: Some(failure),
    }
}

const fn map_personalized_tracks_error(
    error: PersonalizedTracksError,
) -> QqMusicPersonalizedTracksLoadFailure {
    match error {
        PersonalizedTracksError::AuthenticationRequired => {
            QqMusicPersonalizedTracksLoadFailure::AuthenticationRequired
        }
        PersonalizedTracksError::CredentialRejected => {
            QqMusicPersonalizedTracksLoadFailure::CredentialRejected
        }
        PersonalizedTracksError::Network => QqMusicPersonalizedTracksLoadFailure::Network,
        PersonalizedTracksError::ServiceUnavailable => {
            QqMusicPersonalizedTracksLoadFailure::ServiceUnavailable
        }
        PersonalizedTracksError::InvalidResponse => {
            QqMusicPersonalizedTracksLoadFailure::InvalidResponse
        }
        PersonalizedTracksError::Replaced => QqMusicPersonalizedTracksLoadFailure::Replaced,
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicRelatedTracksLoadFailure {
    CoreUnavailable,
    InvalidTrack,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicRelatedTracksLoad {
    pub tracks: Vec<LibraryTrackSummary>,
    pub omitted_track_count: u32,
    pub failure: Option<QqMusicRelatedTracksLoadFailure>,
}

impl fmt::Debug for QqMusicRelatedTracksLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRelatedTracksLoad")
            .field("track_count", &self.tracks.len())
            .field("omitted_track_count", &self.omitted_track_count)
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use seed-Track related recommendation load. QQ
/// identity parsing and protocol fields remain in Rust Core.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicRelatedTracksLoadHandle {
    provider_id: String,
    opaque_id: String,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicRelatedTracksLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRelatedTracksLoadHandle")
            .field("seed", &"[REDACTED]")
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicRelatedTracksLoadHandle {
    pub async fn run(&self) -> QqMusicRelatedTracksLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_related_tracks_load(QqMusicRelatedTracksLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_related_tracks_load(QqMusicRelatedTracksLoadFailure::AlreadyRunning);
        }
        let seed = music_domain::ProviderId::new(self.provider_id.clone())
            .ok()
            .and_then(|provider| music_domain::TrackId::new(provider, self.opaque_id.clone()).ok());
        let outcome = match seed {
            Some(seed) => with_native_provider!(
                &self.provider_id,
                |provider| {
                    tokio::select! {
                        () = self.cancelled.notified() => {
                            failed_related_tracks_load(QqMusicRelatedTracksLoadFailure::Cancelled)
                        }
                        result = provider.related_tracks(seed) => {
                            if self.active.load(Ordering::SeqCst) {
                                map_related_tracks_load(result)
                            } else {
                                failed_related_tracks_load(QqMusicRelatedTracksLoadFailure::Cancelled)
                            }
                        }
                    }
                },
                failed_related_tracks_load(QqMusicRelatedTracksLoadFailure::CoreUnavailable)
            ),
            None => failed_related_tracks_load(QqMusicRelatedTracksLoadFailure::InvalidTrack),
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
pub fn begin_qq_music_related_tracks_load(
    provider_id: String,
    opaque_id: String,
) -> QqMusicRelatedTracksLoadHandle {
    QqMusicRelatedTracksLoadHandle {
        provider_id,
        opaque_id,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_related_tracks_load(
    result: Result<music_domain::RelatedTracksCollection, RelatedTracksError>,
) -> QqMusicRelatedTracksLoad {
    match result {
        Ok(collection) => QqMusicRelatedTracksLoad {
            tracks: collection
                .tracks()
                .iter()
                .map(bridge_track_summary)
                .collect(),
            omitted_track_count: collection.omitted_track_count(),
            failure: None,
        },
        Err(error) => failed_related_tracks_load(map_related_tracks_error(error)),
    }
}

const fn failed_related_tracks_load(
    failure: QqMusicRelatedTracksLoadFailure,
) -> QqMusicRelatedTracksLoad {
    QqMusicRelatedTracksLoad {
        tracks: Vec::new(),
        omitted_track_count: 0,
        failure: Some(failure),
    }
}

const fn map_related_tracks_error(error: RelatedTracksError) -> QqMusicRelatedTracksLoadFailure {
    match error {
        RelatedTracksError::InvalidTrack => QqMusicRelatedTracksLoadFailure::InvalidTrack,
        RelatedTracksError::Network => QqMusicRelatedTracksLoadFailure::Network,
        RelatedTracksError::ServiceUnavailable => {
            QqMusicRelatedTracksLoadFailure::ServiceUnavailable
        }
        RelatedTracksError::InvalidResponse => QqMusicRelatedTracksLoadFailure::InvalidResponse,
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
    pub omitted_track_count: u32,
    pub tracks: Vec<LibraryTrackSummary>,
    pub failure: Option<QqMusicRadarTrackPageLoadFailure>,
}

impl fmt::Debug for QqMusicRadarTrackPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicRadarTrackPageLoad")
            .field("page", &self.page)
            .field("has_more", &self.has_more)
            .field("omitted_track_count", &self.omitted_track_count)
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
            omitted_track_count: page.omitted_track_count(),
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
        omitted_track_count: 0,
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
    use provider_api::{
        DailyRecommendationError, PersonalizedPlaylistsError, PersonalizedTracksError,
        RadarRecommendationError, RecommendationError, RelatedTracksError,
    };

    use super::{
        QqMusicDailyRecommendationLoadFailure, QqMusicPersonalizedPlaylistsLoadFailure,
        QqMusicPersonalizedTracksLoadFailure, QqMusicRadarTrackPageLoadFailure,
        QqMusicRecommendedPlaylistPageLoadFailure, QqMusicRelatedTracksLoadFailure,
        begin_qq_music_daily_recommendation_load, begin_qq_music_personalized_playlists_load,
        begin_qq_music_personalized_tracks_load, begin_qq_music_radar_track_page_load,
        begin_qq_music_recommended_playlist_page_load, begin_qq_music_related_tracks_load,
        map_daily_error, map_daily_load, map_daily_tracks_load, map_error, map_load,
        map_personalized_playlists_error, map_personalized_playlists_load,
        map_personalized_tracks_error, map_personalized_tracks_load, map_radar_error,
        map_radar_load, map_related_tracks_error, map_related_tracks_load,
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

        let personalized_cases = [
            (
                PersonalizedPlaylistsError::AuthenticationRequired,
                QqMusicPersonalizedPlaylistsLoadFailure::AuthenticationRequired,
            ),
            (
                PersonalizedPlaylistsError::CredentialRejected,
                QqMusicPersonalizedPlaylistsLoadFailure::CredentialRejected,
            ),
            (
                PersonalizedPlaylistsError::Network,
                QqMusicPersonalizedPlaylistsLoadFailure::Network,
            ),
            (
                PersonalizedPlaylistsError::ServiceUnavailable,
                QqMusicPersonalizedPlaylistsLoadFailure::ServiceUnavailable,
            ),
            (
                PersonalizedPlaylistsError::InvalidResponse,
                QqMusicPersonalizedPlaylistsLoadFailure::InvalidResponse,
            ),
            (
                PersonalizedPlaylistsError::Replaced,
                QqMusicPersonalizedPlaylistsLoadFailure::Replaced,
            ),
        ];
        for (source, expected) in personalized_cases {
            assert_eq!(map_personalized_playlists_error(source), expected);
        }

        let personalized_track_cases = [
            (
                PersonalizedTracksError::AuthenticationRequired,
                QqMusicPersonalizedTracksLoadFailure::AuthenticationRequired,
            ),
            (
                PersonalizedTracksError::CredentialRejected,
                QqMusicPersonalizedTracksLoadFailure::CredentialRejected,
            ),
            (
                PersonalizedTracksError::Network,
                QqMusicPersonalizedTracksLoadFailure::Network,
            ),
            (
                PersonalizedTracksError::ServiceUnavailable,
                QqMusicPersonalizedTracksLoadFailure::ServiceUnavailable,
            ),
            (
                PersonalizedTracksError::InvalidResponse,
                QqMusicPersonalizedTracksLoadFailure::InvalidResponse,
            ),
            (
                PersonalizedTracksError::Replaced,
                QqMusicPersonalizedTracksLoadFailure::Replaced,
            ),
        ];
        for (source, expected) in personalized_track_cases {
            assert_eq!(map_personalized_tracks_error(source), expected);
        }

        let related_track_cases = [
            (
                RelatedTracksError::InvalidTrack,
                QqMusicRelatedTracksLoadFailure::InvalidTrack,
            ),
            (
                RelatedTracksError::Network,
                QqMusicRelatedTracksLoadFailure::Network,
            ),
            (
                RelatedTracksError::ServiceUnavailable,
                QqMusicRelatedTracksLoadFailure::ServiceUnavailable,
            ),
            (
                RelatedTracksError::InvalidResponse,
                QqMusicRelatedTracksLoadFailure::InvalidResponse,
            ),
        ];
        for (source, expected) in related_track_cases {
            assert_eq!(map_related_tracks_error(source), expected);
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
    fn maps_netease_daily_tracks_without_fabricating_a_playlist() {
        let track = TrackSummary::new(
            TrackId::new(
                ProviderId::new("netease-cloud-music").expect("provider"),
                "track:private-daily-id",
            )
            .expect("Track ID"),
            "must-not-leak-daily-track",
            vec!["private-daily-artist".into()],
        )
        .expect("Track");
        let mapped =
            map_daily_tracks_load(Ok(music_domain::DailyTracksCollection::new(vec![track], 1)));

        assert!(mapped.failure.is_none());
        assert!(mapped.playlist.is_none());
        assert_eq!(mapped.tracks.len(), 1);
        assert_eq!(mapped.omitted_track_count, 1);
        assert_eq!(mapped.tracks[0].provider_id, "netease-cloud-music");
        let debug = format!("{mapped:?} {:?}", mapped.tracks[0]);
        for private in [
            "must-not-leak-daily-track",
            "private-daily-artist",
            "private-daily-id",
        ] {
            assert!(!debug.contains(private));
        }

        let empty =
            map_daily_tracks_load(Ok(music_domain::DailyTracksCollection::new(Vec::new(), 0)));
        assert!(empty.failure.is_none());
        assert!(empty.playlist.is_none());
        assert!(empty.tracks.is_empty());
    }

    #[test]
    fn maps_personalized_playlists_without_exposing_content() {
        let playlist = PlaylistSummary::new(
            PlaylistId::new(
                ProviderId::new("qq-music").expect("provider"),
                "catalog:91001",
            )
            .expect("Playlist ID"),
            "must-not-leak-personalized",
        )
        .expect("Playlist summary");
        let mapped = map_personalized_playlists_load(Ok(
            music_domain::PersonalizedPlaylistsCollection::new(vec![playlist], 1),
        ));
        assert!(mapped.failure.is_none());
        assert_eq!(mapped.playlists.len(), 1);
        assert_eq!(mapped.omitted_playlist_count, 1);
        let debug = format!("{mapped:?} {:?}", mapped.playlists[0]);
        assert!(!debug.contains("must-not-leak-personalized"));
        assert!(!debug.contains("91001"));

        let empty = map_personalized_playlists_load(Ok(
            music_domain::PersonalizedPlaylistsCollection::new(Vec::new(), 0),
        ));
        assert!(empty.playlists.is_empty());
        assert!(empty.failure.is_none());
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

    #[test]
    fn maps_personalized_tracks_without_exposing_identity_or_content() {
        let track = TrackSummary::new(
            TrackId::new(
                ProviderId::new("qq-music").expect("provider"),
                "track:41001:0:private-mid:-",
            )
            .expect("Track ID"),
            "must-not-leak-personalized-track",
            vec!["private-artist".into()],
        )
        .expect("Track");
        let mapped = map_personalized_tracks_load(Ok(
            music_domain::PersonalizedTracksCollection::new(vec![track], 1),
        ));

        assert!(mapped.failure.is_none());
        assert_eq!(mapped.tracks.len(), 1);
        assert_eq!(mapped.omitted_track_count, 1);
        let debug = format!("{mapped:?} {:?}", mapped.tracks[0]);
        for private in [
            "must-not-leak-personalized-track",
            "private-artist",
            "private-mid",
            "41001",
        ] {
            assert!(!debug.contains(private));
        }

        let empty = map_personalized_tracks_load(Ok(
            music_domain::PersonalizedTracksCollection::new(Vec::new(), 0),
        ));
        assert!(empty.failure.is_none());
        assert!(empty.tracks.is_empty());
    }

    #[test]
    fn maps_related_tracks_without_exposing_identity_or_content() {
        let track = TrackSummary::new(
            TrackId::new(
                ProviderId::new("qq-music").expect("provider"),
                "track:51001:0:private-related-mid:-",
            )
            .expect("Track ID"),
            "must-not-leak-related-track",
            vec!["private-related-artist".into()],
        )
        .expect("Track");
        let mapped = map_related_tracks_load(Ok(music_domain::RelatedTracksCollection::new(
            vec![track],
            1,
        )));

        assert!(mapped.failure.is_none());
        assert_eq!(mapped.tracks.len(), 1);
        assert_eq!(mapped.omitted_track_count, 1);
        let debug = format!("{mapped:?} {:?}", mapped.tracks[0]);
        for private in [
            "must-not-leak-related-track",
            "private-related-artist",
            "private-related-mid",
            "51001",
        ] {
            assert!(!debug.contains(private));
        }

        let empty = map_related_tracks_load(Ok(music_domain::RelatedTracksCollection::new(
            Vec::new(),
            0,
        )));
        assert!(empty.failure.is_none());
        assert!(empty.tracks.is_empty());
    }

    #[tokio::test]
    async fn cancellation_is_exact_and_terminal() {
        let handle = begin_qq_music_recommended_playlist_page_load("qq-music".into(), 0, 20);
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

        let daily = begin_qq_music_daily_recommendation_load("qq-music".into());
        assert!(daily.is_active());
        assert!(daily.cancel());
        assert!(!daily.cancel());
        assert_eq!(
            daily.run().await.failure,
            Some(QqMusicDailyRecommendationLoadFailure::Cancelled)
        );

        let personalized = begin_qq_music_personalized_playlists_load("qq-music".into());
        assert!(personalized.is_active());
        assert!(personalized.cancel());
        assert!(!personalized.cancel());
        assert_eq!(
            personalized.run().await.failure,
            Some(QqMusicPersonalizedPlaylistsLoadFailure::Cancelled)
        );

        let personalized_tracks = begin_qq_music_personalized_tracks_load("qq-music".into());
        assert!(personalized_tracks.is_active());
        assert!(personalized_tracks.cancel());
        assert!(!personalized_tracks.cancel());
        assert_eq!(
            personalized_tracks.run().await.failure,
            Some(QqMusicPersonalizedTracksLoadFailure::Cancelled)
        );

        let related_tracks = begin_qq_music_related_tracks_load(
            "qq-music".to_owned(),
            "track:51001:0:private-related-mid:-".to_owned(),
        );
        assert!(related_tracks.is_active());
        assert!(related_tracks.cancel());
        assert!(!related_tracks.cancel());
        assert_eq!(
            related_tracks.run().await.failure,
            Some(QqMusicRelatedTracksLoadFailure::Cancelled)
        );
    }
}
