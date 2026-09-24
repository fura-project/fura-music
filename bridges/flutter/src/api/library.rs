use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use provider_api::{
    PlaylistDetailsProvider, RecentHistoryProvider, UserLibraryError, UserPlaylistsProvider,
};
use tokio::sync::Notify;

use super::album::{CatalogAlbumSummary, bridge_album_summary};
use super::artist::{CatalogArtistSummary, bridge_artist_summary};
use super::with_native_provider;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryPlaylistOwnership {
    Unspecified,
    Owned,
    Saved,
}

#[derive(Clone, Eq, PartialEq)]
pub struct LibraryPlaylistSummary {
    pub provider_id: String,
    pub opaque_id: String,
    pub title: String,
    pub artwork_uri: Option<String>,
    pub track_count: Option<u32>,
    pub is_liked_songs: bool,
    pub ownership: Option<LibraryPlaylistOwnership>,
}

impl fmt::Debug for LibraryPlaylistSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("LibraryPlaylistSummary")
            .field("provider_id", &self.provider_id)
            .field("opaque_id", &"[REDACTED]")
            .field("title", &"[REDACTED]")
            .field("has_artwork", &self.artwork_uri.is_some())
            .field("track_count", &self.track_count)
            .field("is_liked_songs", &self.is_liked_songs)
            .field("ownership", &self.ownership)
            .finish()
    }
}

