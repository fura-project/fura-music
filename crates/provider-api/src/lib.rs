//! Small, UI-free provider contracts.

use std::fmt;
use std::future::Future;

use music_domain::{
    AlbumId, AlbumSearchPage, AlbumTracksPage, ArtistAlbumsPage, ArtistId, ArtistSearchPage,
    ArtistTracksPage, PlaylistId, PlaylistSummary, PlaylistTracksPage, ProviderId, RankingGroup,
    RankingId, RankingTracksPage, RecommendedPlaylistsPage, ResolvedMediaSource,
    SynchronizedLyrics, TrackId, TrackSearchPage,
};

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum ProviderCapability {
    Search,
    Authentication,
    Catalog,
    Recommendations,
    UserLibrary,
    PlaylistMutation,
    Lyrics,
    MediaResolution,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SearchError {
    Network,
    ServiceUnavailable,
    InvalidResponse,
}

impl fmt::Display for SearchError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::Network => "search network request failed",
            Self::ServiceUnavailable => "search service is unavailable",
            Self::InvalidResponse => "search service returned an invalid response",
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for SearchError {}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CatalogError {
    Network,
    ServiceUnavailable,
    InvalidResponse,
}

impl fmt::Display for CatalogError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::Network => "catalog network request failed",
            Self::ServiceUnavailable => "catalog service is unavailable",
            Self::InvalidResponse => "catalog service returned an invalid response",
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for CatalogError {}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RecommendationError {
    Network,
    ServiceUnavailable,
    InvalidResponse,
}

impl fmt::Display for RecommendationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::Network => "recommendation network request failed",
            Self::ServiceUnavailable => "recommendation service is unavailable",
            Self::InvalidResponse => "recommendation service returned an invalid response",
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for RecommendationError {}

/// Provider-neutral Track search. Query ranking and page conversion remain
/// owned by the concrete Provider.
pub trait TrackSearchProvider: MusicProvider + Sync {
    type Error;

    fn search_tracks(
        &self,
        query: String,
        page: u32,
        size: u32,
    ) -> impl Future<Output = Result<TrackSearchPage, Self::Error>> + Send;
}

/// Provider-neutral Artist search. Query ranking and page conversion remain
/// owned by the concrete Provider.
pub trait ArtistSearchProvider: MusicProvider + Sync {
    type Error;

    fn search_artists(
        &self,
        query: String,
        page: u32,
        size: u32,
    ) -> impl Future<Output = Result<ArtistSearchPage, Self::Error>> + Send;
}

/// Provider-neutral Album search. Query ranking and page conversion remain
/// owned by the concrete Provider.
pub trait AlbumSearchProvider: MusicProvider + Sync {
    type Error;

    fn search_albums(
        &self,
        query: String,
        page: u32,
        size: u32,
    ) -> impl Future<Output = Result<AlbumSearchPage, Self::Error>> + Send;
}

/// Provider-neutral offset-paged Album Track browsing. Album metadata and
/// mutation are deliberately separate future capabilities.
pub trait AlbumTracksProvider: MusicProvider + Sync {
    type Error;

    fn album_tracks(
        &self,
        album_id: AlbumId,
        offset: u32,
        size: u32,
    ) -> impl Future<Output = Result<AlbumTracksPage, Self::Error>> + Send;
}

/// Provider-neutral offset-paged Artist Track browsing. Artist details,
/// albums, and mutation are deliberately separate future capabilities.
pub trait ArtistTracksProvider: MusicProvider + Sync {
    type Error;

    fn artist_tracks(
        &self,
        artist_id: ArtistId,
        offset: u32,
        size: u32,
    ) -> impl Future<Output = Result<ArtistTracksPage, Self::Error>> + Send;
}

/// Provider-neutral offset-paged Album browsing for one Artist. Artist
/// biographies, follows, and Album mutation are separate capabilities.
pub trait ArtistAlbumsProvider: MusicProvider + Sync {
    type Error;

    fn artist_albums(
        &self,
        artist_id: ArtistId,
        offset: u32,
        size: u32,
    ) -> impl Future<Output = Result<ArtistAlbumsPage, Self::Error>> + Send;
}

/// Provider-neutral offset-paged playlist recommendations. Personalization,
/// mutation, and heterogeneous home-feed cards are separate capabilities.
pub trait RecommendedPlaylistsProvider: MusicProvider + Sync {
    type Error;

    fn recommended_playlists(
        &self,
        offset: u32,
        size: u32,
    ) -> impl Future<Output = Result<RecommendedPlaylistsPage, Self::Error>> + Send;
}

/// Provider-neutral current-ranking discovery and Track browsing. Historical
/// period selection, ranking mutation, and editorial layout remain separate.
pub trait RankingsProvider: MusicProvider + Sync {
    type Error;

    fn ranking_groups(&self)
    -> impl Future<Output = Result<Vec<RankingGroup>, Self::Error>> + Send;

    fn ranking_tracks(
        &self,
        ranking_id: RankingId,
        offset: u32,
        size: u32,
    ) -> impl Future<Output = Result<RankingTracksPage, Self::Error>> + Send;
}

/// Describes behavior that is implemented now, not planned future behavior.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProviderDescriptor {
    pub id: ProviderId,
    pub display_name: String,
    pub capabilities: Vec<ProviderCapability>,
}

