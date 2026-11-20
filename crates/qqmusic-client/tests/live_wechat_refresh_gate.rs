use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use qqmusic_client::{
    Credential, CredentialRefreshError, CredentialVerificationError, HttpRequest, HttpResponse,
    HttpTransport, QqMusicClient, QrImageMediaType, ReqwestTransport, ReqwestTransportError,
    WechatCredentialExchangeError, WechatQrError, WechatQrLoginCoordinator, WechatQrLoginError,
    WechatQrLoginProgress, validate_credential_refresh_material,
};

#[path = "support/user_library_gate.rs"]
mod user_library_gate;

const ENABLE_ENV: &str = "FURA_QQ_WECHAT_REFRESH_PROTOCOL_GATE";
const QR_PATH_ENV: &str = "FURA_QQ_WECHAT_REFRESH_QR_PATH";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum GateClassification {
    Pass,
    BlockedByProtocol,
    BlockedByRiskControl,
    ImplementationDefect,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
enum FieldPresence {
    #[default]
    Absent,
    Present,
}

impl FieldPresence {
    const fn from_bool(value: bool) -> Self {
        if value { Self::Present } else { Self::Absent }
    }

    const fn is_present(self) -> bool {
        matches!(self, Self::Present)
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct RefreshResponsePresence {
    music_key: FieldPresence,
    open_id: FieldPresence,
    refresh_token: FieldPresence,
    union_id: FieldPresence,
    refresh_key: FieldPresence,
    encrypted_uin: FieldPresence,
    expiry: FieldPresence,
}

impl RefreshResponsePresence {
    fn decode(bytes: &[u8]) -> Self {
        let Ok(value) = serde_json::from_slice::<serde_json::Value>(bytes) else {
            return Self::default();
        };
        let Some(data) = value
            .get("music.login.LoginServer.Login")
            .and_then(|login| login.get("data"))
            .and_then(serde_json::Value::as_object)
        else {
            return Self::default();
        };
        let nonempty = |names: &[&str]| {
            names.iter().any(|name| {
                data.get(*name)
                    .and_then(serde_json::Value::as_str)
                    .is_some_and(|value| !value.is_empty())
            })
        };
        let positive = |names: &[&str]| {
            names.iter().any(|name| {
                data.get(*name)
                    .and_then(serde_json::Value::as_u64)
                    .is_some_and(|value| value > 0)
            })
        };
        Self {
            music_key: FieldPresence::from_bool(nonempty(&["musickey"])),
            open_id: FieldPresence::from_bool(nonempty(&["openid", "psrf_wxopenid", "wxopenid"])),
            refresh_token: FieldPresence::from_bool(nonempty(&[
                "refresh_token",
                "psrf_wxrefresh_token",
                "wxrefresh_token",
            ])),
            union_id: FieldPresence::from_bool(nonempty(&[
                "unionid",
                "psrf_wxunionid",
                "wxunionid",
            ])),
            refresh_key: FieldPresence::from_bool(nonempty(&["refresh_key"])),
            encrypted_uin: FieldPresence::from_bool(nonempty(&["encryptUin"])),
            expiry: FieldPresence::from_bool(positive(&[
                "musickeyCreateTime",
                "keyExpiresIn",
                "expired_at",
            ])),
        }
    }
}

#[derive(Default)]
struct RefreshObservationState {
    armed: AtomicBool,
    response: Mutex<Option<RefreshResponsePresence>>,
}

#[derive(Clone)]
struct ObservingTransport {
    inner: ReqwestTransport,
    observation: Arc<RefreshObservationState>,
}

impl ObservingTransport {
    fn new(inner: ReqwestTransport) -> Self {
        Self {
            inner,
            observation: Arc::new(RefreshObservationState::default()),
        }
    }

    fn begin_refresh_observation(&self) {
        *self.observation.response.lock().expect("observation lock") = None;
        self.observation.armed.store(true, Ordering::SeqCst);
    }

    fn take_refresh_observation(&self) -> Option<RefreshResponsePresence> {
        self.observation.armed.store(false, Ordering::SeqCst);
        self.observation
            .response
            .lock()
            .expect("observation lock")
            .take()
    }
}

impl HttpTransport for ObservingTransport {
    type Error = ReqwestTransportError;

    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
        let observe = self.observation.armed.swap(false, Ordering::SeqCst);
        let response = self.inner.execute(request).await?;
        if observe {
            *self.observation.response.lock().expect("observation lock") =
                Some(RefreshResponsePresence::decode(response.body()));
        }
        Ok(response)
    }
}

impl GateClassification {
    const fn label(self) -> &'static str {
        match self {
            Self::Pass => "PASS",
            Self::BlockedByProtocol => "BLOCKED_BY_PROTOCOL",
            Self::BlockedByRiskControl => "BLOCKED_BY_RISK_CONTROL",
            Self::ImplementationDefect => "IMPLEMENTATION_DEFECT",
        }
    }
}

struct TransientQrFile {
    path: PathBuf,
    present: bool,
}

impl TransientQrFile {
    fn create(
        mut path: PathBuf,
        media_type: QrImageMediaType,
        bytes: &[u8],
    ) -> std::io::Result<Self> {
        let expected_extension = match media_type {
            QrImageMediaType::Png => "png",
            QrImageMediaType::Jpeg => "jpg",
        };
        if path.extension().is_none() {
            path.set_extension(expected_extension);
        } else if path.extension().and_then(|value| value.to_str()) != Some(expected_extension) {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                format!("QR output must use the .{expected_extension} extension"),
            ));
        }
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options.open(&path)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        Ok(Self {
            path,
            present: true,
        })
    }

    fn remove(&mut self) {
        if self.present {
            let _ = fs::remove_file(&self.path);
            self.present = false;
        }
    }
}

