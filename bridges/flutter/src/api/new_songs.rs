use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use provider_api::{CatalogError, NewSongsProvider};
use tokio::sync::Notify;

use super::authentication::native_qq_music_provider;
use super::library::{LibraryTrackSummary, bridge_track_summary};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicNewSongCategory {
    MainlandChina,
    Western,
    Japan,
    Korea,
    Latest,
    HongKongTaiwan,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicNewSongsLoadFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicNewSongsLoad {
    pub category: QqMusicNewSongCategory,
    pub tracks: Vec<LibraryTrackSummary>,
    pub failure: Option<QqMusicNewSongsLoadFailure>,
}

impl fmt::Debug for QqMusicNewSongsLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicNewSongsLoad")
            .field("category", &self.category)
            .field("track_count", &self.tracks.len())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use public new-song load. QQ request category
/// values and response validation remain inside the Rust Provider stack.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicNewSongsLoadHandle {
    category: QqMusicNewSongCategory,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicNewSongsLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicNewSongsLoadHandle")
            .field("category", &self.category)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicNewSongsLoadHandle {
    pub async fn run(&self) -> QqMusicNewSongsLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_load(self.category, QqMusicNewSongsLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_load(self.category, QqMusicNewSongsLoadFailure::AlreadyRunning);
        }
        let outcome = match native_qq_music_provider() {
            Ok(provider) => {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_load(self.category, QqMusicNewSongsLoadFailure::Cancelled)
                    }
                    result = provider.new_songs(domain_category(self.category)) => {
                        if self.active.load(Ordering::SeqCst) {
                            map_load(result, self.category)
                        } else {
                            failed_load(self.category, QqMusicNewSongsLoadFailure::Cancelled)
                        }
                    }
                }
            }
            Err(()) => failed_load(self.category, QqMusicNewSongsLoadFailure::CoreUnavailable),
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
pub fn begin_qq_music_new_songs_load(
    category: QqMusicNewSongCategory,
) -> QqMusicNewSongsLoadHandle {
    QqMusicNewSongsLoadHandle {
        category,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

const fn domain_category(category: QqMusicNewSongCategory) -> music_domain::NewSongCategory {
    match category {
        QqMusicNewSongCategory::MainlandChina => music_domain::NewSongCategory::MainlandChina,
        QqMusicNewSongCategory::Western => music_domain::NewSongCategory::Western,
        QqMusicNewSongCategory::Japan => music_domain::NewSongCategory::Japan,
        QqMusicNewSongCategory::Korea => music_domain::NewSongCategory::Korea,
        QqMusicNewSongCategory::Latest => music_domain::NewSongCategory::Latest,
        QqMusicNewSongCategory::HongKongTaiwan => music_domain::NewSongCategory::HongKongTaiwan,
    }
}

const fn bridge_category(category: music_domain::NewSongCategory) -> QqMusicNewSongCategory {
    match category {
        music_domain::NewSongCategory::MainlandChina => QqMusicNewSongCategory::MainlandChina,
        music_domain::NewSongCategory::Western => QqMusicNewSongCategory::Western,
        music_domain::NewSongCategory::Japan => QqMusicNewSongCategory::Japan,
        music_domain::NewSongCategory::Korea => QqMusicNewSongCategory::Korea,
        music_domain::NewSongCategory::Latest => QqMusicNewSongCategory::Latest,
        music_domain::NewSongCategory::HongKongTaiwan => QqMusicNewSongCategory::HongKongTaiwan,
    }
}

fn map_load(
    result: Result<music_domain::NewSongCollection, CatalogError>,
    requested_category: QqMusicNewSongCategory,
) -> QqMusicNewSongsLoad {
    match result {
        Ok(collection) => QqMusicNewSongsLoad {
            category: bridge_category(collection.category()),
            tracks: collection
                .tracks()
                .iter()
                .map(bridge_track_summary)
                .collect(),
            failure: None,
        },
        Err(error) => failed_load(requested_category, map_error(error)),
    }
}

const fn failed_load(
    category: QqMusicNewSongCategory,
    failure: QqMusicNewSongsLoadFailure,
) -> QqMusicNewSongsLoad {
    QqMusicNewSongsLoad {
        category,
        tracks: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_error(error: CatalogError) -> QqMusicNewSongsLoadFailure {
    match error {
        CatalogError::Network => QqMusicNewSongsLoadFailure::Network,
        CatalogError::ServiceUnavailable => QqMusicNewSongsLoadFailure::ServiceUnavailable,
        CatalogError::InvalidResponse => QqMusicNewSongsLoadFailure::InvalidResponse,
    }
}

#[cfg(test)]
mod tests {
    use music_domain::{NewSongCategory, NewSongCollection, ProviderId, TrackId, TrackSummary};
    use provider_api::CatalogError;

    use super::{
        QqMusicNewSongCategory, QqMusicNewSongsLoadFailure, begin_qq_music_new_songs_load,
        map_error, map_load,
    };

    #[test]
    fn maps_new_songs_without_exposing_identity_or_content() {
        let provider = ProviderId::new("qq-music").expect("provider");
        let track = TrackSummary::new(
            TrackId::new(provider, "track:41001:0:private-mid:private-file-mid").expect("Track ID"),
            "must-not-leak-track",
            vec!["must-not-leak-artist".into()],
        )
        .expect("Track");
        let mapped = map_load(
            Ok(NewSongCollection::new(NewSongCategory::Latest, vec![track])),
            QqMusicNewSongCategory::Latest,
        );

        assert_eq!(mapped.category, QqMusicNewSongCategory::Latest);
        assert_eq!(mapped.tracks.len(), 1);
        assert_eq!(mapped.tracks[0].title, "must-not-leak-track");
        let debug = format!("{mapped:?} {:?}", mapped.tracks[0]);
        for private in ["must-not-leak", "private-mid", "41001"] {
            assert!(!debug.contains(private));
        }
    }

    #[test]
    fn maps_catalog_failures_precisely() {
        assert_eq!(
            map_error(CatalogError::Network),
            QqMusicNewSongsLoadFailure::Network
        );
        assert_eq!(
            map_error(CatalogError::ServiceUnavailable),
            QqMusicNewSongsLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_error(CatalogError::InvalidResponse),
            QqMusicNewSongsLoadFailure::InvalidResponse
        );
    }

    #[tokio::test]
    async fn cancellation_is_exact_and_terminal() {
        let handle = begin_qq_music_new_songs_load(QqMusicNewSongCategory::Western);
        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let result = handle.run().await;
        assert_eq!(result.category, QqMusicNewSongCategory::Western);
        assert_eq!(result.failure, Some(QqMusicNewSongsLoadFailure::Cancelled));
    }
}