/// Baseline contract shared by every approved provider implementation.
pub trait MusicProvider {
    fn descriptor(&self) -> ProviderDescriptor;
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QrImageFormat {
    Png,
    Jpeg,
}

/// Provider-neutral QR authentication material safe for presentation.
#[derive(Clone, Eq, PartialEq)]
pub struct QrAuthenticationChallenge {
    image_format: QrImageFormat,
    image_bytes: Vec<u8>,
}

impl QrAuthenticationChallenge {
    #[must_use]
    pub const fn new(image_format: QrImageFormat, image_bytes: Vec<u8>) -> Self {
        Self {
            image_format,
            image_bytes,
        }
    }

    #[must_use]
    pub const fn image_format(&self) -> QrImageFormat {
        self.image_format
    }

    #[must_use]
    pub fn image_bytes(&self) -> &[u8] {
        &self.image_bytes
    }
}

impl fmt::Debug for QrAuthenticationChallenge {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QrAuthenticationChallenge")
            .field("image_format", &self.image_format)
            .field(
                "image_bytes",
                &format_args!("[{} bytes]", self.image_bytes.len()),
            )
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QrAuthenticationProgress {
    WaitingForScan,
    ScannedAwaitingConfirmation,
    Authenticated,
    Expired,
    Refused,
    TimedOut,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AuthenticationError {
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Rejected,
    Cancelled,
    Replaced,
    SessionClosed,
    SessionFinished,
    TimedOut,
    TooManyNetworkFailures,
}

impl fmt::Display for AuthenticationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::Network => "authentication network request failed",
            Self::ServiceUnavailable => "authentication service is unavailable",
            Self::InvalidResponse => "authentication service returned an invalid response",
            Self::Rejected => "authentication was rejected by the provider",
            Self::Cancelled => "authentication was cancelled",
            Self::Replaced => "authentication was replaced by a newer attempt",
            Self::SessionClosed => "authentication coordinator was closed",
            Self::SessionFinished => "authentication session has finished",
            Self::TimedOut => "authentication session timed out",
            Self::TooManyNetworkFailures => {
                "authentication stopped after repeated network failures"
            }
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for AuthenticationError {}

/// One provider-owned QR authentication attempt.
pub trait QrAuthenticationSession: Send {
    type Error;

    fn challenge(&self) -> QrAuthenticationChallenge;
    fn is_active(&self) -> bool;
    fn cancel(&self) -> bool;
    fn advance(
        &mut self,
    ) -> impl Future<Output = Result<QrAuthenticationProgress, Self::Error>> + Send;
}

/// Optional QR authentication capability implemented only by eligible providers.
pub trait QrAuthenticationProvider: MusicProvider + Sync {
    type Error;
    type Session: QrAuthenticationSession<Error = Self::Error>;

    fn begin_qr_authentication(
        &self,
    ) -> impl Future<Output = Result<Self::Session, Self::Error>> + Send;
    fn has_authenticated_credential(&self) -> bool;
    fn sign_out(&self);
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum UserLibraryError {
    AuthenticationRequired,
    CredentialRejected,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Replaced,
}

impl fmt::Display for UserLibraryError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::AuthenticationRequired => "user library requires authentication",
            Self::CredentialRejected => "user-library credential was rejected",
            Self::Network => "user-library network request failed",
            Self::ServiceUnavailable => "user-library service is unavailable",
            Self::InvalidResponse => "user-library service returned an invalid response",
            Self::Replaced => "user-library request was replaced by newer account state",
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for UserLibraryError {}

/// Narrow first user-library capability. Favorited playlists deliberately use
/// a separate future operation instead of being implied by this owned list.
pub trait OwnedPlaylistsProvider: MusicProvider + Sync {
    type Error;

    fn owned_playlists(
        &self,
    ) -> impl Future<Output = Result<Vec<PlaylistSummary>, Self::Error>> + Send;
}

/// Complete provider-owned playlist collection for the current user. The
/// implementation owns source-specific pagination and deduplication.
pub trait UserPlaylistsProvider: MusicProvider + Sync {
    type Error;

    fn user_playlists(
        &self,
    ) -> impl Future<Output = Result<Vec<PlaylistSummary>, Self::Error>> + Send;
}

/// Provider-neutral paged playlist-detail capability. The owning provider
/// interprets opaque playlist identity and source-specific continuation rules.
pub trait PlaylistDetailsProvider: MusicProvider + Sync {
    type Error;

    fn playlist_tracks_page(
        &self,
        playlist_id: PlaylistId,
        offset: u32,
        size: u32,
    ) -> impl Future<Output = Result<PlaylistTracksPage, Self::Error>> + Send;
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LyricsError {
    AuthenticationRequired,
    CredentialRejected,
    Unavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Replaced,
}

impl fmt::Display for LyricsError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::AuthenticationRequired => "lyrics require authentication",
            Self::CredentialRejected => "lyric credential was rejected",
            Self::Unavailable => "lyrics are unavailable for the requested track",
            Self::Network => "lyric network request failed",
            Self::ServiceUnavailable => "lyric service is unavailable",
            Self::InvalidResponse => "lyric service returned an invalid response",
            Self::Replaced => "lyric request was replaced by newer account state",
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for LyricsError {}

/// Provider-neutral synchronized lyric capability. The owning provider keeps
/// track identity parsing, protocol decryption, QRC parsing, and auxiliary
/// line alignment behind this boundary.
pub trait LyricsProvider: MusicProvider + Sync {
    type Error;

    fn lyrics(
        &self,
        track_id: TrackId,
    ) -> impl Future<Output = Result<SynchronizedLyrics, Self::Error>> + Send;
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MediaResolutionError {
    AuthenticationRequired,
    CredentialRejected,
    Unavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    CoreUnavailable,
    Replaced,
}

impl fmt::Display for MediaResolutionError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::AuthenticationRequired => "media resolution requires authentication",
            Self::CredentialRejected => "media-resolution credential was rejected",
            Self::Unavailable => "the requested media source is unavailable",
            Self::Network => "media-resolution network request failed",
            Self::ServiceUnavailable => "media-resolution service is unavailable",
            Self::InvalidResponse => "media-resolution service returned an invalid response",
            Self::CoreUnavailable => "media-resolution core support is unavailable",
            Self::Replaced => "media-resolution request was replaced by newer account state",
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for MediaResolutionError {}

/// First provider-neutral media capability. It deliberately resolves only the
/// standard source selected for M1; quality negotiation is added only with
/// evidence and a real product setting.
pub trait MediaResolutionProvider: MusicProvider + Sync {
    type Error;

    fn resolve_standard_media(
        &self,
        track_id: TrackId,
    ) -> impl Future<Output = Result<ResolvedMediaSource, Self::Error>> + Send;
}

#[cfg(test)]
mod tests {
    use super::{
        MusicProvider, ProviderCapability, ProviderDescriptor, QrAuthenticationChallenge,
        QrImageFormat,
    };
    use music_domain::ProviderId;

    struct LibraryOnlyProvider;

    impl MusicProvider for LibraryOnlyProvider {
        fn descriptor(&self) -> ProviderDescriptor {
            ProviderDescriptor {
                id: ProviderId::new("local").expect("static provider id"),
                display_name: "Local".into(),
                capabilities: vec![ProviderCapability::Catalog],
            }
        }
    }

    #[test]
    fn providers_can_truthfully_expose_partial_capabilities() {
        let descriptor = LibraryOnlyProvider.descriptor();
        assert_eq!(descriptor.id.as_str(), "local");
        assert_eq!(descriptor.capabilities, [ProviderCapability::Catalog]);
    }

    #[test]
    fn qr_challenge_debug_output_does_not_dump_image_bytes() {
        let challenge = QrAuthenticationChallenge::new(
            QrImageFormat::Png,
            b"sensitive-binary-fixture".to_vec(),
        );

        let debug = format!("{challenge:?}");
        assert!(debug.contains("24 bytes"));
        assert!(!debug.contains("sensitive"));
    }
}
