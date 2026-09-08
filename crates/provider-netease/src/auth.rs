use super::{NeteaseProvider, playlist, provider_id, song};
use music_domain::{
    AccountSummary, PlaylistId, PlaylistOwnership, PlaylistPurpose, PlaylistSummary,
    PlaylistTracksPage, TrackSummary,
};
use netease_client::{Credential, Error, NeteaseClient, QrKey, QrPoll, Transport};
use provider_api::{
    AccountSummaryError, AccountSummaryProvider, AuthenticationError, DailyRecommendationError,
    DailyTracksProvider, OwnedPlaylistsProvider, PersonalizedTracksError,
    PersonalizedTracksProvider, QrAuthenticationChallenge, QrAuthenticationChannel,
    QrAuthenticationProgress, QrAuthenticationProvider, QrAuthenticationSession, QrImageFormat,
    UserLibraryError, UserPlaylistsProvider,
};
use std::{
    future::Future,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};
use tokio::sync::watch;

#[derive(Default)]
struct State {
    generation: u64,
    active: Option<(Credential, u64)>,
    pending: Option<Credential>,
    liked_playlist: Option<u64>,
}
pub(super) struct AuthOwner {
    state: Mutex<State>,
    changed: watch::Sender<u64>,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum Failure {
    Client(Error),
    Replaced,
}
impl From<Error> for Failure {
    fn from(e: Error) -> Self {
        Self::Client(e)
    }
}
impl AuthOwner {
    pub(super) fn new() -> Self {
        let (changed, _) = watch::channel(0);
        Self {
            state: Mutex::new(State::default()),
            changed,
        }
    }
    fn lock(&self) -> std::sync::MutexGuard<'_, State> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }
    fn bump(&self, state: &mut State) {
        state.generation = state
            .generation
            .checked_add(1)
            .expect("session generation exhausted");
        self.changed.send_replace(state.generation);
    }
    pub(super) fn generation(&self) -> u64 {
        self.lock().generation
    }
    fn current(&self, generation: u64) -> Result<(), Failure> {
        if self.generation() == generation {
            Ok(())
        } else {
            Err(Failure::Replaced)
        }
    }
    pub(super) fn snapshot(&self) -> Result<(u64, Credential, u64), Failure> {
        let s = self.lock();
        let (c, u) = s.active.clone().ok_or(Error::AuthenticationRequired)?;
        Ok((s.generation, c, u))
    }
    pub(super) async fn run<R>(
        &self,
        generation: u64,
        future: impl Future<Output = Result<R, Error>>,
    ) -> Result<R, Failure> {
        let mut changed = self.changed.subscribe();
        self.current(generation)?;
        let result = tokio::select! { biased; _=changed.changed()=>return Err(Failure::Replaced), result=future=>result };
        self.current(generation)?;
        if matches!(result, Err(Error::CredentialRejected)) {
            // only this exact generation may clear its rejected credential
            let mut s = self.lock();
            if s.generation != generation {
                return Err(Failure::Replaced);
            }
            s.active = None;
            s.liked_playlist = None;
            s.pending = None;
            self.bump(&mut s);
        }
        result.map_err(Failure::Client)
    }
    fn install(&self, generation: u64, credential: Credential, user: u64) -> Result<(), Failure> {
        let mut s = self.lock();
        if s.generation != generation {
            return Err(Failure::Replaced);
        }
        s.pending = None;
        s.active = Some((credential, user));
        s.liked_playlist = None;
        self.bump(&mut s);
        Ok(())
    }
}
fn account_error(f: Failure) -> AccountSummaryError {
    match f {
        Failure::Replaced => AccountSummaryError::Replaced,
        Failure::Client(e) => match e {
            Error::AuthenticationRequired => AccountSummaryError::AuthenticationRequired,
            Error::CredentialRejected => AccountSummaryError::CredentialRejected,
            Error::TemporaryNetworkFailure => AccountSummaryError::Network,
            Error::ResponseShapeMismatch | Error::ResponseBound | Error::InputBound => {
                AccountSummaryError::InvalidResponse
            }
            _ => AccountSummaryError::ServiceUnavailable,
        },
    }
}
fn auth_error(f: Failure) -> AuthenticationError {
    match f {
        Failure::Replaced => AuthenticationError::Replaced,
        Failure::Client(e) => match e {
            Error::TemporaryNetworkFailure => AuthenticationError::Network,
            Error::CredentialRejected => AuthenticationError::Rejected,
            Error::ResponseShapeMismatch | Error::ResponseBound | Error::InputBound => {
                AuthenticationError::InvalidResponse
            }
            _ => AuthenticationError::ServiceUnavailable,
        },
    }
}
pub(super) fn library_error(f: Failure) -> UserLibraryError {
    match account_error(f) {
        AccountSummaryError::AuthenticationRequired => UserLibraryError::AuthenticationRequired,
        AccountSummaryError::CredentialRejected => UserLibraryError::CredentialRejected,
        AccountSummaryError::Network => UserLibraryError::Network,
        AccountSummaryError::ServiceUnavailable => UserLibraryError::ServiceUnavailable,
        AccountSummaryError::InvalidResponse => UserLibraryError::InvalidResponse,
        AccountSummaryError::Replaced => UserLibraryError::Replaced,
    }
}
impl<T: Transport> NeteaseProvider<T> {
    /// Import a candidate only. No file, vault, browser or client credential is ever read here.
    /// # Errors
    /// Rejects foreign, malformed, oversized or future credential documents before state changes.
    pub fn import_credential(&self, bytes: &[u8]) -> Result<(), AccountSummaryError> {
        let credential = Credential::import(bytes).map_err(|e| account_error(e.into()))?;
        let mut s = self.auth.lock();
        self.auth.bump(&mut s);
        s.active = None;
        s.liked_playlist = None;
        s.pending = Some(credential);
        Ok(())
    }
    /// # Errors
    /// Returns serialization/invariant failures without exposing cookie content.
    pub fn export_credential(&self) -> Result<Option<Vec<u8>>, AccountSummaryError> {
        self.auth
            .lock()
            .active
            .as_ref()
            .map(|(c, _)| c.export().map_err(|e| account_error(e.into())))
            .transpose()
    }
    /// Explicit candidate verification; transient errors retain the candidate, rejection clears it.
    /// # Errors
    /// Authentication, response, network and generation failures remain distinct.
    pub async fn verify_restored_credential(&self) -> Result<(), AccountSummaryError> {
        let (g, c) = {
            let s = self.auth.lock();
            (
                s.generation,
                s.pending
                    .clone()
                    .ok_or(AccountSummaryError::AuthenticationRequired)?,
            )
        };
        let account = self
            .auth
            .run(g, self.client.account(&c))
            .await
            .map_err(account_error)?;
        self.auth.install(g, c, account.id).map_err(account_error)
    }
}
impl<T: Transport> AccountSummaryProvider for NeteaseProvider<T> {
    type Error = AccountSummaryError;
    async fn account_summary(&self) -> Result<AccountSummary, Self::Error> {
        let (g, c, user) = self.auth.snapshot().map_err(account_error)?;
        let a = self
            .auth
            .run(g, self.client.account(&c))
            .await
            .map_err(account_error)?;
        if a.id != user {
            return Err(AccountSummaryError::InvalidResponse);
        }
        AccountSummary::new(provider_id(), a.name)
            .map(|s| s.with_avatar_uri(a.avatar))
            .map_err(|_| AccountSummaryError::InvalidResponse)
    }
}
/// One opaque, generation-bound QR attempt. Drop/cancel never confirms an account.
pub struct NeteaseQrSession<T> {
    client: Arc<NeteaseClient<T>>,
    auth: Arc<AuthOwner>,
    generation: u64,
    key: QrKey,
    image: Vec<u8>,
    deadline: tokio::time::Instant,
    finished: bool,
    active: Arc<AtomicBool>,
    network_failures: u8,
}
impl<T: Transport> QrAuthenticationProvider for NeteaseProvider<T> {
    type Error = AuthenticationError;
    type Session = NeteaseQrSession<T>;
    async fn begin_qr_authentication(
        &self,
        channel: QrAuthenticationChannel,
    ) -> Result<Self::Session, Self::Error> {
        if channel != QrAuthenticationChannel::ProviderDefault {
            return Err(AuthenticationError::Rejected);
        }
        let deadline = tokio::time::Instant::now() + Duration::from_mins(3);
        let generation = {
            let mut s = self.auth.lock();
            self.auth.bump(&mut s);
            s.active = None;
            s.liked_playlist = None;
            s.pending = None;
            s.generation
        };
        let key =
            tokio::time::timeout_at(deadline, self.auth.run(generation, self.client.qr_key()))
                .await
                .map_err(|_| AuthenticationError::TimedOut)?
                .map_err(auth_error)?;
        let image = key.image_png().map_err(|e| auth_error(e.into()))?;
        Ok(NeteaseQrSession {
            client: self.client.clone(),
            auth: self.auth.clone(),
            generation,
            key,
            image,
            deadline,
            finished: false,
            active: Arc::new(AtomicBool::new(true)),
            network_failures: 0,
        })
    }
    fn has_authenticated_credential(&self) -> bool {
        self.auth.lock().active.is_some()
    }
    fn sign_out(&self) {
        let mut s = self.auth.lock();
        s.active = None;
        s.liked_playlist = None;
        s.pending = None;
        self.auth.bump(&mut s);
    }
}
/// Cancellation authority for one QR generation, usable while `advance` holds its mutable borrow.
pub struct NeteaseQrCancellation {
    auth: Arc<AuthOwner>,
    generation: u64,
    active: Arc<AtomicBool>,
}
impl NeteaseQrCancellation {
    #[must_use]
    pub fn cancel(&self) -> bool {
        if !self.active.swap(false, Ordering::SeqCst) {
            return false;
        }
        let mut s = self.auth.lock();
        if s.generation != self.generation {
            return false;
        }
        self.auth.bump(&mut s);
        true
    }
}
impl<T> NeteaseQrSession<T> {
    #[must_use]
    pub fn cancellation_handle(&self) -> NeteaseQrCancellation {
        NeteaseQrCancellation {
            auth: self.auth.clone(),
            generation: self.generation,
            active: self.active.clone(),
        }
    }
    fn finish(&mut self) {
        self.finished = true;
        self.active.store(false, Ordering::SeqCst);
    }
}

impl<T> Drop for NeteaseQrSession<T> {
    fn drop(&mut self) {
        self.active.store(false, Ordering::SeqCst);
        if !self.finished {
            let mut s = self.auth.lock();
            if s.generation == self.generation {
                self.auth.bump(&mut s);
            }
        }
    }
}
impl<T: Transport> QrAuthenticationSession for NeteaseQrSession<T> {
    type Error = AuthenticationError;
    fn challenge(&self) -> QrAuthenticationChallenge {
        QrAuthenticationChallenge::new(QrImageFormat::Png, self.image.clone())
    }
    fn is_active(&self) -> bool {
        !self.finished
            && self.active.load(Ordering::SeqCst)
            && self.auth.generation() == self.generation
            && tokio::time::Instant::now() < self.deadline
    }
    fn cancel(&self) -> bool {
        self.cancellation_handle().cancel()
    }
    async fn advance(&mut self) -> Result<QrAuthenticationProgress, Self::Error> {
        if self.finished {
            return Err(AuthenticationError::SessionFinished);
        }
        if tokio::time::Instant::now() >= self.deadline {
            self.finish();
            return Ok(QrAuthenticationProgress::TimedOut);
        }
        self.auth.current(self.generation).map_err(auth_error)?;
        let result = tokio::time::timeout_at(
            self.deadline,
            self.auth
                .run(self.generation, self.client.qr_poll(&self.key)),
        )
        .await;
        let poll = match result {
            Err(_) => {
                self.finish();
                return Ok(QrAuthenticationProgress::TimedOut);
            }
            Ok(Err(Failure::Client(Error::TemporaryNetworkFailure))) => {
                self.network_failures += 1;
                if self.network_failures >= 3 {
                    self.finish();
                    return Err(AuthenticationError::TooManyNetworkFailures);
                }
                return Err(AuthenticationError::Network);
            }
            Ok(Err(e)) => {
                self.finish();
                return Err(auth_error(e));
            }
            Ok(Ok(poll)) => poll,
        };
        self.network_failures = 0;
        match poll {
            QrPoll::Waiting => Ok(QrAuthenticationProgress::WaitingForScan),
            QrPoll::Scanned => Ok(QrAuthenticationProgress::ScannedAwaitingConfirmation),
            QrPoll::Expired => {
                self.finish();
                Ok(QrAuthenticationProgress::Expired)
            }
            QrPoll::Confirmed(c) => {
                self.finish();
                let a = tokio::time::timeout_at(
                    self.deadline,
                    self.auth.run(self.generation, self.client.account(&c)),
                )
                .await
                .map_err(|_| AuthenticationError::TimedOut)?
                .map_err(auth_error)?;
                self.auth
                    .install(self.generation, c, a.id)
                    .map_err(auth_error)?;
                Ok(QrAuthenticationProgress::Authenticated)
            }
        }
    }
}
impl<T: Transport> UserPlaylistsProvider for NeteaseProvider<T> {
    type Error = UserLibraryError;
    async fn user_playlists(&self) -> Result<Vec<PlaylistSummary>, Self::Error> {
        let (g, c, user) = self.auth.snapshot().map_err(library_error)?;
        let mut offset = 0;
        let mut rows = Vec::new();
        let mut seen = std::collections::HashSet::new();
        let mut liked_id = None;
        for _ in 0..10 {
            let page = self
                .auth
                .run(g, self.client.user_playlists(&c, user, offset, 100))
                .await
                .map_err(library_error)?;
            offset +=
                u32::try_from(page.items.len()).map_err(|_| UserLibraryError::InvalidResponse)?;
            for p in page.items {
                if !seen.insert(p.playlist.id) {
                    return Err(UserLibraryError::InvalidResponse);
                }
                let owned = p.creator.id == user;
                let liked = p.special_type == 5 && owned;
                let mut summary = playlist(p.playlist)
                    .map_err(|e| library_error(e.into()))?
                    .with_ownership(if owned {
                        PlaylistOwnership::Owned
                    } else {
                        PlaylistOwnership::Saved
                    });
                if liked {
                    let actual_id = summary
                        .id()
                        .opaque()
                        .parse::<u64>()
                        .map_err(|_| UserLibraryError::InvalidResponse)?;
                    if liked_id.replace(actual_id).is_some() {
                        return Err(UserLibraryError::InvalidResponse);
                    }
                    summary = PlaylistSummary::new(
                        PlaylistId::new(
                            provider_id(),
                            format!("liked:{user}:{}", summary.id().opaque()),
                        )
                        .map_err(|_| UserLibraryError::InvalidResponse)?,
                        summary.title(),
                    )
                    .map_err(|_| UserLibraryError::InvalidResponse)?
                    .with_artwork_uri(summary.artwork_uri().map(str::to_owned))
                    .with_track_count(summary.track_count())
                    .with_purpose(PlaylistPurpose::LikedSongs)
                    .with_ownership(PlaylistOwnership::Owned);
                }
                rows.push(summary);
            }
            if !page.more {
                let mut state = self.auth.lock();
                if state.generation != g {
                    return Err(UserLibraryError::Replaced);
                }
                state.liked_playlist = liked_id;
                return Ok(rows);
            }
        }
        Err(UserLibraryError::InvalidResponse)
    }
}
impl<T: Transport> OwnedPlaylistsProvider for NeteaseProvider<T> {
    type Error = UserLibraryError;
    async fn owned_playlists(&self) -> Result<Vec<PlaylistSummary>, Self::Error> {
        Ok(self
            .user_playlists()
            .await?
            .into_iter()
            .filter(|p| p.ownership() == PlaylistOwnership::Owned)
            .collect())
    }
}
impl<T: Transport> NeteaseProvider<T> {
    pub(super) async fn playlist_source(
        &self,
        id: u64,
        offset: u32,
        size: u32,
    ) -> Result<netease_client::PlaylistPage, Failure> {
        let (g, c) = {
            let state = self.auth.lock();
            (
                state.generation,
                state.active.as_ref().map(|(c, _)| c.clone()),
            )
        };
        let Some(c) = c else {
            return self
                .auth
                .run(g, self.client.playlist_page(id, offset, size))
                .await;
        };
        let selection = self
            .auth
            .run(
                g,
                self.client
                    .authenticated_playlist_selection(&c, id, offset, size),
            )
            .await?;
        let songs = if selection.ids().is_empty() {
            vec![]
        } else {
            self.auth
                .run(g, self.client.authenticated_songs(&c, selection.ids()))
                .await?
        };
        self.auth.current(g)?;
        selection.with_songs(songs).map_err(Failure::Client)
    }
    pub(super) async fn liked_page(
        &self,
        owner: u64,
        expected_playlist: u64,
        offset: u32,
        size: u32,
    ) -> Result<PlaylistTracksPage, Failure> {
        if size == 0 || size > 100 || offset > 1000 {
            return Err(Error::InputBound.into());
        }
        let (g, c, user) = self.auth.snapshot()?;
        if owner != user {
            return Err(Error::InputBound.into());
        }
        {
            let state = self.auth.lock();
            if state.generation != g {
                return Err(Failure::Replaced);
            }
            if state.liked_playlist != Some(expected_playlist) {
                return Err(Error::InputBound.into());
            }
        }
        let ids = self.auth.run(g, self.client.liked_ids(&c, user)).await?;
        let total = u32::try_from(ids.len()).map_err(|_| Error::ResponseBound)?;
        let selected: Vec<_> = ids
            .into_iter()
            .skip(offset as usize)
            .take(size as usize)
            .collect();
        let next = offset + u32::try_from(selected.len()).map_err(|_| Error::ResponseBound)?;
        let songs = if selected.is_empty() {
            vec![]
        } else {
            self.auth
                .run(g, self.client.authenticated_songs(&c, &selected))
                .await?
        };
        let mut lookup: std::collections::HashMap<_, _> =
            songs.into_iter().map(|s| (s.id, s)).collect();
        let tracks = selected
            .iter()
            .filter_map(|id| lookup.remove(id))
            .map(song)
            .collect::<Result<Vec<_>, _>>()?;
        let omitted =
            next - offset - u32::try_from(tracks.len()).map_err(|_| Error::ResponseBound)?;
        Ok(PlaylistTracksPage::new_with_cursor(
            offset,
            next,
            total,
            next < total,
            omitted,
            tracks,
        ))
    }
}
impl<T: Transport> PersonalizedTracksProvider for NeteaseProvider<T> {
    type Error = PersonalizedTracksError;
    async fn personalized_tracks(&self) -> Result<Vec<TrackSummary>, Self::Error> {
        let map = |e| match library_error(e) {
            UserLibraryError::AuthenticationRequired => {
                PersonalizedTracksError::AuthenticationRequired
            }
            UserLibraryError::CredentialRejected => PersonalizedTracksError::CredentialRejected,
            UserLibraryError::Network => PersonalizedTracksError::Network,
            UserLibraryError::ServiceUnavailable => PersonalizedTracksError::ServiceUnavailable,
            UserLibraryError::InvalidResponse => PersonalizedTracksError::InvalidResponse,
            UserLibraryError::Replaced => PersonalizedTracksError::Replaced,
        };
        let (g, c, _) = self.auth.snapshot().map_err(map)?;
        self.auth
            .run(g, self.client.personal_fm(&c))
            .await
            .map_err(map)?
            .into_iter()
            .map(song)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| map(e.into()))
    }
}
impl<T: Transport> DailyTracksProvider for NeteaseProvider<T> {
    type Error = DailyRecommendationError;
    async fn daily_tracks(&self) -> Result<Vec<TrackSummary>, Self::Error> {
        let map = |e| match library_error(e) {
            UserLibraryError::AuthenticationRequired => {
                DailyRecommendationError::AuthenticationRequired
            }
            UserLibraryError::CredentialRejected => DailyRecommendationError::CredentialRejected,
            UserLibraryError::Network => DailyRecommendationError::Network,
            UserLibraryError::ServiceUnavailable => DailyRecommendationError::ServiceUnavailable,
            UserLibraryError::InvalidResponse => DailyRecommendationError::InvalidResponse,
            UserLibraryError::Replaced => DailyRecommendationError::Replaced,
        };
        let (g, c, _) = self.auth.snapshot().map_err(map)?;
        self.auth
            .run(g, self.client.daily_tracks(&c))
            .await
            .map_err(map)?
            .into_iter()
            .map(song)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| map(e.into()))
    }
}

