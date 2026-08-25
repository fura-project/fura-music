use std::fmt;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use tokio::sync::watch;

use crate::{
    Credential, HttpTransport, QqMusicClient, WechatAuthorizationCode,
    WechatCredentialExchangeError, WechatQrError, WechatQrPollResult, WechatQrSession,
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum AttemptState {
    Idle,
    Active(u64),
    CoordinatorClosed,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Interruption {
    Cancelled,
    Superseded,
    CoordinatorClosed,
}

pub enum WechatQrLoginError<E> {
    Protocol(WechatQrError<E>),
    CredentialExchange(WechatCredentialExchangeError<E>),
    Cancelled,
    Superseded,
    CoordinatorClosed,
    SessionFinished,
}

impl<E> fmt::Debug for WechatQrLoginError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Protocol(error) => formatter.debug_tuple("Protocol").field(error).finish(),
            Self::CredentialExchange(error) => formatter
                .debug_tuple("CredentialExchange")
                .field(error)
                .finish(),
            Self::Cancelled => formatter.write_str("Cancelled"),
            Self::Superseded => formatter.write_str("Superseded"),
            Self::CoordinatorClosed => formatter.write_str("CoordinatorClosed"),
            Self::SessionFinished => formatter.write_str("SessionFinished"),
        }
    }
}

impl<E> fmt::Display for WechatQrLoginError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Protocol(error) => error.fmt(formatter),
            Self::CredentialExchange(error) => error.fmt(formatter),
            Self::Cancelled => formatter.write_str("WeChat QR login was cancelled"),
            Self::Superseded => {
                formatter.write_str("WeChat QR login was replaced by a newer session")
            }
            Self::CoordinatorClosed => {
                formatter.write_str("WeChat QR login coordinator was closed")
            }
            Self::SessionFinished => formatter.write_str("WeChat QR login session has finished"),
        }
    }
}

impl<E> std::error::Error for WechatQrLoginError<E>
where
    E: std::error::Error + 'static,
{
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Protocol(error) => Some(error),
            Self::CredentialExchange(error) => Some(error),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum WechatQrLoginProgress {
    WaitingForScan,
    ScannedAwaitingConfirmation,
    Authenticated(Box<Credential>),
    Expired,
    Refused,
}

impl<E> From<Interruption> for WechatQrLoginError<E> {
    fn from(value: Interruption) -> Self {
        match value {
            Interruption::Cancelled => Self::Cancelled,
            Interruption::Superseded => Self::Superseded,
            Interruption::CoordinatorClosed => Self::CoordinatorClosed,
        }
    }
}

/// Owns replacement and cancellation for one logical `WeChat` QR login flow.
///
/// Starting a new session supersedes the previous generation. Dropping this
/// coordinator closes all sessions created by it.
pub struct WechatQrLoginCoordinator<T> {
    client: Arc<QqMusicClient<T>>,
    next_generation: AtomicU64,
    state: watch::Sender<AttemptState>,
}

impl<T> fmt::Debug for WechatQrLoginCoordinator<T> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("WechatQrLoginCoordinator")
            .field("state", &*self.state.borrow())
            .finish_non_exhaustive()
    }
}

impl<T> WechatQrLoginCoordinator<T> {
    #[must_use]
    pub fn new(client: QqMusicClient<T>) -> Self {
        let (state, _receiver) = watch::channel(AttemptState::Idle);
        Self {
            client: Arc::new(client),
            next_generation: AtomicU64::new(1),
            state,
        }
    }

    #[must_use]
    pub fn has_active_session(&self) -> bool {
        matches!(*self.state.borrow(), AttemptState::Active(_))
    }

    /// Cancels the current generation. Returns whether one was active.
    pub fn cancel_active(&self) -> bool {
        self.state.send_if_modified(|state| {
            if matches!(state, AttemptState::Active(_)) {
                *state = AttemptState::Idle;
                true
            } else {
                false
            }
        })
    }

    fn allocate_generation(&self) -> u64 {
        self.next_generation
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |current| {
                Some(if current == u64::MAX { 1 } else { current + 1 })
            })
            .expect("generation update closure always returns Some")
    }
}

