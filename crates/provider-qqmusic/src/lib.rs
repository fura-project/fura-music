//! QQ Music provider mapping layer.

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};

use music_domain::{
    AccountSummary, AlbumDetails, AlbumId, AlbumSearchPage, AlbumSummary, AlbumTracksPage,
    ArtistAlbumsPage, ArtistId, ArtistSearchPage, ArtistSummary, ArtistTracksPage, AudioFormat,
    AudioQuality, FavoriteAlbumsPage, FavoriteArtistsPage, MusicVideo, MusicVideoId,
    MusicVideoQuality, MusicVideoSource, NewAlbumRegion, NewAlbumRelease, NewAlbumReleasesPage,
    NewSongCategory, NewSongCollection, PlaylistId, PlaylistOwnership, PlaylistPurpose,
    PlaylistSearchPage, PlaylistSummary, PlaylistTracksPage, ProviderId, RadarTrackPage,
    RankingGroup, RankingId, RankingSummary, RankingTracksPage, RecommendedPlaylistsPage,
    ResolvedMediaSource, SynchronizedLyricLine, SynchronizedLyrics, TimedLyricSegment,
    TrackComment, TrackCommentId, TrackCommentsPage, TrackId, TrackSearchItem, TrackSearchPage,
    TrackSummary,
};
use provider_api::{
    AccountSummaryError, AccountSummaryProvider, AlbumDetailsProvider,
    AlbumFavoriteMutationProvider, AlbumSearchProvider, AlbumTracksProvider, ArtistAlbumsProvider,
    ArtistSearchProvider, ArtistTracksProvider, AuthenticationError, CatalogError, CommentsError,
    DailyRecommendationError, DailyRecommendationProvider, FavoriteAlbumsProvider,
    FavoriteArtistsProvider, LibraryMutationError, LyricsError, LyricsProvider,
    MediaResolutionError, MediaSourceResolver, MusicProvider, MusicVideoError,
    NewAlbumReleasesProvider, NewSongsProvider, OwnedPlaylistsProvider, PersonalizedPlaylistsError,
    PersonalizedPlaylistsProvider, PersonalizedTracksError, PersonalizedTracksProvider,
    PhoneAuthenticationCodeState, PhoneAuthenticationProvider, PhoneAuthenticationSession,
    PlaylistCreationProvider, PlaylistDeletionProvider, PlaylistDetailsProvider,
    PlaylistSearchProvider, PlaylistTrackMutationProvider, ProviderCapability, ProviderDescriptor,
    QrAuthenticationChallenge, QrAuthenticationChannel, QrAuthenticationProgress,
    QrAuthenticationProvider, QrAuthenticationSession, QrImageFormat, RadarRecommendationError,
    RadarRecommendationsProvider, RankingsProvider, RecommendationError,
    RecommendedPlaylistsProvider, RelatedTracksError, RelatedTracksProvider, SearchError,
    TrackCommentsProvider, TrackLikeMutationProvider, TrackMusicVideoProvider, TrackSearchProvider,
    UserLibraryError, UserPlaylistsProvider,
};
use qqmusic_client::{
    Credential, CredentialPersistenceError, CredentialRestorePlan, CredentialVerificationError,
    HttpTransport, PhoneAuthCodeResult, PhoneAuthorizationSession, PhoneLoginError,
    QqMusicAlbumDetailsError, QqMusicAlbumFavoriteError, QqMusicAlbumFavoriteState,
    QqMusicAlbumSearchError, QqMusicAlbumSummary, QqMusicAlbumTracksError,
    QqMusicArtistAlbumsError, QqMusicArtistSearchError, QqMusicArtistTracksError,
    QqMusicAudioQuality, QqMusicClient, QqMusicCreatePlaylistError, QqMusicDailyRecommendation,
    QqMusicDailyRecommendationError, QqMusicDeletePlaylistError, QqMusicFavoriteAlbumsError,
    QqMusicFavoriteArtistsError, QqMusicFavoritePlaylist, QqMusicFavoritePlaylistsError,
    QqMusicLyrics, QqMusicLyricsError, QqMusicMediaError, QqMusicMusicVideoQuality,
    QqMusicNewAlbumArea, QqMusicNewAlbumsError, QqMusicNewSongCategory, QqMusicNewSongsError,
    QqMusicOwnedPlaylist, QqMusicOwnedPlaylistsError, QqMusicPersonalizedPlaylist,
    QqMusicPersonalizedPlaylistsError, QqMusicPersonalizedTracksError, QqMusicPlaylistDetailError,
    QqMusicPlaylistSearchError, QqMusicPlaylistSearchSummary, QqMusicPlaylistTrackError,
    QqMusicPlaylistTrackState, QqMusicRadarError, QqMusicRankingSummary, QqMusicRankingsError,
    QqMusicRecommendedPlaylist, QqMusicRecommendedPlaylistsError, QqMusicRelatedTracksError,
    QqMusicSearchError, QqMusicTrackComment, QqMusicTrackCommentsError, QqMusicTrackLikeState,
    QqMusicTrackMusicVideo, QqMusicTrackMusicVideoError, QqMusicTrackSummary, QqQrError,
    QrImageMediaType, QrLoginChannel, WechatCredentialExchangeError, WechatQrError,
    WechatQrLoginCancellation, WechatQrLoginCoordinator, WechatQrLoginError, WechatQrLoginProgress,
    WechatQrLoginSession,
};

const FAVORITE_PLAYLIST_PAGE_SIZE: u32 = 100;
const MAX_FAVORITE_PLAYLIST_PAGES: usize = 10;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicCredentialRestoreState {
    SignedOut,
    VerificationRequired,
    LocallyExpired,
}

#[derive(Debug, Default)]
enum QqMusicCredentialState {
    #[default]
    SignedOut,
    PendingVerification(Credential),
    LocallyExpired(Credential),
    Authenticated(Credential),
}

#[derive(Debug)]
pub struct QqMusicProvider<T> {
    login: WechatQrLoginCoordinator<T>,
    credential: Arc<Mutex<QqMusicCredentialState>>,
    next_restore_verification: AtomicU32,
    active_restore_verification: Mutex<Option<u32>>,
    next_phone_authentication: AtomicU32,
    active_phone_authentication: Arc<Mutex<Option<u32>>>,
}

/// QQ-owned immediate-playback source edge. It deliberately borrows the
/// catalog/account provider so both responsibilities share one authenticated
/// session without making the provider itself the generic playback router.
#[derive(Clone, Copy)]
pub struct QqMusicMediaSourceResolver<'a, T> {
    provider: &'a QqMusicProvider<T>,
}

impl<T> QqMusicProvider<T> {
    #[must_use]
    pub fn new(client: QqMusicClient<T>) -> Self {
        Self {
            login: WechatQrLoginCoordinator::new(client),
            credential: Arc::new(Mutex::new(QqMusicCredentialState::SignedOut)),
            next_restore_verification: AtomicU32::new(1),
            active_restore_verification: Mutex::new(None),
            next_phone_authentication: AtomicU32::new(1),
            active_phone_authentication: Arc::new(Mutex::new(None)),
        }
    }

    #[must_use]
    pub fn client(&self) -> &QqMusicClient<T> {
        self.login.client()
    }

    #[must_use]
    pub const fn media_source_resolver(&self) -> QqMusicMediaSourceResolver<'_, T> {
        QqMusicMediaSourceResolver { provider: self }
    }

    #[must_use]
    pub fn has_authenticated_credential(&self) -> bool {
        matches!(
            *credential_guard(&self.credential),
            QqMusicCredentialState::Authenticated(_)
        )
    }

    fn authenticated_account_credential(&self) -> Result<Credential, AccountSummaryError> {
        match &*credential_guard(&self.credential) {
            QqMusicCredentialState::Authenticated(credential) => Ok(credential.clone()),
            QqMusicCredentialState::SignedOut
            | QqMusicCredentialState::PendingVerification(_)
            | QqMusicCredentialState::LocallyExpired(_) => {
                Err(AccountSummaryError::AuthenticationRequired)
            }
        }
    }

    fn finish_account_await(
        &self,
        candidate: &Credential,
        rejected: bool,
    ) -> Result<(), AccountSummaryError> {
        let mut state = credential_guard(&self.credential);
        let still_current = matches!(
            &*state,
            QqMusicCredentialState::Authenticated(current) if current == candidate
        );
        if !still_current {
            return Err(AccountSummaryError::Replaced);
        }
        if rejected {
            *state = QqMusicCredentialState::SignedOut;
            return Err(AccountSummaryError::CredentialRejected);
        }
        Ok(())
    }

    fn authenticated_credential(&self) -> Result<Credential, UserLibraryError> {
        match &*credential_guard(&self.credential) {
            QqMusicCredentialState::Authenticated(credential) => Ok(credential.clone()),
            QqMusicCredentialState::SignedOut
            | QqMusicCredentialState::PendingVerification(_)
            | QqMusicCredentialState::LocallyExpired(_) => {
                Err(UserLibraryError::AuthenticationRequired)
            }
        }
    }

    fn finish_library_await(
        &self,
        candidate: &Credential,
        rejected: bool,
    ) -> Result<(), UserLibraryError> {
        let mut state = credential_guard(&self.credential);
        let still_current = matches!(
            &*state,
            QqMusicCredentialState::Authenticated(current) if current == candidate
        );
        if !still_current {
            return Err(UserLibraryError::Replaced);
        }
        if rejected {
            *state = QqMusicCredentialState::SignedOut;
            return Err(UserLibraryError::CredentialRejected);
        }
        Ok(())
    }

    fn media_credential(&self) -> Result<Option<Credential>, MediaResolutionError> {
        match &*credential_guard(&self.credential) {
            QqMusicCredentialState::Authenticated(credential) => Ok(Some(credential.clone())),
            QqMusicCredentialState::SignedOut => Ok(None),
            QqMusicCredentialState::PendingVerification(_)
            | QqMusicCredentialState::LocallyExpired(_) => {
                Err(MediaResolutionError::AuthenticationRequired)
            }
        }
    }

    fn finish_media_await(
        &self,
        candidate: &Credential,
        rejected: bool,
    ) -> Result<(), MediaResolutionError> {
        let mut state = credential_guard(&self.credential);
        let still_current = matches!(
            &*state,
            QqMusicCredentialState::Authenticated(current) if current == candidate
        );
        if !still_current {
            return Err(MediaResolutionError::Replaced);
        }
        if rejected {
            *state = QqMusicCredentialState::SignedOut;
            return Err(MediaResolutionError::CredentialRejected);
        }
        Ok(())
    }

    fn authenticated_lyrics_credential(&self) -> Result<Credential, LyricsError> {
        match &*credential_guard(&self.credential) {
            QqMusicCredentialState::Authenticated(credential) => Ok(credential.clone()),
            QqMusicCredentialState::SignedOut
            | QqMusicCredentialState::PendingVerification(_)
            | QqMusicCredentialState::LocallyExpired(_) => Err(LyricsError::AuthenticationRequired),
        }
    }

    fn finish_lyrics_await(
        &self,
        candidate: &Credential,
        rejected: bool,
    ) -> Result<(), LyricsError> {
        let mut state = credential_guard(&self.credential);
        let still_current = matches!(
            &*state,
            QqMusicCredentialState::Authenticated(current) if current == candidate
        );
        if !still_current {
            return Err(LyricsError::Replaced);
        }
        if rejected {
            *state = QqMusicCredentialState::SignedOut;
            return Err(LyricsError::CredentialRejected);
        }
        Ok(())
    }

    fn authenticated_radar_credential(&self) -> Result<Credential, RadarRecommendationError> {
        match &*credential_guard(&self.credential) {
            QqMusicCredentialState::Authenticated(credential) => Ok(credential.clone()),
            QqMusicCredentialState::SignedOut
            | QqMusicCredentialState::PendingVerification(_)
            | QqMusicCredentialState::LocallyExpired(_) => {
                Err(RadarRecommendationError::AuthenticationRequired)
            }
        }
    }

    fn finish_radar_await(
        &self,
        candidate: &Credential,
        rejected: bool,
    ) -> Result<(), RadarRecommendationError> {
        let mut state = credential_guard(&self.credential);
        let still_current = matches!(
            &*state,
            QqMusicCredentialState::Authenticated(current) if current == candidate
        );
        if !still_current {
            return Err(RadarRecommendationError::Replaced);
        }
        if rejected {
            *state = QqMusicCredentialState::SignedOut;
            return Err(RadarRecommendationError::CredentialRejected);
        }
        Ok(())
    }

    fn authenticated_daily_credential(&self) -> Result<Credential, DailyRecommendationError> {
        match &*credential_guard(&self.credential) {
            QqMusicCredentialState::Authenticated(credential) => Ok(credential.clone()),
            QqMusicCredentialState::SignedOut
            | QqMusicCredentialState::PendingVerification(_)
            | QqMusicCredentialState::LocallyExpired(_) => {
                Err(DailyRecommendationError::AuthenticationRequired)
            }
        }
    }

    fn finish_daily_await(
        &self,
        candidate: &Credential,
        rejected: bool,
    ) -> Result<(), DailyRecommendationError> {
        let mut state = credential_guard(&self.credential);
        let still_current = matches!(
            &*state,
            QqMusicCredentialState::Authenticated(current) if current == candidate
        );
        if !still_current {
            return Err(DailyRecommendationError::Replaced);
        }
        if rejected {
            *state = QqMusicCredentialState::SignedOut;
            return Err(DailyRecommendationError::CredentialRejected);
        }
        Ok(())
    }

    fn authenticated_personalized_playlists_credential(
        &self,
    ) -> Result<Credential, PersonalizedPlaylistsError> {
        match &*credential_guard(&self.credential) {
            QqMusicCredentialState::Authenticated(credential) => Ok(credential.clone()),
            QqMusicCredentialState::SignedOut
            | QqMusicCredentialState::PendingVerification(_)
            | QqMusicCredentialState::LocallyExpired(_) => {
                Err(PersonalizedPlaylistsError::AuthenticationRequired)
            }
        }
    }

    fn finish_personalized_playlists_await(
        &self,
        candidate: &Credential,
        rejected: bool,
    ) -> Result<(), PersonalizedPlaylistsError> {
        let mut state = credential_guard(&self.credential);
        let still_current = matches!(
            &*state,
            QqMusicCredentialState::Authenticated(current) if current == candidate
        );
        if !still_current {
            return Err(PersonalizedPlaylistsError::Replaced);
        }
        if rejected {
            *state = QqMusicCredentialState::SignedOut;
            return Err(PersonalizedPlaylistsError::CredentialRejected);
        }
        Ok(())
    }

    fn authenticated_personalized_tracks_credential(
        &self,
    ) -> Result<Credential, PersonalizedTracksError> {
        match &*credential_guard(&self.credential) {
            QqMusicCredentialState::Authenticated(credential) => Ok(credential.clone()),
            QqMusicCredentialState::SignedOut
            | QqMusicCredentialState::PendingVerification(_)
            | QqMusicCredentialState::LocallyExpired(_) => {
                Err(PersonalizedTracksError::AuthenticationRequired)
            }
        }
    }

    fn finish_personalized_tracks_await(
        &self,
        candidate: &Credential,
        rejected: bool,
    ) -> Result<(), PersonalizedTracksError> {
        let mut state = credential_guard(&self.credential);
        let still_current = matches!(
            &*state,
            QqMusicCredentialState::Authenticated(current) if current == candidate
        );
        if !still_current {
            return Err(PersonalizedTracksError::Replaced);
        }
        if rejected {
            *state = QqMusicCredentialState::SignedOut;
            return Err(PersonalizedTracksError::CredentialRejected);
        }
        Ok(())
    }

    /// Returns a cloned startup candidate for server verification or a future
    /// refresh decision. Authenticated QR credentials are intentionally not
    /// exposed through this restore-only accessor.
    #[must_use]
    pub fn restored_credential(&self) -> Option<(QqMusicCredentialRestoreState, Credential)> {
        match &*credential_guard(&self.credential) {
            QqMusicCredentialState::PendingVerification(credential) => Some((
                QqMusicCredentialRestoreState::VerificationRequired,
                credential.clone(),
            )),
            QqMusicCredentialState::LocallyExpired(credential) => Some((
                QqMusicCredentialRestoreState::LocallyExpired,
                credential.clone(),
            )),
            QqMusicCredentialState::SignedOut | QqMusicCredentialState::Authenticated(_) => None,
        }
    }

    /// Reserves exact cancellation authority for one server-verification
    /// attempt. A newer reservation supersedes the older ID.
    #[must_use]
    pub fn reserve_restored_credential_verification(&self) -> Option<u32> {
        if !matches!(
            *credential_guard(&self.credential),
            QqMusicCredentialState::PendingVerification(_)
        ) {
            return None;
        }
        let attempt_id = self
            .next_restore_verification
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |current| {
                Some(if current == u32::MAX { 1 } else { current + 1 })
            })
            .unwrap_or_else(std::convert::identity);
        *restore_verification_guard(&self.active_restore_verification) = Some(attempt_id);
        Some(attempt_id)
    }

    /// Cancels only the matching verification attempt while retaining the
    /// candidate for an explicit retry.
    #[must_use]
    pub fn cancel_restored_credential_verification(&self, attempt_id: u32) -> bool {
        let mut active = restore_verification_guard(&self.active_restore_verification);
        if *active != Some(attempt_id) {
            return false;
        }
        *active = None;
        true
    }

    /// Cancels the currently creating or active QR generation.
    ///
    /// Higher layers should prefer a generation-specific session cancellation
    /// handle after QR creation completes.
    #[must_use]
    pub fn cancel_active_authentication(&self) -> bool {
        let qr_cancelled = self.login.cancel_active();
        let phone_cancelled = phone_authentication_guard(&self.active_phone_authentication)
            .take()
            .is_some();
        qr_cancelled || phone_cancelled
    }

    /// Cancels local authentication work and removes every retained QQ Music
    /// credential state from this process. Platform-vault cleanup remains the
    /// responsibility of the application edge.
    pub fn sign_out(&self) {
        self.login.cancel_active();
        *phone_authentication_guard(&self.active_phone_authentication) = None;
        let mut credential = credential_guard(&self.credential);
        let mut verification = restore_verification_guard(&self.active_restore_verification);
        *credential = QqMusicCredentialState::SignedOut;
        *verification = None;
    }

    /// Exports the current credential as a short-lived, versioned secret
    /// document for the platform secure-storage adapter.
    ///
    /// # Errors
    ///
    /// Returns a serialization error without exposing credential content.
    pub fn encode_authenticated_credential(
        &self,
    ) -> Result<Option<Vec<u8>>, CredentialPersistenceError> {
        let credential = credential_guard(&self.credential);
        match &*credential {
            QqMusicCredentialState::Authenticated(credential) => {
                credential.encode_for_secure_storage().map(Some)
            }
            QqMusicCredentialState::SignedOut
            | QqMusicCredentialState::PendingVerification(_)
            | QqMusicCredentialState::LocallyExpired(_) => Ok(None),
        }
    }

    /// Loads an optional versioned credential document and classifies the next
    /// action without treating the credential as authenticated.
    ///
    /// # Errors
    ///
    /// Returns a diagnostics-safe persistence error and leaves the previous
    /// in-memory state unchanged when the document is malformed or invalid.
    pub fn restore_credential_from_secure_storage(
        &self,
        secret_bytes: Option<&[u8]>,
        now_unix_seconds: u64,
    ) -> Result<QqMusicCredentialRestoreState, CredentialPersistenceError> {
        let credential = secret_bytes
            .map(Credential::decode_from_secure_storage)
            .transpose()?;
        let plan = CredentialRestorePlan::from_loaded(credential, now_unix_seconds);
        let (state, result) = match plan {
            CredentialRestorePlan::SignedOut => (
                QqMusicCredentialState::SignedOut,
                QqMusicCredentialRestoreState::SignedOut,
            ),
            CredentialRestorePlan::VerifyWithServer(credential) => (
                QqMusicCredentialState::PendingVerification(credential),
                QqMusicCredentialRestoreState::VerificationRequired,
            ),
            CredentialRestorePlan::LocallyExpired(credential) => (
                QqMusicCredentialState::LocallyExpired(credential),
                QqMusicCredentialRestoreState::LocallyExpired,
            ),
        };
        *credential_guard(&self.credential) = state;
        *restore_verification_guard(&self.active_restore_verification) = None;
        Ok(result)
    }
}

impl<T> QqMusicProvider<T>
where
    T: HttpTransport,
{
    /// Verifies the retained startup candidate and promotes it only if no
    /// newer authentication action has superseded that exact credential.
    ///
    /// # Errors
    ///
    /// Keeps credential rejection distinct from transient transport, service,
    /// and response-shape failures. Transient failures retain the candidate for
    /// an explicit retry; a verified rejection clears it.
    pub async fn verify_restored_credential(
        &self,
        attempt_id: u32,
    ) -> Result<(), AuthenticationError> {
        let candidate = {
            let state = credential_guard(&self.credential);
            let active = restore_verification_guard(&self.active_restore_verification);
            let QqMusicCredentialState::PendingVerification(candidate) = &*state else {
                return Err(AuthenticationError::Replaced);
            };
            if *active != Some(attempt_id) {
                return Err(AuthenticationError::Replaced);
            }
            candidate.clone()
        };

        let verification = self.client().verify_credential(&candidate).await;
        let mut state = credential_guard(&self.credential);
        let mut active = restore_verification_guard(&self.active_restore_verification);
        let still_current = *active == Some(attempt_id)
            && matches!(
                &*state,
                QqMusicCredentialState::PendingVerification(current) if current == &candidate
            );
        if !still_current {
            return Err(AuthenticationError::Replaced);
        }
        *active = None;

        match verification {
            Ok(_) => {
                *state = QqMusicCredentialState::Authenticated(candidate);
                Ok(())
            }
            Err(CredentialVerificationError::Rejected { .. }) => {
                *state = QqMusicCredentialState::SignedOut;
                Err(AuthenticationError::Rejected)
            }
            Err(error) => Err(map_verification_error(&error)),
        }
    }
}

impl<T> MusicProvider for QqMusicProvider<T> {
    fn descriptor(&self) -> ProviderDescriptor {
        ProviderDescriptor {
            id: qq_music_provider_id(),
            display_name: "QQ Music".into(),
            capabilities: vec![
                ProviderCapability::Search,
                ProviderCapability::Catalog,
                ProviderCapability::Recommendations,
                ProviderCapability::Authentication,
                ProviderCapability::UserLibrary,
                ProviderCapability::PlaylistMutation,
                ProviderCapability::Lyrics,
                ProviderCapability::Comments,
                ProviderCapability::MusicVideo,
            ],
        }
    }
}

impl<T> TrackSearchProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = SearchError;

    async fn search_tracks(
        &self,
        query: String,
        page: u32,
        size: u32,
    ) -> Result<TrackSearchPage, Self::Error> {
        let response = self.client().search_tracks(&query, page, size).await;
        let page = response.as_ref().map_err(map_search_error)?;
        if page.has_more() && page.tracks().is_empty() {
            return Err(SearchError::InvalidResponse);
        }
        let items = page
            .tracks()
            .iter()
            .map(map_search_item)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|()| SearchError::InvalidResponse)?;
        Ok(TrackSearchPage::new(
            page.page(),
            page.total(),
            page.has_more(),
            items,
        ))
    }
}

impl<T> ArtistSearchProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = SearchError;

    async fn search_artists(
        &self,
        query: String,
        page: u32,
        size: u32,
    ) -> Result<ArtistSearchPage, Self::Error> {
        let response = self.client().search_artists(&query, page, size).await;
        let page = response.as_ref().map_err(map_artist_search_error)?;
        if page.has_more() && page.artists().is_empty() {
            return Err(SearchError::InvalidResponse);
        }
        let artists = page
            .artists()
            .iter()
            .map(map_artist_summary)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|()| SearchError::InvalidResponse)?;
        Ok(ArtistSearchPage::new(
            page.page(),
            page.total(),
            page.has_more(),
            artists,
        ))
    }
}

impl<T> AlbumSearchProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = SearchError;

    async fn search_albums(
        &self,
        query: String,
        page: u32,
        size: u32,
    ) -> Result<AlbumSearchPage, Self::Error> {
        let response = self.client().search_albums(&query, page, size).await;
        let page = response.as_ref().map_err(map_album_search_error)?;
        if page.has_more() && page.albums().is_empty() {
            return Err(SearchError::InvalidResponse);
        }
        let albums = page
            .albums()
            .iter()
            .map(map_album_summary)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|()| SearchError::InvalidResponse)?;
        Ok(AlbumSearchPage::new(
            page.page(),
            page.total(),
            page.has_more(),
            albums,
        ))
    }
}

impl<T> PlaylistSearchProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = SearchError;

    async fn search_playlists(
        &self,
        query: String,
        page: u32,
        size: u32,
    ) -> Result<PlaylistSearchPage, Self::Error> {
        let response = self.client().search_playlists(&query, page, size).await;
        let page = response.as_ref().map_err(map_playlist_search_error)?;
        if page.has_more() && page.playlists().is_empty() {
            return Err(SearchError::InvalidResponse);
        }
        let playlists = page
            .playlists()
            .iter()
            .map(map_playlist_search_summary)
            .collect::<Result<Vec<_>, _>>()?;
        Ok(PlaylistSearchPage::new(
            page.page(),
            page.total(),
            page.has_more(),
            playlists,
        ))
    }
}

impl<T> AlbumTracksProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = CatalogError;

    async fn album_tracks(
        &self,
        requested_id: AlbumId,
        offset: u32,
        size: u32,
    ) -> Result<AlbumTracksPage, Self::Error> {
        let catalog_mid = parse_album_mid(&requested_id)?;
        let response = self.client().album_tracks(catalog_mid, offset, size).await;
        let page = response.as_ref().map_err(map_album_tracks_error)?;
        let tracks = page
            .tracks()
            .iter()
            .map(map_track_summary)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|()| CatalogError::InvalidResponse)?;
        Ok(AlbumTracksPage::new(
            page.offset(),
            page.total(),
            page.has_more(),
            tracks,
        ))
    }
}

impl<T> AlbumDetailsProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = CatalogError;

    async fn album_details(&self, requested_id: AlbumId) -> Result<AlbumDetails, Self::Error> {
        let catalog_mid = parse_album_mid(&requested_id)?;
        let response = self.client().album_details(catalog_mid).await;
        let details = response.as_ref().map_err(map_album_details_error)?;
        let album =
            map_album_summary(details.album()).map_err(|()| CatalogError::InvalidResponse)?;
        let artists = details
            .artists()
            .iter()
            .map(map_artist_summary)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|()| CatalogError::InvalidResponse)?;
        Ok(AlbumDetails::new(album, artists)
            .with_subtitle(details.subtitle().map(str::to_owned))
            .with_release_date(details.release_date().map(str::to_owned))
            .with_description(details.description().map(str::to_owned))
            .with_language(details.language().map(str::to_owned))
            .with_album_type(details.album_type().map(str::to_owned))
            .with_genre(details.genre().map(str::to_owned))
            .with_company(details.company().map(str::to_owned)))
    }
}

impl<T> ArtistTracksProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = CatalogError;

    async fn artist_tracks(
        &self,
        requested_id: ArtistId,
        offset: u32,
        size: u32,
    ) -> Result<ArtistTracksPage, Self::Error> {
        let (numeric_id, artist_mid) = parse_artist_identity(&requested_id)?;
        let response = match numeric_id {
            Some(numeric_id) => {
                self.client()
                    .artist_tracks(numeric_id, artist_mid, offset, size)
                    .await
            }
            None => {
                self.client()
                    .artist_tracks_by_mid(artist_mid, offset, size)
                    .await
            }
        };
        let page = response.as_ref().map_err(map_artist_tracks_error)?;
        let tracks = page
            .tracks()
            .iter()
            .map(map_track_summary)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|()| CatalogError::InvalidResponse)?;
        Ok(ArtistTracksPage::new(
            page.offset(),
            page.total(),
            page.has_more(),
            tracks,
        ))
    }
}

impl<T> ArtistAlbumsProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = CatalogError;

    async fn artist_albums(
        &self,
        requested_id: ArtistId,
        offset: u32,
        size: u32,
    ) -> Result<ArtistAlbumsPage, Self::Error> {
        let (_, artist_mid) = parse_artist_identity(&requested_id)?;
        let response = self.client().artist_albums(artist_mid, offset, size).await;
        let page = response.as_ref().map_err(map_artist_albums_error)?;
        let albums = page
            .albums()
            .iter()
            .map(map_album_summary)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|()| CatalogError::InvalidResponse)?;
        Ok(ArtistAlbumsPage::new(
            page.offset(),
            page.total(),
            page.has_more(),
            albums,
        ))
    }
}

impl<T> NewAlbumReleasesProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = CatalogError;

    async fn new_album_releases(
        &self,
        region: NewAlbumRegion,
        offset: u32,
        size: u32,
    ) -> Result<NewAlbumReleasesPage, Self::Error> {
        let response = self
            .client()
            .new_album_releases(map_new_album_region(region), offset, size)
            .await;
        let page = response.as_ref().map_err(map_new_albums_error)?;
        let releases = page
            .releases()
            .iter()
            .map(|release| {
                let album = map_album_summary(release.album())?;
                let artists = release
                    .artists()
                    .iter()
                    .map(map_artist_summary)
                    .collect::<Result<Vec<_>, _>>()?;
                Ok(NewAlbumRelease::new(
                    album,
                    artists,
                    release.release_date().map(str::to_owned),
                ))
            })
            .collect::<Result<Vec<_>, ()>>()
            .map_err(|()| CatalogError::InvalidResponse)?;
        Ok(NewAlbumReleasesPage::new(
            region,
            page.offset(),
            page.total(),
            page.has_more(),
            releases,
        ))
    }
}

impl<T> NewSongsProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = CatalogError;

    async fn new_songs(&self, category: NewSongCategory) -> Result<NewSongCollection, Self::Error> {
        let response = self
            .client()
            .new_songs(map_new_song_category(category))
            .await;
        let collection = response.as_ref().map_err(map_new_songs_error)?;
        let tracks = collection
            .tracks()
            .iter()
            .map(map_track_summary)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|()| CatalogError::InvalidResponse)?;
        Ok(NewSongCollection::new(category, tracks))
    }
}

impl<T> RecommendedPlaylistsProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = RecommendationError;

    async fn recommended_playlists(
        &self,
        offset: u32,
        size: u32,
    ) -> Result<RecommendedPlaylistsPage, Self::Error> {
        let response = self.client().recommended_playlists(offset, size).await;
        let page = response.as_ref().map_err(map_recommendations_error)?;
        let playlists = page
            .playlists()
            .iter()
            .map(map_recommended_playlist)
            .collect::<Result<Vec<_>, _>>()?;
        Ok(RecommendedPlaylistsPage::new(
            page.offset(),
            page.has_more(),
            playlists,
        ))
    }
}

impl<T> DailyRecommendationProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = DailyRecommendationError;

    async fn daily_recommendation(&self) -> Result<Option<PlaylistSummary>, Self::Error> {
        let candidate = self.authenticated_daily_credential()?;
        let response = self.client().daily_recommendation(&candidate).await;
        self.finish_daily_await(
            &candidate,
            matches!(
                response,
                Err(QqMusicDailyRecommendationError::Rejected { .. })
            ),
        )?;
        response
            .as_ref()
            .map_err(map_daily_recommendation_error)?
            .as_ref()
            .map(map_daily_recommendation)
            .transpose()
    }
}

impl<T> PersonalizedPlaylistsProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = PersonalizedPlaylistsError;

    async fn personalized_playlists(&self) -> Result<Vec<PlaylistSummary>, Self::Error> {
        let candidate = self.authenticated_personalized_playlists_credential()?;
        let response = self.client().personalized_playlists(&candidate).await;
        self.finish_personalized_playlists_await(
            &candidate,
            matches!(
                response,
                Err(QqMusicPersonalizedPlaylistsError::Rejected { .. })
            ),
        )?;
        response
            .as_ref()
            .map_err(map_personalized_playlists_error)?
            .iter()
            .map(map_personalized_playlist)
            .collect()
    }
}

impl<T> PersonalizedTracksProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = PersonalizedTracksError;

    async fn personalized_tracks(&self) -> Result<Vec<TrackSummary>, Self::Error> {
        let candidate = self.authenticated_personalized_tracks_credential()?;
        let response = self.client().personalized_tracks(&candidate).await;
        self.finish_personalized_tracks_await(
            &candidate,
            matches!(
                response,
                Err(QqMusicPersonalizedTracksError::Rejected { .. })
            ),
        )?;
        response
            .as_ref()
            .map_err(map_personalized_tracks_error)?
            .tracks()
            .iter()
            .map(map_track_summary)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|()| PersonalizedTracksError::InvalidResponse)
    }
}

impl<T> RelatedTracksProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = RelatedTracksError;

    async fn related_tracks(&self, seed: TrackId) -> Result<Vec<TrackSummary>, Self::Error> {
        let identity =
            parse_track_identity(&seed).map_err(|()| RelatedTracksError::InvalidTrack)?;
        self.client()
            .related_tracks(identity.song_id)
            .await
            .as_ref()
            .map_err(map_related_tracks_error)?
            .tracks()
            .iter()
            .map(map_track_summary)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|()| RelatedTracksError::InvalidResponse)
    }
}

