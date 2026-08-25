//! QQ Music provider mapping layer.

use std::collections::HashSet;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};

use music_domain::{
    PlaylistId, PlaylistSummary, PlaylistTracksPage, ProviderId, TrackId, TrackSummary,
};
use provider_api::{
    AuthenticationError, MusicProvider, OwnedPlaylistsProvider, PlaylistDetailsProvider,
    ProviderCapability, ProviderDescriptor, QrAuthenticationChallenge, QrAuthenticationProgress,
    QrAuthenticationProvider, QrAuthenticationSession, QrImageFormat, UserLibraryError,
    UserPlaylistsProvider,
};
use qqmusic_client::{
    Credential, CredentialPersistenceError, CredentialRestorePlan, CredentialVerificationError,
    HttpTransport, QqMusicClient, QqMusicFavoritePlaylist, QqMusicFavoritePlaylistsError,
    QqMusicOwnedPlaylist, QqMusicOwnedPlaylistsError, QqMusicPlaylistDetailError,
    QqMusicTrackSummary, QrImageMediaType, WechatCredentialExchangeError, WechatQrError,
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
}

impl<T> QqMusicProvider<T> {
    #[must_use]
    pub fn new(client: QqMusicClient<T>) -> Self {
        Self {
            login: WechatQrLoginCoordinator::new(client),
            credential: Arc::new(Mutex::new(QqMusicCredentialState::SignedOut)),
            next_restore_verification: AtomicU32::new(1),
            active_restore_verification: Mutex::new(None),
        }
    }

    #[must_use]
    pub fn client(&self) -> &QqMusicClient<T> {
        self.login.client()
    }

    #[must_use]
    pub fn has_authenticated_credential(&self) -> bool {
        matches!(
            *credential_guard(&self.credential),
            QqMusicCredentialState::Authenticated(_)
        )
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
        self.login.cancel_active()
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
            Ok(()) => {
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
                ProviderCapability::Authentication,
                ProviderCapability::UserLibrary,
            ],
        }
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
            .collect::<Result<Vec<_>, _>>()?;
        Ok(PlaylistTracksPage::new(
            page.offset(),
            page.total(),
            page.has_more(),
            tracks,
        ))
    }
}

impl<T> QrAuthenticationProvider for QqMusicProvider<T>
where
    T: HttpTransport + 'static,
{
    type Error = AuthenticationError;
    type Session = QqMusicQrAuthenticationSession<T>;

    async fn begin_qr_authentication(&self) -> Result<Self::Session, Self::Error> {
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
        let session = self.login.begin().await.map_err(map_login_error)?;
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
        let image = self.session.qr().image();
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
        })
        .map_err(|_| UserLibraryError::InvalidResponse)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum QqMusicPlaylistRoute {
    Ordinary { playlist_id: u64 },
    LikedSongs,
}