impl Drop for TransientQrFile {
    fn drop(&mut self) {
        self.remove();
    }
}

fn report(classification: GateClassification, phase: &str, detail: &str) {
    eprintln!(
        "FURA_QQ_REFRESH_GATE classification={} phase={phase} detail={detail}",
        classification.label(),
    );
}

fn musicu_code_is_rate_limited(global_code: i64, result_code: Option<i64>) -> bool {
    global_code == 2001 || result_code == Some(2001)
}

fn classify_login_error(
    error: &WechatQrLoginError<qqmusic_client::ReqwestTransportError>,
) -> GateClassification {
    match error {
        WechatQrLoginError::Protocol(WechatQrError::HttpStatus { status: 429, .. })
        | WechatQrLoginError::CredentialExchange(WechatCredentialExchangeError::HttpStatus(429)) => {
            GateClassification::BlockedByRiskControl
        }
        WechatQrLoginError::CredentialExchange(WechatCredentialExchangeError::Upstream {
            global_code,
            login_code,
        }) if musicu_code_is_rate_limited(*global_code, *login_code) => {
            GateClassification::BlockedByRiskControl
        }
        WechatQrLoginError::Cancelled
        | WechatQrLoginError::Superseded
        | WechatQrLoginError::CoordinatorClosed
        | WechatQrLoginError::SessionFinished => GateClassification::ImplementationDefect,
        _ => GateClassification::BlockedByProtocol,
    }
}

fn classify_verification_error(
    error: &CredentialVerificationError<qqmusic_client::ReqwestTransportError>,
) -> GateClassification {
    match error {
        CredentialVerificationError::HttpStatus(429) => GateClassification::BlockedByRiskControl,
        CredentialVerificationError::Upstream {
            global_code,
            verification_code,
        } if musicu_code_is_rate_limited(*global_code, *verification_code) => {
            GateClassification::BlockedByRiskControl
        }
        _ => GateClassification::BlockedByProtocol,
    }
}