impl<T> WechatQrLoginCoordinator<T>
where
    T: HttpTransport + 'static,
{
    /// Creates a new QR session and atomically supersedes any older attempt.
    ///
    /// # Errors
    ///
    /// Returns a protocol error or a lifecycle error when the attempt is
    /// cancelled, replaced, or closed while QR creation is in flight.
    pub async fn begin(&self) -> Result<WechatQrLoginSession<T>, WechatQrLoginError<T::Error>> {
        let generation = self.allocate_generation();
        self.state.send_replace(AttemptState::Active(generation));
        let mut state = self.state.subscribe();

        let qr_result = tokio::select! {
            biased;
            interruption = wait_for_interruption(&mut state, generation) => {
                return Err(interruption.into());
            }
            result = self.client.create_wechat_qr() => {
                result
            }
        };
        let qr = match qr_result {
            Ok(qr) => qr,
            Err(error) => {
                clear_if_current(&self.state, generation);
                return Err(WechatQrLoginError::Protocol(error));
            }
        };
        ensure_current(&state, generation)?;

        Ok(WechatQrLoginSession {
            client: Arc::clone(&self.client),
            qr,
            generation,
            state,
            sender: self.state.clone(),
            pending_authorization: None,
            finished: false,
        })
    }
}

impl<T> Drop for WechatQrLoginCoordinator<T> {
    fn drop(&mut self) {
        self.state.send_replace(AttemptState::CoordinatorClosed);
    }
}

/// A single cancellable QR generation returned by [`WechatQrLoginCoordinator`].
pub struct WechatQrLoginSession<T> {
    client: Arc<QqMusicClient<T>>,
    qr: WechatQrSession,
    generation: u64,
    state: watch::Receiver<AttemptState>,
    sender: watch::Sender<AttemptState>,
    pending_authorization: Option<WechatAuthorizationCode>,
    finished: bool,
}

impl<T> fmt::Debug for WechatQrLoginSession<T> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("WechatQrLoginSession")
            .field("qr", &self.qr)
            .field("active", &self.is_active())
            .field(
                "authorization_pending",
                &self.pending_authorization.is_some(),
            )
            .field("finished", &self.finished)
            .finish_non_exhaustive()
    }
}

impl<T> WechatQrLoginSession<T> {
    #[must_use]
    pub const fn qr(&self) -> &WechatQrSession {
        &self.qr
    }

    #[must_use]
    pub fn is_active(&self) -> bool {
        matches!(
            *self.state.borrow(),
            AttemptState::Active(current) if current == self.generation
        )
    }

    /// Cancels this generation if it is still current.
    #[must_use]
    pub fn cancel(&self) -> bool {
        clear_if_current(&self.sender, self.generation)
    }
}

impl<T> WechatQrLoginSession<T>
where
    T: HttpTransport + 'static,
{
    /// Advances one protocol step while racing network work against lifecycle
    /// cancellation or replacement.
    ///
    /// A 405 authorization code stays inside this session and is exchanged
    /// under the same generation gate. Dropping the losing future aborts the
    /// in-flight HTTP request. Terminal states finish this generation; waiting
    /// states remain active for an explicit subsequent call.
    ///
    /// # Errors
    ///
    /// Returns poll/exchange failures separately from cancellation,
    /// replacement, coordinator disposal, and calls made after a terminal
    /// result.
    pub async fn advance(&mut self) -> Result<WechatQrLoginProgress, WechatQrLoginError<T::Error>> {
        if self.finished {
            return Err(WechatQrLoginError::SessionFinished);
        }
        ensure_current(&self.state, self.generation)?;

        if self.pending_authorization.is_some() {
            return self.exchange_pending_authorization().await;
        }

        let result = tokio::select! {
            biased;
            interruption = wait_for_interruption(&mut self.state, self.generation) => {
                return Err(interruption.into());
            }
            result = self.client.poll_wechat_qr(&self.qr) => {
                result.map_err(WechatQrLoginError::Protocol)?
            }
        };
        ensure_current(&self.state, self.generation)?;

        match result {
            WechatQrPollResult::WaitingForScan => Ok(WechatQrLoginProgress::WaitingForScan),
            WechatQrPollResult::ScannedAwaitingConfirmation => {
                Ok(WechatQrLoginProgress::ScannedAwaitingConfirmation)
            }
            WechatQrPollResult::Authorized(code) => {
                self.pending_authorization = Some(code);
                self.exchange_pending_authorization().await
            }
            WechatQrPollResult::Expired => {
                self.finish();
                Ok(WechatQrLoginProgress::Expired)
            }
            WechatQrPollResult::Refused => {
                self.finish();
                Ok(WechatQrLoginProgress::Refused)
            }
        }
    }

    async fn exchange_pending_authorization(
        &mut self,
    ) -> Result<WechatQrLoginProgress, WechatQrLoginError<T::Error>> {
        let code = self
            .pending_authorization
            .as_ref()
            .expect("called only while authorization is pending");
        let credential = tokio::select! {
            biased;
            interruption = wait_for_interruption(&mut self.state, self.generation) => {
                return Err(interruption.into());
            }
            result = self.client.exchange_wechat_code(code) => {
                result.map_err(WechatQrLoginError::CredentialExchange)?
            }
        };
        ensure_current(&self.state, self.generation)?;
        self.pending_authorization = None;
        self.finish();
        Ok(WechatQrLoginProgress::Authenticated(Box::new(credential)))
    }

    fn finish(&mut self) {
        self.finished = true;
        clear_if_current(&self.sender, self.generation);
    }
}

