use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use provider_api::{FavoriteAlbumsProvider, UserLibraryError};
use tokio::sync::Notify;

use super::album::{CatalogAlbumSummary, bridge_album_summary};
use super::authentication::native_qq_music_provider;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicFavoriteAlbumPageLoadFailure {
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
pub struct QqMusicFavoriteAlbumPageLoad {
    pub offset: u32,
    pub total: u32,
    pub has_more: bool,
    pub albums: Vec<CatalogAlbumSummary>,
    pub failure: Option<QqMusicFavoriteAlbumPageLoadFailure>,
}

impl fmt::Debug for QqMusicFavoriteAlbumPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicFavoriteAlbumPageLoad")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("album_count", &self.albums.len())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use authenticated favorite-Album page load. The
/// handle contains only provider-neutral pagination, never account material.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicFavoriteAlbumPageLoadHandle {
    offset: u32,
    size: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicFavoriteAlbumPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicFavoriteAlbumPageLoadHandle")
            .field("offset", &self.offset)
            .field("size", &self.size)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicFavoriteAlbumPageLoadHandle {
    pub async fn run(&self) -> QqMusicFavoriteAlbumPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_load(QqMusicFavoriteAlbumPageLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_load(QqMusicFavoriteAlbumPageLoadFailure::AlreadyRunning);
        }
        let outcome = match native_qq_music_provider() {
            Ok(provider) => {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_load(QqMusicFavoriteAlbumPageLoadFailure::Cancelled)
                    }
                    result = provider.favorite_albums(self.offset, self.size) => {
                        if self.active.load(Ordering::SeqCst) {
                            map_load(result)
                        } else {
                            failed_load(QqMusicFavoriteAlbumPageLoadFailure::Cancelled)
                        }
                    }
                }
            }
            Err(()) => failed_load(QqMusicFavoriteAlbumPageLoadFailure::CoreUnavailable),
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
pub fn begin_qq_music_favorite_album_page_load(
    offset: u32,
    size: u32,
) -> QqMusicFavoriteAlbumPageLoadHandle {
    QqMusicFavoriteAlbumPageLoadHandle {
        offset,
        size,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_load(
    result: Result<music_domain::FavoriteAlbumsPage, UserLibraryError>,
) -> QqMusicFavoriteAlbumPageLoad {
    match result {
        Ok(page) => QqMusicFavoriteAlbumPageLoad {
            offset: page.offset(),
            total: page.total(),
            has_more: page.has_more(),
            albums: page.albums().iter().map(bridge_album_summary).collect(),
            failure: None,
        },
        Err(error) => failed_load(map_error(error)),
    }
}

const fn failed_load(failure: QqMusicFavoriteAlbumPageLoadFailure) -> QqMusicFavoriteAlbumPageLoad {
    QqMusicFavoriteAlbumPageLoad {
        offset: 0,
        total: 0,
        has_more: false,
        albums: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_error(error: UserLibraryError) -> QqMusicFavoriteAlbumPageLoadFailure {
    match error {
        UserLibraryError::AuthenticationRequired => {
            QqMusicFavoriteAlbumPageLoadFailure::AuthenticationRequired
        }
        UserLibraryError::CredentialRejected => {
            QqMusicFavoriteAlbumPageLoadFailure::CredentialRejected
        }
        UserLibraryError::Network => QqMusicFavoriteAlbumPageLoadFailure::Network,
        UserLibraryError::ServiceUnavailable => {
            QqMusicFavoriteAlbumPageLoadFailure::ServiceUnavailable
        }
        UserLibraryError::InvalidResponse => QqMusicFavoriteAlbumPageLoadFailure::InvalidResponse,
        UserLibraryError::Replaced => QqMusicFavoriteAlbumPageLoadFailure::Replaced,
    }
}

#[cfg(test)]
mod tests {
    use music_domain::{AlbumId, AlbumSummary, FavoriteAlbumsPage, ProviderId};
    use provider_api::UserLibraryError;

    use super::{
        QqMusicFavoriteAlbumPageLoadFailure, begin_qq_music_favorite_album_page_load, map_error,
        map_load,
    };

    #[test]
    fn maps_album_page_without_exposing_content_in_diagnostics() {
        let id = AlbumId::new(
            ProviderId::new("qq-music").expect("provider"),
            "album:43001:fixtureAlbumMid",
        )
        .expect("Album ID");
        let album = AlbumSummary::new(id, "must-not-leak")
            .expect("Album")
            .with_artwork_uri(Some("https://example.invalid/album.jpg".into()));

        let mapped = map_load(Ok(FavoriteAlbumsPage::new(20, 21, false, vec![album])));

        assert_eq!(mapped.offset, 20);
        assert_eq!(mapped.total, 21);
        assert!(!mapped.has_more);
        assert_eq!(mapped.albums.len(), 1);
        assert_eq!(mapped.albums[0].provider_id, "qq-music");
        assert_eq!(mapped.albums[0].opaque_id, "album:43001:fixtureAlbumMid");
        assert_eq!(mapped.albums[0].title, "must-not-leak");
        let debug = format!("{mapped:?} {:?}", mapped.albums[0]);
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("43001"));
        assert!(!debug.contains("fixtureAlbumMid"));
    }

    #[test]
    fn maps_all_library_failures_precisely() {
        let cases = [
            (
                UserLibraryError::AuthenticationRequired,
                QqMusicFavoriteAlbumPageLoadFailure::AuthenticationRequired,
            ),
            (
                UserLibraryError::CredentialRejected,
                QqMusicFavoriteAlbumPageLoadFailure::CredentialRejected,
            ),
            (
                UserLibraryError::Network,
                QqMusicFavoriteAlbumPageLoadFailure::Network,
            ),
            (
                UserLibraryError::ServiceUnavailable,
                QqMusicFavoriteAlbumPageLoadFailure::ServiceUnavailable,
            ),
            (
                UserLibraryError::InvalidResponse,
                QqMusicFavoriteAlbumPageLoadFailure::InvalidResponse,
            ),
            (
                UserLibraryError::Replaced,
                QqMusicFavoriteAlbumPageLoadFailure::Replaced,
            ),
        ];
        for (input, expected) in cases {
            assert_eq!(map_error(input), expected);
        }
    }

    #[tokio::test]
    async fn cancellation_is_exact_and_terminal() {
        let handle = begin_qq_music_favorite_album_page_load(0, 20);

        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let result = handle.run().await;
        assert_eq!(
            result.failure,
            Some(QqMusicFavoriteAlbumPageLoadFailure::Cancelled)
        );
    }
}