async fn authenticate_disposable_session(
    qr_path: PathBuf,
) -> Option<(WechatQrLoginCoordinator<ObservingTransport>, Credential)> {
    let Ok(transport) = ReqwestTransport::new() else {
        report(
            GateClassification::ImplementationDefect,
            "preflight",
            "native HTTPS transport unavailable",
        );
        return None;
    };
    let coordinator =
        WechatQrLoginCoordinator::new(QqMusicClient::new(ObservingTransport::new(transport)));
    let mut session = match coordinator.begin().await {
        Ok(session) => session,
        Err(error) => {
            report(classify_login_error(&error), "qr_bootstrap", "failed");
            return None;
        }
    };
    let Ok(mut qr_file) = TransientQrFile::create(
        qr_path,
        session.image().media_type(),
        session.image().bytes(),
    ) else {
        report(
            GateClassification::ImplementationDefect,
            "qr_publish",
            "could not create private transient QR file",
        );
        return None;
    };
    eprintln!("FURA_QQ_REFRESH_GATE interaction=SCAN_QR status=READY");

    loop {
        match session.advance().await {
            Ok(WechatQrLoginProgress::WaitingForScan) => {
                eprintln!("FURA_QQ_REFRESH_GATE interaction=SCAN_QR status=WAITING");
            }
            Ok(WechatQrLoginProgress::ScannedAwaitingConfirmation) => {
                eprintln!("FURA_QQ_REFRESH_GATE interaction=CONFIRM status=WAITING");
            }
            Ok(WechatQrLoginProgress::Authenticated(credential)) => {
                qr_file.remove();
                eprintln!("FURA_QQ_REFRESH_GATE phase=wechat_login outcome=accepted");
                return Some((coordinator, *credential));
            }
            Ok(WechatQrLoginProgress::Expired | WechatQrLoginProgress::TimedOut) => {
                report(
                    GateClassification::BlockedByProtocol,
                    "human_interaction",
                    "QR session expired",
                );
                return None;
            }
            Ok(WechatQrLoginProgress::Refused) => {
                report(
                    GateClassification::BlockedByProtocol,
                    "human_interaction",
                    "authorization refused",
                );
                return None;
            }
            Err(error) => {
                report(classify_login_error(&error), "wechat_login", "failed");
                return None;
            }
        }
        tokio::time::sleep(Duration::from_secs(1)).await;
    }
}

async fn refresh_once_and_verify_once(
    coordinator: &WechatQrLoginCoordinator<ObservingTransport>,
    credential: &Credential,
) -> Option<Credential> {
    let initial = credential.session_secrets();
    eprintln!(
        "FURA_QQ_REFRESH_GATE phase=initial_capture initial_openid_present={} initial_refresh_token_present={} initial_unionid_present={} initial_refresh_key_present={} initial_encrypted_uin_present={} initial_expiry_present={}",
        initial.open_id().is_some(),
        initial.refresh_token().is_some(),
        initial.union_id().is_some(),
        initial.refresh_key().is_some(),
        initial.encrypted_uin().is_some(),
        credential.expires_at_unix_seconds().is_some()
            || credential.refresh_expiry_value().is_some(),
    );
    coordinator.client().transport().begin_refresh_observation();
    let refresh_result = coordinator.client().refresh_credential(credential).await;
    let returned = coordinator
        .client()
        .transport()
        .take_refresh_observation()
        .unwrap_or_default();
    eprintln!(
        "FURA_QQ_REFRESH_GATE phase=refresh_response returned_musickey_present={} returned_openid_present={} returned_refresh_token_present={} returned_unionid_present={} returned_refresh_key_present={} returned_encrypted_uin_present={} returned_expiry_present={}",
        returned.music_key.is_present(),
        returned.open_id.is_present(),
        returned.refresh_token.is_present(),
        returned.union_id.is_present(),
        returned.refresh_key.is_present(),
        returned.encrypted_uin.is_present(),
        returned.expiry.is_present(),
    );
    let refreshed = match refresh_result {
        Ok(credential) => credential,
        Err(CredentialRefreshError::RateLimited | CredentialRefreshError::AccountChanged) => {
            report(
                GateClassification::BlockedByRiskControl,
                "refresh",
                "rate limit or account mismatch",
            );
            return None;
        }
        Err(_) => {
            report(
                GateClassification::BlockedByProtocol,
                "refresh",
                "request was not accepted",
            );
            return None;
        }
    };
    let candidate = refreshed.session_secrets();
    eprintln!(
        "FURA_QQ_REFRESH_GATE phase=candidate_decode candidate_openid_present={} candidate_refresh_token_present={} candidate_unionid_present={} candidate_refresh_key_present={} candidate_encrypted_uin_present={} candidate_next_refreshable={}",
        candidate.open_id().is_some(),
        candidate.refresh_token().is_some(),
        candidate.union_id().is_some(),
        candidate.refresh_key().is_some(),
        candidate.encrypted_uin().is_some(),
        validate_credential_refresh_material(&refreshed).is_ok(),
    );

    match coordinator.client().verify_credential(&refreshed).await {
        Ok(summary) => {
            let summary_state = if summary.is_some() {
                "present"
            } else {
                "absent"
            };
            report(
                GateClassification::Pass,
                "account_verification",
                summary_state,
            );
            Some(refreshed)
        }
        Err(error) => {
            report(
                classify_verification_error(&error),
                "account_verification",
                "failed",
            );
            None
        }
    }
}

