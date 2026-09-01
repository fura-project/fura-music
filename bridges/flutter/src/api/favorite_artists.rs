use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use provider_api::{FavoriteArtistsProvider, UserLibraryError};
use tokio::sync::Notify;

use super::artist::{CatalogArtistSummary, bridge_artist_summary};
use super::authentication::native_qq_music_provider;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicFavoriteArtistPageLoadFailure {
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
pub struct QqMusicFavoriteArtistPageLoad {
    pub offset: u32,
    pub total: u32,
    pub has_more: bool,
    pub artists: Vec<CatalogArtistSummary>,
    pub failure: Option<QqMusicFavoriteArtistPageLoadFailure>,
}

impl fmt::Debug for QqMusicFavoriteArtistPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicFavoriteArtistPageLoad")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("artist_count", &self.artists.len())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use authenticated favorite-Artist page load. The
/// handle contains only provider-neutral pagination, never account material.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicFavoriteArtistPageLoadHandle {
    offset: u32,
    size: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicFavoriteArtistPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicFavoriteArtistPageLoadHandle")
            .field("offset", &self.offset)
            .field("size", &self.size)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicFavoriteArtistPageLoadHandle {
    pub async fn run(&self) -> QqMusicFavoriteArtistPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_load(QqMusicFavoriteArtistPageLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_load(QqMusicFavoriteArtistPageLoadFailure::AlreadyRunning);
        }
        let outcome = match native_qq_music_provider() {
            Ok(provider) => {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_load(QqMusicFavoriteArtistPageLoadFailure::Cancelled)
                    }
                    result = provider.favorite_artists(self.offset, self.size) => {
                        if self.active.load(Ordering::SeqCst) {
                            map_load(result)
                        } else {
                            failed_load(QqMusicFavoriteArtistPageLoadFailure::Cancelled)
                        }
                    }
                }
            }
            Err(()) => failed_load(QqMusicFavoriteArtistPageLoadFailure::CoreUnavailable),
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
pub fn begin_qq_music_favorite_artist_page_load(
    offset: u32,
    size: u32,
) -> QqMusicFavoriteArtistPageLoadHandle {
    QqMusicFavoriteArtistPageLoadHandle {
        offset,
        size,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_load(
    result: Result<music_domain::FavoriteArtistsPage, UserLibraryError>,
) -> QqMusicFavoriteArtistPageLoad {
    match result {
        Ok(page) => QqMusicFavoriteArtistPageLoad {
            offset: page.offset(),
            total: page.total(),
            has_more: page.has_more(),
            artists: page.artists().iter().map(bridge_artist_summary).collect(),
            failure: None,
        },
        Err(error) => failed_load(map_error(error)),
    }
}

const fn failed_load(
    failure: QqMusicFavoriteArtistPageLoadFailure,
) -> QqMusicFavoriteArtistPageLoad {
    QqMusicFavoriteArtistPageLoad {
        offset: 0,
        total: 0,
        has_more: false,
        artists: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_error(error: UserLibraryError) -> QqMusicFavoriteArtistPageLoadFailure {
    match error {
        UserLibraryError::AuthenticationRequired => {
            QqMusicFavoriteArtistPageLoadFailure::AuthenticationRequired
        }
        UserLibraryError::CredentialRejected => {
            QqMusicFavoriteArtistPageLoadFailure::CredentialRejected
        }
        UserLibraryError::Network => QqMusicFavoriteArtistPageLoadFailure::Network,
        UserLibraryError::ServiceUnavailable => {
            QqMusicFavoriteArtistPageLoadFailure::ServiceUnavailable
        }
        UserLibraryError::InvalidResponse => QqMusicFavoriteArtistPageLoadFailure::InvalidResponse,
        UserLibraryError::Replaced => QqMusicFavoriteArtistPageLoadFailure::Replaced,
    }
}

#[cfg(test)]
mod tests {
    use music_domain::{ArtistId, ArtistSummary, FavoriteArtistsPage, ProviderId};
    use provider_api::UserLibraryError;

    use super::{
        QqMusicFavoriteArtistPageLoadFailure, begin_qq_music_favorite_artist_page_load, map_error,
        map_load,
    };

    #[test]
    fn maps_artist_page_without_exposing_content_in_diagnostics() {
        let id = ArtistId::new(
            ProviderId::new("qq-music").expect("provider"),
            "artist:-:fixtureArtistMid",
        )
        .expect("Artist ID");
        let artist = ArtistSummary::new(id, "must-not-leak")
            .expect("Artist")
            .with_artwork_uri(Some("https://example.invalid/must-not-leak.jpg".into()));

        let mapped = map_load(Ok(FavoriteArtistsPage::new(20, 21, false, vec![artist])));

        assert_eq!(mapped.offset, 20);
        assert_eq!(mapped.total, 21);
        assert!(!mapped.has_more);
        assert_eq!(mapped.artists.len(), 1);
        assert_eq!(mapped.artists[0].provider_id, "qq-music");
        assert_eq!(mapped.artists[0].opaque_id, "artist:-:fixtureArtistMid");
        assert_eq!(mapped.artists[0].name, "must-not-leak");
        assert_eq!(
            mapped.artists[0].artwork_uri.as_deref(),
            Some("https://example.invalid/must-not-leak.jpg")
        );
        let debug = format!("{mapped:?} {:?}", mapped.artists[0]);
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("fixtureArtistMid"));
        assert!(!debug.contains("example.invalid"));
    }

    #[test]
    fn maps_all_library_failures_precisely() {
        let cases = [
            (
                UserLibraryError::AuthenticationRequired,
                QqMusicFavoriteArtistPageLoadFailure::AuthenticationRequired,
            ),
            (
                UserLibraryError::CredentialRejected,
                QqMusicFavoriteArtistPageLoadFailure::CredentialRejected,
            ),
            (
                UserLibraryError::Network,
                QqMusicFavoriteArtistPageLoadFailure::Network,
            ),
            (
                UserLibraryError::ServiceUnavailable,
                QqMusicFavoriteArtistPageLoadFailure::ServiceUnavailable,
            ),
            (
                UserLibraryError::InvalidResponse,
                QqMusicFavoriteArtistPageLoadFailure::InvalidResponse,
            ),
            (
                UserLibraryError::Replaced,
                QqMusicFavoriteArtistPageLoadFailure::Replaced,
            ),
        ];
        for (input, expected) in cases {
            assert_eq!(map_error(input), expected);
        }
    }

    #[tokio::test]
    async fn cancellation_is_exact_and_terminal() {
        let handle = begin_qq_music_favorite_artist_page_load(0, 20);

        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let result = handle.run().await;
        assert_eq!(
            result.failure,
            Some(QqMusicFavoriteArtistPageLoadFailure::Cancelled)
        );
    }
}