impl<T> RadarRecommendationsProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = RadarRecommendationError;

    async fn radar_tracks(&self, page: u32) -> Result<RadarTrackPage, Self::Error> {
        let candidate = self.authenticated_radar_credential()?;
        let response = self.client().radar_tracks(&candidate, page).await;
        self.finish_radar_await(
            &candidate,
            matches!(response, Err(QqMusicRadarError::Rejected { .. })),
        )?;
        let page = response.as_ref().map_err(map_radar_error)?;
        let tracks = page
            .tracks()
            .iter()
            .map(map_track_summary)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|()| RadarRecommendationError::InvalidResponse)?;
        Ok(RadarTrackPage::new(page.page(), page.has_more(), tracks))
    }
}

impl<T> RankingsProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = CatalogError;

    async fn ranking_groups(&self) -> Result<Vec<RankingGroup>, Self::Error> {
        let response = self.client().ranking_groups().await;
        response
            .as_ref()
            .map_err(map_rankings_error)?
            .iter()
            .map(|group| {
                let rankings = group
                    .rankings()
                    .iter()
                    .map(map_ranking_summary)
                    .collect::<Result<Vec<_>, _>>()?;
                RankingGroup::new(group.title(), rankings)
                    .map_err(|_| CatalogError::InvalidResponse)
            })
            .collect()
    }

    async fn ranking_tracks(
        &self,
        requested_id: RankingId,
        offset: u32,
        size: u32,
    ) -> Result<RankingTracksPage, Self::Error> {
        let top_id = parse_ranking_id(&requested_id)?;
        let response = self.client().ranking_tracks(top_id, offset, size).await;
        let page = response.as_ref().map_err(map_rankings_error)?;
        let ranking = map_ranking_summary(page.ranking())?;
        let tracks = page
            .tracks()
            .iter()
            .map(map_track_summary)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|()| CatalogError::InvalidResponse)?;
        Ok(RankingTracksPage::new(
            ranking,
            page.offset(),
            page.total(),
            page.has_more(),
            tracks,
        ))
    }
}

impl<T> OwnedPlaylistsProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = UserLibraryError;

    async fn owned_playlists(&self) -> Result<Vec<PlaylistSummary>, Self::Error> {
        let candidate = self.authenticated_credential()?;

        let response = self.client().owned_playlists(&candidate).await;
        self.finish_library_await(
            &candidate,
            matches!(response, Err(QqMusicOwnedPlaylistsError::Rejected { .. })),
        )?;
        response
            .as_ref()
            .map_err(map_owned_playlists_error)
            .and_then(|playlists| {
                playlists
                    .playlists()
                    .iter()
                    .map(map_owned_playlist)
                    .collect::<Result<Vec<_>, _>>()
            })
    }
}

impl<T> UserPlaylistsProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = UserLibraryError;

    async fn user_playlists(&self) -> Result<Vec<PlaylistSummary>, Self::Error> {
        let candidate = self.authenticated_credential()?;
        if candidate
            .session_secrets()
            .encrypted_uin()
            .is_none_or(|value| value.trim().is_empty())
        {
            return Err(UserLibraryError::InvalidResponse);
        }

        let owned_response = self.client().owned_playlists(&candidate).await;
        self.finish_library_await(
            &candidate,
            matches!(
                owned_response,
                Err(QqMusicOwnedPlaylistsError::Rejected { .. })
            ),
        )?;
        let owned = owned_response.as_ref().map_err(map_owned_playlists_error)?;
        let mut seen = HashSet::with_capacity(owned.playlists().len());
        let mut playlists = Vec::with_capacity(owned.playlists().len());
        for playlist in owned.playlists() {
            seen.insert(playlist.playlist_id());
            playlists.push(map_owned_playlist(playlist)?);
        }

        let mut offset = 0_u32;
        for _ in 0..MAX_FAVORITE_PLAYLIST_PAGES {
            let favorite_response = self
                .client()
                .favorite_playlists_page(&candidate, offset, FAVORITE_PLAYLIST_PAGE_SIZE)
                .await;
            self.finish_library_await(
                &candidate,
                matches!(
                    favorite_response,
                    Err(QqMusicFavoritePlaylistsError::Rejected { .. })
                ),
            )?;
            let page = favorite_response
                .as_ref()
                .map_err(map_favorite_playlists_error)?;
            let page_length = u32::try_from(page.playlists().len())
                .map_err(|_| UserLibraryError::InvalidResponse)?;
            for playlist in page.playlists() {
                if seen.insert(playlist.playlist_id()) {
                    playlists.push(map_favorite_playlist(playlist)?);
                }
            }
            if !page.has_more() {
                return Ok(playlists);
            }
            if page_length == 0 {
                return Err(UserLibraryError::InvalidResponse);
            }
            offset = offset
                .checked_add(page_length)
                .ok_or(UserLibraryError::InvalidResponse)?;
        }

        Err(UserLibraryError::InvalidResponse)
    }
}

impl<T> FavoriteAlbumsProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = UserLibraryError;

    async fn favorite_albums(
        &self,
        offset: u32,
        size: u32,
    ) -> Result<FavoriteAlbumsPage, Self::Error> {
        let candidate = self.authenticated_credential()?;
        let response = self
            .client()
            .favorite_albums(&candidate, offset, size)
            .await;
        self.finish_library_await(
            &candidate,
            matches!(response, Err(QqMusicFavoriteAlbumsError::Rejected { .. })),
        )?;
        let page = response.as_ref().map_err(map_favorite_albums_error)?;
        let albums = page
            .albums()
            .iter()
            .map(map_album_summary)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|()| UserLibraryError::InvalidResponse)?;
        Ok(FavoriteAlbumsPage::new(
            page.offset(),
            page.total(),
            page.has_more(),
            albums,
        ))
    }
}

impl<T> FavoriteArtistsProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = UserLibraryError;

    async fn favorite_artists(
        &self,
        offset: u32,
        size: u32,
    ) -> Result<FavoriteArtistsPage, Self::Error> {
        let candidate = self.authenticated_credential()?;
        let response = self
            .client()
            .favorite_artists(&candidate, offset, size)
            .await;
        self.finish_library_await(
            &candidate,
            matches!(response, Err(QqMusicFavoriteArtistsError::Rejected { .. })),
        )?;
        let page = response.as_ref().map_err(map_favorite_artists_error)?;
        let artists = page
            .artists()
            .iter()
            .map(map_favorite_artist_summary)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|()| UserLibraryError::InvalidResponse)?;
        Ok(FavoriteArtistsPage::new(
            page.offset(),
            page.total(),
            page.has_more(),
            artists,
        ))
    }
}

impl<T> PlaylistDetailsProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = UserLibraryError;

    async fn playlist_tracks_page(
        &self,
        playlist_id: PlaylistId,
        offset: u32,
        size: u32,
    ) -> Result<PlaylistTracksPage, Self::Error> {
        let candidate = self.authenticated_credential()?;
        let route = parse_playlist_route(&playlist_id)?;
        let response = match route {
            QqMusicPlaylistRoute::Ordinary { playlist_id } => {
                self.client()
                    .playlist_tracks_page(&candidate, playlist_id, offset, size)
                    .await
            }
            QqMusicPlaylistRoute::LikedSongs => {
                self.client()
                    .liked_songs_page(&candidate, offset, size)
                    .await
            }
        };
        self.finish_library_await(
            &candidate,
            matches!(response, Err(QqMusicPlaylistDetailError::Rejected { .. })),
        )?;
        let page = response.as_ref().map_err(map_playlist_detail_error)?;
        if page.has_more() && page.tracks().is_empty() {
            return Err(UserLibraryError::InvalidResponse);
        }
        let tracks = page
            .tracks()
            .iter()
            .map(map_track_summary)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|()| UserLibraryError::InvalidResponse)?;
        Ok(PlaylistTracksPage::new(
            page.offset(),
            page.total(),
            page.has_more(),
            tracks,
        ))
    }
}

impl<T> TrackLikeMutationProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = LibraryMutationError;

    async fn set_track_liked(&self, track_id: TrackId, liked: bool) -> Result<(), Self::Error> {
        let candidate = self
            .authenticated_credential()
            .map_err(map_library_state_to_mutation_error)?;
        let identity =
            parse_track_identity(&track_id).map_err(|()| LibraryMutationError::InvalidRequest)?;
        let state = if liked {
            QqMusicTrackLikeState::Liked
        } else {
            QqMusicTrackLikeState::NotLiked
        };
        let response = self
            .client()
            .set_track_liked(
                &candidate,
                identity.song_id,
                identity.primary_song_type,
                state,
            )
            .await;
        self.finish_library_await(
            &candidate,
            matches!(response, Err(QqMusicPlaylistTrackError::Rejected { .. })),
        )
        .map_err(map_library_state_to_mutation_error)?;
        response.as_ref().map_err(map_playlist_track_error).copied()
    }
}

impl<T> AlbumFavoriteMutationProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = LibraryMutationError;

    async fn set_album_favorite(
        &self,
        album_id: AlbumId,
        favorite: bool,
    ) -> Result<(), Self::Error> {
        let candidate = self
            .authenticated_credential()
            .map_err(map_library_state_to_mutation_error)?;
        let numeric_album_id = parse_album_mutation_id(&album_id)?;
        let state = if favorite {
            QqMusicAlbumFavoriteState::Favorite
        } else {
            QqMusicAlbumFavoriteState::NotFavorite
        };
        let response = self
            .client()
            .set_album_favorite(&candidate, numeric_album_id, state)
            .await;
        self.finish_library_await(
            &candidate,
            matches!(response, Err(QqMusicAlbumFavoriteError::Rejected { .. })),
        )
        .map_err(map_library_state_to_mutation_error)?;
        response.as_ref().map_err(map_album_favorite_error).copied()
    }
}

impl<T> PlaylistTrackMutationProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = LibraryMutationError;

    async fn set_playlist_track_membership(
        &self,
        playlist_id: PlaylistId,
        track_id: TrackId,
        present: bool,
    ) -> Result<(), Self::Error> {
        let directory_id = parse_owned_playlist_mutation_target(&playlist_id)
            .map_err(|()| LibraryMutationError::InvalidRequest)?;
        let identity =
            parse_track_identity(&track_id).map_err(|()| LibraryMutationError::InvalidRequest)?;
        let candidate = self
            .authenticated_credential()
            .map_err(map_library_state_to_mutation_error)?;
        let state = if present {
            QqMusicPlaylistTrackState::Present
        } else {
            QqMusicPlaylistTrackState::Absent
        };
        let response = self
            .client()
            .set_playlist_track_membership(
                &candidate,
                directory_id,
                identity.song_id,
                identity.primary_song_type,
                state,
            )
            .await;
        self.finish_library_await(
            &candidate,
            matches!(response, Err(QqMusicPlaylistTrackError::Rejected { .. })),
        )
        .map_err(map_library_state_to_mutation_error)?;
        response.as_ref().map_err(map_playlist_track_error).copied()
    }
}

impl<T> PlaylistCreationProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = LibraryMutationError;

    async fn create_playlist(&self, name: String) -> Result<PlaylistSummary, Self::Error> {
        let candidate = self
            .authenticated_credential()
            .map_err(map_library_state_to_mutation_error)?;
        let response = self.client().create_playlist(&candidate, &name).await;
        self.finish_library_await(
            &candidate,
            matches!(response, Err(QqMusicCreatePlaylistError::Rejected { .. })),
        )
        .map_err(map_library_state_to_mutation_error)?;
        let created = response.as_ref().map_err(map_create_playlist_error)?;
        let id = PlaylistId::new(
            qq_music_provider_id(),
            format!("owned:{}:{}", created.playlist_id(), created.directory_id()),
        )
        .map_err(|_| LibraryMutationError::InvalidResponseOutcomeUnknown)?;
        PlaylistSummary::new(id, created.name())
            .map_err(|_| LibraryMutationError::InvalidResponseOutcomeUnknown)
    }
}

impl<T> PlaylistDeletionProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = LibraryMutationError;

    async fn delete_playlist(&self, playlist_id: PlaylistId) -> Result<(), Self::Error> {
        let directory_id = parse_owned_playlist_mutation_target(&playlist_id)
            .map_err(|()| LibraryMutationError::InvalidRequest)?;
        let candidate = self
            .authenticated_credential()
            .map_err(map_library_state_to_mutation_error)?;
        let response = self
            .client()
            .delete_playlist(&candidate, directory_id)
            .await;
        self.finish_library_await(
            &candidate,
            matches!(response, Err(QqMusicDeletePlaylistError::Rejected { .. })),
        )
        .map_err(map_library_state_to_mutation_error)?;
        response
            .as_ref()
            .map_err(map_delete_playlist_error)
            .copied()
    }
}

impl<T> MediaSourceResolver for QqMusicMediaSourceResolver<'_, T>
where
    T: HttpTransport + 'static,
{
    fn supports(&self, track_id: &TrackId) -> bool {
        track_id.provider().as_str() == "qq-music"
    }

    async fn resolve_media(
        &self,
        track_id: TrackId,
        preferred_quality: AudioQuality,
    ) -> Result<ResolvedMediaSource, MediaResolutionError> {
        let candidate = self.provider.media_credential()?;
        let route = parse_media_track(&track_id)?;

        let dispatch_response = self.provider.client().cdn_dispatch().await;
        if let Some(candidate) = candidate.as_ref() {
            self.provider.finish_media_await(
                candidate,
                matches!(dispatch_response, Err(QqMusicMediaError::Rejected { .. })),
            )?;
        }
        let dispatch = dispatch_response.as_ref().map_err(map_media_error)?;

        let qualities: &[QqMusicAudioQuality] = match (candidate.as_ref(), preferred_quality) {
            (None, _) | (Some(_), AudioQuality::Standard) => &[QqMusicAudioQuality::Standard],
            (Some(_), AudioQuality::High) => {
                &[QqMusicAudioQuality::High, QqMusicAudioQuality::Standard]
            }
        };
        for (index, quality) in qualities.iter().copied().enumerate() {
            let source_response = match candidate.as_ref() {
                Some(candidate) => {
                    self.provider
                        .client()
                        .mp3_source(
                            candidate,
                            route.song_mid,
                            route.file_media_mid,
                            quality,
                            dispatch,
                        )
                        .await
                }
                None => {
                    self.provider
                        .client()
                        .anonymous_standard_mp3_source(
                            route.song_mid,
                            route.file_media_mid,
                            dispatch,
                        )
                        .await
                }
            };
            if let Some(candidate) = candidate.as_ref() {
                self.provider.finish_media_await(
                    candidate,
                    matches!(source_response, Err(QqMusicMediaError::Rejected { .. })),
                )?;
            }
            match source_response {
                Ok(source) => {
                    let actual_quality = match source.quality() {
                        QqMusicAudioQuality::Standard => AudioQuality::Standard,
                        QqMusicAudioQuality::High => AudioQuality::High,
                    };
                    return ResolvedMediaSource::new(
                        track_id,
                        source.uri().to_owned(),
                        AudioFormat::Mp3,
                        actual_quality,
                        source.valid_for_seconds(),
                    )
                    .map_err(|_| MediaResolutionError::InvalidResponse);
                }
                Err(QqMusicMediaError::Unavailable { .. }) if index + 1 < qualities.len() => {}
                Err(QqMusicMediaError::Unavailable { .. }) if candidate.is_none() => {
                    return Err(MediaResolutionError::AuthenticationRequired);
                }
                Err(error) => return Err(map_media_error(&error)),
            }
        }
        Err(MediaResolutionError::Unavailable)
    }
}

impl<T> LyricsProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = LyricsError;

    async fn lyrics(&self, track_id: TrackId) -> Result<SynchronizedLyrics, Self::Error> {
        let candidate = self.authenticated_lyrics_credential()?;
        let route = parse_lyrics_track(&track_id)?;
        let response = self
            .client()
            .lyrics(&candidate, route.song_mid, route.song_type)
            .await;
        self.finish_lyrics_await(
            &candidate,
            matches!(response, Err(QqMusicLyricsError::Rejected { .. })),
        )?;
        response
            .as_ref()
            .map_err(map_lyrics_error)
            .and_then(|lyrics| map_lyrics(track_id, lyrics))
    }
}

impl<T> TrackCommentsProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = CommentsError;

    async fn track_comments(
        &self,
        track_id: TrackId,
        offset: u32,
        size: u32,
    ) -> Result<TrackCommentsPage, Self::Error> {
        let route = parse_track_identity(&track_id).map_err(|()| CommentsError::InvalidResponse)?;
        let response = self
            .client()
            .track_comments(route.song_id, offset, size)
            .await;
        let page = response.as_ref().map_err(map_comments_error)?;
        if page.has_more() && page.latest_comments().is_empty() {
            return Err(CommentsError::InvalidResponse);
        }
        let hot_comments = page
            .hot_comments()
            .iter()
            .map(map_comment)
            .collect::<Result<Vec<_>, _>>()?;
        let latest_comments = page
            .latest_comments()
            .iter()
            .map(map_comment)
            .collect::<Result<Vec<_>, _>>()?;
        Ok(TrackCommentsPage::new(
            page.offset(),
            page.total(),
            page.has_more(),
            hot_comments,
            latest_comments,
        ))
    }
}

impl<T> TrackMusicVideoProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = MusicVideoError;

    async fn track_music_video(
        &self,
        track_id: TrackId,
    ) -> Result<Option<MusicVideo>, Self::Error> {
        let route =
            parse_track_identity(&track_id).map_err(|()| MusicVideoError::InvalidResponse)?;
        self.client()
            .track_music_video(route.song_mid)
            .await
            .as_ref()
            .map_err(map_music_video_error)?
            .as_ref()
            .map(map_music_video)
            .transpose()
    }
}

impl<T> QrAuthenticationProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = AuthenticationError;
    type Session = QqMusicQrAuthenticationSession<T>;

    async fn begin_qr_authentication(
        &self,
        channel: QrAuthenticationChannel,
    ) -> Result<Self::Session, Self::Error> {
        {
            let mut credential = credential_guard(&self.credential);
            if matches!(
                *credential,
                QqMusicCredentialState::PendingVerification(_)
                    | QqMusicCredentialState::LocallyExpired(_)
            ) {
                *credential = QqMusicCredentialState::SignedOut;
            }
        }
        *restore_verification_guard(&self.active_restore_verification) = None;
        *phone_authentication_guard(&self.active_phone_authentication) = None;
        let session = self
            .login
            .begin_channel(match channel {
                QrAuthenticationChannel::Qq => QrLoginChannel::Qq,
                QrAuthenticationChannel::Wechat => QrLoginChannel::Wechat,
            })
            .await
            .map_err(map_login_error)?;
        Ok(QqMusicQrAuthenticationSession {
            cancellation: QqMusicQrAuthenticationCancellation {
                inner: session.cancellation_handle(),
            },
            session,
            credential: Arc::clone(&self.credential),
        })
    }

    fn has_authenticated_credential(&self) -> bool {
        QqMusicProvider::has_authenticated_credential(self)
    }

    fn sign_out(&self) {
        QqMusicProvider::sign_out(self);
    }
}

impl<T> PhoneAuthenticationProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = AuthenticationError;
    type Session = QqMusicPhoneAuthenticationSession<T>;

    fn begin_phone_authentication(
        &self,
        country_code: String,
        phone_number: String,
    ) -> Result<Self::Session, Self::Error> {
        let session = PhoneAuthorizationSession::new(&country_code, &phone_number)
            .map_err(|_| AuthenticationError::InvalidResponse)?;
        self.login.cancel_active();
        *restore_verification_guard(&self.active_restore_verification) = None;
        {
            let mut credential = credential_guard(&self.credential);
            if matches!(
                *credential,
                QqMusicCredentialState::PendingVerification(_)
                    | QqMusicCredentialState::LocallyExpired(_)
            ) {
                *credential = QqMusicCredentialState::SignedOut;
            }
        }
        let attempt_id = self
            .next_phone_authentication
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |current| {
                Some(if current == u32::MAX { 1 } else { current + 1 })
            })
            .unwrap_or_else(std::convert::identity);
        *phone_authentication_guard(&self.active_phone_authentication) = Some(attempt_id);
        Ok(QqMusicPhoneAuthenticationSession {
            client: self.login.client_handle(),
            session,
            attempt_id,
            active: Arc::clone(&self.active_phone_authentication),
            credential: Arc::clone(&self.credential),
        })
    }
}

pub struct QqMusicPhoneAuthenticationSession<T> {
    client: Arc<QqMusicClient<T>>,
    session: PhoneAuthorizationSession,
    attempt_id: u32,
    active: Arc<Mutex<Option<u32>>>,
    credential: Arc<Mutex<QqMusicCredentialState>>,
}

impl<T> std::fmt::Debug for QqMusicPhoneAuthenticationSession<T> {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("QqMusicPhoneAuthenticationSession")
            .field("active", &self.is_current())
            .finish_non_exhaustive()
    }
}

impl<T> QqMusicPhoneAuthenticationSession<T> {
    fn is_current(&self) -> bool {
        *phone_authentication_guard(&self.active) == Some(self.attempt_id)
    }

    fn clear_if_current(&self) -> bool {
        let mut active = phone_authentication_guard(&self.active);
        if *active != Some(self.attempt_id) {
            return false;
        }
        *active = None;
        true
    }
}

impl<T> PhoneAuthenticationSession for QqMusicPhoneAuthenticationSession<T>
where
    T: HttpTransport + 'static,
{
    type Error = AuthenticationError;

    fn is_active(&self) -> bool {
        self.is_current()
    }

    fn cancel(&self) -> bool {
        self.clear_if_current()
    }

    async fn send_code(&self) -> Result<PhoneAuthenticationCodeState, Self::Error> {
        if !self.is_current() {
            return Err(AuthenticationError::Replaced);
        }
        let result = self.client.send_phone_auth_code(&self.session).await;
        if !self.is_current() {
            return Err(AuthenticationError::Replaced);
        }
        match result.map_err(|error| map_phone_login_error(&error))? {
            PhoneAuthCodeResult::Sent => Ok(PhoneAuthenticationCodeState::Sent),
            PhoneAuthCodeResult::CaptchaRequired { security_url } => {
                Ok(PhoneAuthenticationCodeState::CaptchaRequired { security_url })
            }
            PhoneAuthCodeResult::RateLimited => Ok(PhoneAuthenticationCodeState::RateLimited),
        }
    }

    async fn authorize(&self, verification_code: String) -> Result<(), Self::Error> {
        if !self.is_current() {
            return Err(AuthenticationError::Replaced);
        }
        let credential = self
            .client
            .authorize_phone(&self.session, &verification_code)
            .await
            .map_err(|error| map_phone_login_error(&error))?;
        if !self.clear_if_current() {
            return Err(AuthenticationError::Replaced);
        }
        *credential_guard(&self.credential) = QqMusicCredentialState::Authenticated(credential);
        Ok(())
    }
}

impl<T> AccountSummaryProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = AccountSummaryError;

    async fn account_summary(&self) -> Result<AccountSummary, Self::Error> {
        let candidate = self.authenticated_account_credential()?;
        let response = self.client().verify_credential(&candidate).await;
        let rejected = matches!(response, Err(CredentialVerificationError::Rejected { .. }));
        self.finish_account_await(&candidate, rejected)?;
        let summary = response
            .as_ref()
            .map_err(map_account_summary_error)?
            .as_ref()
            .ok_or(AccountSummaryError::InvalidResponse)?;

        AccountSummary::new(qq_music_provider_id(), summary.display_name())
            .map(|summary_domain| {
                summary_domain.with_avatar_uri(summary.avatar_uri().map(str::to_owned))
            })
            .map_err(|_| AccountSummaryError::InvalidResponse)
    }
}

#[derive(Clone, Debug)]
pub struct QqMusicQrAuthenticationCancellation {
    inner: WechatQrLoginCancellation,
}

impl QqMusicQrAuthenticationCancellation {
    #[must_use]
    pub fn is_active(&self) -> bool {
        self.inner.is_active()
    }

    #[must_use]
    pub fn cancel(&self) -> bool {
        self.inner.cancel()
    }
}

pub struct QqMusicQrAuthenticationSession<T> {
    session: WechatQrLoginSession<T>,
    cancellation: QqMusicQrAuthenticationCancellation,
    credential: Arc<Mutex<QqMusicCredentialState>>,
}

impl<T> std::fmt::Debug for QqMusicQrAuthenticationSession<T> {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("QqMusicQrAuthenticationSession")
            .field("active", &self.cancellation.is_active())
            .finish_non_exhaustive()
    }
}

impl<T> QqMusicQrAuthenticationSession<T> {
    #[must_use]
    pub fn cancellation_handle(&self) -> QqMusicQrAuthenticationCancellation {
        self.cancellation.clone()
    }
}

impl<T> QrAuthenticationSession for QqMusicQrAuthenticationSession<T>
where
    T: HttpTransport + 'static,
{
    type Error = AuthenticationError;

    fn challenge(&self) -> QrAuthenticationChallenge {
        let image = self.session.image();
        let format = match image.media_type() {
            QrImageMediaType::Png => QrImageFormat::Png,
            QrImageMediaType::Jpeg => QrImageFormat::Jpeg,
        };
        QrAuthenticationChallenge::new(format, image.bytes().to_vec())
    }

    fn is_active(&self) -> bool {
        self.cancellation.is_active()
    }

    fn cancel(&self) -> bool {
        self.cancellation.cancel()
    }

    async fn advance(&mut self) -> Result<QrAuthenticationProgress, Self::Error> {
        match self.session.advance().await.map_err(map_login_error)? {
            WechatQrLoginProgress::WaitingForScan => Ok(QrAuthenticationProgress::WaitingForScan),
            WechatQrLoginProgress::ScannedAwaitingConfirmation => {
                Ok(QrAuthenticationProgress::ScannedAwaitingConfirmation)
            }
            WechatQrLoginProgress::Authenticated(credential) => {
                *credential_guard(&self.credential) =
                    QqMusicCredentialState::Authenticated(*credential);
                Ok(QrAuthenticationProgress::Authenticated)
            }
            WechatQrLoginProgress::Expired => Ok(QrAuthenticationProgress::Expired),
            WechatQrLoginProgress::Refused => Ok(QrAuthenticationProgress::Refused),
            WechatQrLoginProgress::TimedOut => Ok(QrAuthenticationProgress::TimedOut),
        }
    }
}

fn credential_guard(
    credential: &Mutex<QqMusicCredentialState>,
) -> std::sync::MutexGuard<'_, QqMusicCredentialState> {
    credential
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn restore_verification_guard(
    attempt: &Mutex<Option<u32>>,
) -> std::sync::MutexGuard<'_, Option<u32>> {
    attempt
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn phone_authentication_guard(
    attempt: &Mutex<Option<u32>>,
) -> std::sync::MutexGuard<'_, Option<u32>> {
    attempt
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn qq_music_provider_id() -> ProviderId {
    ProviderId::new("qq-music").expect("static provider id is valid")
}

fn map_owned_playlist(
    playlist: &QqMusicOwnedPlaylist,
) -> Result<PlaylistSummary, UserLibraryError> {
    let id = PlaylistId::new(
        qq_music_provider_id(),
        format!(
            "owned:{}:{}",
            playlist.playlist_id(),
            playlist.directory_id()
        ),
    )
    .map_err(|_| UserLibraryError::InvalidResponse)?;
    PlaylistSummary::new(id, playlist.name())
        .map(|summary| {
            summary
                .with_artwork_uri(playlist.cover_url().map(str::to_owned))
                .with_track_count(playlist.track_count())
                .with_ownership(PlaylistOwnership::Owned)
                .with_purpose(if playlist.directory_id() == 201 {
                    PlaylistPurpose::LikedSongs
                } else {
                    PlaylistPurpose::Standard
                })
        })
        .map_err(|_| UserLibraryError::InvalidResponse)
}

fn map_favorite_playlist(
    playlist: &QqMusicFavoritePlaylist,
) -> Result<PlaylistSummary, UserLibraryError> {
    let id = PlaylistId::new(
        qq_music_provider_id(),
        format!("favorite:{}", playlist.playlist_id()),
    )
    .map_err(|_| UserLibraryError::InvalidResponse)?;
    PlaylistSummary::new(id, playlist.name())
        .map(|summary| {
            summary
                .with_artwork_uri(playlist.cover_url().map(str::to_owned))
                .with_track_count(playlist.track_count())
                .with_ownership(PlaylistOwnership::Saved)
        })
        .map_err(|_| UserLibraryError::InvalidResponse)
}

fn map_recommended_playlist(
    playlist: &QqMusicRecommendedPlaylist,
) -> Result<PlaylistSummary, RecommendationError> {
    let id = PlaylistId::new(
        qq_music_provider_id(),
        format!("catalog:{}", playlist.playlist_id()),
    )
    .map_err(|_| RecommendationError::InvalidResponse)?;
    PlaylistSummary::new(id, playlist.title())
        .map(|summary| {
            summary
                .with_artwork_uri(playlist.cover_url().map(str::to_owned))
                .with_track_count(playlist.track_count())
        })
        .map_err(|_| RecommendationError::InvalidResponse)
}

fn map_daily_recommendation(
    playlist: &QqMusicDailyRecommendation,
) -> Result<PlaylistSummary, DailyRecommendationError> {
    let id = PlaylistId::new(
        qq_music_provider_id(),
        format!("catalog:{}", playlist.playlist_id()),
    )
    .map_err(|_| DailyRecommendationError::InvalidResponse)?;
    PlaylistSummary::new(id, playlist.title())
        .map(|summary| summary.with_artwork_uri(playlist.artwork_uri().map(str::to_owned)))
        .map_err(|_| DailyRecommendationError::InvalidResponse)
}

fn map_personalized_playlist(
    playlist: &QqMusicPersonalizedPlaylist,
) -> Result<PlaylistSummary, PersonalizedPlaylistsError> {
    let id = PlaylistId::new(
        qq_music_provider_id(),
        format!("catalog:{}", playlist.playlist_id()),
    )
    .map_err(|_| PersonalizedPlaylistsError::InvalidResponse)?;
    PlaylistSummary::new(id, playlist.title())
        .map(|summary| summary.with_artwork_uri(playlist.artwork_uri().map(str::to_owned)))
        .map_err(|_| PersonalizedPlaylistsError::InvalidResponse)
}

fn map_ranking_summary(ranking: &QqMusicRankingSummary) -> Result<RankingSummary, CatalogError> {
    let id = RankingId::new(
        qq_music_provider_id(),
        format!("ranking:{}", ranking.top_id()),
    )
    .map_err(|_| CatalogError::InvalidResponse)?;
    RankingSummary::new(id, ranking.title())
        .map(|summary| {
            summary
                .with_period(ranking.period().map(str::to_owned))
                .with_artwork_uri(ranking.artwork_uri().map(str::to_owned))
                .with_track_count(ranking.total())
        })
        .map_err(|_| CatalogError::InvalidResponse)
}

fn map_playlist_search_summary(
    playlist: &QqMusicPlaylistSearchSummary,
) -> Result<PlaylistSummary, SearchError> {
    let id = PlaylistId::new(
        qq_music_provider_id(),
        format!("catalog:{}", playlist.playlist_id()),
    )
    .map_err(|_| SearchError::InvalidResponse)?;
    PlaylistSummary::new(id, playlist.title())
        .map(|summary| {
            summary
                .with_artwork_uri(playlist.artwork_uri().map(str::to_owned))
                .with_track_count(Some(playlist.track_count()))
        })
        .map_err(|_| SearchError::InvalidResponse)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum QqMusicPlaylistRoute {
    Ordinary { playlist_id: u64 },
    LikedSongs,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct QqMusicMediaTrack<'a> {
    song_mid: &'a str,
    file_media_mid: Option<&'a str>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct QqMusicLyricTrack<'a> {
    song_mid: &'a str,
    song_type: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct QqMusicTrackIdentity<'a> {
    song_id: u64,
    song_mid: &'a str,
    file_media_mid: Option<&'a str>,
    primary_song_type: u32,
}

fn parse_track_identity(track_id: &TrackId) -> Result<QqMusicTrackIdentity<'_>, ()> {
    if track_id.provider() != &qq_music_provider_id() {
        return Err(());
    }
    let mut parts = track_id.opaque().split(':');
    let (prefix, raw_id, raw_primary_type, raw_song_mid, raw_file_media_mid, extra) = (
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
    );
    if prefix != Some("track") || extra.is_some() {
        return Err(());
    }
    let numeric_song_id = raw_id
        .and_then(|value| value.parse::<u64>().ok())
        .filter(|value| *value != 0)
        .ok_or(())?;
    let primary_song_type = raw_primary_type
        .and_then(|value| value.parse::<u32>().ok())
        .ok_or(())?;
    let song_mid = raw_song_mid
        .filter(|value| is_safe_track_mid(value))
        .ok_or(())?;
    let file_media_mid = match raw_file_media_mid {
        Some("-") => None,
        Some(value) if is_safe_track_mid(value) => Some(value),
        _ => return Err(()),
    };
    Ok(QqMusicTrackIdentity {
        song_id: numeric_song_id,
        song_mid,
        file_media_mid,
        primary_song_type,
    })
}

fn is_safe_track_mid(value: &str) -> bool {
    !value.is_empty() && value.len() <= 64 && value.bytes().all(|byte| byte.is_ascii_alphanumeric())
}

fn parse_media_track(track_id: &TrackId) -> Result<QqMusicMediaTrack<'_>, MediaResolutionError> {
    let identity =
        parse_track_identity(track_id).map_err(|()| MediaResolutionError::InvalidResponse)?;
    Ok(QqMusicMediaTrack {
        song_mid: identity.song_mid,
        file_media_mid: identity.file_media_mid,
    })
}