pub(super) fn bridge_playlist_summary(
    playlist: &music_domain::PlaylistSummary,
) -> LibraryPlaylistSummary {
    LibraryPlaylistSummary {
        provider_id: playlist.id().provider().to_string(),
        opaque_id: playlist.id().opaque().to_owned(),
        title: playlist.title().to_owned(),
        artwork_uri: playlist.artwork_uri().map(str::to_owned),
        track_count: playlist.track_count(),
        is_liked_songs: playlist.purpose() == music_domain::PlaylistPurpose::LikedSongs,
        ownership: Some(match playlist.ownership() {
            music_domain::PlaylistOwnership::Unspecified => LibraryPlaylistOwnership::Unspecified,
            music_domain::PlaylistOwnership::Owned => LibraryPlaylistOwnership::Owned,
            music_domain::PlaylistOwnership::Saved => LibraryPlaylistOwnership::Saved,
        }),
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum UserPlaylistLoadFailure {
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
pub struct UserPlaylistLoad {
    pub playlists: Vec<LibraryPlaylistSummary>,
    pub omitted_playlist_count: u32,
    pub failure: Option<UserPlaylistLoadFailure>,
}

impl fmt::Debug for UserPlaylistLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("UserPlaylistLoad")
            .field("playlist_count", &self.playlists.len())
            .field("omitted_playlist_count", &self.omitted_playlist_count)
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use user-library load. The handle contains no
/// credential or QQ Music protocol identifier.
#[flutter_rust_bridge::frb(opaque)]
pub struct UserPlaylistLoadHandle {
    provider_id: String,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for UserPlaylistLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("UserPlaylistLoadHandle")
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl UserPlaylistLoadHandle {
    pub async fn run(&self) -> UserPlaylistLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_load(UserPlaylistLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_load(UserPlaylistLoadFailure::AlreadyRunning);
        }

        let outcome = with_native_provider!(
            &self.provider_id,
            |provider| {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_load(UserPlaylistLoadFailure::Cancelled)
                    }
                    result = provider.user_playlists() => {
                        if self.active.load(Ordering::SeqCst) {
                            map_load(result)
                        } else {
                            failed_load(UserPlaylistLoadFailure::Cancelled)
                        }
                    }
                }
            },
            failed_load(UserPlaylistLoadFailure::CoreUnavailable)
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
pub fn begin_user_playlist_load(provider_id: String) -> UserPlaylistLoadHandle {
    UserPlaylistLoadHandle {
        provider_id,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_load(
    result: Result<music_domain::UserPlaylistsCollection, UserLibraryError>,
) -> UserPlaylistLoad {
    match result {
        Ok(collection) => UserPlaylistLoad {
            playlists: collection
                .playlists()
                .iter()
                .map(bridge_playlist_summary)
                .collect(),
            omitted_playlist_count: collection.omitted_playlist_count(),
            failure: None,
        },
        Err(error) => failed_load(map_error(error)),
    }
}

const fn failed_load(failure: UserPlaylistLoadFailure) -> UserPlaylistLoad {
    UserPlaylistLoad {
        playlists: Vec::new(),
        omitted_playlist_count: 0,
        failure: Some(failure),
    }
}

const fn map_error(error: UserLibraryError) -> UserPlaylistLoadFailure {
    match error {
        UserLibraryError::AuthenticationRequired => UserPlaylistLoadFailure::AuthenticationRequired,
        UserLibraryError::CredentialRejected => UserPlaylistLoadFailure::CredentialRejected,
        UserLibraryError::Network => UserPlaylistLoadFailure::Network,
        UserLibraryError::ServiceUnavailable => UserPlaylistLoadFailure::ServiceUnavailable,
        UserLibraryError::InvalidResponse => UserPlaylistLoadFailure::InvalidResponse,
        UserLibraryError::Replaced => UserPlaylistLoadFailure::Replaced,
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct LibraryTrackSummary {
    pub provider_id: String,
    pub opaque_id: String,
    pub membership_opaque_id: Option<String>,
    pub title: String,
    pub subtitle: Option<String>,
    pub artist_names: Vec<String>,
    pub artists: Vec<CatalogArtistSummary>,
    pub album_title: Option<String>,
    pub album: Option<CatalogAlbumSummary>,
    pub artwork_uri: Option<String>,
    pub duration_seconds: Option<u32>,
}

impl fmt::Debug for LibraryTrackSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("LibraryTrackSummary")
            .field("provider_id", &self.provider_id)
            .field("opaque_id", &"[REDACTED]")
            .field(
                "has_membership_identity",
                &self.membership_opaque_id.is_some(),
            )
            .field("title", &"[REDACTED]")
            .field("has_subtitle", &self.subtitle.is_some())
            .field("artist_count", &self.artist_names.len())
            .field("artist_identity_count", &self.artists.len())
            .field("has_album_title", &self.album_title.is_some())
            .field("has_album", &self.album.is_some())
            .field("has_artwork", &self.artwork_uri.is_some())
            .field("duration_seconds", &self.duration_seconds)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PlaylistTrackPageLoadFailure {
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
pub struct PlaylistTrackPageLoad {
    pub offset: u32,
    pub next_offset: u32,
    pub total: u32,
    pub total_is_exact: bool,
    pub has_more: bool,
    pub omitted_track_count: u32,
    pub membership_is_exact: bool,
    pub membership_track_opaque_ids: Vec<String>,
    pub tracks: Vec<LibraryTrackSummary>,
    pub failure: Option<PlaylistTrackPageLoadFailure>,
}

impl fmt::Debug for PlaylistTrackPageLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PlaylistTrackPageLoad")
            .field("offset", &self.offset)
            .field("next_offset", &self.next_offset)
            .field("total", &self.total)
            .field("total_is_exact", &self.total_is_exact)
            .field("has_more", &self.has_more)
            .field("omitted_track_count", &self.omitted_track_count)
            .field("membership_is_exact", &self.membership_is_exact)
            .field(
                "membership_track_count",
                &self.membership_track_opaque_ids.len(),
            )
            .field("track_count", &self.tracks.len())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use playlist-track page load. Provider identity is
/// carried for routing but remains opaque to this Bridge lifecycle.
#[flutter_rust_bridge::frb(opaque)]
pub struct PlaylistTrackPageLoadHandle {
    provider_id: String,
    opaque_playlist_id: String,
    offset: u32,
    size: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for PlaylistTrackPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PlaylistTrackPageLoadHandle")
            .field("provider_id", &self.provider_id)
            .field("opaque_playlist_id", &"[REDACTED]")
            .field("offset", &self.offset)
            .field("size", &self.size)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl PlaylistTrackPageLoadHandle {
    pub async fn run(&self) -> PlaylistTrackPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_track_page(PlaylistTrackPageLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_track_page(PlaylistTrackPageLoadFailure::AlreadyRunning);
        }

        let outcome = match domain_playlist_id(&self.provider_id, &self.opaque_playlist_id) {
            Ok(playlist_id) => with_native_provider!(
                &self.provider_id,
                |provider| {
                    tokio::select! {
                        () = self.cancelled.notified() => {
                            failed_track_page(PlaylistTrackPageLoadFailure::Cancelled)
                        }
                        result = provider.playlist_tracks_page(playlist_id, self.offset, self.size) => {
                            if self.active.load(Ordering::SeqCst) {
                                map_track_page_load(result)
                            } else {
                                failed_track_page(PlaylistTrackPageLoadFailure::Cancelled)
                            }
                        }
                    }
                },
                failed_track_page(PlaylistTrackPageLoadFailure::CoreUnavailable)
            ),
            Err(()) => failed_track_page(PlaylistTrackPageLoadFailure::InvalidResponse),
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
pub fn begin_playlist_track_page_load(
    provider_id: String,
    opaque_playlist_id: String,
    offset: u32,
    size: u32,
) -> PlaylistTrackPageLoadHandle {
    PlaylistTrackPageLoadHandle {
        provider_id,
        opaque_playlist_id,
        offset,
        size,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

/// One cancellable, single-use account recent-history page load. Source
/// request details and credentials remain behind the Provider boundary.
#[flutter_rust_bridge::frb(opaque)]
pub struct RecentTrackPageLoadHandle {
    provider_id: String,
    offset: u32,
    size: u32,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for RecentTrackPageLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("RecentTrackPageLoadHandle")
            .field("provider_id", &self.provider_id)
            .field("offset", &self.offset)
            .field("size", &self.size)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl RecentTrackPageLoadHandle {
    pub async fn run(&self) -> PlaylistTrackPageLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_track_page(PlaylistTrackPageLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_track_page(PlaylistTrackPageLoadFailure::AlreadyRunning);
        }

        let outcome = with_native_provider!(
            &self.provider_id,
            |provider| {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_track_page(PlaylistTrackPageLoadFailure::Cancelled)
                    }
                    result = provider.recent_tracks_page(self.offset, self.size) => {
                        if self.active.load(Ordering::SeqCst) {
                            map_track_page_load(result)
                        } else {
                            failed_track_page(PlaylistTrackPageLoadFailure::Cancelled)
                        }
                    }
                }
            },
            failed_track_page(PlaylistTrackPageLoadFailure::CoreUnavailable)
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
pub fn begin_recent_track_page_load(
    provider_id: String,
    offset: u32,
    size: u32,
) -> RecentTrackPageLoadHandle {
    RecentTrackPageLoadHandle {
        provider_id,
        offset,
        size,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn domain_playlist_id(
    provider_id: &str,
    opaque_playlist_id: &str,
) -> Result<music_domain::PlaylistId, ()> {
    let provider = music_domain::ProviderId::new(provider_id).map_err(|_| ())?;
    music_domain::PlaylistId::new(provider, opaque_playlist_id).map_err(|_| ())
}

fn map_track_page_load(
    result: Result<music_domain::PlaylistTracksPage, UserLibraryError>,
) -> PlaylistTrackPageLoad {
    match result {
        Ok(page) => PlaylistTrackPageLoad {
            offset: page.offset(),
            next_offset: page.next_offset(),
            total: page.total(),
            total_is_exact: page.total_is_exact(),
            has_more: page.has_more(),
            omitted_track_count: page.omitted_track_count(),
            membership_is_exact: page.membership_is_exact(),
            membership_track_opaque_ids: page.membership_track_opaque_ids().to_vec(),
            tracks: page.tracks().iter().map(bridge_track_summary).collect(),
            failure: None,
        },
        Err(error) => failed_track_page(map_track_page_error(error)),
    }
}

pub(super) fn bridge_track_summary(track: &music_domain::TrackSummary) -> LibraryTrackSummary {
    LibraryTrackSummary {
        provider_id: track.id().provider().to_string(),
        opaque_id: track.id().opaque().to_owned(),
        membership_opaque_id: Some(track.membership_opaque_id().to_owned()),
        title: track.title().to_owned(),
        subtitle: track.subtitle().map(str::to_owned),
        artist_names: track.artist_names().to_vec(),
        artists: track.artists().iter().map(bridge_artist_summary).collect(),
        album_title: track.album_title().map(str::to_owned),
        album: track.album().map(bridge_album_summary),
        artwork_uri: track.artwork_uri().map(str::to_owned),
        duration_seconds: track.duration_seconds(),
    }
}

pub(super) fn domain_track_summary(
    track: LibraryTrackSummary,
) -> Result<music_domain::TrackSummary, ()> {
    let album = track.album.map(domain_album_summary).transpose()?;
    let artists = track
        .artists
        .into_iter()
        .map(domain_artist_summary)
        .collect::<Result<Vec<_>, _>>()?;
    let provider = music_domain::ProviderId::new(track.provider_id).map_err(|_| ())?;
    if album
        .as_ref()
        .is_some_and(|album| album.id().provider() != &provider)
    {
        return Err(());
    }
    if artists
        .iter()
        .any(|artist| artist.id().provider() != &provider)
    {
        return Err(());
    }
    let id = music_domain::TrackId::new(provider, track.opaque_id).map_err(|_| ())?;
    music_domain::TrackSummary::new(id, track.title, track.artist_names)
        .map(|summary| {
            let summary = match track.membership_opaque_id {
                Some(membership_opaque_id) => {
                    summary.with_membership_opaque_id(membership_opaque_id)
                }
                None => summary,
            };
            summary
                .with_subtitle(track.subtitle)
                .with_artists(artists)
                .with_album_title(track.album_title)
                .with_album(album)
                .with_artwork_uri(track.artwork_uri)
                .with_duration_seconds(track.duration_seconds)
        })
        .map_err(|_| ())
}

fn domain_artist_summary(artist: CatalogArtistSummary) -> Result<music_domain::ArtistSummary, ()> {
    let provider = music_domain::ProviderId::new(artist.provider_id).map_err(|_| ())?;
    let id = music_domain::ArtistId::new(provider, artist.opaque_id).map_err(|_| ())?;
    music_domain::ArtistSummary::new(id, artist.name)
        .map(|summary| summary.with_artwork_uri(artist.artwork_uri))
        .map_err(|_| ())
}

fn domain_album_summary(album: CatalogAlbumSummary) -> Result<music_domain::AlbumSummary, ()> {
    let provider = music_domain::ProviderId::new(album.provider_id).map_err(|_| ())?;
    let id = music_domain::AlbumId::new(provider, album.opaque_id).map_err(|_| ())?;
    music_domain::AlbumSummary::new(id, album.title)
        .map(|summary| summary.with_artwork_uri(album.artwork_uri))
        .map_err(|_| ())
}

const fn failed_track_page(failure: PlaylistTrackPageLoadFailure) -> PlaylistTrackPageLoad {
    PlaylistTrackPageLoad {
        offset: 0,
        next_offset: 0,
        total: 0,
        total_is_exact: true,
        has_more: false,
        omitted_track_count: 0,
        membership_is_exact: false,
        membership_track_opaque_ids: Vec::new(),
        tracks: Vec::new(),
        failure: Some(failure),
    }
}

const fn map_track_page_error(error: UserLibraryError) -> PlaylistTrackPageLoadFailure {
    match error {
        UserLibraryError::AuthenticationRequired => {
            PlaylistTrackPageLoadFailure::AuthenticationRequired
        }
        UserLibraryError::CredentialRejected => PlaylistTrackPageLoadFailure::CredentialRejected,
        UserLibraryError::Network => PlaylistTrackPageLoadFailure::Network,
        UserLibraryError::ServiceUnavailable => PlaylistTrackPageLoadFailure::ServiceUnavailable,
        UserLibraryError::InvalidResponse => PlaylistTrackPageLoadFailure::InvalidResponse,
        UserLibraryError::Replaced => PlaylistTrackPageLoadFailure::Replaced,
    }
}

#[cfg(test)]
mod tests {
    use music_domain::{
        AlbumId, AlbumSummary, ArtistId, ArtistSummary, PlaylistId, PlaylistOwnership,
        PlaylistPurpose, PlaylistSummary, PlaylistTracksPage, ProviderId, TrackId, TrackSummary,
        UserPlaylistsCollection,
    };
    use provider_api::UserLibraryError;

    use super::{
        PlaylistTrackPageLoadFailure, UserPlaylistLoadFailure, begin_playlist_track_page_load,
        begin_recent_track_page_load, begin_user_playlist_load, map_error, map_load,
        map_track_page_error, map_track_page_load,
    };

    #[test]
    fn maps_domain_summaries_without_exposing_them_in_diagnostics() {
        let id = PlaylistId::new(
            ProviderId::new("qq-music").expect("provider"),
            "owned:7001:201",
        )
        .expect("playlist ID");
        let summary = PlaylistSummary::new(id, "must-not-leak")
            .expect("summary")
            .with_track_count(Some(42))
            .with_purpose(PlaylistPurpose::LikedSongs)
            .with_ownership(PlaylistOwnership::Owned);
        let favorite_id = PlaylistId::new(
            ProviderId::new("qq-music").expect("provider"),
            "favorite:8001",
        )
        .expect("favorite playlist ID");
        let favorite = PlaylistSummary::new(favorite_id, "favorite-must-not-leak")
            .expect("favorite summary")
            .with_ownership(PlaylistOwnership::Saved);

        let mapped = map_load(Ok(UserPlaylistsCollection::new(vec![summary, favorite], 1)));

        assert_eq!(mapped.playlists.len(), 2);
        assert_eq!(mapped.omitted_playlist_count, 1);
        assert_eq!(mapped.playlists[0].provider_id, "qq-music");
        assert_eq!(mapped.playlists[0].opaque_id, "owned:7001:201");
        assert_eq!(mapped.playlists[0].title, "must-not-leak");
        assert!(mapped.playlists[0].is_liked_songs);
        assert_eq!(
            mapped.playlists[0].ownership,
            Some(super::LibraryPlaylistOwnership::Owned)
        );
        assert_eq!(mapped.playlists[1].opaque_id, "favorite:8001");
        assert_eq!(mapped.playlists[1].title, "favorite-must-not-leak");
        assert!(!mapped.playlists[1].is_liked_songs);
        assert_eq!(
            mapped.playlists[1].ownership,
            Some(super::LibraryPlaylistOwnership::Saved)
        );
        assert!(!format!("{mapped:?}").contains("must-not-leak"));
        assert!(!format!("{:?}", mapped.playlists[0]).contains("7001"));
        assert!(!format!("{:?}", mapped.playlists[1]).contains("8001"));
    }

    #[test]
    fn maps_each_provider_failure_precisely() {
        assert_eq!(
            map_error(UserLibraryError::CredentialRejected),
            UserPlaylistLoadFailure::CredentialRejected
        );
        assert_eq!(
            map_error(UserLibraryError::ServiceUnavailable),
            UserPlaylistLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_error(UserLibraryError::Replaced),
            UserPlaylistLoadFailure::Replaced
        );
    }

    #[tokio::test]
    async fn cancellation_is_exact_and_terminal() {
        let handle = begin_user_playlist_load("qq-music".into());

        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let outcome = handle.run().await;
        assert_eq!(outcome.failure, Some(UserPlaylistLoadFailure::Cancelled));
    }

    #[test]
    fn maps_track_pages_without_parsing_opaque_identity_or_logging_content() {
        let track_id = TrackId::new(
            ProviderId::new("qq-music").expect("provider"),
            "track:41001:0:1:opaque-mid",
        )
        .expect("track ID");
        let track = TrackSummary::new(track_id, "must-not-leak", vec!["private-artist".into()])
            .expect("track summary")
            .with_membership_opaque_id("track-membership:41001:0")
            .with_artists(vec![
                ArtistSummary::new(
                    ArtistId::new(
                        ProviderId::new("qq-music").expect("provider"),
                        "artist:42001:private-mid",
                    )
                    .expect("Artist ID"),
                    "private-artist",
                )
                .expect("Artist")
                .with_artwork_uri(Some("https://example.invalid/artist.jpg".into())),
            ])
            .with_album_title(Some("private-album".into()))
            .with_album(Some(
                AlbumSummary::new(
                    AlbumId::new(
                        ProviderId::new("qq-music").expect("provider"),
                        "album:43001:private-mid",
                    )
                    .expect("Album ID"),
                    "private-album",
                )
                .expect("Album"),
            ))
            .with_duration_seconds(Some(245));

        let mapped =
            map_track_page_load(Ok(PlaylistTracksPage::new_with_cursor_and_total_certainty(
                100,
                102,
                103,
                false,
                true,
                1,
                vec![track],
            )));

        assert_eq!(mapped.offset, 100);
        assert_eq!(mapped.next_offset, 102);
        assert_eq!(mapped.total, 103);
        assert!(!mapped.total_is_exact);
        assert!(mapped.has_more);
        assert_eq!(mapped.omitted_track_count, 1);
        assert!(mapped.membership_is_exact);
        assert_eq!(
            mapped.membership_track_opaque_ids,
            ["track-membership:41001:0"]
        );
        assert_eq!(mapped.tracks.len(), 1);
        assert_eq!(mapped.tracks[0].provider_id, "qq-music");
        assert_eq!(mapped.tracks[0].opaque_id, "track:41001:0:1:opaque-mid");
        assert_eq!(
            mapped.tracks[0].membership_opaque_id.as_deref(),
            Some("track-membership:41001:0")
        );
        assert_eq!(mapped.tracks[0].title, "must-not-leak");
        assert_eq!(mapped.tracks[0].artist_names, ["private-artist"]);
        assert_eq!(mapped.tracks[0].artists.len(), 1);
        assert_eq!(
            mapped.tracks[0].artists[0].artwork_uri.as_deref(),
            Some("https://example.invalid/artist.jpg")
        );
        assert_eq!(
            mapped.tracks[0].artists[0].opaque_id,
            "artist:42001:private-mid"
        );
        assert_eq!(
            mapped.tracks[0].album.as_ref().expect("Album").opaque_id,
            "album:43001:private-mid"
        );
        let debug = format!("{mapped:?} {:?}", mapped.tracks[0]);
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("41001"));
        assert!(!debug.contains("private-artist"));
        assert!(!debug.contains("42001"));
        assert!(!debug.contains("private-mid"));
        assert!(!debug.contains("example.invalid"));
    }

    #[test]
    fn maps_track_page_failures_precisely() {
        assert_eq!(
            map_track_page_error(UserLibraryError::CredentialRejected),
            PlaylistTrackPageLoadFailure::CredentialRejected
        );
        assert_eq!(
            map_track_page_error(UserLibraryError::ServiceUnavailable),
            PlaylistTrackPageLoadFailure::ServiceUnavailable
        );
        assert_eq!(
            map_track_page_error(UserLibraryError::Replaced),
            PlaylistTrackPageLoadFailure::Replaced
        );
    }

    #[tokio::test]
    async fn track_page_cancellation_is_exact_and_terminal() {
        let handle =
            begin_playlist_track_page_load("qq-music".into(), "favorite:8001".into(), 0, 100);

        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let outcome = handle.run().await;
        assert_eq!(
            outcome.failure,
            Some(PlaylistTrackPageLoadFailure::Cancelled)
        );
        assert!(!format!("{handle:?}").contains("8001"));
    }

    #[tokio::test]
    async fn recent_page_cancellation_is_exact_and_terminal() {
        let handle = begin_recent_track_page_load("qq-music".into(), 100, 100);

        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let outcome = handle.run().await;
        assert_eq!(
            outcome.failure,
            Some(PlaylistTrackPageLoadFailure::Cancelled)
        );
        assert!(!handle.is_active());
    }
}
