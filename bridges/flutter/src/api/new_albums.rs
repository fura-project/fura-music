use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use provider_api::{CatalogError, NewAlbumReleasesProvider};
use tokio::sync::Notify;

use super::album::{CatalogAlbumSummary, bridge_album_summary};
use super::artist::{CatalogArtistSummary, bridge_artist_summary};
use super::authentication::native_qq_music_provider;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicNewAlbumRegion {
    MainlandChina,
    HongKongTaiwan,
    Western,
    Korea,
    Japan,
    Other,
}

#[derive(Clone, Eq, PartialEq)]
pub struct CatalogNewAlbumRelease {
    pub album: CatalogAlbumSummary,
    pub artists: Vec<CatalogArtistSummary>,
    pub release_date: Option<String>,
}

impl fmt::Debug for CatalogNewAlbumRelease {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CatalogNewAlbumRelease")
            .field("album", &self.album)
            .field("artist_count", &self.artists.len())
            .field("has_release_date", &self.release_date.is_some())
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicNewAlbumPageLoadFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicNewAlbumPageLoad {
    pub region: QqMusicNewAlbumRegion,
    pub offset: u32,
    pub total: u32,
    pub has_more: bool,
    pub releases: Vec<CatalogNewAlbumRelease>,
    pub failure: Option<QqMusicNewAlbumPageLoadFailure>,
}

impl fmt::Debug for QqMusicNewAlbumPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicNewAlbumPageLoad")
            .field("region", &self.region)
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("release_count", &self.releases.len())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use regional new-Album page load. QQ area values
/// and pagination remain inside the Rust Provider stack.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicNewAlbumPageLoadHandle {
    region: QqMusicNewAlbumRegion,
    offset: u32,
    size: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicNewAlbumPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicNewAlbumPageLoadHandle")
            .field("region", &self.region)
            .field("offset", &self.offset)
            .field("size", &self.size)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicNewAlbumPageLoadHandle {
    pub async fn run(&self) -> QqMusicNewAlbumPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_load(self.region, QqMusicNewAlbumPageLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_load(self.region, QqMusicNewAlbumPageLoadFailure::AlreadyRunning);
        }
        let outcome = match native_qq_music_provider() {
            Ok(provider) => {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_load(self.region, QqMusicNewAlbumPageLoadFailure::Cancelled)
                    }
                    result = provider.new_album_releases(
                        domain_region(self.region),
                        self.offset,
                        self.size,
                    ) => {
                        if self.active.load(Ordering::SeqCst) {
                            map_load(result, self.region)
                        } else {
                            failed_load(self.region, QqMusicNewAlbumPageLoadFailure::Cancelled)
                        }
                    }
                }
            }
            Err(()) => failed_load(self.region, QqMusicNewAlbumPageLoadFailure::CoreUnavailable),
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
pub fn begin_qq_music_new_album_page_load(
    region: QqMusicNewAlbumRegion,
    offset: u32,
    size: u32,
) -> QqMusicNewAlbumPageLoadHandle {
    QqMusicNewAlbumPageLoadHandle {
        region,
        offset,
        size,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

const fn domain_region(region: QqMusicNewAlbumRegion) -> music_domain::NewAlbumRegion {
    match region {
        QqMusicNewAlbumRegion::MainlandChina => music_domain::NewAlbumRegion::MainlandChina,
        QqMusicNewAlbumRegion::HongKongTaiwan => music_domain::NewAlbumRegion::HongKongTaiwan,
        QqMusicNewAlbumRegion::Western => music_domain::NewAlbumRegion::Western,
        QqMusicNewAlbumRegion::Korea => music_domain::NewAlbumRegion::Korea,
        QqMusicNewAlbumRegion::Japan => music_domain::NewAlbumRegion::Japan,
        QqMusicNewAlbumRegion::Other => music_domain::NewAlbumRegion::Other,
    }
}

fn map_load(
    result: Result<music_domain::NewAlbumReleasesPage, CatalogError>,
    requested_region: QqMusicNewAlbumRegion,
) -> QqMusicNewAlbumPageLoad {
    match result {
        Ok(page) => QqMusicNewAlbumPageLoad {
            region: bridge_region(page.region()),
            offset: page.offset(),
            total: page.total(),
            has_more: page.has_more(),
            releases: page
                .releases()
                .iter()
                .map(|release| CatalogNewAlbumRelease {
                    album: bridge_album_summary(release.album()),
                    artists: release
                        .artists()
                        .iter()
                        .map(bridge_artist_summary)
                        .collect(),
                    release_date: release.release_date().map(str::to_owned),
                })
                .collect(),
            failure: None,
        },
        Err(error) => failed_load(requested_region, map_error(error)),
    }
}

const fn bridge_region(region: music_domain::NewAlbumRegion) -> QqMusicNewAlbumRegion {
    match region {
        music_domain::NewAlbumRegion::MainlandChina => QqMusicNewAlbumRegion::MainlandChina,
        music_domain::NewAlbumRegion::HongKongTaiwan => QqMusicNewAlbumRegion::HongKongTaiwan,
        music_domain::NewAlbumRegion::Western => QqMusicNewAlbumRegion::Western,
        music_domain::NewAlbumRegion::Korea => QqMusicNewAlbumRegion::Korea,
        music_domain::NewAlbumRegion::Japan => QqMusicNewAlbumRegion::Japan,
        music_domain::NewAlbumRegion::Other => QqMusicNewAlbumRegion::Other,
    }
}

const fn failed_load(
    region: QqMusicNewAlbumRegion,
    failure: QqMusicNewAlbumPageLoadFailure,
) -> QqMusicNewAlbumPageLoad {
    QqMusicNewAlbumPageLoad {
        region,
        offset: 0,
        total: 0,
        has_more: false,
        releases: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_error(error: CatalogError) -> QqMusicNewAlbumPageLoadFailure {
    match error {
        CatalogError::Network => QqMusicNewAlbumPageLoadFailure::Network,
        CatalogError::ServiceUnavailable => QqMusicNewAlbumPageLoadFailure::ServiceUnavailable,
        CatalogError::InvalidResponse => QqMusicNewAlbumPageLoadFailure::InvalidResponse,
    }
}

#[cfg(test)]
mod tests {
    use music_domain::{
        AlbumId, AlbumSummary, ArtistId, ArtistSummary, NewAlbumRegion, NewAlbumRelease,
        NewAlbumReleasesPage, ProviderId,
    };
    use provider_api::CatalogError;

    use super::{
        QqMusicNewAlbumPageLoadFailure, QqMusicNewAlbumRegion, begin_qq_music_new_album_page_load,
        map_error, map_load,
    };

    #[test]
    fn maps_new_album_page_without_exposing_identity_or_content() {
        let provider = ProviderId::new("qq-music").expect("provider");
        let album = AlbumSummary::new(
            AlbumId::new(provider.clone(), "album:43001:private-mid").expect("Album ID"),
            "must-not-leak-album",
        )
        .expect("Album");
        let artist = ArtistSummary::new(
            ArtistId::new(provider, "artist:42001:private-artist-mid").expect("Artist ID"),
            "must-not-leak-artist",
        )
        .expect("Artist");
        let mapped = map_load(
            Ok(NewAlbumReleasesPage::new(
                NewAlbumRegion::Japan,
                5,
                11,
                true,
                vec![NewAlbumRelease::new(
                    album,
                    vec![artist],
                    Some("2026-08-26".into()),
                )],
            )),
            QqMusicNewAlbumRegion::Japan,
        );

        assert_eq!(mapped.region, QqMusicNewAlbumRegion::Japan);
        assert_eq!(mapped.offset, 5);
        assert_eq!(mapped.total, 11);
        assert!(mapped.has_more);
        assert_eq!(mapped.releases.len(), 1);
        assert_eq!(mapped.releases[0].artists.len(), 1);
        assert_eq!(
            mapped.releases[0].release_date.as_deref(),
            Some("2026-08-26")
        );
        let debug = format!("{mapped:?} {:?}", mapped.releases[0]);
        for private in [
            "must-not-leak",
            "private-mid",
            "42001",
            "43001",
            "2026-08-26",
        ] {
            assert!(!debug.contains(private));
        }
    }

    #[test]
    fn maps_catalog_failures_precisely() {
        assert_eq!(
            map_error(CatalogError::Network),
            QqMusicNewAlbumPageLoadFailure::Network
        );
        assert_eq!(
            map_error(CatalogError::ServiceUnavailable),
            QqMusicNewAlbumPageLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_error(CatalogError::InvalidResponse),
            QqMusicNewAlbumPageLoadFailure::InvalidResponse
        );
    }

    #[tokio::test]
    async fn cancellation_is_exact_and_terminal() {
        let handle = begin_qq_music_new_album_page_load(QqMusicNewAlbumRegion::Western, 0, 20);
        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let result = handle.run().await;
        assert_eq!(result.region, QqMusicNewAlbumRegion::Western);
        assert_eq!(
            result.failure,
            Some(QqMusicNewAlbumPageLoadFailure::Cancelled)
        );
    }
}