fn parse_lyrics_track(track_id: &TrackId) -> Result<QqMusicLyricTrack<'_>, LyricsError> {
    let identity = parse_track_identity(track_id).map_err(|()| LyricsError::InvalidResponse)?;
    Ok(QqMusicLyricTrack {
        song_mid: identity.song_mid,
        song_type: identity.primary_song_type,
    })
}

fn parse_playlist_route(
    playlist_id: &PlaylistId,
) -> Result<QqMusicPlaylistRoute, UserLibraryError> {
    if playlist_id.provider() != &qq_music_provider_id() {
        return Err(UserLibraryError::InvalidResponse);
    }
    let mut parts = playlist_id.opaque().split(':');
    match (parts.next(), parts.next(), parts.next(), parts.next()) {
        (Some("catalog"), Some(raw_id), None, None) => parse_nonzero_u64(raw_id)
            .map(|playlist_id| QqMusicPlaylistRoute::Ordinary { playlist_id }),
        (Some("favorite"), Some(raw_id), None, None) => parse_nonzero_u64(raw_id)
            .map(|playlist_id| QqMusicPlaylistRoute::Ordinary { playlist_id }),
        (Some("owned"), Some(raw_id), Some(raw_directory_id), None) => {
            let playlist_id = parse_nonzero_u64(raw_id)?;
            let directory_id = parse_nonzero_u64(raw_directory_id)?;
            if directory_id == 201 {
                Ok(QqMusicPlaylistRoute::LikedSongs)
            } else {
                Ok(QqMusicPlaylistRoute::Ordinary { playlist_id })
            }
        }
        _ => Err(UserLibraryError::InvalidResponse),
    }
}

fn parse_owned_playlist_mutation_target(playlist_id: &PlaylistId) -> Result<u64, ()> {
    if playlist_id.provider() != &qq_music_provider_id() {
        return Err(());
    }
    let mut parts = playlist_id.opaque().split(':');
    match (parts.next(), parts.next(), parts.next(), parts.next()) {
        (Some("owned"), Some(raw_playlist_id), Some(raw_directory_id), None) => {
            raw_playlist_id
                .parse::<u64>()
                .ok()
                .filter(|value| *value != 0)
                .ok_or(())?;
            raw_directory_id
                .parse::<u64>()
                .ok()
                .filter(|value| *value != 0)
                .ok_or(())
        }
        _ => Err(()),
    }
}

fn parse_nonzero_u64(value: &str) -> Result<u64, UserLibraryError> {
    value
        .parse::<u64>()
        .ok()
        .filter(|value| *value != 0)
        .ok_or(UserLibraryError::InvalidResponse)
}

fn parse_album_mid(requested_id: &AlbumId) -> Result<&str, CatalogError> {
    if requested_id.provider() != &qq_music_provider_id() {
        return Err(CatalogError::InvalidResponse);
    }
    let mut parts = requested_id.opaque().split(':');
    let (prefix, numeric_id, catalog_mid, extra) =
        (parts.next(), parts.next(), parts.next(), parts.next());
    if prefix != Some("album") || extra.is_some() {
        return Err(CatalogError::InvalidResponse);
    }
    match numeric_id {
        Some("-") => {}
        Some(value) => {
            value
                .parse::<u64>()
                .ok()
                .filter(|value| *value != 0)
                .ok_or(CatalogError::InvalidResponse)?;
        }
        None => return Err(CatalogError::InvalidResponse),
    }
    catalog_mid
        .filter(|value| is_safe_track_mid(value))
        .ok_or(CatalogError::InvalidResponse)
}

fn parse_album_mutation_id(requested_id: &AlbumId) -> Result<u64, LibraryMutationError> {
    if requested_id.provider() != &qq_music_provider_id() {
        return Err(LibraryMutationError::InvalidRequest);
    }
    let mut parts = requested_id.opaque().split(':');
    let (prefix, numeric_id, album_mid, extra) =
        (parts.next(), parts.next(), parts.next(), parts.next());
    if prefix != Some("album") || extra.is_some() {
        return Err(LibraryMutationError::InvalidRequest);
    }
    album_mid
        .filter(|value| is_safe_track_mid(value))
        .ok_or(LibraryMutationError::InvalidRequest)?;
    numeric_id
        .and_then(|value| value.parse::<u64>().ok())
        .filter(|value| *value != 0)
        .ok_or(LibraryMutationError::InvalidRequest)
}

fn parse_artist_identity(requested_id: &ArtistId) -> Result<(Option<u64>, &str), CatalogError> {
    if requested_id.provider() != &qq_music_provider_id() {
        return Err(CatalogError::InvalidResponse);
    }
    let mut parts = requested_id.opaque().split(':');
    let (prefix, numeric_id, artist_mid, extra) =
        (parts.next(), parts.next(), parts.next(), parts.next());
    if prefix != Some("artist") || extra.is_some() {
        return Err(CatalogError::InvalidResponse);
    }
    let numeric_id = match numeric_id {
        Some("-") => None,
        Some(value) => Some(
            value
                .parse::<u64>()
                .ok()
                .filter(|value| *value != 0)
                .ok_or(CatalogError::InvalidResponse)?,
        ),
        None => return Err(CatalogError::InvalidResponse),
    };
    let artist_mid = artist_mid
        .filter(|value| is_safe_track_mid(value))
        .ok_or(CatalogError::InvalidResponse)?;
    Ok((numeric_id, artist_mid))
}

fn parse_ranking_id(requested_id: &RankingId) -> Result<u64, CatalogError> {
    if requested_id.provider() != &qq_music_provider_id() {
        return Err(CatalogError::InvalidResponse);
    }
    let mut parts = requested_id.opaque().split(':');
    match (parts.next(), parts.next(), parts.next()) {
        (Some("ranking"), Some(raw_id), None) => raw_id
            .parse::<u64>()
            .ok()
            .filter(|value| *value != 0)
            .ok_or(CatalogError::InvalidResponse),
        _ => Err(CatalogError::InvalidResponse),
    }
}

fn map_search_item(track: &QqMusicTrackSummary) -> Result<TrackSearchItem, ()> {
    let summary = map_track_summary(track)?;
    let album = summary.album().cloned();
    let artists = summary.artists().to_vec();
    Ok(TrackSearchItem::new(summary, album, artists))
}

fn map_artist_summary(artist: &qqmusic_client::QqMusicArtistSummary) -> Result<ArtistSummary, ()> {
    let numeric_id = artist.artist_id().filter(|value| *value != 0).ok_or(())?;
    let mid = artist
        .media_mid()
        .filter(|value| is_safe_track_mid(value))
        .ok_or(())?;
    let id = ArtistId::new(qq_music_provider_id(), format!("artist:{numeric_id}:{mid}"))
        .map_err(|_| ())?;
    ArtistSummary::new(id, artist.name())
        .map(|summary| summary.with_artwork_uri(artist_artwork_uri(mid)))
        .map_err(|_| ())
}

fn map_favorite_artist_summary(
    artist: &qqmusic_client::QqMusicArtistSummary,
) -> Result<ArtistSummary, ()> {
    if artist.artist_id().is_some() {
        return Err(());
    }
    let mid = artist
        .media_mid()
        .filter(|value| is_safe_track_mid(value))
        .ok_or(())?;
    let id = ArtistId::new(qq_music_provider_id(), format!("artist:-:{mid}")).map_err(|_| ())?;
    ArtistSummary::new(id, artist.name())
        .map(|summary| summary.with_artwork_uri(artist_artwork_uri(mid)))
        .map_err(|_| ())
}

fn map_album_summary(album: &QqMusicAlbumSummary) -> Result<AlbumSummary, ()> {
    let mid = album
        .media_mid()
        .filter(|value| is_safe_track_mid(value))
        .ok_or(())?;
    let title = album.name().ok_or(())?;
    let opaque = format!(
        "album:{}:{mid}",
        album.album_id().map_or("-".into(), |id| id.to_string())
    );
    let id = AlbumId::new(qq_music_provider_id(), opaque).map_err(|_| ())?;
    AlbumSummary::new(id, title)
        .map(|summary| summary.with_artwork_uri(album_artwork_uri(mid)))
        .map_err(|_| ())
}

const fn map_new_album_region(region: NewAlbumRegion) -> QqMusicNewAlbumArea {
    match region {
        NewAlbumRegion::MainlandChina => QqMusicNewAlbumArea::MainlandChina,
        NewAlbumRegion::HongKongTaiwan => QqMusicNewAlbumArea::HongKongTaiwan,
        NewAlbumRegion::Western => QqMusicNewAlbumArea::Western,
        NewAlbumRegion::Korea => QqMusicNewAlbumArea::Korea,
        NewAlbumRegion::Japan => QqMusicNewAlbumArea::Japan,
        NewAlbumRegion::Other => QqMusicNewAlbumArea::Other,
    }
}

const fn map_new_song_category(category: NewSongCategory) -> QqMusicNewSongCategory {
    match category {
        NewSongCategory::MainlandChina => QqMusicNewSongCategory::MainlandChina,
        NewSongCategory::Western => QqMusicNewSongCategory::Western,
        NewSongCategory::Japan => QqMusicNewSongCategory::Japan,
        NewSongCategory::Korea => QqMusicNewSongCategory::Korea,
        NewSongCategory::Latest => QqMusicNewSongCategory::Latest,
        NewSongCategory::HongKongTaiwan => QqMusicNewSongCategory::HongKongTaiwan,
    }
}

fn map_track_summary(track: &QqMusicTrackSummary) -> Result<TrackSummary, ()> {
    let file_media_mid = track.file_media_mid().unwrap_or("-");
    let id = TrackId::new(
        qq_music_provider_id(),
        format!(
            "track:{}:{}:{}:{}",
            track.track_id(),
            track.song_type(),
            track.song_mid(),
            file_media_mid
        ),
    )
    .map_err(|_| ())?;
    let artists = track
        .artists()
        .iter()
        .map(|artist| artist.name().to_owned())
        .collect();
    let credited_artists = track
        .artists()
        .iter()
        .filter_map(|artist| map_artist_summary(artist).ok())
        .collect();
    let album_title = track
        .album()
        .and_then(qqmusic_client::QqMusicAlbumSummary::name)
        .map(str::to_owned);
    let artwork_uri = track
        .album()
        .and_then(qqmusic_client::QqMusicAlbumSummary::media_mid)
        .and_then(album_artwork_uri);
    let album = track
        .album()
        .and_then(|album| map_album_summary(album).ok());
    TrackSummary::new(id, track.title(), artists)
        .map(|summary| {
            summary
                .with_subtitle(track.subtitle().map(str::to_owned))
                .with_artists(credited_artists)
                .with_album_title(album_title)
                .with_album(album)
                .with_artwork_uri(artwork_uri)
                .with_duration_seconds(Some(track.duration_seconds()))
        })
        .map_err(|_| ())
}

fn map_comment(comment: &QqMusicTrackComment) -> Result<TrackComment, CommentsError> {
    let id = TrackCommentId::new(
        qq_music_provider_id(),
        format!("comment:{}", comment.comment_id()),
    )
    .map_err(|_| CommentsError::InvalidResponse)?;
    TrackComment::new(
        id,
        comment.author_display_name(),
        comment.content(),
        comment.published_at_unix_seconds(),
        comment.praise_count(),
    )
    .map_err(|_| CommentsError::InvalidResponse)
}

fn map_music_video(video: &QqMusicTrackMusicVideo) -> Result<MusicVideo, MusicVideoError> {
    let id = MusicVideoId::new(qq_music_provider_id(), format!("mv:{}", video.vid()))
        .map_err(|_| MusicVideoError::InvalidResponse)?;
    let quality = match video.quality() {
        QqMusicMusicVideoQuality::FullHd => MusicVideoQuality::FullHd,
        QqMusicMusicVideoQuality::Hd => MusicVideoQuality::Hd,
        QqMusicMusicVideoQuality::Sd => MusicVideoQuality::Sd,
        QqMusicMusicVideoQuality::Low => MusicVideoQuality::Low,
    };
    let source = MusicVideoSource::new(video.source_uri(), quality)
        .map_err(|_| MusicVideoError::InvalidResponse)?;
    MusicVideo::new(id, video.title(), video.artist_names().to_vec(), source)
        .map(|video_domain| {
            video_domain
                .with_artwork_uri(video.artwork_uri().map(str::to_owned))
                .with_duration_seconds(Some(video.duration_seconds()))
        })
        .map_err(|_| MusicVideoError::InvalidResponse)
}

fn album_artwork_uri(media_mid: &str) -> Option<String> {
    let safe = !media_mid.is_empty()
        && media_mid
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'));
    safe.then(|| format!("https://y.gtimg.cn/music/photo_new/T002R300x300M000{media_mid}.jpg"))
}

fn artist_artwork_uri(media_mid: &str) -> Option<String> {
    is_safe_track_mid(media_mid)
        .then(|| format!("https://y.gtimg.cn/music/photo_new/T001R300x300M000{media_mid}.jpg"))
}

fn map_lyrics(
    track_id: TrackId,
    lyrics: &QqMusicLyrics,
) -> Result<SynchronizedLyrics, LyricsError> {
    let translations = unique_auxiliary_by_start(
        lyrics
            .translation()
            .iter()
            .map(|line| (line.start_ms(), line.text())),
    );
    let romanizations = unique_auxiliary_by_start(
        lyrics
            .romanization()
            .iter()
            .map(|line| (line.start_ms(), line.text())),
    );
    let lines = lyrics
        .original()
        .iter()
        .map(|line| {
            let segments = line
                .segments()
                .iter()
                .map(|segment| {
                    TimedLyricSegment::new(
                        segment.text(),
                        segment.start_ms(),
                        segment.duration_ms(),
                    )
                    .map_err(|_| LyricsError::InvalidResponse)
                })
                .collect::<Result<Vec<_>, _>>()?;
            SynchronizedLyricLine::new(line.text(), line.start_ms(), line.duration_ms(), segments)
                .map(|mapped| {
                    mapped
                        .with_translation(auxiliary_at(&translations, line.start_ms()))
                        .with_romanization(auxiliary_at(&romanizations, line.start_ms()))
                })
                .map_err(|_| LyricsError::InvalidResponse)
        })
        .collect::<Result<Vec<_>, _>>()?;
    SynchronizedLyrics::new(track_id, lines).map_err(|_| LyricsError::InvalidResponse)
}

fn unique_auxiliary_by_start<'a>(
    lines: impl IntoIterator<Item = (u32, &'a str)>,
) -> HashMap<u32, Option<&'a str>> {
    let mut by_start = HashMap::new();
    for (start_ms, text) in lines {
        by_start
            .entry(start_ms)
            .and_modify(|current| *current = None)
            .or_insert(Some(text));
    }
    by_start
}

fn auxiliary_at(by_start: &HashMap<u32, Option<&str>>, start_ms: u32) -> Option<String> {
    by_start
        .get(&start_ms)
        .copied()
        .flatten()
        .map(str::to_owned)
}

fn map_owned_playlists_error<E>(error: &QqMusicOwnedPlaylistsError<E>) -> UserLibraryError {
    match error {
        QqMusicOwnedPlaylistsError::Transport(_) => UserLibraryError::Network,
        QqMusicOwnedPlaylistsError::HttpStatus(_) | QqMusicOwnedPlaylistsError::Upstream { .. } => {
            UserLibraryError::ServiceUnavailable
        }
        QqMusicOwnedPlaylistsError::Rejected { .. } => UserLibraryError::CredentialRejected,
        QqMusicOwnedPlaylistsError::Serialize
        | QqMusicOwnedPlaylistsError::InvalidJson
        | QqMusicOwnedPlaylistsError::MissingGlobalCode
        | QqMusicOwnedPlaylistsError::MissingResult
        | QqMusicOwnedPlaylistsError::MissingResultCode
        | QqMusicOwnedPlaylistsError::MissingData
        | QqMusicOwnedPlaylistsError::MissingPlaylists
        | QqMusicOwnedPlaylistsError::InvalidPlaylist { .. } => UserLibraryError::InvalidResponse,
    }
}

fn map_favorite_playlists_error<E>(error: &QqMusicFavoritePlaylistsError<E>) -> UserLibraryError {
    match error {
        QqMusicFavoritePlaylistsError::Transport(_) => UserLibraryError::Network,
        QqMusicFavoritePlaylistsError::HttpStatus(_)
        | QqMusicFavoritePlaylistsError::Upstream { .. } => UserLibraryError::ServiceUnavailable,
        QqMusicFavoritePlaylistsError::Rejected { .. } => UserLibraryError::CredentialRejected,
        QqMusicFavoritePlaylistsError::MissingEncryptedUin
        | QqMusicFavoritePlaylistsError::InvalidPageSize { .. }
        | QqMusicFavoritePlaylistsError::Serialize
        | QqMusicFavoritePlaylistsError::InvalidJson
        | QqMusicFavoritePlaylistsError::MissingGlobalCode
        | QqMusicFavoritePlaylistsError::MissingResult
        | QqMusicFavoritePlaylistsError::MissingResultCode
        | QqMusicFavoritePlaylistsError::MissingData
        | QqMusicFavoritePlaylistsError::MissingPlaylists
        | QqMusicFavoritePlaylistsError::MissingTotal
        | QqMusicFavoritePlaylistsError::MissingHasMore
        | QqMusicFavoritePlaylistsError::InvalidHasMore
        | QqMusicFavoritePlaylistsError::InvalidPlaylist { .. } => {
            UserLibraryError::InvalidResponse
        }
    }
}

fn map_favorite_albums_error<E>(error: &QqMusicFavoriteAlbumsError<E>) -> UserLibraryError {
    match error {
        QqMusicFavoriteAlbumsError::Rejected { .. } => UserLibraryError::CredentialRejected,
        QqMusicFavoriteAlbumsError::Transport(_) => UserLibraryError::Network,
        QqMusicFavoriteAlbumsError::HttpStatus(_) | QqMusicFavoriteAlbumsError::Upstream { .. } => {
            UserLibraryError::ServiceUnavailable
        }
        QqMusicFavoriteAlbumsError::InvalidPageSize { .. }
        | QqMusicFavoriteAlbumsError::InvalidRange
        | QqMusicFavoriteAlbumsError::InvalidJson
        | QqMusicFavoriteAlbumsError::MissingGlobalCode
        | QqMusicFavoriteAlbumsError::MissingData
        | QqMusicFavoriteAlbumsError::MissingAlbums
        | QqMusicFavoriteAlbumsError::MissingTotal
        | QqMusicFavoriteAlbumsError::MissingHasMore
        | QqMusicFavoriteAlbumsError::InvalidHasMore
        | QqMusicFavoriteAlbumsError::InvalidPagination
        | QqMusicFavoriteAlbumsError::InvalidAlbum { .. } => UserLibraryError::InvalidResponse,
    }
}

fn map_favorite_artists_error<E>(error: &QqMusicFavoriteArtistsError<E>) -> UserLibraryError {
    match error {
        QqMusicFavoriteArtistsError::Rejected { .. } => UserLibraryError::CredentialRejected,
        QqMusicFavoriteArtistsError::Transport(_) => UserLibraryError::Network,
        QqMusicFavoriteArtistsError::HttpStatus(_)
        | QqMusicFavoriteArtistsError::Upstream { .. } => UserLibraryError::ServiceUnavailable,
        QqMusicFavoriteArtistsError::MissingEncryptedUin
        | QqMusicFavoriteArtistsError::InvalidPageSize { .. }
        | QqMusicFavoriteArtistsError::Serialize
        | QqMusicFavoriteArtistsError::InvalidJson
        | QqMusicFavoriteArtistsError::MissingGlobalCode
        | QqMusicFavoriteArtistsError::MissingResult
        | QqMusicFavoriteArtistsError::MissingResultCode
        | QqMusicFavoriteArtistsError::MissingData
        | QqMusicFavoriteArtistsError::MissingArtists
        | QqMusicFavoriteArtistsError::MissingTotal
        | QqMusicFavoriteArtistsError::MissingHasMore
        | QqMusicFavoriteArtistsError::InvalidHasMore
        | QqMusicFavoriteArtistsError::InvalidPagination
        | QqMusicFavoriteArtistsError::InvalidArtist { .. } => UserLibraryError::InvalidResponse,
    }
}

fn map_playlist_detail_error<E>(error: &QqMusicPlaylistDetailError<E>) -> UserLibraryError {
    match error {
        QqMusicPlaylistDetailError::Transport(_) => UserLibraryError::Network,
        QqMusicPlaylistDetailError::HttpStatus(_) | QqMusicPlaylistDetailError::Upstream { .. } => {
            UserLibraryError::ServiceUnavailable
        }
        QqMusicPlaylistDetailError::Rejected { .. } => UserLibraryError::CredentialRejected,
        QqMusicPlaylistDetailError::InvalidPlaylistId
        | QqMusicPlaylistDetailError::MissingEncryptedUin
        | QqMusicPlaylistDetailError::InvalidPageSize { .. }
        | QqMusicPlaylistDetailError::Serialize
        | QqMusicPlaylistDetailError::InvalidJson
        | QqMusicPlaylistDetailError::MissingGlobalCode
        | QqMusicPlaylistDetailError::MissingResult
        | QqMusicPlaylistDetailError::MissingResultCode
        | QqMusicPlaylistDetailError::MissingData
        | QqMusicPlaylistDetailError::MissingTracks
        | QqMusicPlaylistDetailError::MissingTotal
        | QqMusicPlaylistDetailError::MissingHasMore
        | QqMusicPlaylistDetailError::InvalidHasMore
        | QqMusicPlaylistDetailError::InvalidTrack { .. }
        | QqMusicPlaylistDetailError::InvalidArtist { .. } => UserLibraryError::InvalidResponse,
    }
}

const fn map_library_state_to_mutation_error(error: UserLibraryError) -> LibraryMutationError {
    match error {
        UserLibraryError::AuthenticationRequired => LibraryMutationError::AuthenticationRequired,
        UserLibraryError::CredentialRejected => LibraryMutationError::CredentialRejected,
        UserLibraryError::Network => LibraryMutationError::NetworkOutcomeUnknown,
        UserLibraryError::ServiceUnavailable => LibraryMutationError::ServiceUnavailable,
        UserLibraryError::InvalidResponse => LibraryMutationError::InvalidResponseOutcomeUnknown,
        UserLibraryError::Replaced => LibraryMutationError::Replaced,
    }
}

fn map_playlist_track_error<E>(error: &QqMusicPlaylistTrackError<E>) -> LibraryMutationError {
    match error {
        QqMusicPlaylistTrackError::Transport(_) => LibraryMutationError::NetworkOutcomeUnknown,
        QqMusicPlaylistTrackError::Rejected { .. } => LibraryMutationError::CredentialRejected,
        QqMusicPlaylistTrackError::HttpStatus(_)
        | QqMusicPlaylistTrackError::Upstream { .. }
        | QqMusicPlaylistTrackError::MutationRejected { .. } => {
            LibraryMutationError::ServiceUnavailable
        }
        QqMusicPlaylistTrackError::InvalidDirectoryId
        | QqMusicPlaylistTrackError::InvalidSongId
        | QqMusicPlaylistTrackError::Serialize => LibraryMutationError::InvalidRequest,
        QqMusicPlaylistTrackError::InvalidJson
        | QqMusicPlaylistTrackError::MissingGlobalCode
        | QqMusicPlaylistTrackError::MissingResult
        | QqMusicPlaylistTrackError::MissingResultCode
        | QqMusicPlaylistTrackError::MissingData
        | QqMusicPlaylistTrackError::MissingMutationCode => {
            LibraryMutationError::InvalidResponseOutcomeUnknown
        }
    }
}

fn map_create_playlist_error<E>(error: &QqMusicCreatePlaylistError<E>) -> LibraryMutationError {
    match error {
        QqMusicCreatePlaylistError::Transport(_) => LibraryMutationError::NetworkOutcomeUnknown,
        QqMusicCreatePlaylistError::Rejected { .. } => LibraryMutationError::CredentialRejected,
        QqMusicCreatePlaylistError::HttpStatus(_)
        | QqMusicCreatePlaylistError::Upstream { .. }
        | QqMusicCreatePlaylistError::MutationRejected { .. } => {
            LibraryMutationError::ServiceUnavailable
        }
        QqMusicCreatePlaylistError::InvalidName | QqMusicCreatePlaylistError::Serialize => {
            LibraryMutationError::InvalidRequest
        }
        QqMusicCreatePlaylistError::InvalidJson
        | QqMusicCreatePlaylistError::MissingGlobalCode
        | QqMusicCreatePlaylistError::MissingResult
        | QqMusicCreatePlaylistError::MissingResultCode
        | QqMusicCreatePlaylistError::MissingData
        | QqMusicCreatePlaylistError::MissingMutationCode
        | QqMusicCreatePlaylistError::MissingCreatedResult
        | QqMusicCreatePlaylistError::MissingPlaylistId
        | QqMusicCreatePlaylistError::ConflictingPlaylistId
        | QqMusicCreatePlaylistError::MissingDirectoryId
        | QqMusicCreatePlaylistError::InvalidReturnedName => {
            LibraryMutationError::InvalidResponseOutcomeUnknown
        }
    }
}

fn map_delete_playlist_error<E>(error: &QqMusicDeletePlaylistError<E>) -> LibraryMutationError {
    match error {
        QqMusicDeletePlaylistError::Transport(_) => LibraryMutationError::NetworkOutcomeUnknown,
        QqMusicDeletePlaylistError::Rejected { .. } => LibraryMutationError::CredentialRejected,
        QqMusicDeletePlaylistError::HttpStatus(_)
        | QqMusicDeletePlaylistError::Upstream { .. }
        | QqMusicDeletePlaylistError::MutationRejected { .. } => {
            LibraryMutationError::ServiceUnavailable
        }
        QqMusicDeletePlaylistError::InvalidDirectoryId | QqMusicDeletePlaylistError::Serialize => {
            LibraryMutationError::InvalidRequest
        }
        QqMusicDeletePlaylistError::InvalidJson
        | QqMusicDeletePlaylistError::MissingGlobalCode
        | QqMusicDeletePlaylistError::MissingResult
        | QqMusicDeletePlaylistError::MissingResultCode
        | QqMusicDeletePlaylistError::MissingData
        | QqMusicDeletePlaylistError::MissingMutationCode
        | QqMusicDeletePlaylistError::MissingDeletedResult
        | QqMusicDeletePlaylistError::MissingDirectoryId
        | QqMusicDeletePlaylistError::MismatchedDirectoryId => {
            LibraryMutationError::InvalidResponseOutcomeUnknown
        }
    }
}

fn map_album_favorite_error<E>(error: &QqMusicAlbumFavoriteError<E>) -> LibraryMutationError {
    match error {
        QqMusicAlbumFavoriteError::Transport(_) => LibraryMutationError::NetworkOutcomeUnknown,
        QqMusicAlbumFavoriteError::Rejected { .. } => LibraryMutationError::CredentialRejected,
        QqMusicAlbumFavoriteError::HttpStatus(_)
        | QqMusicAlbumFavoriteError::Upstream { .. }
        | QqMusicAlbumFavoriteError::MutationRejected { .. }
        | QqMusicAlbumFavoriteError::FailedAlbumIds => LibraryMutationError::ServiceUnavailable,
        QqMusicAlbumFavoriteError::InvalidAlbumId | QqMusicAlbumFavoriteError::Serialize => {
            LibraryMutationError::InvalidRequest
        }
        QqMusicAlbumFavoriteError::InvalidJson
        | QqMusicAlbumFavoriteError::MissingGlobalCode
        | QqMusicAlbumFavoriteError::MissingResult
        | QqMusicAlbumFavoriteError::MissingResultCode
        | QqMusicAlbumFavoriteError::MissingData
        | QqMusicAlbumFavoriteError::MissingMutationCode
        | QqMusicAlbumFavoriteError::MissingFailedAlbumIds
        | QqMusicAlbumFavoriteError::InvalidFailedAlbumIds => {
            LibraryMutationError::InvalidResponseOutcomeUnknown
        }
    }
}

fn map_search_error<E>(error: &QqMusicSearchError<E>) -> SearchError {
    match error {
        QqMusicSearchError::Transport(_) => SearchError::Network,
        QqMusicSearchError::HttpStatus(_) | QqMusicSearchError::Upstream { .. } => {
            SearchError::ServiceUnavailable
        }
        QqMusicSearchError::InvalidQuery
        | QqMusicSearchError::InvalidPage { .. }
        | QqMusicSearchError::InvalidPageSize { .. }
        | QqMusicSearchError::Serialize
        | QqMusicSearchError::InvalidJson
        | QqMusicSearchError::MissingGlobalCode
        | QqMusicSearchError::MissingResult
        | QqMusicSearchError::MissingResultCode
        | QqMusicSearchError::MissingData
        | QqMusicSearchError::MissingBody
        | QqMusicSearchError::MissingSongResults
        | QqMusicSearchError::MissingTracks
        | QqMusicSearchError::MissingMeta
        | QqMusicSearchError::MissingCurrentPage
        | QqMusicSearchError::MissingNextPage
        | QqMusicSearchError::MissingTotal
        | QqMusicSearchError::InvalidPagination
        | QqMusicSearchError::InvalidTrack { .. }
        | QqMusicSearchError::InvalidArtist { .. } => SearchError::InvalidResponse,
    }
}

fn map_artist_search_error<E>(error: &QqMusicArtistSearchError<E>) -> SearchError {
    match error {
        QqMusicArtistSearchError::Transport(_) => SearchError::Network,
        QqMusicArtistSearchError::HttpStatus(_) | QqMusicArtistSearchError::Upstream { .. } => {
            SearchError::ServiceUnavailable
        }
        QqMusicArtistSearchError::InvalidQuery
        | QqMusicArtistSearchError::InvalidPage { .. }
        | QqMusicArtistSearchError::InvalidPageSize { .. }
        | QqMusicArtistSearchError::Serialize
        | QqMusicArtistSearchError::InvalidJson
        | QqMusicArtistSearchError::MissingGlobalCode
        | QqMusicArtistSearchError::MissingResult
        | QqMusicArtistSearchError::MissingResultCode
        | QqMusicArtistSearchError::MissingData
        | QqMusicArtistSearchError::MissingBody
        | QqMusicArtistSearchError::MissingArtistResults
        | QqMusicArtistSearchError::MissingArtists
        | QqMusicArtistSearchError::MissingMeta
        | QqMusicArtistSearchError::MissingCurrentPage
        | QqMusicArtistSearchError::MissingNextPage
        | QqMusicArtistSearchError::MissingTotal
        | QqMusicArtistSearchError::MissingPageSize
        | QqMusicArtistSearchError::InvalidPagination
        | QqMusicArtistSearchError::InvalidArtist { .. } => SearchError::InvalidResponse,
    }
}

fn map_album_search_error<E>(error: &QqMusicAlbumSearchError<E>) -> SearchError {
    match error {
        QqMusicAlbumSearchError::Transport(_) => SearchError::Network,
        QqMusicAlbumSearchError::HttpStatus(_) | QqMusicAlbumSearchError::Upstream { .. } => {
            SearchError::ServiceUnavailable
        }
        QqMusicAlbumSearchError::InvalidQuery
        | QqMusicAlbumSearchError::InvalidPage { .. }
        | QqMusicAlbumSearchError::InvalidPageSize { .. }
        | QqMusicAlbumSearchError::Serialize
        | QqMusicAlbumSearchError::InvalidJson
        | QqMusicAlbumSearchError::MissingGlobalCode
        | QqMusicAlbumSearchError::MissingResult
        | QqMusicAlbumSearchError::MissingResultCode
        | QqMusicAlbumSearchError::MissingData
        | QqMusicAlbumSearchError::MissingBody
        | QqMusicAlbumSearchError::MissingAlbumResults
        | QqMusicAlbumSearchError::MissingAlbums
        | QqMusicAlbumSearchError::MissingMeta
        | QqMusicAlbumSearchError::MissingCurrentPage
        | QqMusicAlbumSearchError::MissingNextPage
        | QqMusicAlbumSearchError::MissingTotal
        | QqMusicAlbumSearchError::MissingPageSize
        | QqMusicAlbumSearchError::InvalidPagination
        | QqMusicAlbumSearchError::InvalidAlbum { .. } => SearchError::InvalidResponse,
    }
}

fn map_playlist_search_error<E>(error: &QqMusicPlaylistSearchError<E>) -> SearchError {
    match error {
        QqMusicPlaylistSearchError::Transport(_) => SearchError::Network,
        QqMusicPlaylistSearchError::HttpStatus(_) | QqMusicPlaylistSearchError::Upstream { .. } => {
            SearchError::ServiceUnavailable
        }
        QqMusicPlaylistSearchError::InvalidQuery
        | QqMusicPlaylistSearchError::InvalidPage { .. }
        | QqMusicPlaylistSearchError::InvalidPageSize { .. }
        | QqMusicPlaylistSearchError::Serialize
        | QqMusicPlaylistSearchError::InvalidJson
        | QqMusicPlaylistSearchError::MissingGlobalCode
        | QqMusicPlaylistSearchError::MissingResult
        | QqMusicPlaylistSearchError::MissingResultCode
        | QqMusicPlaylistSearchError::MissingData
        | QqMusicPlaylistSearchError::MissingBody
        | QqMusicPlaylistSearchError::MissingPlaylistResults
        | QqMusicPlaylistSearchError::MissingPlaylists
        | QqMusicPlaylistSearchError::MissingMeta
        | QqMusicPlaylistSearchError::MissingCurrentPage
        | QqMusicPlaylistSearchError::MissingNextPage
        | QqMusicPlaylistSearchError::MissingTotal
        | QqMusicPlaylistSearchError::MissingPageSize
        | QqMusicPlaylistSearchError::InvalidPagination
        | QqMusicPlaylistSearchError::InvalidPlaylist { .. } => SearchError::InvalidResponse,
    }
}