fn parse_playlist_route(
    playlist_id: &PlaylistId,
) -> Result<QqMusicPlaylistRoute, UserLibraryError> {
    if playlist_id.provider() != &qq_music_provider_id() {
        return Err(UserLibraryError::InvalidResponse);
    }
    let mut parts = playlist_id.opaque().split(':');
    match (parts.next(), parts.next(), parts.next(), parts.next()) {
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

fn parse_nonzero_u64(value: &str) -> Result<u64, UserLibraryError> {
    value
        .parse::<u64>()
        .ok()
        .filter(|value| *value != 0)
        .ok_or(UserLibraryError::InvalidResponse)
}

fn map_track_summary(track: &QqMusicTrackSummary) -> Result<TrackSummary, UserLibraryError> {
    let vkey_song_type = track
        .vkey_song_type()
        .map_or_else(|| "-".into(), |value| value.to_string());
    let id = TrackId::new(
        qq_music_provider_id(),
        format!(
            "track:{}:{}:{}:{}",
            track.track_id(),
            track.song_type(),
            vkey_song_type,
            track.media_mid()
        ),
    )
    .map_err(|_| UserLibraryError::InvalidResponse)?;
    let artists = track
        .artists()
        .iter()
        .map(|artist| artist.name().to_owned())
        .collect();
    let album_title = track
        .album()
        .and_then(qqmusic_client::QqMusicAlbumSummary::name)
        .map(str::to_owned);
    let artwork_uri = track
        .album()
        .and_then(qqmusic_client::QqMusicAlbumSummary::media_mid)
        .and_then(album_artwork_uri);
    TrackSummary::new(id, track.title(), artists)
        .map(|summary| {
            summary
                .with_subtitle(track.subtitle().map(str::to_owned))
                .with_album_title(album_title)
                .with_artwork_uri(artwork_uri)
                .with_duration_seconds(Some(track.duration_seconds()))
        })
        .map_err(|_| UserLibraryError::InvalidResponse)
}

fn album_artwork_uri(media_mid: &str) -> Option<String> {
    let safe = !media_mid.is_empty()
        && media_mid
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'));
    safe.then(|| format!("https://y.gtimg.cn/music/photo_new/T002R300x300M000{media_mid}.jpg"))
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

fn map_login_error<E>(error: WechatQrLoginError<E>) -> AuthenticationError {
    match error {
        WechatQrLoginError::Protocol(error) => map_qr_error(&error),
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

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::convert::Infallible;
    use std::sync::{Arc, Mutex};

    use super::{QqMusicCredentialRestoreState, QqMusicProvider};
    use music_domain::{PlaylistId, ProviderId};
    use provider_api::{
        MusicProvider, OwnedPlaylistsProvider, PlaylistDetailsProvider, ProviderCapability,
        QrAuthenticationProgress, QrAuthenticationProvider, QrAuthenticationSession, QrImageFormat,
        UserLibraryError, UserPlaylistsProvider,
    };
    use qqmusic_client::{
        Credential, CredentialExpiry, CredentialSessionSecrets, HttpMethod, HttpRequest,
        HttpResponse, HttpTransport, LoginType, QqMusicClient,
    };
    use serde_json::{Value, json};
    use tokio::sync::Notify;

    struct SuccessfulAuthenticationTransport;

    struct VerificationTransport {
        response: HttpResponse,
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

    impl VerificationTransport {
        fn new(code: i64) -> Self {
            Self {
                response: HttpResponse::new(
                    200,
                    serde_json::to_vec(&json!({
                        "code": 0,
                        "music.UserInfo.userInfoServer": {
                            "code": code,
                            "data": {"info": {}}
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
    struct GatedPlaylistDetailTransport {
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

    #[test]
    fn descriptor_claims_only_implemented_capabilities() {
        let provider = QqMusicProvider::new(QqMusicClient::new(()));
        let descriptor = provider.descriptor();

        assert_eq!(descriptor.id.as_str(), "qq-music");
        assert_eq!(descriptor.display_name, "QQ Music");
        assert_eq!(
            descriptor.capabilities,
            [
                ProviderCapability::Authentication,
                ProviderCapability::UserLibrary,
            ]
        );
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

    fn playlist_track_fixture() -> Value {
        json!([{
            "id": 41001,
            "mid": "fixture-track-mid",
            "name": "Fallback fixture title",
            "title": "Synthetic track",
            "subtitle": "Synthetic subtitle",
            "type": 0,
            "songtype": 1,
            "interval": 245,
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
        assert_eq!(playlists[2].track_count(), Some(9));
        assert_eq!(playlists[3].id().opaque(), "favorite:8002");

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
    async fn routes_playlist_identities_and_maps_provider_independent_tracks() {
        let provider = QqMusicProvider::new(QqMusicClient::new(PlaylistDetailTransport::new([
            playlist_detail_page_json(&playlist_track_fixture(), 51, true),
            playlist_detail_page_json(&playlist_track_fixture(), 1, false),
            playlist_detail_page_json(&playlist_track_fixture(), 1, false),
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
        assert_eq!(track.id().opaque(), "track:41001:0:1:fixture-track-mid");
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

        provider
            .playlist_tracks_page(qq_playlist_id("owned:7002:202"), 0, 100)
            .await
            .expect("ordinary owned playlist detail");
        provider
            .playlist_tracks_page(qq_playlist_id("owned:7001:201"), 0, 100)
            .await
            .expect("liked-songs detail");

        let requests = provider.client().transport().requests();
        assert_eq!(requests.len(), 3);
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
                .begin_qr_authentication()
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
            .begin_qr_authentication()
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
}