/// Human-operated, disposable-session QQ `WeChat` refresh gate.
///
/// The test is Debug-only, ignored by default, requires two explicit
/// environment values, writes only a create-new transient QR image, performs
/// exactly one refresh request followed by one account verification, and does
/// not persist or print credential/account material.
#[tokio::test]
#[ignore = "Human-operated disposable QQ WeChat session; explicit Debug gate only"]
async fn bounded_disposable_wechat_refresh_gate() {
    if !cfg!(debug_assertions) {
        report(
            GateClassification::ImplementationDefect,
            "preflight",
            "gate must run in a Debug test profile",
        );
        return;
    }
    if std::env::var(ENABLE_ENV).as_deref() != Ok("1") {
        eprintln!("skipped: set {ENABLE_ENV}=1 for the bounded protocol gate");
        return;
    }
    let Some(qr_path) = std::env::var_os(QR_PATH_ENV).map(PathBuf::from) else {
        report(
            GateClassification::ImplementationDefect,
            "preflight",
            "missing transient QR output path",
        );
        return;
    };
    if !qr_path.is_absolute() || qr_path.parent().is_none_or(|parent| !parent.is_dir()) {
        report(
            GateClassification::ImplementationDefect,
            "preflight",
            "QR output path must be absolute and its parent must exist",
        );
        return;
    }

    let Some((coordinator, credential)) = authenticate_disposable_session(qr_path).await else {
        return;
    };
    // Exactly one refresh and one account verification; no ordinary read.
    let _ = refresh_once_and_verify_once(&coordinator, &credential).await;
}

/// One fresh disposable `WeChat` login, one refresh, then the existing bounded
/// independent User Library read matrix. No Vault, fallback, retry, mutation,
/// pagination, or personal response content is used or retained.
#[tokio::test]
#[ignore = "Human-operated QQ WeChat refresh to User Library regression"]
async fn bounded_disposable_wechat_user_library_post_refresh_gate() {
    const LIBRARY_GATE: &str = "FURA_QQ_USER_LIBRARY_GATE";
    if !cfg!(debug_assertions) || std::env::var(LIBRARY_GATE).as_deref() != Ok("1") {
        eprintln!("{LIBRARY_GATE} result=NOT_RUN reason=debug_and_explicit_opt_in_required");
        return;
    }
    let Some(qr_path) = std::env::var_os("FURA_QQ_USER_LIBRARY_QR_PATH")
        .map(PathBuf::from)
        .filter(|path| path.is_absolute() && path.parent().is_some_and(std::path::Path::is_dir))
    else {
        eprintln!("{LIBRARY_GATE} result=NOT_RUN reason=private_qr_path_required");
        return;
    };

    let Some((coordinator, credential)) = authenticate_disposable_session(qr_path).await else {
        return;
    };
    let Some(refreshed) = refresh_once_and_verify_once(&coordinator, &credential).await else {
        return;
    };
    let transport = coordinator.client().transport().inner.clone();
    user_library_gate::run_reads(transport, &refreshed).await;
}