fn map_album_tracks_error<E>(error: &QqMusicAlbumTracksError<E>) -> CatalogError {
    match error {
        QqMusicAlbumTracksError::Transport(_) => CatalogError::Network,
        QqMusicAlbumTracksError::HttpStatus(_) | QqMusicAlbumTracksError::Upstream { .. } => {
            CatalogError::ServiceUnavailable
        }
        QqMusicAlbumTracksError::InvalidAlbumMid
        | QqMusicAlbumTracksError::InvalidPageSize { .. }
        | QqMusicAlbumTracksError::Serialize
        | QqMusicAlbumTracksError::InvalidJson
        | QqMusicAlbumTracksError::MissingGlobalCode
        | QqMusicAlbumTracksError::MissingResult
        | QqMusicAlbumTracksError::MissingResultCode
        | QqMusicAlbumTracksError::MissingData
        | QqMusicAlbumTracksError::MissingAlbumMid
        | QqMusicAlbumTracksError::MismatchedAlbumMid
        | QqMusicAlbumTracksError::MissingOffset
        | QqMusicAlbumTracksError::MissingTotal
        | QqMusicAlbumTracksError::MissingTracks
        | QqMusicAlbumTracksError::InvalidPagination
        | QqMusicAlbumTracksError::InvalidTrack { .. }
        | QqMusicAlbumTracksError::InvalidArtist { .. } => CatalogError::InvalidResponse,
    }
}

fn map_album_details_error<E>(error: &QqMusicAlbumDetailsError<E>) -> CatalogError {
    match error {
        QqMusicAlbumDetailsError::Transport(_) => CatalogError::Network,
        QqMusicAlbumDetailsError::HttpStatus(_) | QqMusicAlbumDetailsError::Upstream { .. } => {
            CatalogError::ServiceUnavailable
        }
        QqMusicAlbumDetailsError::InvalidAlbumMid
        | QqMusicAlbumDetailsError::Serialize
        | QqMusicAlbumDetailsError::InvalidJson
        | QqMusicAlbumDetailsError::MissingGlobalCode
        | QqMusicAlbumDetailsError::MissingResult
        | QqMusicAlbumDetailsError::MissingResultCode
        | QqMusicAlbumDetailsError::MissingData
        | QqMusicAlbumDetailsError::MissingBasicInfo
        | QqMusicAlbumDetailsError::MissingSingers
        | QqMusicAlbumDetailsError::InvalidAlbum { .. }
        | QqMusicAlbumDetailsError::MismatchedAlbumMid
        | QqMusicAlbumDetailsError::InvalidArtist { .. }
        | QqMusicAlbumDetailsError::InvalidMetadata { .. } => CatalogError::InvalidResponse,
    }
}

fn map_artist_tracks_error<E>(error: &QqMusicArtistTracksError<E>) -> CatalogError {
    match error {
        QqMusicArtistTracksError::Transport(_) => CatalogError::Network,
        QqMusicArtistTracksError::HttpStatus(_) | QqMusicArtistTracksError::Upstream { .. } => {
            CatalogError::ServiceUnavailable
        }
        QqMusicArtistTracksError::InvalidArtistId
        | QqMusicArtistTracksError::InvalidArtistMid
        | QqMusicArtistTracksError::InvalidPageSize { .. }
        | QqMusicArtistTracksError::Serialize
        | QqMusicArtistTracksError::InvalidJson
        | QqMusicArtistTracksError::MissingGlobalCode
        | QqMusicArtistTracksError::MissingResult
        | QqMusicArtistTracksError::MissingResultCode
        | QqMusicArtistTracksError::MissingData
        | QqMusicArtistTracksError::MissingArtistMid
        | QqMusicArtistTracksError::MismatchedArtistMid
        | QqMusicArtistTracksError::MissingTotal
        | QqMusicArtistTracksError::MissingTracks
        | QqMusicArtistTracksError::InvalidPagination
        | QqMusicArtistTracksError::InvalidTrack { .. }
        | QqMusicArtistTracksError::InvalidArtist { .. } => CatalogError::InvalidResponse,
    }
}

fn map_artist_albums_error<E>(error: &QqMusicArtistAlbumsError<E>) -> CatalogError {
    match error {
        QqMusicArtistAlbumsError::Transport(_) => CatalogError::Network,
        QqMusicArtistAlbumsError::HttpStatus(_) | QqMusicArtistAlbumsError::Upstream { .. } => {
            CatalogError::ServiceUnavailable
        }
        QqMusicArtistAlbumsError::InvalidArtistMid
        | QqMusicArtistAlbumsError::InvalidPageSize { .. }
        | QqMusicArtistAlbumsError::Serialize
        | QqMusicArtistAlbumsError::InvalidJson
        | QqMusicArtistAlbumsError::MissingGlobalCode
        | QqMusicArtistAlbumsError::MissingResult
        | QqMusicArtistAlbumsError::MissingResultCode
        | QqMusicArtistAlbumsError::MissingData
        | QqMusicArtistAlbumsError::MissingArtistMid
        | QqMusicArtistAlbumsError::MismatchedArtistMid
        | QqMusicArtistAlbumsError::MissingTotal
        | QqMusicArtistAlbumsError::MissingAlbums
        | QqMusicArtistAlbumsError::InvalidPagination
        | QqMusicArtistAlbumsError::InvalidAlbum { .. } => CatalogError::InvalidResponse,
    }
}

fn map_new_albums_error<E>(error: &QqMusicNewAlbumsError<E>) -> CatalogError {
    match error {
        QqMusicNewAlbumsError::Transport(_) => CatalogError::Network,
        QqMusicNewAlbumsError::HttpStatus(_) | QqMusicNewAlbumsError::Upstream { .. } => {
            CatalogError::ServiceUnavailable
        }
        QqMusicNewAlbumsError::InvalidPageSize { .. }
        | QqMusicNewAlbumsError::Serialize
        | QqMusicNewAlbumsError::InvalidJson
        | QqMusicNewAlbumsError::MissingGlobalCode
        | QqMusicNewAlbumsError::MissingResult
        | QqMusicNewAlbumsError::MissingResultCode
        | QqMusicNewAlbumsError::MissingData
        | QqMusicNewAlbumsError::MissingTotal
        | QqMusicNewAlbumsError::MissingAlbums
        | QqMusicNewAlbumsError::InvalidPagination
        | QqMusicNewAlbumsError::InvalidAlbum { .. }
        | QqMusicNewAlbumsError::InvalidArtist { .. } => CatalogError::InvalidResponse,
    }
}

fn map_new_songs_error<E>(error: &QqMusicNewSongsError<E>) -> CatalogError {
    match error {
        QqMusicNewSongsError::Transport(_) => CatalogError::Network,
        QqMusicNewSongsError::HttpStatus(_) | QqMusicNewSongsError::Upstream { .. } => {
            CatalogError::ServiceUnavailable
        }
        QqMusicNewSongsError::Serialize
        | QqMusicNewSongsError::InvalidJson
        | QqMusicNewSongsError::MissingGlobalCode
        | QqMusicNewSongsError::MissingResult
        | QqMusicNewSongsError::MissingResultCode
        | QqMusicNewSongsError::MissingData
        | QqMusicNewSongsError::MissingReturnedCategory
        | QqMusicNewSongsError::MismatchedCategory
        | QqMusicNewSongsError::MissingTracks
        | QqMusicNewSongsError::TooManyTracks { .. }
        | QqMusicNewSongsError::InvalidTrack { .. }
        | QqMusicNewSongsError::InvalidArtist { .. } => CatalogError::InvalidResponse,
    }
}

fn map_recommendations_error<E>(
    error: &QqMusicRecommendedPlaylistsError<E>,
) -> RecommendationError {
    match error {
        QqMusicRecommendedPlaylistsError::Transport(_) => RecommendationError::Network,
        QqMusicRecommendedPlaylistsError::HttpStatus(_)
        | QqMusicRecommendedPlaylistsError::Upstream { .. } => {
            RecommendationError::ServiceUnavailable
        }
        QqMusicRecommendedPlaylistsError::InvalidPageSize { .. }
        | QqMusicRecommendedPlaylistsError::Serialize
        | QqMusicRecommendedPlaylistsError::InvalidJson
        | QqMusicRecommendedPlaylistsError::MissingGlobalCode
        | QqMusicRecommendedPlaylistsError::MissingResult
        | QqMusicRecommendedPlaylistsError::MissingResultCode
        | QqMusicRecommendedPlaylistsError::MissingData
        | QqMusicRecommendedPlaylistsError::MissingPlaylists
        | QqMusicRecommendedPlaylistsError::MissingHasMore
        | QqMusicRecommendedPlaylistsError::InvalidPagination
        | QqMusicRecommendedPlaylistsError::InvalidPlaylist { .. } => {
            RecommendationError::InvalidResponse
        }
    }
}

fn map_daily_recommendation_error<E>(
    error: &QqMusicDailyRecommendationError<E>,
) -> DailyRecommendationError {
    match error {
        QqMusicDailyRecommendationError::Rejected { .. } => {
            DailyRecommendationError::CredentialRejected
        }
        QqMusicDailyRecommendationError::Transport(_) => DailyRecommendationError::Network,
        QqMusicDailyRecommendationError::HttpStatus(_)
        | QqMusicDailyRecommendationError::Upstream { .. } => {
            DailyRecommendationError::ServiceUnavailable
        }
        QqMusicDailyRecommendationError::Serialize
        | QqMusicDailyRecommendationError::InvalidJson
        | QqMusicDailyRecommendationError::MissingGlobalCode
        | QqMusicDailyRecommendationError::MissingResult
        | QqMusicDailyRecommendationError::MissingResultCode
        | QqMusicDailyRecommendationError::MissingData
        | QqMusicDailyRecommendationError::MissingDataCode
        | QqMusicDailyRecommendationError::MissingShelves
        | QqMusicDailyRecommendationError::InvalidFeed
        | QqMusicDailyRecommendationError::MultipleDailyPlaylists
        | QqMusicDailyRecommendationError::InvalidDailyPlaylist { .. } => {
            DailyRecommendationError::InvalidResponse
        }
    }
}

fn map_personalized_playlists_error<E>(
    error: &QqMusicPersonalizedPlaylistsError<E>,
) -> PersonalizedPlaylistsError {
    match error {
        QqMusicPersonalizedPlaylistsError::Rejected { .. } => {
            PersonalizedPlaylistsError::CredentialRejected
        }
        QqMusicPersonalizedPlaylistsError::Transport(_) => PersonalizedPlaylistsError::Network,
        QqMusicPersonalizedPlaylistsError::HttpStatus(_)
        | QqMusicPersonalizedPlaylistsError::Upstream { .. } => {
            PersonalizedPlaylistsError::ServiceUnavailable
        }
        QqMusicPersonalizedPlaylistsError::Serialize
        | QqMusicPersonalizedPlaylistsError::InvalidJson
        | QqMusicPersonalizedPlaylistsError::MissingGlobalCode
        | QqMusicPersonalizedPlaylistsError::MissingResult
        | QqMusicPersonalizedPlaylistsError::MissingResultCode
        | QqMusicPersonalizedPlaylistsError::MissingData
        | QqMusicPersonalizedPlaylistsError::MissingDataCode
        | QqMusicPersonalizedPlaylistsError::MissingShelves
        | QqMusicPersonalizedPlaylistsError::InvalidFeed
        | QqMusicPersonalizedPlaylistsError::MultiplePlaylistShelves
        | QqMusicPersonalizedPlaylistsError::TooManyPlaylists
        | QqMusicPersonalizedPlaylistsError::DuplicatePlaylistId
        | QqMusicPersonalizedPlaylistsError::InvalidPlaylist { .. } => {
            PersonalizedPlaylistsError::InvalidResponse
        }
    }
}

fn map_personalized_tracks_error<E>(
    error: &QqMusicPersonalizedTracksError<E>,
) -> PersonalizedTracksError {
    match error {
        QqMusicPersonalizedTracksError::Rejected { .. } => {
            PersonalizedTracksError::CredentialRejected
        }
        QqMusicPersonalizedTracksError::Transport(_) => PersonalizedTracksError::Network,
        QqMusicPersonalizedTracksError::HttpStatus(_)
        | QqMusicPersonalizedTracksError::Upstream { .. } => {
            PersonalizedTracksError::ServiceUnavailable
        }
        QqMusicPersonalizedTracksError::Serialize
        | QqMusicPersonalizedTracksError::InvalidJson
        | QqMusicPersonalizedTracksError::MissingGlobalCode
        | QqMusicPersonalizedTracksError::MissingResult
        | QqMusicPersonalizedTracksError::MissingResultCode
        | QqMusicPersonalizedTracksError::MissingData
        | QqMusicPersonalizedTracksError::MissingTracks
        | QqMusicPersonalizedTracksError::TooManyTracks { .. }
        | QqMusicPersonalizedTracksError::DuplicateTrackIdentity
        | QqMusicPersonalizedTracksError::InvalidTrack { .. }
        | QqMusicPersonalizedTracksError::InvalidArtist { .. } => {
            PersonalizedTracksError::InvalidResponse
        }
    }
}

fn map_related_tracks_error<E>(error: &QqMusicRelatedTracksError<E>) -> RelatedTracksError {
    match error {
        QqMusicRelatedTracksError::Transport(_) => RelatedTracksError::Network,
        QqMusicRelatedTracksError::HttpStatus(_) | QqMusicRelatedTracksError::Upstream { .. } => {
            RelatedTracksError::ServiceUnavailable
        }
        QqMusicRelatedTracksError::InvalidSongId
        | QqMusicRelatedTracksError::Serialize
        | QqMusicRelatedTracksError::Signing
        | QqMusicRelatedTracksError::InvalidJson
        | QqMusicRelatedTracksError::MissingGlobalCode
        | QqMusicRelatedTracksError::MissingResult
        | QqMusicRelatedTracksError::MissingResultCode
        | QqMusicRelatedTracksError::MissingData
        | QqMusicRelatedTracksError::MissingTracks
        | QqMusicRelatedTracksError::TooManyTracks { .. }
        | QqMusicRelatedTracksError::DuplicateTrackIdentity
        | QqMusicRelatedTracksError::InvalidTrack { .. }
        | QqMusicRelatedTracksError::InvalidArtist { .. } => RelatedTracksError::InvalidResponse,
    }
}

fn map_radar_error<E>(error: &QqMusicRadarError<E>) -> RadarRecommendationError {
    match error {
        QqMusicRadarError::Rejected { .. } => RadarRecommendationError::CredentialRejected,
        QqMusicRadarError::Transport(_) => RadarRecommendationError::Network,
        QqMusicRadarError::HttpStatus(_) | QqMusicRadarError::Upstream { .. } => {
            RadarRecommendationError::ServiceUnavailable
        }
        QqMusicRadarError::InvalidPage { .. }
        | QqMusicRadarError::Serialize
        | QqMusicRadarError::InvalidJson
        | QqMusicRadarError::MissingGlobalCode
        | QqMusicRadarError::MissingResult
        | QqMusicRadarError::MissingResultCode
        | QqMusicRadarError::MissingData
        | QqMusicRadarError::MissingTracks
        | QqMusicRadarError::MissingHasMore
        | QqMusicRadarError::InvalidPagination
        | QqMusicRadarError::InvalidTrack { .. }
        | QqMusicRadarError::InvalidArtist { .. } => RadarRecommendationError::InvalidResponse,
    }
}

fn map_rankings_error<E>(error: &QqMusicRankingsError<E>) -> CatalogError {
    match error {
        QqMusicRankingsError::Transport(_) => CatalogError::Network,
        QqMusicRankingsError::HttpStatus(_) | QqMusicRankingsError::Upstream { .. } => {
            CatalogError::ServiceUnavailable
        }
        QqMusicRankingsError::InvalidRankingId
        | QqMusicRankingsError::InvalidPageSize { .. }
        | QqMusicRankingsError::Serialize
        | QqMusicRankingsError::InvalidJson
        | QqMusicRankingsError::MissingGlobalCode
        | QqMusicRankingsError::MissingResult
        | QqMusicRankingsError::MissingResultCode
        | QqMusicRankingsError::MissingData
        | QqMusicRankingsError::MissingGroups
        | QqMusicRankingsError::InvalidGroup { .. }
        | QqMusicRankingsError::InvalidRanking { .. }
        | QqMusicRankingsError::MismatchedRankingId
        | QqMusicRankingsError::MissingTotal
        | QqMusicRankingsError::MissingTracks
        | QqMusicRankingsError::InvalidPagination
        | QqMusicRankingsError::InvalidTrack { .. }
        | QqMusicRankingsError::InvalidArtist { .. } => CatalogError::InvalidResponse,
    }
}

fn map_comments_error<E>(error: &QqMusicTrackCommentsError<E>) -> CommentsError {
    match error {
        QqMusicTrackCommentsError::Transport(_) => CommentsError::Network,
        QqMusicTrackCommentsError::HttpStatus(_) | QqMusicTrackCommentsError::Upstream { .. } => {
            CommentsError::ServiceUnavailable
        }
        QqMusicTrackCommentsError::InvalidSongId
        | QqMusicTrackCommentsError::InvalidPageSize { .. }
        | QqMusicTrackCommentsError::InvalidOffset { .. }
        | QqMusicTrackCommentsError::InvalidJson
        | QqMusicTrackCommentsError::MissingLatestComments
        | QqMusicTrackCommentsError::MissingTotal
        | QqMusicTrackCommentsError::InvalidPagination
        | QqMusicTrackCommentsError::InvalidComment { .. } => CommentsError::InvalidResponse,
    }
}

fn map_music_video_error<E>(error: &QqMusicTrackMusicVideoError<E>) -> MusicVideoError {
    match error {
        QqMusicTrackMusicVideoError::Transport { .. } => MusicVideoError::Network,
        QqMusicTrackMusicVideoError::HttpStatus { .. }
        | QqMusicTrackMusicVideoError::Upstream { .. } => MusicVideoError::ServiceUnavailable,
        QqMusicTrackMusicVideoError::SourceUnavailable => MusicVideoError::SourceUnavailable,
        QqMusicTrackMusicVideoError::InvalidSongMid
        | QqMusicTrackMusicVideoError::RandomnessUnavailable
        | QqMusicTrackMusicVideoError::Serialize(_)
        | QqMusicTrackMusicVideoError::InvalidJson(_)
        | QqMusicTrackMusicVideoError::InvalidResponse { .. } => MusicVideoError::InvalidResponse,
    }
}

fn map_media_error<E>(error: &QqMusicMediaError<E>) -> MediaResolutionError {
    match error {
        QqMusicMediaError::Transport { .. } => MediaResolutionError::Network,
        QqMusicMediaError::HttpStatus { .. } | QqMusicMediaError::Upstream { .. } => {
            MediaResolutionError::ServiceUnavailable
        }
        QqMusicMediaError::Rejected { .. } => MediaResolutionError::CredentialRejected,
        QqMusicMediaError::Unavailable { .. } => MediaResolutionError::Unavailable,
        QqMusicMediaError::RandomnessUnavailable | QqMusicMediaError::Serialize(_) => {
            MediaResolutionError::CoreUnavailable
        }
        QqMusicMediaError::InvalidSongMid
        | QqMusicMediaError::InvalidFileMediaMid
        | QqMusicMediaError::InvalidJson(_)
        | QqMusicMediaError::InvalidResponse { .. } => MediaResolutionError::InvalidResponse,
    }
}

fn map_lyrics_error<E>(error: &QqMusicLyricsError<E>) -> LyricsError {
    match error {
        QqMusicLyricsError::Transport(_) => LyricsError::Network,
        QqMusicLyricsError::HttpStatus(_) | QqMusicLyricsError::Upstream { .. } => {
            LyricsError::ServiceUnavailable
        }
        QqMusicLyricsError::Rejected { .. } => LyricsError::CredentialRejected,
        QqMusicLyricsError::Unavailable => LyricsError::Unavailable,
        QqMusicLyricsError::InvalidSongMid
        | QqMusicLyricsError::Serialize
        | QqMusicLyricsError::InvalidJson
        | QqMusicLyricsError::MissingGlobalCode
        | QqMusicLyricsError::MissingResult
        | QqMusicLyricsError::MissingResultCode
        | QqMusicLyricsError::MissingData
        | QqMusicLyricsError::MissingLyrics
        | QqMusicLyricsError::InvalidDocument { .. } => LyricsError::InvalidResponse,
    }
}

fn map_login_error<E>(error: WechatQrLoginError<E>) -> AuthenticationError {
    match error {
        WechatQrLoginError::Protocol(error) => map_qr_error(&error),
        WechatQrLoginError::QqProtocol(error) => map_qq_qr_error(&error),
        WechatQrLoginError::CredentialExchange(error) => map_exchange_error(&error),
        WechatQrLoginError::Cancelled => AuthenticationError::Cancelled,
        WechatQrLoginError::Superseded => AuthenticationError::Replaced,
        WechatQrLoginError::CoordinatorClosed => AuthenticationError::SessionClosed,
        WechatQrLoginError::SessionFinished => AuthenticationError::SessionFinished,
        WechatQrLoginError::SessionTimedOut => AuthenticationError::TimedOut,
        WechatQrLoginError::TransportFailureLimitReached { .. } => {
            AuthenticationError::TooManyNetworkFailures
        }
    }
}

fn map_qq_qr_error<E>(error: &QqQrError<E>) -> AuthenticationError {
    match error {
        QqQrError::Transport(_) => AuthenticationError::Network,
        QqQrError::HttpStatus { .. } => AuthenticationError::ServiceUnavailable,
        QqQrError::Credential(qqmusic_client::LoginCredentialError::Upstream { .. }) => {
            AuthenticationError::Rejected
        }
        QqQrError::InvalidImage
        | QqQrError::MissingQrsig
        | QqQrError::InvalidCookie
        | QqQrError::ClockBeforeUnixEpoch
        | QqQrError::RandomnessUnavailable
        | QqQrError::ResponseNotUtf8
        | QqQrError::InvalidPollResponse
        | QqQrError::UnrecognizedPollStatus(_)
        | QqQrError::MissingAuthorization
        | QqQrError::MissingPSkey
        | QqQrError::MissingRedirect
        | QqQrError::MissingAuthorizationCode
        | QqQrError::Serialize
        | QqQrError::Credential(_) => AuthenticationError::InvalidResponse,
    }
}

fn map_phone_login_error<E>(error: &PhoneLoginError<E>) -> AuthenticationError {
    match error {
        PhoneLoginError::Transport(_) => AuthenticationError::Network,
        PhoneLoginError::HttpStatus(_) => AuthenticationError::ServiceUnavailable,
        PhoneLoginError::Upstream(_)
        | PhoneLoginError::Credential(qqmusic_client::LoginCredentialError::Upstream { .. }) => {
            AuthenticationError::Rejected
        }
        PhoneLoginError::Invalid(_)
        | PhoneLoginError::Serialize
        | PhoneLoginError::InvalidJson
        | PhoneLoginError::MissingResult
        | PhoneLoginError::Credential(_) => AuthenticationError::InvalidResponse,
    }
}

fn map_qr_error<E>(error: &WechatQrError<E>) -> AuthenticationError {
    match error {
        WechatQrError::Transport(_) => AuthenticationError::Network,
        WechatQrError::HttpStatus { .. } => AuthenticationError::ServiceUnavailable,
        WechatQrError::ConnectPageTooLarge
        | WechatQrError::ConnectPageNotUtf8
        | WechatQrError::MissingIdentifier
        | WechatQrError::InvalidIdentifier
        | WechatQrError::ImageTooLarge
        | WechatQrError::InvalidImage
        | WechatQrError::ClockBeforeUnixEpoch
        | WechatQrError::PollResponseTooLarge
        | WechatQrError::PollResponseNotUtf8
        | WechatQrError::MissingPollStatus
        | WechatQrError::InvalidPollStatus
        | WechatQrError::MissingAuthorizationCode
        | WechatQrError::UnrecognizedPollStatus { .. } => AuthenticationError::InvalidResponse,
    }
}

fn map_exchange_error<E>(error: &WechatCredentialExchangeError<E>) -> AuthenticationError {
    match error {
        WechatCredentialExchangeError::Transport(_) => AuthenticationError::Network,
        WechatCredentialExchangeError::HttpStatus(_) => AuthenticationError::ServiceUnavailable,
        WechatCredentialExchangeError::Upstream { .. } => AuthenticationError::Rejected,
        WechatCredentialExchangeError::Serialize
        | WechatCredentialExchangeError::InvalidJson
        | WechatCredentialExchangeError::MissingGlobalCode
        | WechatCredentialExchangeError::MissingLoginResult
        | WechatCredentialExchangeError::MissingCredentialData
        | WechatCredentialExchangeError::InvalidCredential(_)
        | WechatCredentialExchangeError::InvalidExpiry(_)
        | WechatCredentialExchangeError::UnexpectedLoginType(_) => {
            AuthenticationError::InvalidResponse
        }
    }
}

fn map_verification_error<E>(error: &CredentialVerificationError<E>) -> AuthenticationError {
    match error {
        CredentialVerificationError::Transport(_) => AuthenticationError::Network,
        CredentialVerificationError::HttpStatus(_)
        | CredentialVerificationError::Upstream { .. } => AuthenticationError::ServiceUnavailable,
        CredentialVerificationError::Rejected { .. } => AuthenticationError::Rejected,
        CredentialVerificationError::Serialize
        | CredentialVerificationError::InvalidJson
        | CredentialVerificationError::MissingGlobalCode
        | CredentialVerificationError::MissingVerificationResult
        | CredentialVerificationError::MissingVerificationCode => {
            AuthenticationError::InvalidResponse
        }
    }
}