impl<T> Drop for WechatQrLoginSession<T> {
    fn drop(&mut self) {
        clear_if_current(&self.sender, self.generation);
    }
}

fn clear_if_current(sender: &watch::Sender<AttemptState>, generation: u64) -> bool {
    sender.send_if_modified(|state| {
        if *state == AttemptState::Active(generation) {
            *state = AttemptState::Idle;
            true
        } else {
            false
        }
    })
}

fn ensure_current<E>(
    state: &watch::Receiver<AttemptState>,
    generation: u64,
) -> Result<(), WechatQrLoginError<E>> {
    match interruption_for(*state.borrow(), generation) {
        Some(interruption) => Err(interruption.into()),
        None => Ok(()),
    }
}

async fn wait_for_interruption(
    state: &mut watch::Receiver<AttemptState>,
    generation: u64,
) -> Interruption {
    loop {
        if let Some(interruption) = interruption_for(*state.borrow_and_update(), generation) {
            return interruption;
        }
        if state.changed().await.is_err() {
            return Interruption::CoordinatorClosed;
        }
    }
}

fn interruption_for(state: AttemptState, generation: u64) -> Option<Interruption> {
    match state {
        AttemptState::Active(current) if current == generation => None,
        AttemptState::Active(_) => Some(Interruption::Superseded),
        AttemptState::Idle => Some(Interruption::Cancelled),
        AttemptState::CoordinatorClosed => Some(Interruption::CoordinatorClosed),
    }
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

    use tokio::sync::Semaphore;

    use super::{WechatQrLoginCoordinator, WechatQrLoginError};
    use crate::{
        HttpMethod, HttpRequest, HttpResponse, HttpTransport, QqMusicClient,
        WechatCredentialExchangeError, WechatQrLoginProgress,
    };

    #[derive(Clone)]
    struct LifecycleTransport {
        status: u16,
        started: Arc<Semaphore>,
        release: Arc<Semaphore>,
        cancelled: Arc<AtomicBool>,
    }

    impl LifecycleTransport {
        fn blocked(poll_status: u16) -> Self {
            Self {
                status: poll_status,
                started: Arc::new(Semaphore::new(0)),
                release: Arc::new(Semaphore::new(0)),
                cancelled: Arc::new(AtomicBool::new(false)),
            }
        }

        fn ready(poll_status: u16) -> Self {
            let transport = Self::blocked(poll_status);
            transport.release.add_permits(1);
            transport
        }

        async fn wait_until_poll_started(&self) {
            self.started
                .acquire()
                .await
                .expect("poll-start semaphore remains open")
                .forget();
        }

        fn was_poll_cancelled(&self) -> bool {
            self.cancelled.load(Ordering::SeqCst)
        }
    }

    struct CancellationMarker {
        cancelled: Arc<AtomicBool>,
        completed: bool,
    }

    impl Drop for CancellationMarker {
        fn drop(&mut self) {
            if !self.completed {
                self.cancelled.store(true, Ordering::SeqCst);
            }
        }
    }

    impl HttpTransport for LifecycleTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            if request.url() == "https://open.weixin.qq.com/connect/qrconnect" {
                return Ok(HttpResponse::new(
                    200,
                    br#"<a href="?uuid=lifecycle-fixture">login</a>"#.to_vec(),
                ));
            }
            if request
                .url()
                .starts_with("https://open.weixin.qq.com/connect/qrcode/")
            {
                return Ok(HttpResponse::new(200, b"\xff\xd8\xfffixture-jpeg".to_vec()));
            }

            assert_eq!(
                request.url(),
                "https://lp.open.weixin.qq.com/connect/l/qrconnect"
            );
            self.started.add_permits(1);
            let mut marker = CancellationMarker {
                cancelled: Arc::clone(&self.cancelled),
                completed: false,
            };
            self.release
                .acquire()
                .await
                .expect("poll-release semaphore remains open")
                .forget();
            marker.completed = true;
            let code = if self.status == 405 {
                "late-secret-code"
            } else {
                ""
            };
            Ok(HttpResponse::new(
                200,
                format!("window.wx_errcode={};window.wx_code='{code}';", self.status).into_bytes(),
            ))
        }
    }

    struct InvalidQrTransport;

    impl HttpTransport for InvalidQrTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            let body = if request.url() == "https://open.weixin.qq.com/connect/qrconnect" {
                br#"<a href="?uuid=lifecycle-fixture">login</a>"#.to_vec()
            } else {
                b"not-an-image".to_vec()
            };
            Ok(HttpResponse::new(200, body))
        }
    }

    #[derive(Clone)]
    struct FirstConnectBlocksTransport {
        first_connect: Arc<AtomicBool>,
        started: Arc<Semaphore>,
        release: Arc<Semaphore>,
        cancelled: Arc<AtomicBool>,
    }

    impl FirstConnectBlocksTransport {
        fn new() -> Self {
            Self {
                first_connect: Arc::new(AtomicBool::new(true)),
                started: Arc::new(Semaphore::new(0)),
                release: Arc::new(Semaphore::new(0)),
                cancelled: Arc::new(AtomicBool::new(false)),
            }
        }

        async fn wait_until_first_connect_started(&self) {
            self.started
                .acquire()
                .await
                .expect("connect-start semaphore remains open")
                .forget();
        }
    }

    impl HttpTransport for FirstConnectBlocksTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            if request.url() == "https://open.weixin.qq.com/connect/qrconnect" {
                if self.first_connect.swap(false, Ordering::SeqCst) {
                    self.started.add_permits(1);
                    let mut marker = CancellationMarker {
                        cancelled: Arc::clone(&self.cancelled),
                        completed: false,
                    };
                    self.release
                        .acquire()
                        .await
                        .expect("connect-release semaphore remains open")
                        .forget();
                    marker.completed = true;
                }
                return Ok(HttpResponse::new(
                    200,
                    br#"<a href="?uuid=lifecycle-fixture">login</a>"#.to_vec(),
                ));
            }

            Ok(HttpResponse::new(200, b"\xff\xd8\xfffixture-jpeg".to_vec()))
        }
    }

    #[derive(Clone)]
    struct ExchangeLifecycleTransport {
        block_exchange: bool,
        fail_first: bool,
        started: Arc<Semaphore>,
        release: Arc<Semaphore>,
        cancelled: Arc<AtomicBool>,
        exchange_calls: Arc<AtomicUsize>,
        poll_calls: Arc<AtomicUsize>,
    }

    impl ExchangeLifecycleTransport {
        fn ready(fail_first: bool) -> Self {
            Self {
                block_exchange: false,
                fail_first,
                started: Arc::new(Semaphore::new(0)),
                release: Arc::new(Semaphore::new(0)),
                cancelled: Arc::new(AtomicBool::new(false)),
                exchange_calls: Arc::new(AtomicUsize::new(0)),
                poll_calls: Arc::new(AtomicUsize::new(0)),
            }
        }

        fn blocked() -> Self {
            Self {
                block_exchange: true,
                ..Self::ready(false)
            }
        }

        async fn wait_until_exchange_started(&self) {
            self.started
                .acquire()
                .await
                .expect("exchange-start semaphore remains open")
                .forget();
        }

        fn success_response() -> HttpResponse {
            HttpResponse::new(
                200,
                serde_json::to_vec(&serde_json::json!({
                    "code": 0,
                    "music.login.LoginServer.Login": {
                        "code": 0,
                        "data": {
                            "str_musicid": "456",
                            "musickey": "late-secret-music-key",
                            "refresh_token": "late-secret-refresh-token"
                        }
                    }
                }))
                .expect("exchange fixture JSON"),
            )
        }
    }

    impl HttpTransport for ExchangeLifecycleTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            if request.url() == "https://open.weixin.qq.com/connect/qrconnect" {
                return Ok(HttpResponse::new(
                    200,
                    br#"<a href="?uuid=lifecycle-fixture">login</a>"#.to_vec(),
                ));
            }
            if request
                .url()
                .starts_with("https://open.weixin.qq.com/connect/qrcode/")
            {
                return Ok(HttpResponse::new(200, b"\xff\xd8\xfffixture-jpeg".to_vec()));
            }
            if request.method() == HttpMethod::Get {
                self.poll_calls.fetch_add(1, Ordering::SeqCst);
                return Ok(HttpResponse::new(
                    200,
                    b"window.wx_errcode=405;window.wx_code='late-secret-code';".to_vec(),
                ));
            }

            let call = self.exchange_calls.fetch_add(1, Ordering::SeqCst);
            if self.block_exchange {
                self.started.add_permits(1);
                let mut marker = CancellationMarker {
                    cancelled: Arc::clone(&self.cancelled),
                    completed: false,
                };
                self.release
                    .acquire()
                    .await
                    .expect("exchange-release semaphore remains open")
                    .forget();
                marker.completed = true;
            }
            if self.fail_first && call == 0 {
                return Ok(HttpResponse::new(
                    200,
                    serde_json::to_vec(&serde_json::json!({
                        "code": 0,
                        "music.login.LoginServer.Login": { "code": 1000, "data": {} }
                    }))
                    .expect("failure fixture JSON"),
                ));
            }
            Ok(Self::success_response())
        }
    }

    #[tokio::test]
    async fn replacement_aborts_poll_and_suppresses_the_old_result() {
        let transport = LifecycleTransport::blocked(405);
        let coordinator = WechatQrLoginCoordinator::new(QqMusicClient::new(transport.clone()));
        let mut first = coordinator.begin().await.expect("first QR session");
        let poll = tokio::spawn(async move { first.advance().await });
        transport.wait_until_poll_started().await;

        let second = coordinator.begin().await.expect("replacement QR session");
        let error = poll
            .await
            .expect("poll task")
            .expect_err("old session is superseded");

        assert!(matches!(error, WechatQrLoginError::Superseded));
        assert!(transport.was_poll_cancelled());
        assert!(second.is_active());
        drop(second);
        assert!(!coordinator.has_active_session());
    }

    #[tokio::test]
    async fn explicit_cancellation_aborts_the_in_flight_poll() {
        let transport = LifecycleTransport::blocked(405);
        let coordinator = WechatQrLoginCoordinator::new(QqMusicClient::new(transport.clone()));
        let mut session = coordinator.begin().await.expect("QR session");
        let poll = tokio::spawn(async move { session.advance().await });
        transport.wait_until_poll_started().await;

        assert!(coordinator.cancel_active());
        let error = poll
            .await
            .expect("poll task")
            .expect_err("poll is cancelled");

        assert!(matches!(error, WechatQrLoginError::Cancelled));
        assert!(transport.was_poll_cancelled());
        assert!(!coordinator.has_active_session());
    }

    #[tokio::test]
    async fn dropping_coordinator_aborts_poll_and_closes_session() {
        let transport = LifecycleTransport::blocked(405);
        let coordinator = WechatQrLoginCoordinator::new(QqMusicClient::new(transport.clone()));
        let mut session = coordinator.begin().await.expect("QR session");
        let poll = tokio::spawn(async move { session.advance().await });
        transport.wait_until_poll_started().await;

        drop(coordinator);
        let error = poll
            .await
            .expect("poll task")
            .expect_err("coordinator is closed");

        assert!(matches!(error, WechatQrLoginError::CoordinatorClosed));
        assert!(transport.was_poll_cancelled());
    }

    #[tokio::test]
    async fn terminal_result_finishes_session_and_cannot_be_polled_again() {
        let transport = LifecycleTransport::ready(402);
        let coordinator = WechatQrLoginCoordinator::new(QqMusicClient::new(transport));
        let mut session = coordinator.begin().await.expect("QR session");

        let result = session.advance().await.expect("expired protocol result");

        assert_eq!(result, WechatQrLoginProgress::Expired);
        assert!(!session.is_active());
        assert!(!coordinator.has_active_session());
        assert!(matches!(
            session.advance().await,
            Err(WechatQrLoginError::SessionFinished)
        ));
    }

    #[tokio::test]
    async fn dropping_session_clears_only_its_own_generation() {
        let transport = LifecycleTransport::blocked(408);
        let coordinator = WechatQrLoginCoordinator::new(QqMusicClient::new(transport));
        let first = coordinator.begin().await.expect("first session");
        let second = coordinator.begin().await.expect("second session");

        drop(first);
        assert!(coordinator.has_active_session());
        assert!(second.is_active());
        drop(second);
        assert!(!coordinator.has_active_session());
    }

    #[tokio::test]
    async fn failed_qr_creation_does_not_leave_an_orphaned_active_generation() {
        let coordinator = WechatQrLoginCoordinator::new(QqMusicClient::new(InvalidQrTransport));

        let error = coordinator
            .begin()
            .await
            .expect_err("invalid QR image is a protocol error");

        assert!(matches!(error, WechatQrLoginError::Protocol(_)));
        assert!(!coordinator.has_active_session());
    }

    #[tokio::test]
    async fn replacement_also_aborts_an_in_flight_qr_creation() {
        let transport = FirstConnectBlocksTransport::new();
        let coordinator = Arc::new(WechatQrLoginCoordinator::new(QqMusicClient::new(
            transport.clone(),
        )));
        let first_coordinator = Arc::clone(&coordinator);
        let first = tokio::spawn(async move { first_coordinator.begin().await });
        transport.wait_until_first_connect_started().await;

        let second = coordinator.begin().await.expect("replacement QR session");
        let error = first
            .await
            .expect("first begin task")
            .expect_err("first QR creation is superseded");

        assert!(matches!(error, WechatQrLoginError::Superseded));
        assert!(transport.cancelled.load(Ordering::SeqCst));
        assert!(second.is_active());
    }

    #[tokio::test]
    async fn authorization_is_exchanged_inside_the_same_generation() {
        let transport = ExchangeLifecycleTransport::ready(false);
        let coordinator = WechatQrLoginCoordinator::new(QqMusicClient::new(transport.clone()));
        let mut session = coordinator.begin().await.expect("QR session");

        let progress = session.advance().await.expect("credential exchange");

        let WechatQrLoginProgress::Authenticated(credential) = &progress else {
            panic!("expected authenticated progress");
        };
        assert_eq!(credential.music_id(), "456");
        assert_eq!(transport.poll_calls.load(Ordering::SeqCst), 1);
        assert_eq!(transport.exchange_calls.load(Ordering::SeqCst), 1);
        assert!(!session.is_active());
        assert!(!coordinator.has_active_session());
        assert!(!format!("{progress:?}").contains("late-secret"));
    }

    #[tokio::test]
    async fn replacement_aborts_exchange_and_suppresses_late_credential() {
        let transport = ExchangeLifecycleTransport::blocked();
        let coordinator = WechatQrLoginCoordinator::new(QqMusicClient::new(transport.clone()));
        let mut first = coordinator.begin().await.expect("first QR session");
        let advance = tokio::spawn(async move { first.advance().await });
        transport.wait_until_exchange_started().await;

        let second = coordinator.begin().await.expect("replacement QR session");
        let error = advance
            .await
            .expect("advance task")
            .expect_err("old exchange is superseded");

        assert!(matches!(error, WechatQrLoginError::Superseded));
        assert!(transport.cancelled.load(Ordering::SeqCst));
        assert!(second.is_active());
    }

    #[tokio::test]
    async fn exchange_failure_keeps_code_for_explicit_retry_without_repolling() {
        let transport = ExchangeLifecycleTransport::ready(true);
        let coordinator = WechatQrLoginCoordinator::new(QqMusicClient::new(transport.clone()));
        let mut session = coordinator.begin().await.expect("QR session");

        let first_error = session
            .advance()
            .await
            .expect_err("first exchange is rejected");

        assert!(matches!(
            first_error,
            WechatQrLoginError::CredentialExchange(WechatCredentialExchangeError::Upstream {
                global_code: 0,
                login_code: Some(1000)
            })
        ));
        assert!(session.is_active());
        let retry = session.advance().await.expect("explicit exchange retry");
        assert!(matches!(retry, WechatQrLoginProgress::Authenticated(_)));
        assert_eq!(transport.poll_calls.load(Ordering::SeqCst), 1);
        assert_eq!(transport.exchange_calls.load(Ordering::SeqCst), 2);
    }
}