impl<T: Transport> NeteaseProvider<T> {
    pub(super) async fn resolve_source(&self, id: u64) -> Result<netease_client::Media, Failure> {
        let (g, c) = {
            let s = self.auth.lock();
            (s.generation, s.active.as_ref().map(|(c, _)| c.clone()))
        };
        match c {
            Some(c) => {
                self.auth
                    .run(g, self.client.authenticated_media(&c, id))
                    .await
            }
            None => self.auth.run(g, self.client.media(id)).await,
        }
    }
}

impl<T: Transport> provider_api::PersonalizedPlaylistsProvider for NeteaseProvider<T> {
    type Error = provider_api::PersonalizedPlaylistsError;
    async fn personalized_playlists(&self) -> Result<Vec<PlaylistSummary>, Self::Error> {
        use provider_api::PersonalizedPlaylistsError as E;
        let map = |e| match library_error(e) {
            UserLibraryError::AuthenticationRequired => E::AuthenticationRequired,
            UserLibraryError::CredentialRejected => E::CredentialRejected,
            UserLibraryError::Network => E::Network,
            UserLibraryError::ServiceUnavailable => E::ServiceUnavailable,
            UserLibraryError::InvalidResponse => E::InvalidResponse,
            UserLibraryError::Replaced => E::Replaced,
        };
        let (g, c, _) = self.auth.snapshot().map_err(map)?;
        self.auth
            .run(g, self.client.personalized_playlists(&c))
            .await
            .map_err(map)?
            .into_iter()
            .map(playlist)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| map(e.into()))
    }
}
macro_rules! favorite_page {
    ($contract:ident,$method:ident,$page:ident,$map:ident) => {
        impl<T: Transport> provider_api::$contract for NeteaseProvider<T> {
            type Error = UserLibraryError;
            async fn $method(
                &self,
                offset: u32,
                size: u32,
            ) -> Result<music_domain::$page, Self::Error> {
                let (g, c, _) = self.auth.snapshot().map_err(library_error)?;
                let p = self
                    .auth
                    .run(g, self.client.$method(&c, offset, size))
                    .await
                    .map_err(library_error)?;
                Ok(music_domain::$page::new(
                    p.offset,
                    p.total,
                    p.more,
                    p.items
                        .into_iter()
                        .map(super::$map)
                        .collect::<Result<Vec<_>, _>>()
                        .map_err(|e| library_error(e.into()))?,
                ))
            }
        }
    };
}
favorite_page!(
    FavoriteAlbumsProvider,
    favorite_albums,
    FavoriteAlbumsPage,
    album
);
favorite_page!(
    FavoriteArtistsProvider,
    favorite_artists,
    FavoriteArtistsPage,
    artist
);