fn map_account_summary_error<E>(error: &CredentialVerificationError<E>) -> AccountSummaryError {
    match error {
        CredentialVerificationError::Transport(_) => AccountSummaryError::Network,
        CredentialVerificationError::HttpStatus(_)
        | CredentialVerificationError::Upstream { .. } => AccountSummaryError::ServiceUnavailable,
        CredentialVerificationError::Rejected { .. } => AccountSummaryError::CredentialRejected,
        CredentialVerificationError::Serialize
        | CredentialVerificationError::InvalidJson
        | CredentialVerificationError::MissingGlobalCode
        | CredentialVerificationError::MissingVerificationResult
        | CredentialVerificationError::MissingVerificationCode => {
            AccountSummaryError::InvalidResponse
        }
    }
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::convert::Infallible;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{Arc, Mutex};

    use super::{QqMusicCredentialRestoreState, QqMusicProvider};
    use music_domain::{
        AlbumId, ArtistId, AudioFormat, AudioQuality, NewAlbumRegion, NewSongCategory, PlaylistId,
        PlaylistOwnership, PlaylistPurpose, ProviderId, RankingId, TrackId,
    };
    use provider_api::{
        AccountSummaryError, AccountSummaryProvider, AlbumDetailsProvider,
        AlbumFavoriteMutationProvider, AlbumSearchProvider, AlbumTracksProvider,
        ArtistAlbumsProvider, ArtistSearchProvider, ArtistTracksProvider, CatalogError,
        CommentsError, DailyRecommendationError, DailyRecommendationProvider,
        FavoriteAlbumsProvider, FavoriteArtistsProvider, LibraryMutationError, LyricsError,
        LyricsProvider, MediaResolutionError, MediaSourceResolver, MusicProvider, MusicVideoError,
        NewAlbumReleasesProvider, NewSongsProvider, OwnedPlaylistsProvider,
        PersonalizedPlaylistsError, PersonalizedPlaylistsProvider, PersonalizedTracksError,
        PersonalizedTracksProvider, PhoneAuthenticationCodeState, PhoneAuthenticationProvider,
        PhoneAuthenticationSession, PlaylistCreationProvider, PlaylistDeletionProvider,
        PlaylistDetailsProvider, PlaylistSearchProvider, PlaylistTrackMutationProvider,
        ProviderCapability, QrAuthenticationChannel, QrAuthenticationProgress,
        QrAuthenticationProvider, QrAuthenticationSession, QrImageFormat, RadarRecommendationError,
        RadarRecommendationsProvider, RankingsProvider, RecommendationError,
        RecommendedPlaylistsProvider, RelatedTracksError, RelatedTracksProvider, SearchError,
        TrackCommentsProvider, TrackLikeMutationProvider, TrackMusicVideoProvider,
        TrackSearchProvider, UserLibraryError, UserPlaylistsProvider,
    };
    use qqmusic_client::{
        Credential, CredentialExpiry, CredentialSessionSecrets, HttpMethod, HttpRequest,
        HttpResponse, HttpTransport, LoginType, QqMusicAlbumDetailsError, QqMusicAlbumSearchError,
        QqMusicAlbumTracksError, QqMusicArtistAlbumsError, QqMusicArtistSearchError,
        QqMusicArtistTracksError, QqMusicClient, QqMusicDailyRecommendationError,
        QqMusicFavoriteAlbumsError, QqMusicFavoriteArtistsError, QqMusicNewAlbumsError,
        QqMusicNewSongsError, QqMusicPersonalizedPlaylistsError, QqMusicPersonalizedTracksError,
        QqMusicPlaylistSearchError, QqMusicRadarError, QqMusicRankingsError,
        QqMusicRecommendedPlaylistsError, QqMusicSearchError, QqMusicTrackCommentsError,
        QqMusicTrackMusicVideoError,
    };
    use serde_json::{Value, json};
    use tokio::sync::Notify;

    struct SuccessfulAuthenticationTransport;

    struct PhoneAuthenticationTransport {
        responses: Mutex<VecDeque<HttpResponse>>,
    }

    struct VerificationTransport {
        response: HttpResponse,
    }

    impl PhoneAuthenticationTransport {
        fn successful() -> Self {
            Self {
                responses: Mutex::new(
                    [
                        json!({
                            "code": 0,
                            "req_0": {"code": 0, "data": {}}
                        }),
                        json!({
                            "code": 0,
                            "req_0": {
                                "code": 0,
                                "data": {
                                    "str_musicid": "123456",
                                    "musickey": "private-phone-key",
                                    "loginType": 2
                                }
                            }
                        }),
                    ]
                    .into_iter()
                    .map(|value| {
                        HttpResponse::new(
                            200,
                            serde_json::to_vec(&value).expect("phone fixture JSON"),
                        )
                    })
                    .collect(),
                ),
            }
        }
    }

    struct OwnedPlaylistsTransport {
        response: HttpResponse,
    }

    struct UserPlaylistsTransport {
        responses: Mutex<VecDeque<HttpResponse>>,
        requests: Mutex<Vec<HttpRequest>>,
    }

    struct PlaylistDetailTransport {
        responses: Mutex<VecDeque<HttpResponse>>,
        requests: Mutex<Vec<HttpRequest>>,
    }

    struct SearchTransport {
        response: HttpResponse,
    }

    struct TrackLikeTransport {
        response: HttpResponse,
        requests: Mutex<Vec<HttpRequest>>,
    }

    struct MediaTransport {
        responses: Mutex<VecDeque<HttpResponse>>,
        requests: Mutex<Vec<HttpRequest>>,
    }

    struct LyricsTransport {
        response: Mutex<Option<HttpResponse>>,
        requests: Mutex<Vec<HttpRequest>>,
    }

    const SYNTHETIC_ORIGINAL_LYRIC: &str = "6447440FA5912BEC47EBDC0F7AB9DBF847898BC76ABCB709C0C54D9D6978ECB97215F4B28B51CCAE8B4EB4770A40E946F617E688A35972D20678A27250A2CC7A27B47B4F03BC55A3A2C612D6BB5D5E1F84A193DD1300931765FDCE14968B9672AC39037736BFCF7477FFB1FC1A30262A2642D946938797373D17F93807532D4521F920DE15943C1C159ECE086BD712BBD41B53DB6F9B3611440AD23536818A61FCDEA679DAB19A08";
    const SYNTHETIC_TRANSLATION_LYRIC: &str = "32DABB4C5E9846FA45D76834744321F1D6DEBD05CD29B5D704D95053C04BB7107871D3901D3239B44E462C5D14EF95C3";
    const SYNTHETIC_ROMANIZATION_LYRIC: &str =
        "32DABB4C5E9846FAF51AD82250F0023B114969FFF15F2E8D0463E1D98F0635733405C33283708F7F";

    impl OwnedPlaylistsTransport {
        fn new(code: i64) -> Self {
            Self {
                response: HttpResponse::new(
                    200,
                    serde_json::to_vec(&json!({
                        "code": 0,
                        "music.musicasset.PlaylistBaseRead": {
                            "code": code,
                            "data": {
                                "v_playlist": [{
                                    "tid": 7001,
                                    "dirId": 201,
                                    "dirName": "Synthetic liked songs",
                                    "picUrl": "https://example.invalid/liked.jpg",
                                    "songNum": 42
                                }]
                            }
                        }
                    }))
                    .expect("fixture JSON"),
                ),
            }
        }
    }

    impl UserPlaylistsTransport {
        fn new(favorite_responses: impl IntoIterator<Item = Value>) -> Self {
            let owned = json!({
                "code": 0,
                "music.musicasset.PlaylistBaseRead": {
                    "code": 0,
                    "data": {
                        "v_playlist": [
                            {
                                "tid": 7001,
                                "dirId": 201,
                                "dirName": "Synthetic liked songs",
                                "songNum": 42
                            },
                            {
                                "tid": 7002,
                                "dirId": 202,
                                "dirName": "Synthetic owned list"
                            }
                        ]
                    }
                }
            });
            let responses = std::iter::once(owned)
                .chain(favorite_responses)
                .map(|response| {
                    HttpResponse::new(200, serde_json::to_vec(&response).expect("fixture JSON"))
                })
                .collect();
            Self {
                responses: Mutex::new(responses),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn requests(&self) -> Vec<HttpRequest> {
            self.requests.lock().expect("request lock").clone()
        }
    }

    impl PlaylistDetailTransport {
        fn new(responses: impl IntoIterator<Item = Value>) -> Self {
            Self {
                responses: Mutex::new(
                    responses
                        .into_iter()
                        .map(|response| {
                            HttpResponse::new(
                                200,
                                serde_json::to_vec(&response).expect("fixture JSON"),
                            )
                        })
                        .collect(),
                ),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn requests(&self) -> Vec<HttpRequest> {
            self.requests.lock().expect("request lock").clone()
        }
    }

    impl SearchTransport {
        fn new(response: &Value) -> Self {
            Self {
                response: HttpResponse::new(
                    200,
                    serde_json::to_vec(&response).expect("fixture JSON"),
                ),
            }
        }
    }

    impl MediaTransport {
        fn new<const N: usize>(responses: [Value; N]) -> Self {
            Self {
                responses: Mutex::new(
                    responses
                        .into_iter()
                        .map(|response| {
                            HttpResponse::new(
                                200,
                                serde_json::to_vec(&response).expect("fixture JSON"),
                            )
                        })
                        .collect(),
                ),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn requests(&self) -> Vec<HttpRequest> {
            self.requests.lock().expect("request lock").clone()
        }
    }

    impl LyricsTransport {
        fn new(response: &Value) -> Self {
            Self {
                response: Mutex::new(Some(HttpResponse::new(
                    200,
                    serde_json::to_vec(response).expect("fixture JSON"),
                ))),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn requests(&self) -> Vec<HttpRequest> {
            self.requests.lock().expect("request lock").clone()
        }
    }

    impl HttpTransport for OwnedPlaylistsTransport {
        type Error = Infallible;

        async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            Ok(self.response.clone())
        }
    }

    impl HttpTransport for UserPlaylistsTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("request lock").push(request);
            Ok(self
                .responses
                .lock()
                .expect("response lock")
                .pop_front()
                .expect("fixture response"))
        }
    }

    impl HttpTransport for PlaylistDetailTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("request lock").push(request);
            Ok(self
                .responses
                .lock()
                .expect("response lock")
                .pop_front()
                .expect("fixture response"))
        }
    }

    impl HttpTransport for SearchTransport {
        type Error = Infallible;

        async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            Ok(self.response.clone())
        }
    }

    impl TrackLikeTransport {
        fn new(response: &Value) -> Self {
            Self {
                response: HttpResponse::new(
                    200,
                    serde_json::to_vec(response).expect("fixture JSON"),
                ),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn requests(&self) -> Vec<HttpRequest> {
            self.requests.lock().expect("request lock").clone()
        }
    }

    impl HttpTransport for TrackLikeTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("request lock").push(request);
            Ok(self.response.clone())
        }
    }

    impl HttpTransport for MediaTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("request lock").push(request);
            Ok(self
                .responses
                .lock()
                .expect("response lock")
                .pop_front()
                .expect("fixture response"))
        }
    }

    impl HttpTransport for LyricsTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("request lock").push(request);
            Ok(self
                .response
                .lock()
                .expect("response lock")
                .take()
                .expect("fixture response"))
        }
    }

    impl VerificationTransport {
        fn new(code: i64) -> Self {
            Self {
                response: HttpResponse::new(
                    200,
                    serde_json::to_vec(&json!({
                        "code": 0,
                        "music.UserInfo.userInfoServer": {
                            "code": code,
                            "data": {
                                "info": {
                                    "nick": "Synthetic listener",
                                    "logo": "https://example.invalid/avatar.jpg"
                                }
                            }
                        }
                    }))
                    .expect("fixture JSON"),
                ),
            }
        }
    }

    impl HttpTransport for VerificationTransport {
        type Error = Infallible;

        async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            Ok(self.response.clone())
        }
    }

    #[derive(Clone)]
    struct GatedVerificationTransport {
        verification_started: Arc<Notify>,
        release_verification: Arc<Notify>,
    }

    #[derive(Clone)]
    struct GatedOwnedPlaylistsTransport {
        request_started: Arc<Notify>,
        release_request: Arc<Notify>,
    }

    #[derive(Clone)]
    struct GatedFavoritePlaylistsTransport {
        favorite_started: Arc<Notify>,
        release_favorite: Arc<Notify>,
    }

    #[derive(Clone)]
    struct GatedFavoriteAlbumsTransport {
        request_started: Arc<Notify>,
        release_request: Arc<Notify>,
    }

    #[derive(Clone)]
    struct GatedFavoriteArtistsTransport {
        request_started: Arc<Notify>,
        release_request: Arc<Notify>,
    }

    #[derive(Clone)]
    struct GatedPlaylistDetailTransport {
        request_started: Arc<Notify>,
        release_request: Arc<Notify>,
    }

    #[derive(Clone)]
    struct GatedTrackLikeTransport {
        request_started: Arc<Notify>,
        release_request: Arc<Notify>,
    }

    #[derive(Clone)]
    struct GatedMediaTransport {
        gate_call: usize,
        calls: Arc<AtomicUsize>,
        request_started: Arc<Notify>,
        release_request: Arc<Notify>,
    }

    #[derive(Clone)]
    struct GatedLyricsTransport {
        request_started: Arc<Notify>,
        release_request: Arc<Notify>,
    }

    #[derive(Clone)]
    struct GatedRadarTransport {
        request_started: Arc<Notify>,
        release_request: Arc<Notify>,
    }

    #[derive(Clone)]
    struct GatedDailyTransport {
        request_started: Arc<Notify>,
        release_request: Arc<Notify>,
    }

    impl HttpTransport for GatedOwnedPlaylistsTransport {
        type Error = Infallible;

        async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.request_started.notify_one();
            self.release_request.notified().await;
            Ok(OwnedPlaylistsTransport::new(0).response)
        }
    }

    impl HttpTransport for GatedFavoritePlaylistsTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            let body: Value =
                serde_json::from_slice(request.body_bytes().expect("library request body"))
                    .expect("request JSON");
            if body.get("music.musicasset.PlaylistFavRead").is_some() {
                self.favorite_started.notify_one();
                self.release_favorite.notified().await;
                return Ok(favorite_page_response(
                    &json!([{"id": 8001, "title": "Late favorite"}]),
                    1,
                    false,
                ));
            }
            Ok(OwnedPlaylistsTransport::new(0).response)
        }
    }

    impl HttpTransport for GatedFavoriteAlbumsTransport {
        type Error = Infallible;

        async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.request_started.notify_one();
            self.release_request.notified().await;
            Ok(HttpResponse::new(
                200,
                serde_json::to_vec(&favorite_album_page_json(
                    &json!([{
                        "albumid": 43001,
                        "albummid": "fixtureAlbumMid",
                        "albumname": "Late favorite Album"
                    }]),
                    1,
                    false,
                ))
                .expect("fixture JSON"),
            ))
        }
    }

    impl HttpTransport for GatedFavoriteArtistsTransport {
        type Error = Infallible;

        async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.request_started.notify_one();
            self.release_request.notified().await;
            Ok(HttpResponse::new(
                200,
                serde_json::to_vec(&favorite_artist_page_json(
                    &json!([{
                        "MID": "fixtureArtistMid",
                        "Name": "Late favorite Artist"
                    }]),
                    1,
                    false,
                ))
                .expect("fixture JSON"),
            ))
        }
    }

    impl HttpTransport for GatedPlaylistDetailTransport {
        type Error = Infallible;

        async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.request_started.notify_one();
            self.release_request.notified().await;
            Ok(HttpResponse::new(
                200,
                serde_json::to_vec(&playlist_detail_page_json(
                    &playlist_track_fixture(),
                    1,
                    false,
                ))
                .expect("fixture JSON"),
            ))
        }
    }

    impl HttpTransport for GatedTrackLikeTransport {
        type Error = Infallible;

        async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.request_started.notify_one();
            self.release_request.notified().await;
            Ok(HttpResponse::new(
                200,
                serde_json::to_vec(&json!({
                    "code": 0,
                    "req_0": {"code": 0, "data": {"retCode": 0}}
                }))
                .expect("fixture JSON"),
            ))
        }
    }

    impl HttpTransport for GatedMediaTransport {
        type Error = Infallible;

        async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            let call = self.calls.fetch_add(1, Ordering::SeqCst) + 1;
            if call == self.gate_call {
                self.request_started.notify_one();
                self.release_request.notified().await;
            }
            let response = match call {
                1 => media_dispatch_json(),
                2 => high_media_vkey_json(101_404, ""),
                _ => media_vkey_json(0, "M500fixtureFileMid1.mp3?vkey=private"),
            };
            Ok(HttpResponse::new(
                200,
                serde_json::to_vec(&response).expect("fixture JSON"),
            ))
        }
    }

    impl HttpTransport for GatedLyricsTransport {
        type Error = Infallible;

        async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.request_started.notify_one();
            self.release_request.notified().await;
            Ok(HttpResponse::new(
                200,
                serde_json::to_vec(&lyrics_success_json()).expect("fixture JSON"),
            ))
        }
    }

    impl HttpTransport for GatedRadarTransport {
        type Error = Infallible;

        async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.request_started.notify_one();
            self.release_request.notified().await;
            Ok(HttpResponse::new(
                200,
                serde_json::to_vec(&radar_response(0, false)).expect("fixture JSON"),
            ))
        }
    }

    impl HttpTransport for GatedDailyTransport {
        type Error = Infallible;

        async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.request_started.notify_one();
            self.release_request.notified().await;
            Ok(HttpResponse::new(
                200,
                serde_json::to_vec(&daily_response(&[daily_card(
                    "7251579717",
                    "Late Daily 30",
                )]))
                .expect("fixture JSON"),
            ))
        }
    }

    impl HttpTransport for GatedVerificationTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            if request.method() == HttpMethod::Post {
                self.verification_started.notify_one();
                self.release_verification.notified().await;
                return Ok(VerificationTransport::new(0).response);
            }
            if request.url() == "https://open.weixin.qq.com/connect/qrconnect" {
                return Ok(HttpResponse::new(
                    200,
                    br#"<a href="?uuid=replacement-fixture">login</a>"#.to_vec(),
                ));
            }
            Ok(HttpResponse::new(
                200,
                b"\xff\xd8\xffreplacement-qr".to_vec(),
            ))
        }
    }

    impl HttpTransport for SuccessfulAuthenticationTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            if request.url() == "https://open.weixin.qq.com/connect/qrconnect" {
                return Ok(HttpResponse::new(
                    200,
                    br#"<a href="?uuid=provider-fixture">login</a>"#.to_vec(),
                ));
            }
            if request
                .url()
                .starts_with("https://open.weixin.qq.com/connect/qrcode/")
            {
                return Ok(HttpResponse::new(
                    200,
                    b"\xff\xd8\xffprivate-qr-fixture".to_vec(),
                ));
            }
            if request.method() == HttpMethod::Get {
                return Ok(HttpResponse::new(
                    200,
                    b"window.wx_errcode=405;window.wx_code='private-oauth-code';".to_vec(),
                ));
            }

            Ok(HttpResponse::new(
                200,
                br#"{
                    "code": 0,
                    "music.login.LoginServer.Login": {
                        "code": 0,
                        "data": {
                            "str_musicid": "123456",
                            "musickey": "private-music-key",
                            "refresh_token": "private-refresh-token"
                        }
                    }
                }"#
                .to_vec(),
            ))
        }
    }

    impl HttpTransport for PhoneAuthenticationTransport {
        type Error = Infallible;

        async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            Ok(self
                .responses
                .lock()
                .expect("phone response lock")
                .pop_front()
                .expect("phone fixture response"))
        }
    }

    #[test]
    fn descriptor_claims_only_implemented_capabilities() {
        let provider = QqMusicProvider::new(QqMusicClient::new(()));
        let descriptor = provider.descriptor();

        assert_eq!(descriptor.id.as_str(), "qq-music");
        assert_eq!(descriptor.display_name, "QQ Music");
        assert_eq!(
            descriptor.capabilities,
            [
                ProviderCapability::Search,
                ProviderCapability::Catalog,
                ProviderCapability::Recommendations,
                ProviderCapability::Authentication,
                ProviderCapability::UserLibrary,
                ProviderCapability::PlaylistMutation,
                ProviderCapability::Lyrics,
                ProviderCapability::Comments,
                ProviderCapability::MusicVideo,
            ]
        );
    }

    #[tokio::test]
    async fn maps_opaque_track_to_provider_neutral_read_only_comments() {
        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "hot_comment": {"commentlist": [{
                "commentid": "91001",
                "nick": "Synthetic hot author",
                "rootcommentcontent": "Synthetic hot comment",
                "praisenum": 41,
                "time": 1_700_000_001
            }]},
            "comment": {
                "commenttotal": 21,
                "commentlist": [{
                    "commentid": 92001,
                    "nick": "Synthetic latest author",
                    "rootcommentcontent": "Synthetic latest comment",
                    "praisenum": 7,
                    "time": 1_700_000_002
                }]
            }
        }))));

        let page = provider
            .track_comments(
                qq_track_id("track:41001:0:fixtureTrackMid1:fixtureFileMid1"),
                0,
                20,
            )
            .await
            .expect("provider comments");

        assert_eq!(page.total(), 21);
        assert!(page.has_more());
        assert_eq!(page.hot_comments()[0].id().provider().as_str(), "qq-music");
        assert_eq!(page.hot_comments()[0].id().opaque(), "comment:91001");
        assert_eq!(
            page.latest_comments()[0].author_display_name(),
            "Synthetic latest author"
        );
        let debug = format!("{page:?} {:?}", page.latest_comments()[0]);
        assert!(!debug.contains("Synthetic latest"));
        assert!(!debug.contains("92001"));
    }

    #[tokio::test]
    async fn rejects_foreign_comment_identity_and_maps_comment_failures() {
        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({}))));
        let foreign = TrackId::new(
            ProviderId::new("local").expect("provider"),
            "track:41001:0:fixtureTrackMid1:fixtureFileMid1",
        )
        .expect("track ID");
        assert_eq!(
            provider.track_comments(foreign, 0, 20).await,
            Err(CommentsError::InvalidResponse)
        );
        assert_eq!(
            super::map_comments_error(&QqMusicTrackCommentsError::<Infallible>::HttpStatus(503)),
            CommentsError::ServiceUnavailable
        );
        assert_eq!(
            super::map_comments_error(&QqMusicTrackCommentsError::<Infallible>::InvalidJson),
            CommentsError::InvalidResponse
        );
    }

    #[tokio::test]
    async fn maps_exact_track_associated_mv_without_exposing_qq_shapes() {
        let provider = QqMusicProvider::new(QqMusicClient::new(MediaTransport::new([
            json!({
                "code": 0,
                "songinfo": {
                    "code": 0,
                    "data": {"track_info": {
                        "mid": "fixtureTrackMid1",
                        "mv": {"vid": "fixtureMvVid"}
                    }}
                }
            }),
            json!({
                "code": 0,
                "mvinfo": {"code": 0, "data": {"fixtureMvVid": {
                    "vid": "fixtureMvVid",
                    "name": "Synthetic MV",
                    "cover_pic": "https://example.invalid/synthetic-cover.jpg",
                    "duration": 181,
                    "singers": [{"name": "Synthetic Artist"}]
                }}},
                "mvurl": {"code": 0, "data": {"fixtureMvVid": {"mp4": [{
                    "code": 0,
                    "filetype": 30,
                    "freeflow_url": ["https://example.invalid/private-mv.mp4"],
                    "url": [],
                    "comm_url": []
                }]}}}
            }),
        ])));

        let video = provider
            .track_music_video(qq_track_id(
                "track:41001:0:fixtureTrackMid1:fixtureFileMid1",
            ))
            .await
            .expect("provider MV")
            .expect("associated MV");
        assert_eq!(video.id().provider().as_str(), "qq-music");
        assert_eq!(video.id().opaque(), "mv:fixtureMvVid");
        assert_eq!(video.title(), "Synthetic MV");
        assert_eq!(video.artist_names(), &["Synthetic Artist"]);
        assert_eq!(video.duration_seconds(), Some(181));
        assert_eq!(
            video.source().quality(),
            music_domain::MusicVideoQuality::Hd
        );
        assert_eq!(
            video.source().uri(),
            "https://example.invalid/private-mv.mp4"
        );
        let debug = format!("{video:?}");
        for private in [
            "fixtureMvVid",
            "Synthetic MV",
            "Synthetic Artist",
            "private-mv",
        ] {
            assert!(!debug.contains(private));
        }
    }

    #[tokio::test]
    async fn preserves_no_mv_and_maps_mv_failures() {
        let provider = QqMusicProvider::new(QqMusicClient::new(MediaTransport::new([json!({
            "code": 0,
            "songinfo": {"code": 0, "data": {"track_info": {
                "mid": "fixtureTrackMid1",
                "mv": {"vid": ""}
            }}}
        })])));
        assert!(
            provider
                .track_music_video(qq_track_id(
                    "track:41001:0:fixtureTrackMid1:fixtureFileMid1"
                ))
                .await
                .expect("no MV")
                .is_none()
        );

        let foreign = TrackId::new(
            ProviderId::new("local").expect("provider"),
            "track:41001:0:fixtureTrackMid1:fixtureFileMid1",
        )
        .expect("track ID");
        assert_eq!(
            provider.track_music_video(foreign).await,
            Err(MusicVideoError::InvalidResponse)
        );
        assert_eq!(
            super::map_music_video_error(
                &QqMusicTrackMusicVideoError::<Infallible>::SourceUnavailable
            ),
            MusicVideoError::SourceUnavailable
        );
    }

    #[tokio::test]
    async fn maps_public_track_search_without_account_state() {
        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "search": {
                "code": 0,
                "data": {
                    "body": {"song": {"list": [{
                        "id": 41001,
                        "mid": "fixtureTrackMid1",
                        "title": "Synthetic track",
                        "subtitle": "Synthetic subtitle",
                        "type": 0,
                        "interval": 245,
                        "file": {"media_mid": "fixtureFileMid1"},
                        "singer": [
                            {"id": 42001, "mid": "artistOneMid", "name": "Artist one"},
                            {"id": 42002, "mid": "artistTwoMid", "name": "Artist two"}
                        ],
                        "album": {"id": 43001, "mid": "fixtureAlbumMid", "name": "Synthetic album"}
                    }]}},
                    "meta": {"curpage": 1, "nextpage": -1, "sum": 1}
                }
            }
        }))));

        let page = provider
            .search_tracks("synthetic query".into(), 1, 30)
            .await
            .expect("search page");

        assert_eq!(page.page(), 1);
        assert_eq!(page.total(), 1);
        assert!(!page.has_more());
        assert_eq!(page.items().len(), 1);
        let item = &page.items()[0];
        let track = item.track();
        assert_eq!(track.id().provider().as_str(), "qq-music");
        assert_eq!(
            track.id().opaque(),
            "track:41001:0:fixtureTrackMid1:fixtureFileMid1"
        );
        assert_eq!(track.title(), "Synthetic track");
        assert_eq!(track.artist_names(), ["Artist one", "Artist two"]);
        assert_eq!(track.artists().len(), 2);
        assert_eq!(
            track.artists()[0].id().opaque(),
            "artist:42001:artistOneMid"
        );
        assert_eq!(
            track.artists()[1].id().opaque(),
            "artist:42002:artistTwoMid"
        );
        assert_eq!(track.album_title(), Some("Synthetic album"));
        let album = track.album().expect("Album context");
        assert_eq!(album.id().opaque(), "album:43001:fixtureAlbumMid");
        assert_eq!(album.title(), "Synthetic album");
        assert_eq!(
            track.artwork_uri(),
            Some("https://y.gtimg.cn/music/photo_new/T002R300x300M000fixtureAlbumMid.jpg")
        );
        let album = item.album().expect("Album transition");
        assert_eq!(album.id().opaque(), "album:43001:fixtureAlbumMid");
        assert_eq!(track.album(), Some(album));
        assert_eq!(album.title(), "Synthetic album");
        assert_eq!(item.artists().len(), 2);
        assert_eq!(track.artists(), item.artists());
        assert_eq!(item.artists()[0].id().opaque(), "artist:42001:artistOneMid");
        assert_eq!(item.artists()[0].name(), "Artist one");
        assert_eq!(item.artists()[1].id().opaque(), "artist:42002:artistTwoMid");
        assert!(!provider.has_authenticated_credential());
        let debug = format!("{page:?} {item:?}");
        assert!(!debug.contains("Synthetic track"));
        assert!(!debug.contains("41001"));
    }

    #[tokio::test]
    async fn maps_public_artist_search_without_account_state() {
        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "music.search.SearchCgiService": {
                "code": 0,
                "data": {
                    "body": {"singer": {"list": [{
                        "singerID": 42001,
                        "singerMID": "fixtureArtistMid",
                        "singerName": "Synthetic Artist",
                        "singerPic": "https://example.invalid/private.jpg",
                        "songNum": 12,
                        "albumNum": 3
                    }]}},
                    "meta": {"curpage": 1, "nextpage": -1, "sum": 1, "perpage": 30}
                }
            }
        }))));

        let page = provider
            .search_artists("synthetic query".into(), 1, 30)
            .await
            .expect("Artist search page");

        assert_eq!(page.page(), 1);
        assert_eq!(page.total(), 1);
        assert!(!page.has_more());
        assert_eq!(page.artists().len(), 1);
        assert_eq!(
            page.artists()[0].id().opaque(),
            "artist:42001:fixtureArtistMid"
        );
        assert_eq!(page.artists()[0].name(), "Synthetic Artist");
        assert_eq!(
            page.artists()[0].artwork_uri(),
            Some("https://y.gtimg.cn/music/photo_new/T001R300x300M000fixtureArtistMid.jpg")
        );
        assert!(!provider.has_authenticated_credential());
        let debug = format!("{page:?}");
        assert!(!debug.contains("Synthetic Artist"));
        assert!(!debug.contains("42001"));
        assert!(!debug.contains("private.jpg"));
    }

    #[tokio::test]
    async fn maps_public_album_search_without_account_state() {
        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "music.search.SearchCgiService": {
                "code": 0,
                "data": {
                    "body": {"album": {"list": [{
                        "albumID": 43001,
                        "albumMID": "fixtureAlbumMid",
                        "albumName": "Synthetic Album",
                        "albumPic": "https://example.invalid/private.jpg",
                        "publicTime": "2026-08-26",
                        "song_count": 12,
                        "singer_list": []
                    }]}},
                    "meta": {"curpage": 1, "nextpage": -1, "sum": 1, "perpage": 30}
                }
            }
        }))));

        let page = provider
            .search_albums("synthetic query".into(), 1, 30)
            .await
            .expect("Album search page");

        assert_eq!(page.page(), 1);
        assert_eq!(page.total(), 1);
        assert!(!page.has_more());
        assert_eq!(page.albums().len(), 1);
        assert_eq!(
            page.albums()[0].id().opaque(),
            "album:43001:fixtureAlbumMid"
        );
        assert_eq!(page.albums()[0].title(), "Synthetic Album");
        assert!(!provider.has_authenticated_credential());
        let debug = format!("{page:?}");
        assert!(!debug.contains("Synthetic Album"));
        assert!(!debug.contains("43001"));
        assert!(!debug.contains("private.jpg"));
    }

    #[tokio::test]
    async fn maps_public_playlist_search_without_account_state() {
        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "music.search.SearchCgiService": {
                "code": 0,
                "data": {
                    "body": {"songlist": {"list": [{
                        "dissid": "81001",
                        "dissname": "Synthetic Playlist",
                        "imgurl": "https://example.invalid/private.jpg",
                        "song_count": 12
                    }]}},
                    "meta": {"curpage": 1, "nextpage": -1, "sum": 1, "perpage": 30}
                }
            }
        }))));

        let page = provider
            .search_playlists("synthetic query".into(), 1, 30)
            .await
            .expect("Playlist search page");

        assert_eq!(page.page(), 1);
        assert_eq!(page.total(), 1);
        assert!(!page.has_more());
        assert_eq!(page.playlists().len(), 1);
        assert_eq!(page.playlists()[0].id().opaque(), "catalog:81001");
        assert_eq!(page.playlists()[0].title(), "Synthetic Playlist");
        assert_eq!(page.playlists()[0].track_count(), Some(12));
        assert!(!provider.has_authenticated_credential());
        let debug = format!("{page:?}");
        assert!(!debug.contains("Synthetic Playlist"));
        assert!(!debug.contains("81001"));
        assert!(!debug.contains("private.jpg"));
    }

    #[test]
    fn maps_search_failures_without_guessing_account_state() {
        assert_eq!(
            super::map_search_error(&QqMusicSearchError::<Infallible>::HttpStatus(503)),
            SearchError::ServiceUnavailable
        );
        assert_eq!(
            super::map_search_error(&QqMusicSearchError::<Infallible>::InvalidPagination),
            SearchError::InvalidResponse
        );
        assert_eq!(
            super::map_artist_search_error(&QqMusicArtistSearchError::<Infallible>::HttpStatus(
                503
            )),
            SearchError::ServiceUnavailable
        );
        assert_eq!(
            super::map_artist_search_error(
                &QqMusicArtistSearchError::<Infallible>::InvalidPagination
            ),
            SearchError::InvalidResponse
        );
        assert_eq!(
            super::map_album_search_error(&QqMusicAlbumSearchError::<Infallible>::HttpStatus(503)),
            SearchError::ServiceUnavailable
        );
        assert_eq!(
            super::map_album_search_error(
                &QqMusicAlbumSearchError::<Infallible>::InvalidPagination
            ),
            SearchError::InvalidResponse
        );
        assert_eq!(
            super::map_playlist_search_error(
                &QqMusicPlaylistSearchError::<Infallible>::HttpStatus(503)
            ),
            SearchError::ServiceUnavailable
        );
        assert_eq!(
            super::map_playlist_search_error(
                &QqMusicPlaylistSearchError::<Infallible>::InvalidPagination
            ),
            SearchError::InvalidResponse
        );
    }

    #[tokio::test]
    async fn maps_public_album_tracks_and_rejects_foreign_identity() {
        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "albumSongs": {
                "code": 0,
                "data": {
                    "albumMid": "fixtureAlbumMid",
                    "curBegin": 0,
                    "totalNum": 1,
                    "songList": [{"songInfo": {
                        "id": 41001,
                        "mid": "fixtureTrackMid1",
                        "title": "Synthetic track",
                        "type": 0,
                        "interval": 245,
                        "file": {"media_mid": "fixtureFileMid1"},
                        "singer": [{"name": "Artist one"}],
                        "album": {"mid": "fixtureAlbumMid", "name": "Synthetic album"}
                    }}]
                }
            }
        }))));
        let album_id = AlbumId::new(
            ProviderId::new("qq-music").expect("provider"),
            "album:43001:fixtureAlbumMid",
        )
        .expect("Album ID");
        let page = provider
            .album_tracks(album_id, 0, 30)
            .await
            .expect("Album Tracks");

        assert_eq!(page.offset(), 0);
        assert_eq!(page.total(), 1);
        assert!(!page.has_more());
        assert_eq!(page.tracks().len(), 1);
        assert_eq!(
            page.tracks()[0].id().opaque(),
            "track:41001:0:fixtureTrackMid1:fixtureFileMid1"
        );
        assert!(!provider.has_authenticated_credential());

        let foreign = AlbumId::new(
            ProviderId::new("local").expect("provider"),
            "album:43001:fixtureAlbumMid",
        )
        .expect("foreign Album ID");
        assert_eq!(
            provider.album_tracks(foreign, 0, 30).await,
            Err(CatalogError::InvalidResponse)
        );
    }

    #[tokio::test]
    async fn maps_public_album_details_and_rejects_foreign_identity() {
        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "album": {
                "code": 0,
                "data": {
                    "basicInfo": {
                        "albumID": 43001,
                        "albumMid": "fixtureAlbumMid",
                        "albumName": "Synthetic Album",
                        "tranName": "Synthetic Subtitle",
                        "publishDate": "2026-08-26",
                        "desc": "Synthetic Description",
                        "language": "Synthetic Language",
                        "albumType": "Synthetic Type",
                        "genre": "Synthetic Genre"
                    },
                    "company": {"name": "Synthetic Company"},
                    "singer": {"singerList": [{
                        "singerID": 42001,
                        "mid": "fixtureArtistMid",
                        "name": "Synthetic Artist"
                    }]}
                }
            }
        }))));
        let album_id = AlbumId::new(
            ProviderId::new("qq-music").expect("provider"),
            "album:43001:fixtureAlbumMid",
        )
        .expect("Album ID");

        let details = provider
            .album_details(album_id)
            .await
            .expect("Album details");

        assert_eq!(details.album().id().opaque(), "album:43001:fixtureAlbumMid");
        assert_eq!(details.artists().len(), 1);
        assert_eq!(details.subtitle(), Some("Synthetic Subtitle"));
        assert_eq!(details.release_date(), Some("2026-08-26"));
        assert_eq!(details.description(), Some("Synthetic Description"));
        assert_eq!(details.language(), Some("Synthetic Language"));
        assert_eq!(details.album_type(), Some("Synthetic Type"));
        assert_eq!(details.genre(), Some("Synthetic Genre"));
        assert_eq!(details.company(), Some("Synthetic Company"));
        assert!(!provider.has_authenticated_credential());

        let foreign = AlbumId::new(
            ProviderId::new("local").expect("provider"),
            "album:43001:fixtureAlbumMid",
        )
        .expect("foreign Album ID");
        assert_eq!(
            provider.album_details(foreign).await,
            Err(CatalogError::InvalidResponse)
        );
    }

    #[test]
    fn maps_album_protocol_failures_coarsely() {
        assert_eq!(
            super::map_album_tracks_error(&QqMusicAlbumTracksError::<Infallible>::HttpStatus(503)),
            CatalogError::ServiceUnavailable
        );
        assert_eq!(
            super::map_album_tracks_error(
                &QqMusicAlbumTracksError::<Infallible>::InvalidPagination
            ),
            CatalogError::InvalidResponse
        );
        assert_eq!(
            super::map_album_details_error(&QqMusicAlbumDetailsError::<Infallible>::HttpStatus(
                503
            )),
            CatalogError::ServiceUnavailable
        );
        assert_eq!(
            super::map_album_details_error(
                &QqMusicAlbumDetailsError::<Infallible>::MismatchedAlbumMid
            ),
            CatalogError::InvalidResponse
        );
    }

    #[tokio::test]
    async fn maps_public_artist_tracks_and_rejects_foreign_identity() {
        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "artistSongs": {
                "code": 0,
                "data": {
                    "singerMid": "fixtureArtistMid",
                    "totalNum": 1,
                    "songList": [{"songInfo": {
                        "id": 41001,
                        "mid": "fixtureTrackMid1",
                        "title": "Synthetic track",
                        "type": 0,
                        "interval": 245,
                        "file": {"media_mid": "fixtureFileMid1"},
                        "singer": [{"name": "Artist one"}],
                        "album": {"mid": "fixtureAlbumMid", "name": "Synthetic album"}
                    }}]
                }
            }
        }))));
        let artist_id = ArtistId::new(
            ProviderId::new("qq-music").expect("provider"),
            "artist:42001:fixtureArtistMid",
        )
        .expect("Artist ID");
        let page = provider
            .artist_tracks(artist_id, 0, 30)
            .await
            .expect("Artist Tracks");

        assert_eq!(page.offset(), 0);
        assert_eq!(page.total(), 1);
        assert!(!page.has_more());
        assert_eq!(page.tracks().len(), 1);
        assert_eq!(
            page.tracks()[0].id().opaque(),
            "track:41001:0:fixtureTrackMid1:fixtureFileMid1"
        );
        assert!(!provider.has_authenticated_credential());

        let mid_only_artist_id = ArtistId::new(
            ProviderId::new("qq-music").expect("provider"),
            "artist:-:fixtureArtistMid",
        )
        .expect("MID-only Artist ID");
        let mid_only_page = provider
            .artist_tracks(mid_only_artist_id, 0, 30)
            .await
            .expect("MID-only Artist Tracks");
        assert_eq!(mid_only_page.tracks().len(), 1);

        let foreign = ArtistId::new(
            ProviderId::new("local").expect("provider"),
            "artist:42001:fixtureArtistMid",
        )
        .expect("foreign Artist ID");
        assert_eq!(
            provider.artist_tracks(foreign, 0, 30).await,
            Err(CatalogError::InvalidResponse)
        );
    }

    #[tokio::test]
    async fn maps_public_artist_albums_and_rejects_foreign_identity() {
        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "artistAlbums": {
                "code": 0,
                "data": {
                    "singerMid": "fixtureArtistMid",
                    "total": 1,
                    "albumList": [{
                        "albumID": 43001,
                        "albumMid": "fixtureAlbumMid",
                        "albumName": "Synthetic album"
                    }]
                }
            }
        }))));
        let artist_id = ArtistId::new(
            ProviderId::new("qq-music").expect("provider"),
            "artist:42001:fixtureArtistMid",
        )
        .expect("Artist ID");
        let page = provider
            .artist_albums(artist_id, 0, 30)
            .await
            .expect("Artist Albums");

        assert_eq!(page.offset(), 0);
        assert_eq!(page.total(), 1);
        assert!(!page.has_more());
        assert_eq!(page.albums().len(), 1);
        assert_eq!(
            page.albums()[0].id().opaque(),
            "album:43001:fixtureAlbumMid"
        );
        assert_eq!(page.albums()[0].title(), "Synthetic album");
        assert_eq!(
            page.albums()[0].artwork_uri(),
            Some("https://y.gtimg.cn/music/photo_new/T002R300x300M000fixtureAlbumMid.jpg")
        );
        assert!(!provider.has_authenticated_credential());
        let debug = format!("{page:?} {:?}", page.albums()[0]);
        assert!(!debug.contains("Synthetic album"));
        assert!(!debug.contains("fixtureAlbumMid"));

        let mid_only_artist_id = ArtistId::new(
            ProviderId::new("qq-music").expect("provider"),
            "artist:-:fixtureArtistMid",
        )
        .expect("MID-only Artist ID");
        assert_eq!(
            provider
                .artist_albums(mid_only_artist_id, 0, 30)
                .await
                .expect("MID-only Artist Albums")
                .albums()
                .len(),
            1
        );

        let foreign = ArtistId::new(
            ProviderId::new("local").expect("provider"),
            "artist:42001:fixtureArtistMid",
        )
        .expect("foreign Artist ID");
        assert_eq!(
            provider.artist_albums(foreign, 0, 30).await,
            Err(CatalogError::InvalidResponse)
        );
    }

    #[tokio::test]
    async fn maps_public_regional_new_albums_without_account_state() {
        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "newAlbum": {
                "code": 0,
                "data": {
                    "total": 6,
                    "albums": [{
                        "id": 43001,
                        "mid": "fixtureAlbumMid",
                        "name": "Synthetic new Album",
                        "release_time": "2026-08-26",
                        "singers": [{
                            "id": 42001,
                            "mid": "fixtureArtistMid",
                            "name": "Synthetic Artist"
                        }]
                    }]
                }
            }
        }))));

        let page = provider
            .new_album_releases(NewAlbumRegion::Japan, 5, 1)
            .await
            .expect("new Album releases");

        assert_eq!(page.region(), NewAlbumRegion::Japan);
        assert_eq!(page.offset(), 5);
        assert_eq!(page.total(), 6);
        assert!(!page.has_more());
        assert_eq!(page.releases().len(), 1);
        let release = &page.releases()[0];
        assert_eq!(release.album().id().opaque(), "album:43001:fixtureAlbumMid");
        assert_eq!(
            release.album().artwork_uri(),
            Some("https://y.gtimg.cn/music/photo_new/T002R300x300M000fixtureAlbumMid.jpg")
        );
        assert_eq!(
            release.artists()[0].id().opaque(),
            "artist:42001:fixtureArtistMid"
        );
        assert_eq!(release.release_date(), Some("2026-08-26"));
        assert!(!provider.has_authenticated_credential());
        let debug = format!("{page:?}");
        assert!(!debug.contains("Synthetic new Album"));
        assert!(!debug.contains("Synthetic Artist"));
        assert!(!debug.contains("fixtureAlbumMid"));
        assert!(!debug.contains("2026-08-26"));
    }

    #[tokio::test]
    async fn maps_public_new_songs_without_account_state() {
        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "new_song": {
                "code": 0,
                "data": {
                    "type": 5,
                    "songlist": [{
                        "id": 41001,
                        "mid": "fixtureTrackMid1",
                        "title": "Synthetic new track",
                        "subtitle": "Synthetic subtitle",
                        "type": 0,
                        "interval": 245,
                        "file": {"media_mid": "fixtureFileMid1"},
                        "singer": [{
                            "id": 42001,
                            "mid": "fixtureArtistMid",
                            "name": "Synthetic Artist"
                        }],
                        "album": {
                            "id": 43001,
                            "mid": "fixtureAlbumMid",
                            "name": "Synthetic Album"
                        }
                    }]
                }
            }
        }))));

        let collection = provider
            .new_songs(NewSongCategory::Latest)
            .await
            .expect("new-song collection");

        assert_eq!(collection.category(), NewSongCategory::Latest);
        assert_eq!(collection.tracks().len(), 1);
        let track = &collection.tracks()[0];
        assert_eq!(
            track.id().opaque(),
            "track:41001:0:fixtureTrackMid1:fixtureFileMid1"
        );
        assert_eq!(
            track.artists()[0].id().opaque(),
            "artist:42001:fixtureArtistMid"
        );
        assert_eq!(
            track.album().expect("Album context").id().opaque(),
            "album:43001:fixtureAlbumMid"
        );
        assert!(!provider.has_authenticated_credential());
        let debug = format!("{collection:?}");
        assert!(!debug.contains("Synthetic new track"));
        assert!(!debug.contains("fixtureTrackMid1"));
    }

    #[test]
    fn maps_artist_protocol_failures_coarsely() {
        assert_eq!(
            super::map_artist_tracks_error(&QqMusicArtistTracksError::<Infallible>::HttpStatus(
                503
            )),
            CatalogError::ServiceUnavailable
        );
        assert_eq!(
            super::map_artist_tracks_error(
                &QqMusicArtistTracksError::<Infallible>::InvalidPagination
            ),
            CatalogError::InvalidResponse
        );
        assert_eq!(
            super::map_artist_albums_error(&QqMusicArtistAlbumsError::<Infallible>::HttpStatus(
                503
            )),
            CatalogError::ServiceUnavailable
        );
        assert_eq!(
            super::map_artist_albums_error(
                &QqMusicArtistAlbumsError::<Infallible>::InvalidPagination
            ),
            CatalogError::InvalidResponse
        );
        assert_eq!(
            super::map_new_albums_error(&QqMusicNewAlbumsError::<Infallible>::HttpStatus(503)),
            CatalogError::ServiceUnavailable
        );
        assert_eq!(
            super::map_new_albums_error(&QqMusicNewAlbumsError::<Infallible>::InvalidPagination),
            CatalogError::InvalidResponse
        );
        assert_eq!(
            super::map_new_songs_error(&QqMusicNewSongsError::<Infallible>::HttpStatus(503)),
            CatalogError::ServiceUnavailable
        );
        assert_eq!(
            super::map_new_songs_error(&QqMusicNewSongsError::<Infallible>::MismatchedCategory),
            CatalogError::InvalidResponse
        );
    }

    #[tokio::test]
    async fn maps_public_recommended_playlists_without_account_state() {
        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "recommend": {
                "code": 0,
                "data": {
                    "List": [{
                        "Playlist": {"basic": {
                            "tid": 81001,
                            "title": "Synthetic discovery",
                            "cover": {"medium_url": "https://example.invalid/discovery.jpg"},
                            "song_cnt": 27
                        }}
                    }],
                    "HasMore": true
                }
            }
        }))));

        let page = provider
            .recommended_playlists(20, 20)
            .await
            .expect("recommended playlists");

        assert_eq!(page.offset(), 20);
        assert!(page.has_more());
        assert_eq!(page.playlists().len(), 1);
        let playlist = &page.playlists()[0];
        assert_eq!(playlist.id().provider().as_str(), "qq-music");
        assert_eq!(playlist.id().opaque(), "catalog:81001");
        assert_eq!(playlist.title(), "Synthetic discovery");
        assert_eq!(
            playlist.artwork_uri(),
            Some("https://example.invalid/discovery.jpg")
        );
        assert_eq!(playlist.track_count(), Some(27));
        assert!(!provider.has_authenticated_credential());
        assert!(!format!("{page:?}").contains("Synthetic discovery"));
        assert!(!format!("{page:?}").contains("81001"));
    }

    fn radar_response(code: i64, has_more: bool) -> Value {
        json!({
            "code": 0,
            "radar": {
                "code": code,
                "data": {
                    "VecSongs": [{"Track": {
                        "id": 41001,
                        "mid": "fixtureTrackMid1",
                        "title": "Synthetic Radar track",
                        "subtitle": "Synthetic subtitle",
                        "type": 0,
                        "interval": 245,
                        "file": {"media_mid": "fixtureFileMid1"},
                        "singer": [{
                            "id": 42001,
                            "mid": "fixtureArtistMid",
                            "name": "Synthetic artist"
                        }],
                        "album": {
                            "id": 43001,
                            "mid": "fixtureAlbumMid",
                            "name": "Synthetic album"
                        }
                    }}],
                    "HasMore": has_more
                }
            }
        })
    }

    #[tokio::test]
    async fn authenticated_radar_maps_tracks_and_clears_only_explicit_rejection() {
        let signed_out = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(
            &radar_response(0, false),
        )));
        assert_eq!(
            signed_out.radar_tracks(1).await,
            Err(RadarRecommendationError::AuthenticationRequired)
        );

        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(
            &radar_response(0, true),
        )));
        set_authenticated(&provider, "123456");
        let page = provider.radar_tracks(2).await.expect("Radar Track page");
        assert_eq!(page.page(), 2);
        assert!(page.has_more());
        assert_eq!(page.tracks().len(), 1);
        assert_eq!(page.tracks()[0].id().provider().as_str(), "qq-music");
        assert_eq!(
            page.tracks()[0].id().opaque(),
            "track:41001:0:fixtureTrackMid1:fixtureFileMid1"
        );
        assert_eq!(page.tracks()[0].title(), "Synthetic Radar track");
        assert!(provider.has_authenticated_credential());
        let debug = format!("{page:?}");
        assert!(!debug.contains("Synthetic Radar track"));
        assert!(!debug.contains("41001"));

        let rejected = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "radar": {"code": 104_401}
        }))));
        set_authenticated(&rejected, "123456");
        assert_eq!(
            rejected.radar_tracks(1).await,
            Err(RadarRecommendationError::CredentialRejected)
        );
        assert!(!rejected.has_authenticated_credential());

        let upstream = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(
            &radar_response(50_006, false),
        )));
        set_authenticated(&upstream, "123456");
        assert_eq!(
            upstream.radar_tracks(1).await,
            Err(RadarRecommendationError::ServiceUnavailable)
        );
        assert!(upstream.has_authenticated_credential());
    }

    #[tokio::test]
    async fn late_radar_result_cannot_cross_account_replacement() {
        let request_started = Arc::new(Notify::new());
        let release_request = Arc::new(Notify::new());
        let provider = QqMusicProvider::new(QqMusicClient::new(GatedRadarTransport {
            request_started: Arc::clone(&request_started),
            release_request: Arc::clone(&release_request),
        }));
        set_authenticated(&provider, "123456");

        let request = provider.radar_tracks(1);
        let replacement = async {
            request_started.notified().await;
            set_authenticated(&provider, "654321");
            release_request.notify_one();
        };
        let (result, ()) = tokio::join!(request, replacement);

        assert_eq!(result, Err(RadarRecommendationError::Replaced));
        assert!(provider.has_authenticated_credential());
    }

    fn daily_response(cards: &[Value]) -> Value {
        json!({
            "code": 0,
            "feed": {"code": 0, "data": {
                "retcode": 0,
                "v_shelf": [{"v_niche": [{"v_card": cards}]}]
            }}
        })
    }

    fn daily_card(id: &str, title: &str) -> Value {
        json!({
            "id": id,
            "title": title,
            "cover": "https://example.invalid/daily.jpg",
            "jumptype": 10014,
            "trace": "fixture#daily30:8#private",
            "extra_info": {"moduleID": "recforyou@0@0"}
        })
    }

    fn personalized_playlists_response(code: i64, cards: &[Value]) -> Value {
        json!({
            "code": 0,
            "feed": {"code": code, "data": {
                "retcode": 0,
                "v_shelf": [{
                    "extra_info": {"moduleID": "playlist@135@0"},
                    "v_niche": [{"v_card": cards}]
                }]
            }}
        })
    }

    fn personalized_playlist_card(id: &str, title: &str) -> Value {
        json!({
            "id": id,
            "title": title,
            "cover": "https://example.invalid/personalized.jpg",
            "jumptype": 10014
        })
    }

    fn personalized_tracks_response(code: i64, tracks: &[Value]) -> Value {
        json!({
            "code": 0,
            "radio": {"code": code, "data": {"tracks": tracks}}
        })
    }

    fn related_tracks_response(code: i64, tracks: &[Value]) -> Value {
        json!({
            "code": 0,
            "simsongs": {"code": code, "data": {
                "songInfoList": tracks
            }}
        })
    }

    fn personalized_track(id: u64, mid: &str, title: &str) -> Value {
        json!({
            "id": id,
            "mid": mid,
            "title": title,
            "subtitle": "",
            "type": 0,
            "interval": 245,
            "file": {"media_mid": mid},
            "singer": [{"id": 42001, "mid": "fixtureArtistMid", "name": "Artist"}],
            "album": {"id": 43001, "mid": "fixtureAlbumMid", "name": "Album"}
        })
    }

    #[tokio::test]
    async fn authenticated_daily_recommendation_maps_only_evidenced_playlist() {
        let signed_out = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(
            &daily_response(&[]),
        )));
        assert_eq!(
            signed_out.daily_recommendation().await,
            Err(DailyRecommendationError::AuthenticationRequired)
        );

        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(
            &daily_response(&[daily_card("7251579717", "Synthetic Daily 30")]),
        )));
        set_authenticated(&provider, "123456");
        let daily = provider
            .daily_recommendation()
            .await
            .expect("Daily 30 load")
            .expect("Daily 30 playlist");
        assert_eq!(daily.id().provider().as_str(), "qq-music");
        assert_eq!(daily.id().opaque(), "catalog:7251579717");
        assert_eq!(daily.title(), "Synthetic Daily 30");
        assert_eq!(
            daily.artwork_uri(),
            Some("https://example.invalid/daily.jpg")
        );
        assert!(daily.track_count().is_none());
        assert!(provider.has_authenticated_credential());
        let debug = format!("{daily:?}");
        assert!(!debug.contains("Synthetic Daily 30"));
        assert!(!debug.contains("7251579717"));

        let absent = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(
            &daily_response(&[]),
        )));
        set_authenticated(&absent, "123456");
        assert!(
            absent
                .daily_recommendation()
                .await
                .expect("valid feed without Daily 30")
                .is_none()
        );
        assert!(absent.has_authenticated_credential());
    }

    #[tokio::test]
    async fn daily_recommendation_clears_only_rejection_and_rejects_late_account_result() {
        let rejected = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "feed": {"code": 104_401}
        }))));
        set_authenticated(&rejected, "123456");
        assert_eq!(
            rejected.daily_recommendation().await,
            Err(DailyRecommendationError::CredentialRejected)
        );
        assert!(!rejected.has_authenticated_credential());

        let upstream = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "feed": {"code": 50_006}
        }))));
        set_authenticated(&upstream, "123456");
        assert_eq!(
            upstream.daily_recommendation().await,
            Err(DailyRecommendationError::ServiceUnavailable)
        );
        assert!(upstream.has_authenticated_credential());

        let request_started = Arc::new(Notify::new());
        let release_request = Arc::new(Notify::new());
        let replaced = QqMusicProvider::new(QqMusicClient::new(GatedDailyTransport {
            request_started: Arc::clone(&request_started),
            release_request: Arc::clone(&release_request),
        }));
        set_authenticated(&replaced, "123456");
        let request = replaced.daily_recommendation();
        let replacement = async {
            request_started.notified().await;
            set_authenticated(&replaced, "654321");
            release_request.notify_one();
        };
        let (result, ()) = tokio::join!(request, replacement);
        assert_eq!(result, Err(DailyRecommendationError::Replaced));
        assert!(replaced.has_authenticated_credential());
    }

    #[tokio::test]
    async fn authenticated_personalized_playlists_map_only_evidenced_shelf() {
        let signed_out = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(
            &personalized_playlists_response(0, &[]),
        )));
        assert_eq!(
            signed_out.personalized_playlists().await,
            Err(PersonalizedPlaylistsError::AuthenticationRequired)
        );

        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(
            &personalized_playlists_response(
                0,
                &[personalized_playlist_card(
                    "91001",
                    "Synthetic personalized playlist",
                )],
            ),
        )));
        set_authenticated(&provider, "123456");
        let playlists = provider
            .personalized_playlists()
            .await
            .expect("personalized playlists");
        assert_eq!(playlists.len(), 1);
        assert_eq!(playlists[0].id().provider().as_str(), "qq-music");
        assert_eq!(playlists[0].id().opaque(), "catalog:91001");
        assert_eq!(playlists[0].title(), "Synthetic personalized playlist");
        assert_eq!(
            playlists[0].artwork_uri(),
            Some("https://example.invalid/personalized.jpg")
        );
        assert!(provider.has_authenticated_credential());
        let debug = format!("{playlists:?}");
        assert!(!debug.contains("Synthetic personalized playlist"));
        assert!(!debug.contains("91001"));
    }

    #[tokio::test]
    async fn personalized_playlists_clear_only_rejection_and_reject_late_account_result() {
        let rejected = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "feed": {"code": 104_401}
        }))));
        set_authenticated(&rejected, "123456");
        assert_eq!(
            rejected.personalized_playlists().await,
            Err(PersonalizedPlaylistsError::CredentialRejected)
        );
        assert!(!rejected.has_authenticated_credential());

        let upstream = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(
            &personalized_playlists_response(50_006, &[]),
        )));
        set_authenticated(&upstream, "123456");
        assert_eq!(
            upstream.personalized_playlists().await,
            Err(PersonalizedPlaylistsError::ServiceUnavailable)
        );
        assert!(upstream.has_authenticated_credential());

        let request_started = Arc::new(Notify::new());
        let release_request = Arc::new(Notify::new());
        let replaced = QqMusicProvider::new(QqMusicClient::new(GatedDailyTransport {
            request_started: Arc::clone(&request_started),
            release_request: Arc::clone(&release_request),
        }));
        set_authenticated(&replaced, "123456");
        let request = replaced.personalized_playlists();
        let replacement = async {
            request_started.notified().await;
            set_authenticated(&replaced, "654321");
            release_request.notify_one();
        };
        let (result, ()) = tokio::join!(request, replacement);
        assert_eq!(result, Err(PersonalizedPlaylistsError::Replaced));
        assert!(replaced.has_authenticated_credential());
    }

    #[tokio::test]
    async fn authenticated_personalized_tracks_map_existing_track_domain() {
        let signed_out = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(
            &personalized_tracks_response(0, &[]),
        )));
        assert_eq!(
            signed_out.personalized_tracks().await,
            Err(PersonalizedTracksError::AuthenticationRequired)
        );

        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(
            &personalized_tracks_response(
                0,
                &[personalized_track(
                    41_001,
                    "fixtureTrackMid",
                    "Synthetic personalized Track",
                )],
            ),
        )));
        set_authenticated(&provider, "123456");
        let tracks = provider
            .personalized_tracks()
            .await
            .expect("personalized Tracks");
        assert_eq!(tracks.len(), 1);
        assert_eq!(tracks[0].id().provider().as_str(), "qq-music");
        assert_eq!(
            tracks[0].id().opaque(),
            "track:41001:0:fixtureTrackMid:fixtureTrackMid"
        );
        assert_eq!(tracks[0].title(), "Synthetic personalized Track");
        assert_eq!(tracks[0].artist_names(), &["Artist"]);
        assert_eq!(tracks[0].album_title(), Some("Album"));
        assert!(provider.has_authenticated_credential());
        let debug = format!("{tracks:?}");
        assert!(!debug.contains("Synthetic personalized Track"));
        assert!(!debug.contains("fixtureTrackMid"));
    }

    #[tokio::test]
    async fn related_tracks_parse_only_the_provider_owned_seed_identity() {
        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(
            &related_tracks_response(
                0,
                &[personalized_track(
                    51_001,
                    "relatedFixtureMid",
                    "Synthetic related Track",
                )],
            ),
        )));
        let seed = TrackId::new(
            ProviderId::new("qq-music").expect("Provider"),
            "track:41001:0:seedFixtureMid:-",
        )
        .expect("seed Track");

        let tracks = provider.related_tracks(seed).await.expect("related Tracks");
        assert_eq!(tracks.len(), 1);
        assert_eq!(tracks[0].title(), "Synthetic related Track");
        assert_eq!(
            tracks[0].id().opaque(),
            "track:51001:0:relatedFixtureMid:relatedFixtureMid"
        );
        let debug = format!("{tracks:?}");
        assert!(!debug.contains("Synthetic related Track"));
        assert!(!debug.contains("relatedFixtureMid"));

        let foreign_seed = TrackId::new(
            ProviderId::new("local").expect("Provider"),
            "track:41001:0:seedFixtureMid:-",
        )
        .expect("foreign seed");
        assert_eq!(
            provider.related_tracks(foreign_seed).await,
            Err(RelatedTracksError::InvalidTrack)
        );
    }

    #[tokio::test]
    async fn personalized_tracks_clear_only_rejection_and_reject_late_account_result() {
        let rejected = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "radio": {"code": 104_401}
        }))));
        set_authenticated(&rejected, "123456");
        assert_eq!(
            rejected.personalized_tracks().await,
            Err(PersonalizedTracksError::CredentialRejected)
        );
        assert!(!rejected.has_authenticated_credential());

        let upstream = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(
            &personalized_tracks_response(50_006, &[]),
        )));
        set_authenticated(&upstream, "123456");
        assert_eq!(
            upstream.personalized_tracks().await,
            Err(PersonalizedTracksError::ServiceUnavailable)
        );
        assert!(upstream.has_authenticated_credential());

        let request_started = Arc::new(Notify::new());
        let release_request = Arc::new(Notify::new());
        let replaced = QqMusicProvider::new(QqMusicClient::new(GatedDailyTransport {
            request_started: Arc::clone(&request_started),
            release_request: Arc::clone(&release_request),
        }));
        set_authenticated(&replaced, "123456");
        let request = replaced.personalized_tracks();
        let replacement = async {
            request_started.notified().await;
            set_authenticated(&replaced, "654321");
            release_request.notify_one();
        };
        let (result, ()) = tokio::join!(request, replacement);
        assert_eq!(result, Err(PersonalizedTracksError::Replaced));
        assert!(replaced.has_authenticated_credential());
    }

    #[test]
    fn maps_recommendation_failures_coarsely() {
        assert_eq!(
            super::map_recommendations_error(
                &QqMusicRecommendedPlaylistsError::<Infallible>::HttpStatus(503)
            ),
            RecommendationError::ServiceUnavailable
        );
        assert_eq!(
            super::map_recommendations_error(
                &QqMusicRecommendedPlaylistsError::<Infallible>::InvalidPagination
            ),
            RecommendationError::InvalidResponse
        );
        assert_eq!(
            super::map_radar_error(&QqMusicRadarError::<Infallible>::HttpStatus(503)),
            RadarRecommendationError::ServiceUnavailable
        );
        assert_eq!(
            super::map_radar_error(&QqMusicRadarError::<Infallible>::InvalidPagination),
            RadarRecommendationError::InvalidResponse
        );
        assert_eq!(
            super::map_daily_recommendation_error(
                &QqMusicDailyRecommendationError::<Infallible>::HttpStatus(503)
            ),
            DailyRecommendationError::ServiceUnavailable
        );
        assert_eq!(
            super::map_daily_recommendation_error(
                &QqMusicDailyRecommendationError::<Infallible>::MultipleDailyPlaylists
            ),
            DailyRecommendationError::InvalidResponse
        );
        assert_eq!(
            super::map_personalized_playlists_error(
                &QqMusicPersonalizedPlaylistsError::<Infallible>::HttpStatus(503)
            ),
            PersonalizedPlaylistsError::ServiceUnavailable
        );
        assert_eq!(
            super::map_personalized_playlists_error(
                &QqMusicPersonalizedPlaylistsError::<Infallible>::MultiplePlaylistShelves
            ),
            PersonalizedPlaylistsError::InvalidResponse
        );
        assert_eq!(
            super::map_personalized_tracks_error(
                &QqMusicPersonalizedTracksError::<Infallible>::HttpStatus(503)
            ),
            PersonalizedTracksError::ServiceUnavailable
        );
        assert_eq!(
            super::map_personalized_tracks_error(
                &QqMusicPersonalizedTracksError::<Infallible>::DuplicateTrackIdentity
            ),
            PersonalizedTracksError::InvalidResponse
        );
    }

    #[tokio::test]
    async fn maps_public_ranking_groups_and_tracks_without_account_state() {
        let list_provider =
            QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
                "code": 0,
                "music.musicToplist.Toplist.GetAll": {"code": 0, "data": {"group": [{
                    "groupName": "Synthetic rankings",
                    "toplist": [{
                        "topId": 62001,
                        "title": "Synthetic chart",
                        "period": "fixture-period",
                        "frontPicUrl": "https://example.invalid/chart.jpg",
                        "totalNum": 31
                    }]
                }]}}
            }))));
        let groups = list_provider
            .ranking_groups()
            .await
            .expect("ranking groups");

        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].title(), "Synthetic rankings");
        assert_eq!(groups[0].rankings().len(), 1);
        let ranking = &groups[0].rankings()[0];
        assert_eq!(ranking.id().provider().as_str(), "qq-music");
        assert_eq!(ranking.id().opaque(), "ranking:62001");
        assert_eq!(ranking.period(), Some("fixture-period"));
        assert_eq!(ranking.track_count(), Some(31));
        assert!(!list_provider.has_authenticated_credential());
        assert!(!format!("{groups:?}").contains("Synthetic chart"));
        assert!(!format!("{groups:?}").contains("62001"));

        let detail_provider =
            QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
                "code": 0,
                "music.musicToplist.Toplist.GetDetail": {"code": 0, "data": {
                    "data": {
                        "topId": 62001,
                        "title": "Synthetic chart",
                        "period": "fixture-period",
                        "frontPicUrl": "https://example.invalid/chart.jpg",
                        "totalNum": 31
                    },
                    "songInfoList": [{
                        "id": 41001,
                        "mid": "fixtureTrackMid1",
                        "title": "Synthetic Track",
                        "type": 0,
                        "interval": 245,
                        "file": {"media_mid": "fixtureFileMid1"},
                        "singer": [{"id": 42001, "mid": "artistMid", "name": "Artist"}],
                        "album": {"id": 43001, "mid": "albumMid", "name": "Album"}
                    }]
                }}
            }))));
        let page = detail_provider
            .ranking_tracks(
                RankingId::new(
                    ProviderId::new("qq-music").expect("provider"),
                    "ranking:62001",
                )
                .expect("ranking ID"),
                30,
                5,
            )
            .await
            .expect("ranking Tracks");

        assert_eq!(page.ranking().id().opaque(), "ranking:62001");
        assert_eq!(page.offset(), 30);
        assert_eq!(page.total(), 31);
        assert!(!page.has_more());
        assert_eq!(page.tracks().len(), 1);
        assert_eq!(page.tracks()[0].title(), "Synthetic Track");
        assert!(!detail_provider.has_authenticated_credential());
        let debug = format!("{page:?}");
        assert!(!debug.contains("Synthetic Track"));
        assert!(!debug.contains("62001"));
    }

    #[test]
    fn maps_ranking_failures_coarsely_and_rejects_invalid_opaque_identity() {
        assert_eq!(
            super::map_rankings_error(&QqMusicRankingsError::<Infallible>::HttpStatus(503)),
            CatalogError::ServiceUnavailable
        );
        assert_eq!(
            super::map_rankings_error(&QqMusicRankingsError::<Infallible>::InvalidPagination),
            CatalogError::InvalidResponse
        );
        for opaque in ["ranking:0", "ranking:not-a-number", "ranking:1:extra"] {
            let id = RankingId::new(ProviderId::new("qq-music").expect("provider"), opaque)
                .expect("structural identity");
            assert_eq!(
                super::parse_ranking_id(&id),
                Err(CatalogError::InvalidResponse)
            );
        }
    }

    fn set_authenticated<T>(provider: &QqMusicProvider<T>, music_id: &str) {
        let credential = Credential::new(music_id, "W_X_private-key", LoginType::WECHAT)
            .expect("fixture credential")
            .with_session_secrets(CredentialSessionSecrets::new(
                None,
                None,
                None,
                None,
                None,
                Some(format!("encrypted-{music_id}")),
            ));
        *super::credential_guard(&provider.credential) =
            super::QqMusicCredentialState::Authenticated(credential);
    }

    fn favorite_page_response(playlists: &Value, total: u32, has_more: bool) -> HttpResponse {
        HttpResponse::new(
            200,
            serde_json::to_vec(&json!({
                "code": 0,
                "music.musicasset.PlaylistFavRead": {
                    "code": 0,
                    "data": {
                        "v_list": playlists,
                        "total": total,
                        "hasmore": has_more
                    }
                }
            }))
            .expect("fixture JSON"),
        )
    }

    fn favorite_page_json(playlists: &Value, total: u32, has_more: bool) -> Value {
        json!({
            "code": 0,
            "music.musicasset.PlaylistFavRead": {
                "code": 0,
                "data": {
                    "v_list": playlists,
                    "total": total,
                    "hasmore": has_more
                }
            }
        })
    }

    fn favorite_album_page_json(albums: &Value, total: u32, has_more: bool) -> Value {
        json!({
            "code": 0,
            "subcode": 0,
            "data": {
                "albumlist": albums,
                "totalalbum": total,
                "has_more": has_more
            }
        })
    }

    fn favorite_artist_page_json(artists: &Value, total: u32, has_more: bool) -> Value {
        json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {
                    "Total": total,
                    "List": artists,
                    "HasMore": has_more
                }
            }
        })
    }

    fn playlist_track_fixture() -> Value {
        json!([{
            "id": 41001,
            "mid": "fixtureTrackMid1",
            "name": "Fallback fixture title",
            "title": "Synthetic track",
            "subtitle": "Synthetic subtitle",
            "type": 0,
            "songtype": 13,
            "interval": 245,
            "file": {"media_mid": "fixtureFileMid1"},
            "singer": [
                {"id": 42001, "mid": "artist-one-mid", "name": "Artist one"},
                {"id": 42002, "mid": "artist-two-mid", "name": "Artist two"}
            ],
            "album": {
                "id": 43001,
                "mid": "fixtureAlbumMid",
                "name": "Fallback album",
                "title": "Synthetic album"
            }
        }])
    }

    fn playlist_detail_page_json(tracks: &Value, total: u32, has_more: bool) -> Value {
        json!({
            "code": 0,
            "music.srfDissInfo.DissInfo": {
                "code": 0,
                "data": {
                    "code": 0,
                    "songlist": tracks,
                    "total_song_num": total,
                    "hasmore": has_more
                }
            }
        })
    }

    fn qq_playlist_id(value: &str) -> PlaylistId {
        PlaylistId::new(ProviderId::new("qq-music").expect("provider"), value).expect("playlist ID")
    }

    fn qq_album_id(value: &str) -> AlbumId {
        AlbumId::new(ProviderId::new("qq-music").expect("provider"), value)
            .expect("structural Album ID")
    }

    fn qq_track_id(value: &str) -> TrackId {
        TrackId::new(ProviderId::new("qq-music").expect("provider"), value).expect("track ID")
    }

    fn media_dispatch_json() -> Value {
        json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {
                    "retcode": 0,
                    "sip": ["http://audio.example.test/"],
                    "expiration": 86400,
                    "refreshTime": 1800,
                    "cacheTime": 86400
                }
            }
        })
    }

    fn media_vkey_json(result: i64, path: &str) -> Value {
        json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {
                    "retcode": 0,
                    "expiration": 7200,
                    "midurlinfo": [{
                        "songmid": "fixtureTrackMid1",
                        "filename": "M500fixtureFileMid1.mp3",
                        "purl": path,
                        "result": result
                    }]
                }
            }
        })
    }

    fn high_media_vkey_json(result: i64, path: &str) -> Value {
        let mut response = media_vkey_json(result, path);
        response["req_0"]["data"]["midurlinfo"][0]["filename"] = json!("M800fixtureFileMid1.mp3");
        response
    }

    fn lyrics_success_json() -> Value {
        json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {
                    "crypt": 1,
                    "qrc": 1,
                    "lyric": SYNTHETIC_ORIGINAL_LYRIC,
                    "trans": SYNTHETIC_TRANSLATION_LYRIC,
                    "roma": SYNTHETIC_ROMANIZATION_LYRIC
                }
            }
        })
    }

    #[tokio::test]
    async fn maps_owned_playlists_to_provider_independent_summaries() {
        let provider = QqMusicProvider::new(QqMusicClient::new(OwnedPlaylistsTransport::new(0)));
        set_authenticated(&provider, "123456");

        let playlists = provider.owned_playlists().await.expect("owned playlists");

        assert_eq!(playlists.len(), 1);
        assert_eq!(playlists[0].id().provider().as_str(), "qq-music");
        assert_eq!(playlists[0].id().opaque(), "owned:7001:201");
        assert_eq!(playlists[0].title(), "Synthetic liked songs");
        assert_eq!(playlists[0].track_count(), Some(42));
        assert_eq!(playlists[0].purpose(), PlaylistPurpose::LikedSongs);
        assert_eq!(playlists[0].ownership(), PlaylistOwnership::Owned);
        assert!(!format!("{playlists:?}").contains("Synthetic liked songs"));
    }

    #[tokio::test]
    async fn owned_playlists_require_authentication_and_clear_only_rejection() {
        let provider = QqMusicProvider::new(QqMusicClient::new(OwnedPlaylistsTransport::new(0)));
        assert_eq!(
            provider.owned_playlists().await,
            Err(UserLibraryError::AuthenticationRequired)
        );

        let rejected = QqMusicProvider::new(QqMusicClient::new(OwnedPlaylistsTransport::new(1000)));
        set_authenticated(&rejected, "123456");
        assert_eq!(
            rejected.owned_playlists().await,
            Err(UserLibraryError::CredentialRejected)
        );
        assert!(!rejected.has_authenticated_credential());

        let upstream =
            QqMusicProvider::new(QqMusicClient::new(OwnedPlaylistsTransport::new(50_006)));
        set_authenticated(&upstream, "123456");
        assert_eq!(
            upstream.owned_playlists().await,
            Err(UserLibraryError::ServiceUnavailable)
        );
        assert!(upstream.has_authenticated_credential());
    }

    #[tokio::test]
    async fn late_owned_playlist_result_cannot_cross_account_replacement() {
        let request_started = Arc::new(Notify::new());
        let release_request = Arc::new(Notify::new());
        let provider = QqMusicProvider::new(QqMusicClient::new(GatedOwnedPlaylistsTransport {
            request_started: Arc::clone(&request_started),
            release_request: Arc::clone(&release_request),
        }));
        set_authenticated(&provider, "123456");

        let request = provider.owned_playlists();
        let replacement = async {
            request_started.notified().await;
            set_authenticated(&provider, "654321");
            release_request.notify_one();
        };
        let (result, ()) = tokio::join!(request, replacement);

        assert_eq!(result, Err(UserLibraryError::Replaced));
        assert!(provider.has_authenticated_credential());
    }

    #[tokio::test]
    async fn aggregates_pages_and_deduplicates_by_qq_playlist_identity() {
        let provider = QqMusicProvider::new(QqMusicClient::new(UserPlaylistsTransport::new([
            favorite_page_json(
                &json!([
                    {"id": 7002, "title": "Duplicate owned list"},
                    {"id": 8001, "title": "Synthetic favorite one", "songnum": 9}
                ]),
                3,
                true,
            ),
            favorite_page_json(
                &json!([{"id": 8002, "title": "Synthetic favorite two"}]),
                3,
                false,
            ),
        ])));
        set_authenticated(&provider, "123456");

        let playlists = provider.user_playlists().await.expect("user playlists");

        assert_eq!(playlists.len(), 4);
        assert_eq!(playlists[0].id().opaque(), "owned:7001:201");
        assert_eq!(playlists[1].id().opaque(), "owned:7002:202");
        assert_eq!(playlists[2].id().opaque(), "favorite:8001");
        assert_eq!(playlists[0].ownership(), PlaylistOwnership::Owned);
        assert_eq!(playlists[1].ownership(), PlaylistOwnership::Owned);
        assert_eq!(playlists[2].ownership(), PlaylistOwnership::Saved);
        assert_eq!(playlists[2].track_count(), Some(9));
        assert_eq!(playlists[3].id().opaque(), "favorite:8002");
        assert_eq!(playlists[3].ownership(), PlaylistOwnership::Saved);

        let requests = provider.client().transport().requests();
        assert_eq!(requests.len(), 3);
        let first_favorite: Value =
            serde_json::from_slice(requests[1].body_bytes().expect("first favorite request"))
                .expect("request JSON");
        let second_favorite: Value =
            serde_json::from_slice(requests[2].body_bytes().expect("second favorite request"))
                .expect("request JSON");
        assert_eq!(
            first_favorite["music.musicasset.PlaylistFavRead"]["param"]["offset"],
            0
        );
        assert_eq!(
            second_favorite["music.musicasset.PlaylistFavRead"]["param"]["offset"],
            2
        );
        assert_eq!(
            second_favorite["music.musicasset.PlaylistFavRead"]["param"]["size"],
            100
        );
    }

    #[tokio::test]
    async fn complete_library_requires_encrypted_identity_before_transport() {
        let provider = QqMusicProvider::new(QqMusicClient::new(UserPlaylistsTransport::new([
            favorite_page_json(&json!([]), 0, false),
        ])));
        assert_eq!(
            provider.user_playlists().await,
            Err(UserLibraryError::AuthenticationRequired)
        );

        let credential = Credential::new("123456", "W_X_private-key", LoginType::WECHAT)
            .expect("fixture credential without encrypted UIN");
        *super::credential_guard(&provider.credential) =
            super::QqMusicCredentialState::Authenticated(credential);
        assert_eq!(
            provider.user_playlists().await,
            Err(UserLibraryError::InvalidResponse)
        );
        assert!(provider.client().transport().requests().is_empty());
        assert!(provider.has_authenticated_credential());
    }

    #[tokio::test]
    async fn rejects_non_advancing_and_overlong_favorite_pagination() {
        let non_advancing =
            QqMusicProvider::new(QqMusicClient::new(UserPlaylistsTransport::new([
                favorite_page_json(&json!([]), 1, true),
            ])));
        set_authenticated(&non_advancing, "123456");
        assert_eq!(
            non_advancing.user_playlists().await,
            Err(UserLibraryError::InvalidResponse)
        );
        assert!(non_advancing.has_authenticated_credential());

        let pages = (0..super::MAX_FAVORITE_PLAYLIST_PAGES).map(|index| {
            favorite_page_json(
                &json!([{"id": 8100 + index, "title": format!("Page {index}")}]),
                20,
                true,
            )
        });
        let overlong = QqMusicProvider::new(QqMusicClient::new(UserPlaylistsTransport::new(pages)));
        set_authenticated(&overlong, "123456");
        assert_eq!(
            overlong.user_playlists().await,
            Err(UserLibraryError::InvalidResponse)
        );
        assert_eq!(
            overlong.client().transport().requests().len(),
            1 + super::MAX_FAVORITE_PLAYLIST_PAGES
        );
        assert!(overlong.has_authenticated_credential());
    }

    #[tokio::test]
    async fn favorite_failure_clears_only_explicit_rejection() {
        let rejected =
            QqMusicProvider::new(QqMusicClient::new(UserPlaylistsTransport::new([json!({
                "code": 0,
                "music.musicasset.PlaylistFavRead": {"code": 1000, "data": {}}
            })])));
        set_authenticated(&rejected, "123456");
        assert_eq!(
            rejected.user_playlists().await,
            Err(UserLibraryError::CredentialRejected)
        );
        assert!(!rejected.has_authenticated_credential());

        let upstream =
            QqMusicProvider::new(QqMusicClient::new(UserPlaylistsTransport::new([json!({
                "code": 0,
                "music.musicasset.PlaylistFavRead": {"code": 50006, "data": {}}
            })])));
        set_authenticated(&upstream, "123456");
        assert_eq!(
            upstream.user_playlists().await,
            Err(UserLibraryError::ServiceUnavailable)
        );
        assert!(upstream.has_authenticated_credential());
    }

    #[tokio::test]
    async fn late_favorite_page_cannot_cross_account_replacement() {
        let favorite_started = Arc::new(Notify::new());
        let release_favorite = Arc::new(Notify::new());
        let provider = QqMusicProvider::new(QqMusicClient::new(GatedFavoritePlaylistsTransport {
            favorite_started: Arc::clone(&favorite_started),
            release_favorite: Arc::clone(&release_favorite),
        }));
        set_authenticated(&provider, "123456");

        let request = provider.user_playlists();
        let replacement = async {
            favorite_started.notified().await;
            set_authenticated(&provider, "654321");
            release_favorite.notify_one();
        };
        let (result, ()) = tokio::join!(request, replacement);

        assert_eq!(result, Err(UserLibraryError::Replaced));
        assert!(provider.has_authenticated_credential());
    }

    #[tokio::test]
    async fn favorite_albums_map_existing_domain_and_clear_only_evidenced_rejection() {
        let signed_out = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(
            &favorite_album_page_json(&json!([]), 0, false),
        )));
        assert_eq!(
            signed_out.favorite_albums(0, 20).await,
            Err(UserLibraryError::AuthenticationRequired)
        );

        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(
            &favorite_album_page_json(
                &json!([{
                    "albumid": 43001,
                    "albummid": "fixtureAlbumMid",
                    "albumname": "Synthetic favorite Album"
                }]),
                21,
                false,
            ),
        )));
        set_authenticated(&provider, "123456");
        let page = provider
            .favorite_albums(20, 20)
            .await
            .expect("favorite Albums");
        assert_eq!(page.offset(), 20);
        assert_eq!(page.total(), 21);
        assert!(!page.has_more());
        assert_eq!(page.albums().len(), 1);
        assert_eq!(
            page.albums()[0].id().opaque(),
            "album:43001:fixtureAlbumMid"
        );
        assert_eq!(page.albums()[0].title(), "Synthetic favorite Album");
        assert_eq!(
            page.albums()[0].artwork_uri(),
            Some("https://y.gtimg.cn/music/photo_new/T002R300x300M000fixtureAlbumMid.jpg")
        );
        assert!(provider.has_authenticated_credential());
        let debug = format!("{page:?}");
        assert!(!debug.contains("Synthetic favorite Album"));
        assert!(!debug.contains("fixtureAlbumMid"));

        let rejected = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 4000,
            "subcode": 4000,
            "data": {}
        }))));
        set_authenticated(&rejected, "123456");
        assert_eq!(
            rejected.favorite_albums(0, 20).await,
            Err(UserLibraryError::CredentialRejected)
        );
        assert!(!rejected.has_authenticated_credential());

        let upstream = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": -1,
            "subcode": -2,
            "data": {}
        }))));
        set_authenticated(&upstream, "123456");
        assert_eq!(
            upstream.favorite_albums(0, 20).await,
            Err(UserLibraryError::ServiceUnavailable)
        );
        assert!(upstream.has_authenticated_credential());

        assert_eq!(
            super::map_favorite_albums_error(
                &QqMusicFavoriteAlbumsError::<Infallible>::InvalidPagination
            ),
            UserLibraryError::InvalidResponse
        );
    }

    #[tokio::test]
    async fn late_favorite_album_page_cannot_cross_account_replacement() {
        let request_started = Arc::new(Notify::new());
        let release_request = Arc::new(Notify::new());
        let provider = QqMusicProvider::new(QqMusicClient::new(GatedFavoriteAlbumsTransport {
            request_started: Arc::clone(&request_started),
            release_request: Arc::clone(&release_request),
        }));
        set_authenticated(&provider, "123456");

        let request = provider.favorite_albums(0, 20);
        let replacement = async {
            request_started.notified().await;
            set_authenticated(&provider, "654321");
            release_request.notify_one();
        };
        let (result, ()) = tokio::join!(request, replacement);

        assert_eq!(result, Err(UserLibraryError::Replaced));
        assert!(provider.has_authenticated_credential());
    }

    #[tokio::test]
    async fn favorite_artists_map_mid_only_domain_and_clear_only_rejection() {
        let signed_out = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(
            &favorite_artist_page_json(&json!([]), 0, false),
        )));
        assert_eq!(
            signed_out.favorite_artists(0, 20).await,
            Err(UserLibraryError::AuthenticationRequired)
        );

        let provider = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(
            &favorite_artist_page_json(
                &json!([{"MID": "fixtureArtistMid", "Name": "Synthetic favorite Artist"}]),
                21,
                false,
            ),
        )));
        set_authenticated(&provider, "123456");
        let page = provider
            .favorite_artists(20, 20)
            .await
            .expect("favorite Artists");
        assert_eq!(page.offset(), 20);
        assert_eq!(page.total(), 21);
        assert!(!page.has_more());
        assert_eq!(page.artists().len(), 1);
        assert_eq!(page.artists()[0].id().opaque(), "artist:-:fixtureArtistMid");
        assert_eq!(page.artists()[0].name(), "Synthetic favorite Artist");
        assert_eq!(
            page.artists()[0].artwork_uri(),
            Some("https://y.gtimg.cn/music/photo_new/T001R300x300M000fixtureArtistMid.jpg")
        );
        assert!(provider.has_authenticated_credential());
        let debug = format!("{page:?} {:?}", page.artists()[0]);
        assert!(!debug.contains("Synthetic favorite Artist"));
        assert!(!debug.contains("fixtureArtistMid"));
        assert!(!debug.contains("y.gtimg.cn"));
        assert!(super::artist_artwork_uri("unsafe/path").is_none());

        let rejected = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 104_401}
        }))));
        set_authenticated(&rejected, "123456");
        assert_eq!(
            rejected.favorite_artists(0, 20).await,
            Err(UserLibraryError::CredentialRejected)
        );
        assert!(!rejected.has_authenticated_credential());

        let upstream = QqMusicProvider::new(QqMusicClient::new(SearchTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 50_006}
        }))));
        set_authenticated(&upstream, "123456");
        assert_eq!(
            upstream.favorite_artists(0, 20).await,
            Err(UserLibraryError::ServiceUnavailable)
        );
        assert!(upstream.has_authenticated_credential());

        assert_eq!(
            super::map_favorite_artists_error(
                &QqMusicFavoriteArtistsError::<Infallible>::InvalidPagination
            ),
            UserLibraryError::InvalidResponse
        );
    }

    #[tokio::test]
    async fn late_favorite_artist_page_cannot_cross_account_replacement() {
        let request_started = Arc::new(Notify::new());
        let release_request = Arc::new(Notify::new());
        let provider = QqMusicProvider::new(QqMusicClient::new(GatedFavoriteArtistsTransport {
            request_started: Arc::clone(&request_started),
            release_request: Arc::clone(&release_request),
        }));
        set_authenticated(&provider, "123456");

        let request = provider.favorite_artists(0, 20);
        let replacement = async {
            request_started.notified().await;
            set_authenticated(&provider, "654321");
            release_request.notify_one();
        };
        let (result, ()) = tokio::join!(request, replacement);

        assert_eq!(result, Err(UserLibraryError::Replaced));
        assert!(provider.has_authenticated_credential());
    }

    #[tokio::test]
    async fn routes_playlist_identities_and_maps_provider_independent_tracks() {
        let tracks = playlist_track_fixture();
        let mut tracks_without_file_media_mid = tracks.clone();
        tracks_without_file_media_mid[0]
            .as_object_mut()
            .expect("fixture track")
            .remove("file");
        let provider = QqMusicProvider::new(QqMusicClient::new(PlaylistDetailTransport::new([
            playlist_detail_page_json(&tracks, 51, true),
            playlist_detail_page_json(&tracks_without_file_media_mid, 1, false),
            playlist_detail_page_json(&tracks, 1, false),
            playlist_detail_page_json(&tracks, 1, false),
        ])));
        set_authenticated(&provider, "123456");

        let page = provider
            .playlist_tracks_page(qq_playlist_id("favorite:8001"), 50, 1)
            .await
            .expect("favorite playlist detail");
        assert_eq!(page.offset(), 50);
        assert_eq!(page.total(), 51);
        assert!(page.has_more());
        let track = &page.tracks()[0];
        assert_eq!(track.id().provider().as_str(), "qq-music");
        assert_eq!(
            track.id().opaque(),
            "track:41001:0:fixtureTrackMid1:fixtureFileMid1"
        );
        assert_eq!(track.title(), "Synthetic track");
        assert_eq!(track.artist_names(), ["Artist one", "Artist two"]);
        assert_eq!(track.album_title(), Some("Synthetic album"));
        assert_eq!(
            track.artwork_uri(),
            Some("https://y.gtimg.cn/music/photo_new/T002R300x300M000fixtureAlbumMid.jpg")
        );
        assert_eq!(track.duration_seconds(), Some(245));
        assert!(!format!("{page:?}").contains("Synthetic track"));
        assert!(super::album_artwork_uri("unsafe/path").is_none());

        let fallback_page = provider
            .playlist_tracks_page(qq_playlist_id("owned:7002:202"), 0, 100)
            .await
            .expect("ordinary owned playlist detail");
        assert_eq!(
            fallback_page.tracks()[0].id().opaque(),
            "track:41001:0:fixtureTrackMid1:-"
        );
        provider
            .playlist_tracks_page(qq_playlist_id("owned:7001:201"), 0, 100)
            .await
            .expect("liked-songs detail");
        provider
            .playlist_tracks_page(qq_playlist_id("catalog:81001"), 0, 100)
            .await
            .expect("recommended catalog playlist detail");

        let requests = provider.client().transport().requests();
        assert_eq!(requests.len(), 4);
        let params = requests
            .iter()
            .map(|request| {
                let body: Value = serde_json::from_slice(
                    request.body_bytes().expect("playlist-detail request body"),
                )
                .expect("request JSON");
                body["music.srfDissInfo.DissInfo"]["param"].clone()
            })
            .collect::<Vec<_>>();
        assert_eq!(params[0]["disstid"], 8001);
        assert_eq!(params[0]["song_begin"], 50);
        assert_eq!(params[1]["disstid"], 7002);
        assert_eq!(params[1]["dirid"], 0);
        assert_eq!(params[2]["disstid"], 0);
        assert_eq!(params[2]["dirid"], 201);
        assert_eq!(params[2]["enc_host_uin"], "encrypted-123456");
        assert_eq!(params[3]["disstid"], 81001);
    }

    #[tokio::test]
    async fn rejects_foreign_malformed_and_non_advancing_detail_pages() {
        let provider = QqMusicProvider::new(QqMusicClient::new(PlaylistDetailTransport::new([])));
        set_authenticated(&provider, "123456");
        let foreign = PlaylistId::new(ProviderId::new("local").expect("provider"), "favorite:8001")
            .expect("playlist ID");
        for id in [
            foreign,
            qq_playlist_id("favorite:0"),
            qq_playlist_id("favorite:not-a-number"),
            qq_playlist_id("catalog:0"),
            qq_playlist_id("catalog:not-a-number"),
            qq_playlist_id("owned:7001"),
            qq_playlist_id("owned:7001:201:extra"),
        ] {
            assert_eq!(
                provider.playlist_tracks_page(id, 0, 100).await,
                Err(UserLibraryError::InvalidResponse)
            );
        }
        assert_eq!(
            provider
                .playlist_tracks_page(qq_playlist_id("favorite:8001"), 0, 0)
                .await,
            Err(UserLibraryError::InvalidResponse)
        );
        assert!(provider.client().transport().requests().is_empty());

        let non_advancing =
            QqMusicProvider::new(QqMusicClient::new(PlaylistDetailTransport::new([
                playlist_detail_page_json(&json!([]), 1, true),
            ])));
        set_authenticated(&non_advancing, "123456");
        assert_eq!(
            non_advancing
                .playlist_tracks_page(qq_playlist_id("favorite:8001"), 0, 100)
                .await,
            Err(UserLibraryError::InvalidResponse)
        );
        assert!(non_advancing.has_authenticated_credential());
    }

    #[tokio::test]
    async fn detail_failure_clears_only_explicit_rejection() {
        let rejected =
            QqMusicProvider::new(QqMusicClient::new(PlaylistDetailTransport::new([json!({
                "code": 0,
                "music.srfDissInfo.DissInfo": {"code": 1000, "data": {"code": 0}}
            })])));
        set_authenticated(&rejected, "123456");
        assert_eq!(
            rejected
                .playlist_tracks_page(qq_playlist_id("favorite:8001"), 0, 100)
                .await,
            Err(UserLibraryError::CredentialRejected)
        );
        assert!(!rejected.has_authenticated_credential());

        let upstream =
            QqMusicProvider::new(QqMusicClient::new(PlaylistDetailTransport::new([json!({
                "code": 0,
                "music.srfDissInfo.DissInfo": {"code": 50_006, "data": {"code": 0}}
            })])));
        set_authenticated(&upstream, "123456");
        assert_eq!(
            upstream
                .playlist_tracks_page(qq_playlist_id("favorite:8001"), 0, 100)
                .await,
            Err(UserLibraryError::ServiceUnavailable)
        );
        assert!(upstream.has_authenticated_credential());
    }

    #[tokio::test]
    async fn late_playlist_detail_cannot_cross_account_replacement() {
        let request_started = Arc::new(Notify::new());
        let release_request = Arc::new(Notify::new());
        let provider = QqMusicProvider::new(QqMusicClient::new(GatedPlaylistDetailTransport {
            request_started: Arc::clone(&request_started),
            release_request: Arc::clone(&release_request),
        }));
        set_authenticated(&provider, "123456");

        let request = provider.playlist_tracks_page(qq_playlist_id("favorite:8001"), 0, 100);
        let replacement = async {
            request_started.notified().await;
            set_authenticated(&provider, "654321");
            release_request.notify_one();
        };
        let (result, ()) = tokio::join!(request, replacement);

        assert_eq!(result, Err(UserLibraryError::Replaced));
        assert!(provider.has_authenticated_credential());
    }

    #[tokio::test]
    async fn sets_liked_track_state_from_opaque_identity() {
        for (liked, method) in [(true, "AddSonglist"), (false, "DelSonglist")] {
            let provider =
                QqMusicProvider::new(QqMusicClient::new(TrackLikeTransport::new(&json!({
                    "code": 0,
                    "req_0": {"code": 0, "data": {"retCode": 0}}
                }))));
            set_authenticated(&provider, "123456");

            provider
                .set_track_liked(
                    qq_track_id("track:41001:7:fixtureTrackMid1:fixtureFileMid1"),
                    liked,
                )
                .await
                .expect("confirmed desired like state");

            let requests = provider.client().transport().requests();
            assert_eq!(requests.len(), 1);
            let body: Value =
                serde_json::from_slice(requests[0].body_bytes().expect("mutation body"))
                    .expect("mutation JSON");
            assert_eq!(body["req_0"]["method"], method);
            assert_eq!(
                body["req_0"]["param"]["v_songInfo"],
                json!([{"songId": 41001, "songType": 7}])
            );
        }
    }

    #[tokio::test]
    async fn sets_album_favorite_state_from_numeric_opaque_identity() {
        for (favorite, method) in [(true, "FavAlbum"), (false, "CancelFavAlbum")] {
            let provider =
                QqMusicProvider::new(QqMusicClient::new(TrackLikeTransport::new(&json!({
                    "code": 0,
                    "req_0": {
                        "code": 0,
                        "data": {"result": 0, "v_failedAlbumId": []}
                    }
                }))));
            set_authenticated(&provider, "123456");

            provider
                .set_album_favorite(qq_album_id("album:43001:fixtureAlbumMid"), favorite)
                .await
                .expect("confirmed desired Album favorite state");

            let requests = provider.client().transport().requests();
            assert_eq!(requests.len(), 1);
            let body: Value =
                serde_json::from_slice(requests[0].body_bytes().expect("mutation body"))
                    .expect("mutation JSON");
            assert_eq!(body["req_0"]["method"], method);
            assert_eq!(body["req_0"]["param"], json!({"v_albumId": [43_001]}));
        }
    }

    #[tokio::test]
    async fn album_favorite_rejects_unsupported_identity_and_clears_only_rejected_credential() {
        let invalid = QqMusicProvider::new(QqMusicClient::new(TrackLikeTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 0, "data": {"result": 0, "v_failedAlbumId": []}}
        }))));
        set_authenticated(&invalid, "123456");
        for album_id in [
            qq_album_id("album:-:fixtureAlbumMid"),
            qq_album_id("album:0:fixtureAlbumMid"),
            qq_album_id("album:43001:unsafe-mid"),
            qq_album_id("album:43001:fixtureAlbumMid:extra"),
            AlbumId::new(
                ProviderId::new("local").expect("provider"),
                "album:43001:fixtureAlbumMid",
            )
            .expect("structural Album ID"),
        ] {
            assert_eq!(
                invalid.set_album_favorite(album_id, true).await,
                Err(LibraryMutationError::InvalidRequest)
            );
        }
        assert!(invalid.client().transport().requests().is_empty());
        assert!(invalid.has_authenticated_credential());

        let rejected = QqMusicProvider::new(QqMusicClient::new(TrackLikeTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 104_401}
        }))));
        set_authenticated(&rejected, "123456");
        assert_eq!(
            rejected
                .set_album_favorite(qq_album_id("album:43001:fixtureAlbumMid"), true)
                .await,
            Err(LibraryMutationError::CredentialRejected)
        );
        assert!(!rejected.has_authenticated_credential());
    }

    #[tokio::test]
    async fn sets_owned_playlist_track_membership_from_opaque_identities() {
        for (present, method) in [(true, "AddSonglist"), (false, "DelSonglist")] {
            let provider =
                QqMusicProvider::new(QqMusicClient::new(TrackLikeTransport::new(&json!({
                    "code": 0,
                    "req_0": {"code": 0, "data": {"retCode": 0}}
                }))));
            set_authenticated(&provider, "123456");

            provider
                .set_playlist_track_membership(
                    qq_playlist_id("owned:7002:902"),
                    qq_track_id("track:41001:7:fixtureTrackMid1:fixtureFileMid1"),
                    present,
                )
                .await
                .expect("confirmed desired playlist membership");

            let requests = provider.client().transport().requests();
            assert_eq!(requests.len(), 1);
            let body: Value =
                serde_json::from_slice(requests[0].body_bytes().expect("mutation body"))
                    .expect("mutation JSON");
            assert_eq!(body["req_0"]["method"], method);
            assert_eq!(body["req_0"]["param"]["dirId"], 902);
            assert_eq!(
                body["req_0"]["param"]["v_songInfo"],
                json!([{"songId": 41001, "songType": 7}])
            );
        }
    }

    #[tokio::test]
    async fn playlist_track_mutation_rejects_non_owned_targets_before_transport() {
        let provider = QqMusicProvider::new(QqMusicClient::new(TrackLikeTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 0, "data": {"retCode": 0}}
        }))));
        set_authenticated(&provider, "123456");
        let track = || qq_track_id("track:41001:0:fixtureTrackMid1:fixtureFileMid1");

        for playlist_id in [
            qq_playlist_id("favorite:8001"),
            qq_playlist_id("catalog:81001"),
            qq_playlist_id("owned:7002:0"),
            qq_playlist_id("owned:7002:902:extra"),
            PlaylistId::new(
                ProviderId::new("local").expect("provider"),
                "owned:7002:902",
            )
            .expect("structural playlist ID"),
        ] {
            assert_eq!(
                provider
                    .set_playlist_track_membership(playlist_id, track(), true)
                    .await,
                Err(LibraryMutationError::InvalidRequest)
            );
        }
        assert!(provider.client().transport().requests().is_empty());
    }

    #[tokio::test]
    async fn creates_provider_neutral_owned_playlist_from_confirmed_result() {
        let provider = QqMusicProvider::new(QqMusicClient::new(TrackLikeTransport::new(&json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {
                    "retCode": 0,
                    "result": {
                        "tid": 7002,
                        "dirId": 902,
                        "dirName": "Server playlist"
                    }
                }
            }
        }))));
        set_authenticated(&provider, "123456");

        let created = provider
            .create_playlist("Requested playlist".into())
            .await
            .expect("confirmed playlist creation");

        assert_eq!(created.id().opaque(), "owned:7002:902");
        assert_eq!(created.title(), "Server playlist");
        let requests = provider.client().transport().requests();
        assert_eq!(requests.len(), 1);
        let body: Value = serde_json::from_slice(
            requests[0]
                .body_bytes()
                .expect("create-playlist request body"),
        )
        .expect("create-playlist request JSON");
        assert_eq!(body["req_0"]["method"], "AddPlaylist");
        assert_eq!(
            body["req_0"]["param"],
            json!({"dirName": "Requested playlist"})
        );
    }

    #[tokio::test]
    async fn create_playlist_rejects_invalid_name_and_clears_only_rejected_credential() {
        let invalid = QqMusicProvider::new(QqMusicClient::new(TrackLikeTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 0}
        }))));
        set_authenticated(&invalid, "123456");
        assert_eq!(
            invalid.create_playlist("   ".into()).await,
            Err(LibraryMutationError::InvalidRequest)
        );
        assert!(invalid.client().transport().requests().is_empty());
        assert!(invalid.has_authenticated_credential());

        let rejected = QqMusicProvider::new(QqMusicClient::new(TrackLikeTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 104_401}
        }))));
        set_authenticated(&rejected, "123456");
        assert_eq!(
            rejected.create_playlist("Requested playlist".into()).await,
            Err(LibraryMutationError::CredentialRejected)
        );
        assert!(!rejected.has_authenticated_credential());
    }

    #[tokio::test]
    async fn deletes_only_confirmed_owned_playlist_target() {
        let provider = QqMusicProvider::new(QqMusicClient::new(TrackLikeTransport::new(&json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {
                    "retCode": 0,
                    "result": {"tid": 7002, "dirId": 902}
                }
            }
        }))));
        set_authenticated(&provider, "123456");

        provider
            .delete_playlist(qq_playlist_id("owned:7002:902"))
            .await
            .expect("confirmed playlist deletion");

        let requests = provider.client().transport().requests();
        assert_eq!(requests.len(), 1);
        let body: Value = serde_json::from_slice(
            requests[0]
                .body_bytes()
                .expect("delete-playlist request body"),
        )
        .expect("delete-playlist request JSON");
        assert_eq!(body["req_0"]["method"], "DelPlaylist");
        assert_eq!(body["req_0"]["param"], json!({"dirId": 902}));
    }

    #[tokio::test]
    async fn delete_playlist_rejects_non_owned_targets_before_transport() {
        for playlist_id in [
            PlaylistId::new(
                ProviderId::new("local").expect("provider"),
                "owned:7002:902",
            )
            .expect("structural playlist ID"),
            qq_playlist_id("catalog:7002"),
            qq_playlist_id("favorite:7002"),
            qq_playlist_id("liked:7002:201"),
            qq_playlist_id("owned:7002:0"),
            qq_playlist_id("owned:0:902"),
            qq_playlist_id("owned:not-a-number:902"),
            qq_playlist_id("owned:7002:902:extra"),
        ] {
            let provider = QqMusicProvider::new(QqMusicClient::new(TrackLikeTransport::new(
                &json!({"code": 0}),
            )));
            set_authenticated(&provider, "123456");
            assert_eq!(
                provider.delete_playlist(playlist_id).await,
                Err(LibraryMutationError::InvalidRequest)
            );
            assert!(provider.client().transport().requests().is_empty());
            assert!(provider.has_authenticated_credential());
        }
    }

    #[tokio::test]
    async fn delete_playlist_clears_only_explicitly_rejected_credential() {
        let rejected = QqMusicProvider::new(QqMusicClient::new(TrackLikeTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 104_401}
        }))));
        set_authenticated(&rejected, "123456");

        assert_eq!(
            rejected
                .delete_playlist(qq_playlist_id("owned:7002:902"))
                .await,
            Err(LibraryMutationError::CredentialRejected)
        );
        assert!(!rejected.has_authenticated_credential());

        let unknown = QqMusicProvider::new(QqMusicClient::new(TrackLikeTransport::new(&json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {"retCode": 0, "result": {"dirId": 0}}
            }
        }))));
        set_authenticated(&unknown, "123456");
        assert_eq!(
            unknown
                .delete_playlist(qq_playlist_id("owned:7002:902"))
                .await,
            Err(LibraryMutationError::InvalidResponseOutcomeUnknown)
        );
        assert!(unknown.has_authenticated_credential());
    }

    #[tokio::test]
    async fn like_mutation_rejects_invalid_identity_and_clears_only_rejected_credential() {
        let invalid = QqMusicProvider::new(QqMusicClient::new(TrackLikeTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 0, "data": {"retCode": 0}}
        }))));
        set_authenticated(&invalid, "123456");
        assert_eq!(
            invalid
                .set_track_liked(
                    TrackId::new(
                        ProviderId::new("local").expect("provider"),
                        "track:41001:0:fixtureTrackMid1:fixtureFileMid1",
                    )
                    .expect("structural track ID"),
                    true,
                )
                .await,
            Err(LibraryMutationError::InvalidRequest)
        );
        assert!(invalid.client().transport().requests().is_empty());

        let rejected = QqMusicProvider::new(QqMusicClient::new(TrackLikeTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 104_401}
        }))));
        set_authenticated(&rejected, "123456");
        assert_eq!(
            rejected
                .set_track_liked(
                    qq_track_id("track:41001:0:fixtureTrackMid1:fixtureFileMid1"),
                    true,
                )
                .await,
            Err(LibraryMutationError::CredentialRejected)
        );
        assert!(!rejected.has_authenticated_credential());

        let service = QqMusicProvider::new(QqMusicClient::new(TrackLikeTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 50006}
        }))));
        set_authenticated(&service, "123456");
        assert_eq!(
            service
                .set_track_liked(
                    qq_track_id("track:41001:0:fixtureTrackMid1:fixtureFileMid1"),
                    true,
                )
                .await,
            Err(LibraryMutationError::ServiceUnavailable)
        );
        assert!(service.has_authenticated_credential());
    }

    #[tokio::test]
    async fn late_like_mutation_cannot_cross_account_replacement() {
        let request_started = Arc::new(Notify::new());
        let release_request = Arc::new(Notify::new());
        let provider = QqMusicProvider::new(QqMusicClient::new(GatedTrackLikeTransport {
            request_started: Arc::clone(&request_started),
            release_request: Arc::clone(&release_request),
        }));
        set_authenticated(&provider, "123456");

        let request = provider.set_track_liked(
            qq_track_id("track:41001:0:fixtureTrackMid1:fixtureFileMid1"),
            true,
        );
        let replacement = async {
            request_started.notified().await;
            set_authenticated(&provider, "654321");
            release_request.notify_one();
        };
        let (result, ()) = tokio::join!(request, replacement);

        assert_eq!(result, Err(LibraryMutationError::Replaced));
        assert!(provider.has_authenticated_credential());
    }

    #[tokio::test]
    async fn late_album_favorite_cannot_cross_account_replacement() {
        let request_started = Arc::new(Notify::new());
        let release_request = Arc::new(Notify::new());
        let provider = QqMusicProvider::new(QqMusicClient::new(GatedTrackLikeTransport {
            request_started: Arc::clone(&request_started),
            release_request: Arc::clone(&release_request),
        }));
        set_authenticated(&provider, "123456");

        let request = provider.set_album_favorite(qq_album_id("album:43001:fixtureAlbumMid"), true);
        let replacement = async {
            request_started.notified().await;
            set_authenticated(&provider, "654321");
            release_request.notify_one();
        };
        let (result, ()) = tokio::join!(request, replacement);

        assert_eq!(result, Err(LibraryMutationError::Replaced));
        assert!(provider.has_authenticated_credential());
    }

    #[tokio::test]
    async fn late_playlist_track_mutation_cannot_cross_account_replacement() {
        let request_started = Arc::new(Notify::new());
        let release_request = Arc::new(Notify::new());
        let provider = QqMusicProvider::new(QqMusicClient::new(GatedTrackLikeTransport {
            request_started: Arc::clone(&request_started),
            release_request: Arc::clone(&release_request),
        }));
        set_authenticated(&provider, "123456");

        let request = provider.set_playlist_track_membership(
            qq_playlist_id("owned:7002:902"),
            qq_track_id("track:41001:0:fixtureTrackMid1:fixtureFileMid1"),
            true,
        );
        let replacement = async {
            request_started.notified().await;
            set_authenticated(&provider, "654321");
            release_request.notify_one();
        };
        let (result, ()) = tokio::join!(request, replacement);

        assert_eq!(result, Err(LibraryMutationError::Replaced));
        assert!(provider.has_authenticated_credential());
    }

    #[tokio::test]
    async fn late_create_playlist_cannot_cross_account_replacement() {
        let request_started = Arc::new(Notify::new());
        let release_request = Arc::new(Notify::new());
        let provider = QqMusicProvider::new(QqMusicClient::new(GatedTrackLikeTransport {
            request_started: Arc::clone(&request_started),
            release_request: Arc::clone(&release_request),
        }));
        set_authenticated(&provider, "123456");

        let request = provider.create_playlist("Requested playlist".into());
        let replacement = async {
            request_started.notified().await;
            set_authenticated(&provider, "654321");
            release_request.notify_one();
        };
        let (result, ()) = tokio::join!(request, replacement);

        assert_eq!(result, Err(LibraryMutationError::Replaced));
        assert!(provider.has_authenticated_credential());
    }

    #[tokio::test]
    async fn late_delete_playlist_cannot_cross_account_replacement() {
        let request_started = Arc::new(Notify::new());
        let release_request = Arc::new(Notify::new());
        let provider = QqMusicProvider::new(QqMusicClient::new(GatedTrackLikeTransport {
            request_started: Arc::clone(&request_started),
            release_request: Arc::clone(&release_request),
        }));
        set_authenticated(&provider, "123456");

        let request = provider.delete_playlist(qq_playlist_id("owned:7002:902"));
        let replacement = async {
            request_started.notified().await;
            set_authenticated(&provider, "654321");
            release_request.notify_one();
        };
        let (result, ()) = tokio::join!(request, replacement);

        assert_eq!(result, Err(LibraryMutationError::Replaced));
        assert!(provider.has_authenticated_credential());
    }

    #[tokio::test]
    async fn resolves_opaque_track_to_provider_independent_standard_media() {
        let provider = QqMusicProvider::new(QqMusicClient::new(MediaTransport::new([
            media_dispatch_json(),
            media_vkey_json(0, "M500fixtureFileMid1.mp3?vkey=private-source"),
        ])));
        set_authenticated(&provider, "123456");
        let track_id = qq_track_id("track:41001:0:fixtureTrackMid1:fixtureFileMid1");

        let source = provider
            .media_source_resolver()
            .resolve_media(track_id.clone(), AudioQuality::Standard)
            .await
            .expect("standard media");
        assert_eq!(source.track_id(), &track_id);
        assert_eq!(source.format(), AudioFormat::Mp3);
        assert_eq!(source.quality(), AudioQuality::Standard);
        assert_eq!(source.valid_for_seconds(), 7_200);
        assert_eq!(
            source.uri(),
            "http://audio.example.test/M500fixtureFileMid1.mp3?vkey=private-source"
        );
        assert!(!format!("{source:?}").contains("private-source"));

        let requests = provider.client().transport().requests();
        assert_eq!(requests.len(), 2);
        let vkey: Value =
            serde_json::from_slice(requests[1].body_bytes().expect("vkey request body"))
                .expect("vkey request JSON");
        assert_eq!(vkey["req_0"]["param"]["songtype"], json!([0]));
        assert_eq!(
            vkey["req_0"]["param"]["songmid"],
            json!(["fixtureTrackMid1"])
        );
        assert_eq!(
            vkey["req_0"]["param"]["filename"],
            json!(["M500fixtureFileMid1.mp3"])
        );
    }

    #[tokio::test]
    async fn signed_out_media_uses_anonymous_standard_quality_without_cookie() {
        let provider = QqMusicProvider::new(QqMusicClient::new(MediaTransport::new([
            media_dispatch_json(),
            media_vkey_json(0, "M500fixtureFileMid1.mp3?vkey=public-source"),
        ])));
        let track_id = qq_track_id("track:41001:0:fixtureTrackMid1:fixtureFileMid1");

        let source = provider
            .media_source_resolver()
            .resolve_media(track_id, AudioQuality::High)
            .await
            .expect("anonymous standard source");

        assert_eq!(source.quality(), AudioQuality::Standard);
        assert!(!provider.has_authenticated_credential());
        let requests = provider.client().transport().requests();
        assert_eq!(requests.len(), 2);
        assert!(
            !requests[1]
                .headers()
                .iter()
                .any(|(name, _)| name == "Cookie")
        );
        let body: Value =
            serde_json::from_slice(requests[1].body_bytes().expect("vkey request body"))
                .expect("vkey request JSON");
        assert_eq!(body["comm"]["uid"], json!("0"));
        assert!(body["comm"].get("authst").is_none());
        assert_eq!(
            body["req_0"]["param"]["filename"],
            json!(["M500fixtureFileMid1.mp3"])
        );
    }

    #[tokio::test]
    async fn signed_out_unavailable_media_invites_authentication_without_claiming_why() {
        let provider = QqMusicProvider::new(QqMusicClient::new(MediaTransport::new([
            media_dispatch_json(),
            media_vkey_json(104_003, ""),
        ])));

        assert_eq!(
            provider
                .media_source_resolver()
                .resolve_media(
                    qq_track_id("track:41001:0:fixtureTrackMid1:fixtureFileMid1"),
                    AudioQuality::Standard,
                )
                .await,
            Err(MediaResolutionError::AuthenticationRequired)
        );
        assert!(!provider.has_authenticated_credential());
    }

    #[tokio::test]
    async fn high_quality_reports_actual_source_and_falls_back_only_when_unavailable() {
        let high = QqMusicProvider::new(QqMusicClient::new(MediaTransport::new([
            media_dispatch_json(),
            high_media_vkey_json(0, "M800fixtureFileMid1.mp3?vkey=private-high-source"),
        ])));
        set_authenticated(&high, "123456");
        let high_source = high
            .media_source_resolver()
            .resolve_media(
                qq_track_id("track:41001:0:fixtureTrackMid1:fixtureFileMid1"),
                AudioQuality::High,
            )
            .await
            .expect("high media");
        assert_eq!(high_source.quality(), AudioQuality::High);

        let fallback = QqMusicProvider::new(QqMusicClient::new(MediaTransport::new([
            media_dispatch_json(),
            high_media_vkey_json(101_404, ""),
            media_vkey_json(0, "M500fixtureFileMid1.mp3?vkey=private-standard-source"),
        ])));
        set_authenticated(&fallback, "123456");
        let fallback_source = fallback
            .media_source_resolver()
            .resolve_media(
                qq_track_id("track:41001:0:fixtureTrackMid1:fixtureFileMid1"),
                AudioQuality::High,
            )
            .await
            .expect("standard fallback");
        assert_eq!(fallback_source.quality(), AudioQuality::Standard);
        let requests = fallback.client().transport().requests();
        assert_eq!(requests.len(), 3);
        let high_request: Value =
            serde_json::from_slice(requests[1].body_bytes().expect("high request body"))
                .expect("high request JSON");
        let standard_request: Value =
            serde_json::from_slice(requests[2].body_bytes().expect("standard request body"))
                .expect("standard request JSON");
        assert_eq!(
            high_request["req_0"]["param"]["filename"],
            json!(["M800fixtureFileMid1.mp3"])
        );
        assert_eq!(
            standard_request["req_0"]["param"]["filename"],
            json!(["M500fixtureFileMid1.mp3"])
        );

        let service_failure = QqMusicProvider::new(QqMusicClient::new(MediaTransport::new([
            media_dispatch_json(),
            json!({"code": 0, "req_0": {"code": 50_006}}),
        ])));
        set_authenticated(&service_failure, "123456");
        assert_eq!(
            service_failure
                .media_source_resolver()
                .resolve_media(
                    qq_track_id("track:41001:0:fixtureTrackMid1:fixtureFileMid1"),
                    AudioQuality::High,
                )
                .await,
            Err(MediaResolutionError::ServiceUnavailable)
        );
        assert_eq!(service_failure.client().transport().requests().len(), 2);
    }

    #[tokio::test]
    async fn rejects_foreign_and_malformed_media_identity_before_transport() {
        let provider = QqMusicProvider::new(QqMusicClient::new(MediaTransport::new([])));
        set_authenticated(&provider, "123456");
        let foreign = TrackId::new(
            ProviderId::new("local").expect("provider"),
            "track:41001:0:fixtureTrackMid1:fixtureFileMid1",
        )
        .expect("track ID");
        let invalid = [
            foreign,
            qq_track_id("track:0:0:fixtureTrackMid1:fixtureFileMid1"),
            qq_track_id("track:41001:not-a-type:fixtureTrackMid1:fixtureFileMid1"),
            qq_track_id("track:41001:0:unsafe-mid:fixtureFileMid1"),
            qq_track_id("track:41001:0:fixtureTrackMid1:unsafe-file-mid"),
            qq_track_id("track:41001:0:fixtureTrackMid1:fixtureFileMid1:extra"),
            qq_track_id("wrong:41001:0:fixtureTrackMid1:fixtureFileMid1"),
        ];
        for track_id in invalid {
            assert_eq!(
                provider
                    .media_source_resolver()
                    .resolve_media(track_id, AudioQuality::Standard)
                    .await,
                Err(MediaResolutionError::InvalidResponse)
            );
        }
        assert!(provider.client().transport().requests().is_empty());

        let fallback_id = qq_track_id("track:41001:0:fixtureTrackMid1:-");
        let fallback = super::parse_media_track(&fallback_id)
            .expect("missing file-media MID keeps the documented fallback");
        assert_eq!(fallback.song_mid, "fixtureTrackMid1");
        assert_eq!(fallback.file_media_mid, None);
    }

    #[tokio::test]
    async fn media_failure_clears_only_explicit_rejection() {
        let unavailable = QqMusicProvider::new(QqMusicClient::new(MediaTransport::new([
            media_dispatch_json(),
            media_vkey_json(101_404, ""),
        ])));
        set_authenticated(&unavailable, "123456");
        assert_eq!(
            unavailable
                .media_source_resolver()
                .resolve_media(
                    qq_track_id("track:41001:0:fixtureTrackMid1:fixtureFileMid1",),
                    AudioQuality::Standard
                )
                .await,
            Err(MediaResolutionError::Unavailable)
        );
        assert!(unavailable.has_authenticated_credential());

        let rejected = QqMusicProvider::new(QqMusicClient::new(MediaTransport::new([
            media_dispatch_json(),
            json!({"code": 0, "req_0": {"code": 1000}}),
        ])));
        set_authenticated(&rejected, "123456");
        assert_eq!(
            rejected
                .media_source_resolver()
                .resolve_media(
                    qq_track_id("track:41001:0:fixtureTrackMid1:fixtureFileMid1",),
                    AudioQuality::Standard
                )
                .await,
            Err(MediaResolutionError::CredentialRejected)
        );
        assert!(!rejected.has_authenticated_credential());

        let upstream = QqMusicProvider::new(QqMusicClient::new(MediaTransport::new([
            media_dispatch_json(),
            json!({"code": 0, "req_0": {"code": 50_006}}),
        ])));
        set_authenticated(&upstream, "123456");
        assert_eq!(
            upstream
                .media_source_resolver()
                .resolve_media(
                    qq_track_id("track:41001:0:fixtureTrackMid1:fixtureFileMid1",),
                    AudioQuality::Standard
                )
                .await,
            Err(MediaResolutionError::ServiceUnavailable)
        );
        assert!(upstream.has_authenticated_credential());
    }

    #[tokio::test]
    async fn quality_fallback_rechecks_account_after_every_network_await() {
        for gate_call in [1, 2, 3] {
            let request_started = Arc::new(Notify::new());
            let release_request = Arc::new(Notify::new());
            let calls = Arc::new(AtomicUsize::new(0));
            let provider = QqMusicProvider::new(QqMusicClient::new(GatedMediaTransport {
                gate_call,
                calls: Arc::clone(&calls),
                request_started: Arc::clone(&request_started),
                release_request: Arc::clone(&release_request),
            }));
            set_authenticated(&provider, "123456");

            let resolver = provider.media_source_resolver();
            let request = resolver.resolve_media(
                qq_track_id("track:41001:0:fixtureTrackMid1:fixtureFileMid1"),
                AudioQuality::High,
            );
            let replacement = async {
                request_started.notified().await;
                set_authenticated(&provider, "654321");
                release_request.notify_one();
            };
            let (result, ()) = tokio::join!(request, replacement);

            assert_eq!(result, Err(MediaResolutionError::Replaced));
            assert_eq!(calls.load(Ordering::SeqCst), gate_call);
            assert!(provider.has_authenticated_credential());
        }
    }

    #[tokio::test]
    async fn maps_cloud_qrc_to_provider_neutral_synchronized_lyrics() {
        let provider = QqMusicProvider::new(QqMusicClient::new(LyricsTransport::new(
            &lyrics_success_json(),
        )));
        set_authenticated(&provider, "123456");
        let track_id = qq_track_id("track:41001:7:fixtureMID01:fixtureFileMID01");

        let lyrics = provider
            .lyrics(track_id.clone())
            .await
            .expect("synchronized lyrics");

        assert_eq!(lyrics.track_id(), &track_id);
        assert!(lyrics.has_word_timing());
        assert_eq!(lyrics.lines().len(), 2);
        let first = &lyrics.lines()[0];
        assert_eq!(first.text(), "Synthetic");
        assert_eq!(first.start_ms(), 1_000);
        assert_eq!(first.duration_ms(), 800);
        assert_eq!(first.translation(), Some("Translated fixture"));
        assert_eq!(first.romanization(), Some("Romanized fixture"));
        assert_eq!(first.segments().len(), 2);
        assert_eq!(first.segments()[0].text(), "Syn");
        assert_eq!(first.segments()[0].start_ms(), 1_000);
        assert_eq!(first.segments()[1].start_ms(), 1_400);
        assert_eq!(lyrics.lines()[1].translation(), None);
        assert_eq!(lyrics.lines()[1].romanization(), None);
        assert!(!format!("{lyrics:?}").contains("Synthetic"));

        let requests = provider.client().transport().requests();
        assert_eq!(requests.len(), 1);
        let body: Value =
            serde_json::from_slice(requests[0].body_bytes().expect("lyric request body"))
                .expect("lyric request JSON");
        assert_eq!(body["req_0"]["param"]["songMid"], "fixtureMID01");
        assert_eq!(body["req_0"]["param"]["type"], 7);
    }

    #[test]
    fn ambiguous_auxiliary_timestamps_are_not_attached() {
        let by_start = super::unique_auxiliary_by_start([
            (1_000, "first"),
            (1_000, "duplicate"),
            (2_000, "unique"),
        ]);

        assert_eq!(super::auxiliary_at(&by_start, 1_000), None);
        assert_eq!(
            super::auxiliary_at(&by_start, 2_000),
            Some("unique".to_owned())
        );
        assert_eq!(super::auxiliary_at(&by_start, 3_000), None);
    }

    #[tokio::test]
    async fn lyrics_require_authentication_and_reject_malformed_identity_before_transport() {
        let provider = QqMusicProvider::new(QqMusicClient::new(LyricsTransport::new(
            &lyrics_success_json(),
        )));
        assert_eq!(
            provider
                .lyrics(qq_track_id("track:41001:0:fixtureMID01:fixtureFileMID01"))
                .await,
            Err(LyricsError::AuthenticationRequired)
        );
        set_authenticated(&provider, "123456");
        let foreign = TrackId::new(
            ProviderId::new("local").expect("provider"),
            "track:41001:0:fixtureMID01:fixtureFileMID01",
        )
        .expect("track ID");
        let invalid = [
            foreign,
            qq_track_id("track:0:0:fixtureMID01:fixtureFileMID01"),
            qq_track_id("track:41001:not-a-type:fixtureMID01:fixtureFileMID01"),
            qq_track_id("track:41001:0:unsafe-mid:fixtureFileMID01"),
            qq_track_id("track:41001:0:fixtureMID01:unsafe-file-mid"),
            qq_track_id("track:41001:0:fixtureMID01:fixtureFileMID01:extra"),
            qq_track_id("wrong:41001:0:fixtureMID01:fixtureFileMID01"),
        ];
        for track_id in invalid {
            assert_eq!(
                provider.lyrics(track_id).await,
                Err(LyricsError::InvalidResponse)
            );
        }
        assert!(provider.client().transport().requests().is_empty());
    }

    #[tokio::test]
    async fn lyric_failure_clears_only_explicit_rejection() {
        let unavailable = QqMusicProvider::new(QqMusicClient::new(LyricsTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 0, "data": {"crypt": 1, "qrc": 1, "lyric": ""}}
        }))));
        set_authenticated(&unavailable, "123456");
        assert_eq!(
            unavailable
                .lyrics(qq_track_id("track:41001:0:fixtureMID01:fixtureFileMID01"))
                .await,
            Err(LyricsError::Unavailable)
        );
        assert!(unavailable.has_authenticated_credential());

        let rejected = QqMusicProvider::new(QqMusicClient::new(LyricsTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 1000}
        }))));
        set_authenticated(&rejected, "123456");
        assert_eq!(
            rejected
                .lyrics(qq_track_id("track:41001:0:fixtureMID01:fixtureFileMID01"))
                .await,
            Err(LyricsError::CredentialRejected)
        );
        assert!(!rejected.has_authenticated_credential());

        let upstream = QqMusicProvider::new(QqMusicClient::new(LyricsTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 50_006}
        }))));
        set_authenticated(&upstream, "123456");
        assert_eq!(
            upstream
                .lyrics(qq_track_id("track:41001:0:fixtureMID01:fixtureFileMID01"))
                .await,
            Err(LyricsError::ServiceUnavailable)
        );
        assert!(upstream.has_authenticated_credential());
    }

    #[tokio::test]
    async fn late_lyric_result_cannot_cross_account_replacement() {
        let request_started = Arc::new(Notify::new());
        let release_request = Arc::new(Notify::new());
        let provider = QqMusicProvider::new(QqMusicClient::new(GatedLyricsTransport {
            request_started: Arc::clone(&request_started),
            release_request: Arc::clone(&release_request),
        }));
        set_authenticated(&provider, "123456");

        let request = provider.lyrics(qq_track_id("track:41001:0:fixtureMID01:fixtureFileMID01"));
        let replacement = async {
            request_started.notified().await;
            set_authenticated(&provider, "654321");
            release_request.notify_one();
        };
        let (result, ()) = tokio::join!(request, replacement);

        assert_eq!(result, Err(LyricsError::Replaced));
        assert!(provider.has_authenticated_credential());
    }

    fn restore_candidate<T>(provider: &QqMusicProvider<T>) {
        let encoded = Credential::new("123456", "W_X_private-key", LoginType::WECHAT)
            .expect("fixture credential")
            .encode_for_secure_storage()
            .expect("encode fixture");
        assert_eq!(
            provider
                .restore_credential_from_secure_storage(Some(&encoded), 2_000)
                .expect("restore candidate"),
            QqMusicCredentialRestoreState::VerificationRequired,
        );
    }

    #[tokio::test]
    async fn account_summary_maps_only_public_identity_for_current_credential() {
        let provider = QqMusicProvider::new(QqMusicClient::new(VerificationTransport::new(0)));
        set_authenticated(&provider, "123456");

        let summary = provider.account_summary().await.expect("account summary");

        assert_eq!(summary.provider().as_str(), "qq-music");
        assert_eq!(summary.display_name(), "Synthetic listener");
        assert_eq!(
            summary.avatar_uri(),
            Some("https://example.invalid/avatar.jpg")
        );
        let debug = format!("{summary:?}");
        assert!(!debug.contains("Synthetic listener"));
        assert!(!debug.contains("avatar.jpg"));
        assert!(!debug.contains("123456"));
    }

    #[tokio::test]
    async fn account_summary_requires_authentication_and_rejects_missing_identity() {
        let signed_out = QqMusicProvider::new(QqMusicClient::new(VerificationTransport::new(0)));
        assert_eq!(
            signed_out.account_summary().await,
            Err(AccountSummaryError::AuthenticationRequired)
        );

        let missing = QqMusicProvider::new(QqMusicClient::new(VerificationTransport {
            response: HttpResponse::new(
                200,
                serde_json::to_vec(&json!({
                    "code": 0,
                    "music.UserInfo.userInfoServer": {
                        "code": 0,
                        "data": {"info": {}}
                    }
                }))
                .expect("fixture JSON"),
            ),
        }));
        set_authenticated(&missing, "123456");
        assert_eq!(
            missing.account_summary().await,
            Err(AccountSummaryError::InvalidResponse)
        );
        assert!(missing.has_authenticated_credential());
    }

    #[tokio::test]
    async fn account_summary_rejection_clears_credential_and_late_result_cannot_cross_accounts() {
        let rejected = QqMusicProvider::new(QqMusicClient::new(VerificationTransport::new(1000)));
        set_authenticated(&rejected, "123456");
        assert_eq!(
            rejected.account_summary().await,
            Err(AccountSummaryError::CredentialRejected)
        );
        assert!(!rejected.has_authenticated_credential());

        let verification_started = Arc::new(Notify::new());
        let release_verification = Arc::new(Notify::new());
        let provider = QqMusicProvider::new(QqMusicClient::new(GatedVerificationTransport {
            verification_started: Arc::clone(&verification_started),
            release_verification: Arc::clone(&release_verification),
        }));
        set_authenticated(&provider, "123456");
        let request = provider.account_summary();
        let replacement = async {
            verification_started.notified().await;
            set_authenticated(&provider, "654321");
            release_verification.notify_one();
        };
        let (result, ()) = tokio::join!(request, replacement);

        assert_eq!(result, Err(AccountSummaryError::Replaced));
        assert!(provider.has_authenticated_credential());
    }

    #[tokio::test]
    async fn server_verification_promotes_only_success_and_clears_rejection() {
        let accepted = QqMusicProvider::new(QqMusicClient::new(VerificationTransport::new(0)));
        restore_candidate(&accepted);
        let accepted_attempt = accepted
            .reserve_restored_credential_verification()
            .expect("verification attempt");
        accepted
            .verify_restored_credential(accepted_attempt)
            .await
            .expect("accepted credential");
        assert!(accepted.has_authenticated_credential());
        assert!(accepted.restored_credential().is_none());

        let rejected = QqMusicProvider::new(QqMusicClient::new(VerificationTransport::new(1000)));
        restore_candidate(&rejected);
        let rejected_attempt = rejected
            .reserve_restored_credential_verification()
            .expect("verification attempt");
        assert_eq!(
            rejected.verify_restored_credential(rejected_attempt).await,
            Err(provider_api::AuthenticationError::Rejected),
        );
        assert!(!rejected.has_authenticated_credential());
        assert!(rejected.restored_credential().is_none());
    }

    #[tokio::test]
    async fn non_rejection_upstream_failure_retains_candidate_for_retry() {
        let provider = QqMusicProvider::new(QqMusicClient::new(VerificationTransport::new(50_006)));
        restore_candidate(&provider);
        let attempt_id = provider
            .reserve_restored_credential_verification()
            .expect("verification attempt");

        assert_eq!(
            provider.verify_restored_credential(attempt_id).await,
            Err(provider_api::AuthenticationError::ServiceUnavailable),
        );
        assert!(!provider.has_authenticated_credential());
        assert!(provider.restored_credential().is_some());
    }

    #[tokio::test]
    async fn new_qr_login_supersedes_late_server_verification() {
        let verification_started = Arc::new(Notify::new());
        let release_verification = Arc::new(Notify::new());
        let provider = QqMusicProvider::new(QqMusicClient::new(GatedVerificationTransport {
            verification_started: Arc::clone(&verification_started),
            release_verification: Arc::clone(&release_verification),
        }));
        restore_candidate(&provider);
        let attempt_id = provider
            .reserve_restored_credential_verification()
            .expect("verification attempt");

        let verification = provider.verify_restored_credential(attempt_id);
        let replacement = async {
            verification_started.notified().await;
            let session = provider
                .begin_qr_authentication(QrAuthenticationChannel::Wechat)
                .await
                .expect("replacement QR session");
            release_verification.notify_one();
            drop(session);
        };
        let (result, ()) = tokio::join!(verification, replacement);

        assert_eq!(result, Err(provider_api::AuthenticationError::Replaced));
        assert!(!provider.has_authenticated_credential());
        assert!(provider.restored_credential().is_none());
    }

    #[tokio::test]
    async fn sign_out_supersedes_late_server_verification() {
        let verification_started = Arc::new(Notify::new());
        let release_verification = Arc::new(Notify::new());
        let provider = QqMusicProvider::new(QqMusicClient::new(GatedVerificationTransport {
            verification_started: Arc::clone(&verification_started),
            release_verification: Arc::clone(&release_verification),
        }));
        restore_candidate(&provider);
        let attempt_id = provider
            .reserve_restored_credential_verification()
            .expect("verification attempt");

        let verification = provider.verify_restored_credential(attempt_id);
        let sign_out = async {
            verification_started.notified().await;
            provider.sign_out();
            release_verification.notify_one();
        };
        let (result, ()) = tokio::join!(verification, sign_out);

        assert_eq!(result, Err(provider_api::AuthenticationError::Replaced));
        assert!(!provider.has_authenticated_credential());
        assert!(provider.restored_credential().is_none());
    }

    #[test]
    fn stale_verification_attempt_cannot_cancel_its_replacement() {
        let provider = QqMusicProvider::new(QqMusicClient::new(()));
        restore_candidate(&provider);
        let first = provider
            .reserve_restored_credential_verification()
            .expect("first attempt");
        let second = provider
            .reserve_restored_credential_verification()
            .expect("replacement attempt");

        assert_ne!(first, second);
        assert!(!provider.cancel_restored_credential_verification(first));
        assert!(provider.cancel_restored_credential_verification(second));
        assert!(provider.restored_credential().is_some());
    }

    #[test]
    fn restore_keeps_unverified_and_expired_credentials_unauthenticated() {
        let provider = QqMusicProvider::new(QqMusicClient::new(()));
        assert_eq!(
            provider
                .restore_credential_from_secure_storage(None, 2_000)
                .expect("absent storage is valid"),
            QqMusicCredentialRestoreState::SignedOut,
        );

        let unverified = Credential::new("123456", "private-key", LoginType::WECHAT)
            .expect("fixture credential")
            .encode_for_secure_storage()
            .expect("encode fixture");
        assert_eq!(
            provider
                .restore_credential_from_secure_storage(Some(&unverified), 2_000)
                .expect("valid stored credential"),
            QqMusicCredentialRestoreState::VerificationRequired,
        );
        assert!(!provider.has_authenticated_credential());
        let (state, restored) = provider
            .restored_credential()
            .expect("unverified credential is retained in Rust");
        assert_eq!(state, QqMusicCredentialRestoreState::VerificationRequired);
        assert_eq!(restored.music_id(), "123456");
        assert!(
            provider
                .encode_authenticated_credential()
                .expect("unverified credential must not export")
                .is_none()
        );

        let expired = Credential::new("123456", "private-key", LoginType::WECHAT)
            .expect("fixture credential")
            .with_expiry(CredentialExpiry::new(1_000, 300).expect("fixture expiry"))
            .encode_for_secure_storage()
            .expect("encode fixture");
        assert_eq!(
            provider
                .restore_credential_from_secure_storage(Some(&expired), 2_000)
                .expect("valid expired credential"),
            QqMusicCredentialRestoreState::LocallyExpired,
        );
        assert!(!provider.has_authenticated_credential());
        let (state, _) = provider
            .restored_credential()
            .expect("expired credential is retained for a future decision");
        assert_eq!(state, QqMusicCredentialRestoreState::LocallyExpired);
    }

    #[tokio::test]
    async fn sign_out_clears_authenticated_restore_and_active_qr_state() {
        let authenticated =
            QqMusicProvider::new(QqMusicClient::new(SuccessfulAuthenticationTransport));
        set_authenticated(&authenticated, "123456");
        assert!(authenticated.has_authenticated_credential());
        authenticated.sign_out();
        assert!(!authenticated.has_authenticated_credential());
        assert!(authenticated.restored_credential().is_none());

        let restored = QqMusicProvider::new(QqMusicClient::new(()));
        restore_candidate(&restored);
        let verification = restored
            .reserve_restored_credential_verification()
            .expect("verification attempt");
        restored.sign_out();
        assert!(restored.restored_credential().is_none());
        assert!(!restored.cancel_restored_credential_verification(verification));

        let qr = QqMusicProvider::new(QqMusicClient::new(SuccessfulAuthenticationTransport));
        let session = qr
            .begin_qr_authentication(QrAuthenticationChannel::Wechat)
            .await
            .expect("active QR session");
        assert!(session.is_active());
        qr.sign_out();
        assert!(!session.is_active());
        assert!(!qr.has_authenticated_credential());
    }

    #[test]
    fn malformed_restore_does_not_replace_an_existing_restore_state() {
        let provider = QqMusicProvider::new(QqMusicClient::new(()));
        let unverified = Credential::new("123456", "private-key", LoginType::WECHAT)
            .expect("fixture credential")
            .encode_for_secure_storage()
            .expect("encode fixture");
        provider
            .restore_credential_from_secure_storage(Some(&unverified), 2_000)
            .expect("valid stored credential");

        assert!(
            provider
                .restore_credential_from_secure_storage(Some(b"not-json"), 2_000)
                .is_err()
        );
        assert!(matches!(
            &*super::credential_guard(&provider.credential),
            super::QqMusicCredentialState::PendingVerification(_)
        ));
    }

    #[tokio::test]
    async fn provider_maps_qr_flow_and_retains_credential_inside_the_provider() {
        let provider = QqMusicProvider::new(QqMusicClient::new(SuccessfulAuthenticationTransport));
        let mut session = provider
            .begin_qr_authentication(QrAuthenticationChannel::Wechat)
            .await
            .expect("provider QR session");
        let challenge = session.challenge();

        assert_eq!(challenge.image_format(), QrImageFormat::Jpeg);
        assert_eq!(challenge.image_bytes(), b"\xff\xd8\xffprivate-qr-fixture");
        assert!(!format!("{challenge:?}").contains("private"));
        assert!(!provider.has_authenticated_credential());

        let progress = session.advance().await.expect("provider auth mapping");

        assert_eq!(progress, QrAuthenticationProgress::Authenticated);
        assert!(provider.has_authenticated_credential());
        assert!(!session.is_active());
        assert!(!format!("{session:?}").contains("private"));
        let encoded = provider
            .encode_authenticated_credential()
            .expect("encode credential")
            .expect("authenticated credential");
        let decoded = Credential::decode_from_secure_storage(&encoded)
            .expect("provider emits a valid credential document");
        assert_eq!(decoded.music_id(), "123456");
    }

    #[tokio::test]
    async fn provider_maps_phone_flow_and_retains_credential_inside_the_provider() {
        let provider = QqMusicProvider::new(QqMusicClient::new(
            PhoneAuthenticationTransport::successful(),
        ));
        let session = provider
            .begin_phone_authentication("86".into(), "13000000000".into())
            .expect("provider phone session");

        assert!(session.is_active());
        assert_eq!(
            session.send_code().await.expect("phone-code mapping"),
            PhoneAuthenticationCodeState::Sent
        );
        assert!(!provider.has_authenticated_credential());

        session
            .authorize("123456".into())
            .await
            .expect("phone authorization mapping");

        assert!(!session.is_active());
        assert!(provider.has_authenticated_credential());
        assert!(!format!("{session:?}").contains("13000000000"));
        let encoded = provider
            .encode_authenticated_credential()
            .expect("encode credential")
            .expect("authenticated credential");
        let decoded = Credential::decode_from_secure_storage(&encoded)
            .expect("provider emits a valid credential document");
        assert_eq!(decoded.music_id(), "123456");
        assert_eq!(decoded.login_type(), LoginType::QQ);
    }
}