#[test]
fn risk_classification_is_fail_closed_for_rate_limit_and_account_change() {
    assert!(musicu_code_is_rate_limited(2001, None));
    assert!(musicu_code_is_rate_limited(0, Some(2001)));
    assert!(!musicu_code_is_rate_limited(0, Some(0)));
    assert_eq!(GateClassification::Pass.label(), "PASS");
    assert_eq!(
        GateClassification::BlockedByProtocol.label(),
        "BLOCKED_BY_PROTOCOL",
    );
    assert_eq!(
        GateClassification::BlockedByRiskControl.label(),
        "BLOCKED_BY_RISK_CONTROL",
    );
    assert_eq!(
        GateClassification::ImplementationDefect.label(),
        "IMPLEMENTATION_DEFECT",
    );
}

#[test]
fn refresh_presence_diagnostic_recognizes_aliases_without_values() {
    let observed = RefreshResponsePresence::decode(
        br#"{"code":0,"music.login.LoginServer.Login":{"code":0,"data":{"musickey":"do-not-echo-key-7x","psrf_wxopenid":"do-not-echo-open-7x","wxrefresh_token":"do-not-echo-token-7x","psrf_wxunionid":"do-not-echo-union-7x","refresh_key":"do-not-echo-refresh-key-7x","encryptUin":"do-not-echo-encrypted-uin-7x","keyExpiresIn":123}}}"#,
    );
    assert_eq!(
        observed,
        RefreshResponsePresence {
            music_key: FieldPresence::Present,
            open_id: FieldPresence::Present,
            refresh_token: FieldPresence::Present,
            union_id: FieldPresence::Present,
            refresh_key: FieldPresence::Present,
            encrypted_uin: FieldPresence::Present,
            expiry: FieldPresence::Present,
        }
    );
    assert!(!format!("{observed:?}").contains("do-not-echo"));
}

#[test]
fn transient_qr_file_is_create_new_and_removed_on_drop() {
    let directory =
        std::env::temp_dir().join(format!("fura-qq-refresh-gate-test-{}", std::process::id()));
    fs::create_dir(&directory).expect("temporary directory");
    let path = directory.join("qr.png");
    {
        let _file =
            TransientQrFile::create(path.clone(), QrImageMediaType::Png, b"synthetic-qr-bytes")
                .expect("transient QR file");
        assert_eq!(fs::read(&path).expect("QR bytes"), b"synthetic-qr-bytes");
        assert!(
            TransientQrFile::create(path.clone(), QrImageMediaType::Png, b"replacement").is_err()
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(&path)
                    .expect("QR metadata")
                    .permissions()
                    .mode()
                    & 0o777,
                0o600,
            );
        }
    }
    assert!(!Path::new(&path).exists());
    fs::remove_dir(directory).expect("remove temporary directory");
}

#[test]
fn transient_qr_file_adds_the_protocol_media_extension_to_a_base_path() {
    let directory = std::env::temp_dir().join(format!(
        "fura-qq-refresh-gate-extension-test-{}",
        std::process::id()
    ));
    fs::create_dir(&directory).expect("temporary directory");
    let base_path = directory.join("qr");
    let resolved_path = directory.join("qr.jpg");
    {
        let file =
            TransientQrFile::create(base_path, QrImageMediaType::Jpeg, b"synthetic-jpeg-bytes")
                .expect("transient QR file");
        assert_eq!(file.path, resolved_path);
        assert!(resolved_path.exists());
    }
    assert!(!resolved_path.exists());
    fs::remove_dir(directory).expect("remove temporary directory");
}
