//! Small, UI-free provider contracts.

use std::fmt;
use std::future::Future;

use music_domain::{
    AccountSummary, AlbumDetails, AlbumId, AlbumSearchPage, AlbumTracksPage, ArtistAlbumsPage,
    ArtistId, ArtistSearchPage, ArtistTracksPage, AudioQuality, FavoriteAlbumsPage,
    FavoriteArtistsPage, MusicVideo, NewAlbumRegion, NewAlbumReleasesPage, NewSongCategory,
    NewSongCollection, PlaylistId, PlaylistSearchPage, PlaylistSummary, PlaylistTracksPage,
    ProviderId, RadarTrackPage, RankingGroup, RankingId, RankingTracksPage,
    RecommendedPlaylistsPage, ResolvedMediaSource, SynchronizedLyrics, TrackCommentsPage, TrackId,
    TrackSearchPage, TrackSummary,
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
    Comments,
    MusicVideo,
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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RadarRecommendationError {
    AuthenticationRequired,
    CredentialRejected,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Replaced,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DailyRecommendationError {
    AuthenticationRequired,
    CredentialRejected,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Replaced,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PersonalizedPlaylistsError {
    AuthenticationRequired,
    CredentialRejected,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Replaced,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PersonalizedTracksError {
    AuthenticationRequired,
    CredentialRejected,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Replaced,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RelatedTracksError {
    InvalidTrack,
    Network,
    ServiceUnavailable,
    InvalidResponse,
}

impl fmt::Display for RelatedTracksError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::InvalidTrack => "related Tracks require a valid Provider Track",
            Self::Network => "related-Track network request failed",
            Self::ServiceUnavailable => "related Tracks are unavailable",
            Self::InvalidResponse => "related Tracks returned an invalid response",
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for RelatedTracksError {}

impl fmt::Display for PersonalizedTracksError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::AuthenticationRequired => "personalized Tracks require authentication",
            Self::CredentialRejected => "QQ Music rejected the current credential",
            Self::Network => "personalized-Track network request failed",
            Self::ServiceUnavailable => "personalized Tracks are unavailable",
            Self::InvalidResponse => "personalized Tracks returned an invalid response",
            Self::Replaced => "the authenticated account changed during personalized-Track loading",
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for PersonalizedTracksError {}

impl fmt::Display for PersonalizedPlaylistsError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::AuthenticationRequired => "personalized playlists require authentication",
            Self::CredentialRejected => "QQ Music rejected the current credential",
            Self::Network => "personalized-playlist network request failed",
            Self::ServiceUnavailable => "personalized playlists are unavailable",
            Self::InvalidResponse => "personalized playlists returned an invalid response",
            Self::Replaced => {
                "the authenticated account changed during personalized-playlist loading"
            }
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for PersonalizedPlaylistsError {}

impl fmt::Display for DailyRecommendationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::AuthenticationRequired => "Daily recommendations require authentication",
            Self::CredentialRejected => "QQ Music rejected the current credential",
            Self::Network => "Daily recommendation network request failed",
            Self::ServiceUnavailable => "Daily recommendations are unavailable",
            Self::InvalidResponse => "Daily recommendations returned an invalid response",
            Self::Replaced => {
                "the authenticated account changed during Daily recommendation loading"
            }
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for DailyRecommendationError {}

impl fmt::Display for RadarRecommendationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::AuthenticationRequired => "Radar recommendations require authentication",
            Self::CredentialRejected => "QQ Music rejected the current credential",
            Self::Network => "Radar recommendation network request failed",
            Self::ServiceUnavailable => "Radar recommendations are unavailable",
            Self::InvalidResponse => "Radar recommendations returned an invalid response",
            Self::Replaced => "the authenticated account changed during Radar loading",
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for RadarRecommendationError {}

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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CommentsError {
    Network,
    ServiceUnavailable,
    InvalidResponse,
}

impl fmt::Display for CommentsError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::Network => "comment network request failed",
            Self::ServiceUnavailable => "comments are unavailable",
            Self::InvalidResponse => "comment service returned an invalid response",
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for CommentsError {}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MusicVideoError {
    Network,
    ServiceUnavailable,
    InvalidResponse,
    SourceUnavailable,
}

impl fmt::Display for MusicVideoError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::Network => "music video network request failed",
            Self::ServiceUnavailable => "music video service is unavailable",
            Self::InvalidResponse => "music video service returned an invalid response",
            Self::SourceUnavailable => "music video has no supported playable source",
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for MusicVideoError {}

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

/// Provider-neutral Playlist search. Query ranking and page continuation
/// remain owned by the concrete Provider.
pub trait PlaylistSearchProvider: MusicProvider + Sync {
    type Error;

    fn search_playlists(
        &self,
        query: String,
        page: u32,
        size: u32,
    ) -> impl Future<Output = Result<PlaylistSearchPage, Self::Error>> + Send;
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

/// Provider-neutral canonical metadata for one Album. Track paging and Album
/// mutation remain separate capabilities.
pub trait AlbumDetailsProvider: MusicProvider + Sync {
    type Error;

    fn album_details(
        &self,
        album_id: AlbumId,
    ) -> impl Future<Output = Result<AlbumDetails, Self::Error>> + Send;
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

/// Provider-neutral offset-paged regional new Album releases. Editorial Home
/// cards, notifications, and Album mutation are separate capabilities.
pub trait NewAlbumReleasesProvider: MusicProvider + Sync {
    type Error;

    fn new_album_releases(
        &self,
        region: NewAlbumRegion,
        offset: u32,
        size: u32,
    ) -> impl Future<Output = Result<NewAlbumReleasesPage, Self::Error>> + Send;
}

/// Provider-neutral bounded whole-response new-song categories. Editorial
/// Home shelves, personalization, radio, and invented pagination are separate.
pub trait NewSongsProvider: MusicProvider + Sync {
    type Error;

    fn new_songs(
        &self,
        category: NewSongCategory,
    ) -> impl Future<Output = Result<NewSongCollection, Self::Error>> + Send;
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

/// Provider-neutral authenticated daily recommendation entry. The Provider
/// owns source-specific feed selection and may return no entry when the
/// account is not offered a daily recommendation.
pub trait DailyRecommendationProvider: MusicProvider + Sync {
    type Error;

    fn daily_recommendation(
        &self,
    ) -> impl Future<Output = Result<Option<PlaylistSummary>, Self::Error>> + Send;
}

/// Provider-neutral authenticated personalized playlist summaries. Source
/// feed layout, tracking fields, and product presentation stay outside this
/// capability.
pub trait PersonalizedPlaylistsProvider: MusicProvider + Sync {
    type Error;

    fn personalized_playlists(
        &self,
    ) -> impl Future<Output = Result<Vec<PlaylistSummary>, Self::Error>> + Send;
}

/// Provider-neutral authenticated bounded personalized Track summaries.
/// Radio identity, feedback, continuation, and product presentation remain
/// Provider or future-product concerns.
pub trait PersonalizedTracksProvider: MusicProvider + Sync {
    type Error;

    fn personalized_tracks(
        &self,
    ) -> impl Future<Output = Result<Vec<TrackSummary>, Self::Error>> + Send;
}

/// Provider-neutral bounded Tracks related to one exact seed Track. The
/// Provider owns source identity parsing; presentation owns section wording.
pub trait RelatedTracksProvider: MusicProvider + Sync {
    type Error;

    fn related_tracks(
        &self,
        seed: TrackId,
    ) -> impl Future<Output = Result<Vec<TrackSummary>, Self::Error>> + Send;
}

/// Provider-neutral page-numbered QQ-native Radar Track recommendations.
/// Personalization inputs and service continuation stay with the Provider.
pub trait RadarRecommendationsProvider: MusicProvider + Sync {
    type Error;

    fn radar_tracks(
        &self,
        page: u32,
    ) -> impl Future<Output = Result<RadarTrackPage, Self::Error>> + Send;
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

/// Provider-neutral offset-paged read-only comments for one Track. The owning
/// Provider keeps opaque Track parsing and source-specific hot/new pagination
/// behind this boundary; comment mutation remains a separate capability.
pub trait TrackCommentsProvider: MusicProvider + Sync {
    type Error;

    fn track_comments(
        &self,
        track_id: TrackId,
        offset: u32,
        size: u32,
    ) -> impl Future<Output = Result<TrackCommentsPage, Self::Error>> + Send;
}

/// Provider-neutral lookup of the exact music video associated with one
/// Track. `Ok(None)` is a truthful no-MV result, distinct from failures and
/// from an MV whose source is unavailable.
pub trait TrackMusicVideoProvider: MusicProvider + Sync {
    type Error;

    fn track_music_video(
        &self,
        track_id: TrackId,
    ) -> impl Future<Output = Result<Option<MusicVideo>, Self::Error>> + Send;
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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QrAuthenticationChannel {
    Qq,
    Wechat,
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
        channel: QrAuthenticationChannel,
    ) -> impl Future<Output = Result<Self::Session, Self::Error>> + Send;
    fn has_authenticated_credential(&self) -> bool;
    fn sign_out(&self);
}

/// Provider-neutral presentation of one account exposed by a trusted desktop
/// client's local quick-login service. `selection_id` is attempt-local and
/// opaque; no provider account identifier crosses this contract.
#[derive(Clone, Eq, PartialEq)]
pub struct DesktopQuickAuthenticationAccount {
    selection_id: u32,
    display_name: String,
    account_hint: String,
}

impl DesktopQuickAuthenticationAccount {
    #[must_use]
    pub const fn new(selection_id: u32, display_name: String, account_hint: String) -> Self {
        Self {
            selection_id,
            display_name,
            account_hint,
        }
    }

    #[must_use]
    pub const fn selection_id(&self) -> u32 {
        self.selection_id
    }

    #[must_use]
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    #[must_use]
    pub fn account_hint(&self) -> &str {
        &self.account_hint
    }
}

impl fmt::Debug for DesktopQuickAuthenticationAccount {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("DesktopQuickAuthenticationAccount")
            .field("selection_id", &self.selection_id)
            .field("display_name", &"[REDACTED]")
            .field("account_hint", &"[REDACTED]")
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DesktopQuickAuthenticationError {
    ClientUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    InvalidSelection,
    Rejected,
    Cancelled,
    Replaced,
    SessionFinished,
    AlreadyRunning,
}

impl fmt::Display for DesktopQuickAuthenticationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::ClientUnavailable => "desktop authorization client is unavailable",
            Self::Network => "desktop authorization network request failed",
            Self::ServiceUnavailable => "desktop authorization service is unavailable",
            Self::InvalidResponse => "desktop authorization returned an invalid response",
            Self::InvalidSelection => "desktop authorization account choice is invalid",
            Self::Rejected => "desktop authorization was rejected",
            Self::Cancelled => "desktop authorization was cancelled",
            Self::Replaced => "desktop authorization was replaced",
            Self::SessionFinished => "desktop authorization session has finished",
            Self::AlreadyRunning => "desktop authorization is already running",
        })
    }
}

impl std::error::Error for DesktopQuickAuthenticationError {}

pub trait DesktopQuickAuthenticationSession: Send {
    fn accounts(&self) -> Vec<DesktopQuickAuthenticationAccount>;

    fn authorize(
        &mut self,
        selection_id: u32,
    ) -> impl Future<Output = Result<(), DesktopQuickAuthenticationError>> + Send;
}

/// Optional desktop-client quick authorization implemented only by eligible
/// providers. Discovery remains an explicit user-visible login action.
pub trait DesktopQuickAuthenticationProvider: MusicProvider + Sync {
    type Session: DesktopQuickAuthenticationSession;

    fn begin_desktop_quick_authentication(
        &self,
    ) -> impl Future<Output = Result<Self::Session, DesktopQuickAuthenticationError>> + Send;
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AccountSummaryError {
    AuthenticationRequired,
    CredentialRejected,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Replaced,
}

impl fmt::Display for AccountSummaryError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::AuthenticationRequired => "account summary requires authentication",
            Self::CredentialRejected => "account-summary credential was rejected",
            Self::Network => "account-summary network request failed",
            Self::ServiceUnavailable => "account summary is unavailable",
            Self::InvalidResponse => "account summary returned an invalid response",
            Self::Replaced => "the authenticated account changed during account-summary loading",
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for AccountSummaryError {}

/// Provider-neutral public identity for the exact currently authenticated
/// account. Credentials and provider account identifiers remain private to
/// the concrete Provider.
pub trait AccountSummaryProvider: MusicProvider + Sync {
    type Error;

    fn account_summary(&self) -> impl Future<Output = Result<AccountSummary, Self::Error>> + Send;
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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryMutationError {
    AuthenticationRequired,
    CredentialRejected,
    /// The request may have reached QQ Music, so the desired remote state must
    /// be refreshed before presenting a definitive result.
    NetworkOutcomeUnknown,
    ServiceUnavailable,
    InvalidRequest,
    InvalidResponseOutcomeUnknown,
    /// The write belonged to an older account generation; its remote outcome
    /// may be unknown and must never be applied to the replacement account UI.
    Replaced,
}

impl fmt::Display for LibraryMutationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::AuthenticationRequired => "library mutation requires authentication",
            Self::CredentialRejected => "library-mutation credential was rejected",
            Self::NetworkOutcomeUnknown => "library-mutation network outcome is unknown",
            Self::ServiceUnavailable => "library-mutation service is unavailable",
            Self::InvalidRequest => "library-mutation request is invalid",
            Self::InvalidResponseOutcomeUnknown => {
                "library-mutation response is invalid and its remote outcome is unknown"
            }
            Self::Replaced => "library mutation was replaced by newer account state",
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for LibraryMutationError {}

/// Provider-neutral desired membership in the current account's liked-Track
/// collection. The Provider owns source-specific IDs and write semantics.
pub trait TrackLikeMutationProvider: MusicProvider + Sync {
    type Error;

    fn set_track_liked(
        &self,
        track_id: TrackId,
        liked: bool,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send;
}

/// Provider-neutral desired favorite state for one Album. The Provider owns
/// source-specific opaque identity parsing and write semantics.
pub trait AlbumFavoriteMutationProvider: MusicProvider + Sync {
    type Error;

    fn set_album_favorite(
        &self,
        album_id: AlbumId,
        favorite: bool,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send;
}

/// Provider-neutral desired membership of one Track in one owned playlist.
/// The Provider validates its opaque playlist and Track identities and owns
/// source-specific write semantics.
pub trait PlaylistTrackMutationProvider: MusicProvider + Sync {
    type Error;

    fn set_playlist_track_membership(
        &self,
        playlist_id: PlaylistId,
        track_id: TrackId,
        present: bool,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send;
}

/// Provider-neutral creation of one owned playlist. The Provider owns the
/// source-specific write and returns its confirmed opaque playlist identity.
pub trait PlaylistCreationProvider: MusicProvider + Sync {
    type Error;

    fn create_playlist(
        &self,
        name: String,
    ) -> impl Future<Output = Result<PlaylistSummary, Self::Error>> + Send;
}

/// Provider-neutral deletion of exactly one owned playlist. The Provider owns
/// source-specific opaque identity validation and destructive write semantics.
pub trait PlaylistDeletionProvider: MusicProvider + Sync {
    type Error;

    fn delete_playlist(
        &self,
        playlist_id: PlaylistId,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send;
}

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

/// Provider-neutral paged favorite-Album collection for the current account.
/// The Provider owns authentication and source-specific pagination semantics.
pub trait FavoriteAlbumsProvider: MusicProvider + Sync {
    type Error;

    fn favorite_albums(
        &self,
        offset: u32,
        size: u32,
    ) -> impl Future<Output = Result<FavoriteAlbumsPage, Self::Error>> + Send;
}

/// Provider-neutral paged favorite-Artist collection for the current account.
/// The Provider owns authentication and source-specific pagination semantics.
pub trait FavoriteArtistsProvider: MusicProvider + Sync {
    type Error;

    fn favorite_artists(
        &self,
        offset: u32,
        size: u32,
    ) -> impl Future<Output = Result<FavoriteArtistsPage, Self::Error>> + Send;
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

/// One statically assembled source of provider-neutral immediate-playback
/// media. Catalog and account providers do not own this contract: a resolver
/// may share provider-specific client/authentication state internally, but it
/// advertises support and resolves only already-known [`TrackId`] values.
pub trait MediaSourceResolver: Sync {
    fn supports(&self, track_id: &TrackId) -> bool;

    fn resolve_media(
        &self,
        track_id: TrackId,
        preferred_quality: AudioQuality,
    ) -> impl Future<Output = Result<ResolvedMediaSource, MediaResolutionError>> + Send;
}

/// Small in-process routing authority for immediate playback sources.
///
/// The current product deliberately assembles exactly one production resolver.
/// This coordinator still owns the provider-identity support check so generic
/// playback never reaches a catalog provider directly or asks a resolver to
/// interpret another provider's opaque identity.
pub struct MediaSourceCoordinator<R> {
    resolver: R,
}

impl<R> MediaSourceCoordinator<R>
where
    R: MediaSourceResolver,
{
    #[must_use]
    pub const fn new(resolver: R) -> Self {
        Self { resolver }
    }

    /// # Errors
    ///
    /// Returns [`MediaResolutionError::Unavailable`] when the configured
    /// resolver does not support the Track's provider identity, or forwards
    /// the resolver's truthful typed failure.
    pub async fn resolve_media(
        &self,
        track_id: TrackId,
        preferred_quality: AudioQuality,
    ) -> Result<ResolvedMediaSource, MediaResolutionError> {
        if !self.resolver.supports(&track_id) {
            return Err(MediaResolutionError::Unavailable);
        }
        self.resolver
            .resolve_media(track_id, preferred_quality)
            .await
    }
}

#[cfg(test)]
mod tests {
    use std::future::{Future, ready};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::task::{Context, Poll, Waker};

    use super::{
        DesktopQuickAuthenticationAccount, MediaResolutionError, MediaSourceCoordinator,
        MediaSourceResolver, MusicProvider, ProviderCapability, ProviderDescriptor,
        QrAuthenticationChallenge, QrImageFormat,
    };
    use music_domain::{AudioFormat, AudioQuality, ProviderId, ResolvedMediaSource, TrackId};

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

    #[test]
    fn desktop_quick_account_debug_output_redacts_local_identity() {
        let account = DesktopQuickAuthenticationAccount::new(
            2,
            "Private nickname".to_owned(),
            "21••••90".to_owned(),
        );

        let debug = format!("{account:?}");
        assert!(debug.contains("selection_id: 2"));
        assert!(!debug.contains("Private nickname"));
        assert!(!debug.contains("21"));
    }

    struct SyntheticMediaSourceResolver {
        calls: AtomicUsize,
    }

    impl MediaSourceResolver for SyntheticMediaSourceResolver {
        fn supports(&self, track_id: &TrackId) -> bool {
            track_id.provider().as_str() == "synthetic"
        }

        fn resolve_media(
            &self,
            track_id: TrackId,
            preferred_quality: AudioQuality,
        ) -> impl Future<Output = Result<ResolvedMediaSource, MediaResolutionError>> + Send
        {
            self.calls.fetch_add(1, Ordering::SeqCst);
            ready(
                ResolvedMediaSource::new(
                    track_id,
                    "https://audio.example.test/synthetic.mp3",
                    AudioFormat::Mp3,
                    preferred_quality,
                    60,
                )
                .map_err(|_| MediaResolutionError::InvalidResponse),
            )
        }
    }

    #[test]
    fn media_source_coordinator_routes_through_a_non_qq_test_resolver() {
        let coordinator = MediaSourceCoordinator::new(SyntheticMediaSourceResolver {
            calls: AtomicUsize::new(0),
        });
        let synthetic_track = TrackId::new(
            ProviderId::new("synthetic").expect("provider"),
            "opaque-track",
        )
        .expect("track ID");

        let resolved =
            run_ready(coordinator.resolve_media(synthetic_track.clone(), AudioQuality::High))
                .expect("synthetic source");

        assert_eq!(resolved.track_id(), &synthetic_track);
        assert_eq!(resolved.quality(), AudioQuality::High);
        assert_eq!(coordinator.resolver.calls.load(Ordering::SeqCst), 1);

        let unsupported = TrackId::new(
            ProviderId::new("qq-music").expect("provider"),
            "opaque-track",
        )
        .expect("track ID");
        assert_eq!(
            run_ready(coordinator.resolve_media(unsupported, AudioQuality::Standard)),
            Err(MediaResolutionError::Unavailable)
        );
        assert_eq!(coordinator.resolver.calls.load(Ordering::SeqCst), 1);
    }

    fn run_ready<T>(future: impl Future<Output = T>) -> T {
        let mut future = std::pin::pin!(future);
        let mut context = Context::from_waker(Waker::noop());
        match future.as_mut().poll(&mut context) {
            Poll::Ready(value) => value,
            Poll::Pending => panic!("synthetic resolver unexpectedly blocked"),
        }
    }
}
