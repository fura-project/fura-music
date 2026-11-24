use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use qqmusic_client::{
    Credential, CredentialRefreshError, CredentialVerificationError, HttpRequest, HttpResponse,
    HttpTransport, LoginCredentialError, QqMusicClient, QqQrError, QqQrPollResult,
    QrImageMediaType, ReqwestTransport, ReqwestTransportError,
};

#[cfg(feature = "track-like-status-research")]
#[path = "support/track_like_status_gate.rs"]
mod track_like_status_gate;
#[path = "support/user_library_gate.rs"]
mod user_library_gate;

const ENABLE_ENV: &str = "FURA_QQ_TYPE2_REFRESH_PROTOCOL_GATE";
const QR_PATH_ENV: &str = "FURA_QQ_TYPE2_REFRESH_QR_PATH";

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
enum EncryptedIdentityPresence {
    #[default]
    Unobserved,
    Missing,
    Null,
    Empty,
    Present,
    Other,
}

impl EncryptedIdentityPresence {
    const fn label(self) -> &'static str {
        match self {
            Self::Unobserved => "unobserved",
            Self::Missing => "missing",
            Self::Null => "null",
            Self::Empty => "empty",
            Self::Present => "present",
            Self::Other => "other",
        }
    }
}

#[derive(Clone)]
struct RefreshObservingTransport {
    inner: ReqwestTransport,
    encrypted_identity: Arc<Mutex<EncryptedIdentityPresence>>,
}

impl RefreshObservingTransport {
    fn new(inner: ReqwestTransport) -> Self {
        Self {
            inner,
            encrypted_identity: Arc::new(Mutex::new(EncryptedIdentityPresence::Unobserved)),
        }
    }

    fn encrypted_identity(&self) -> EncryptedIdentityPresence {
        *self.encrypted_identity.lock().expect("refresh observation")
    }
}

impl HttpTransport for RefreshObservingTransport {
    type Error = ReqwestTransportError;

    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
        let response = self.inner.execute(request).await?;
        if let Ok(body) = serde_json::from_slice::<serde_json::Value>(response.body())
            && let Some(data) = body
                .get("music.login.LoginServer.Login")
                .and_then(|value| value.get("data"))
                .and_then(serde_json::Value::as_object)
        {
            let presence = match data.get("encryptUin") {
                None => EncryptedIdentityPresence::Missing,
                Some(serde_json::Value::Null) => EncryptedIdentityPresence::Null,
                Some(serde_json::Value::String(value)) if value.is_empty() => {
                    EncryptedIdentityPresence::Empty
                }
                Some(serde_json::Value::String(_)) => EncryptedIdentityPresence::Present,
                Some(_) => EncryptedIdentityPresence::Other,
            };
            *self.encrypted_identity.lock().expect("refresh observation") = presence;
        }
        Ok(response)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum GateClassification {
    Pass,
    BlockedByProtocol,
    BlockedByRiskControl,
    ImplementationDefect,
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
}

impl TransientQrFile {
    fn create(
        mut path: PathBuf,
        media_type: QrImageMediaType,
        bytes: &[u8],
    ) -> std::io::Result<Self> {
        let extension = match media_type {
            QrImageMediaType::Png => "png",
            QrImageMediaType::Jpeg => "jpg",
        };
        if path.extension().is_none() {
            path.set_extension(extension);
        } else if path.extension().and_then(|value| value.to_str()) != Some(extension) {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                format!("QR output must use the .{extension} extension"),
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
        Ok(Self { path })
    }
}

impl Drop for TransientQrFile {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

fn report(classification: GateClassification, phase: &str, detail: &str) {
    eprintln!(
        "FURA_QQ_TYPE2_REFRESH_GATE classification={} phase={phase} detail={detail}",
        classification.label()
    );
}

fn classify_qr_error(
    error: &QqQrError<qqmusic_client::ReqwestTransportError>,
) -> GateClassification {
    match error {
        QqQrError::HttpStatus { status: 429, .. } => GateClassification::BlockedByRiskControl,
        QqQrError::Credential(LoginCredentialError::Upstream {
            global_code,
            login_code,
        }) if [*global_code, login_code.unwrap_or(0)].iter().any(|code| {
            matches!(
                code,
                2001 | 20_271 | 20_272 | 20_274 | 20_277 | 20_278 | 20_279 | 20_450 | 104_604
            )
        }) =>
        {
            GateClassification::BlockedByRiskControl
        }
        _ => GateClassification::BlockedByProtocol,
    }
}

fn qq_login_failure_detail(
    error: &QqQrError<qqmusic_client::ReqwestTransportError>,
) -> &'static str {
    match error {
        QqQrError::Transport(_) => "transport",
        QqQrError::HttpStatus {
            phase: "check signature",
            ..
        } => "check_signature_http",
        QqQrError::HttpStatus {
            phase: "authorization",
            ..
        } => "authorization_http",
        QqQrError::HttpStatus {
            phase: "credential exchange",
            ..
        } => "credential_exchange_http",
        QqQrError::HttpStatus { .. } => "unexpected_http_phase",
        QqQrError::MissingPSkey => "check_signature_cookie_missing",
        QqQrError::MissingRedirect => "authorization_redirect_missing",
        QqQrError::MissingAuthorizationCode => "authorization_code_missing",
        QqQrError::Serialize => "credential_request_serialize",
        QqQrError::Credential(LoginCredentialError::InvalidJson) => {
            "credential_response_invalid_json"
        }
        QqQrError::Credential(LoginCredentialError::MissingGlobalCode) => {
            "credential_global_code_missing"
        }
        QqQrError::Credential(LoginCredentialError::MissingLoginResult) => {
            "credential_named_result_missing"
        }
        QqQrError::Credential(LoginCredentialError::Upstream { .. }) => {
            "credential_upstream_rejected"
        }
        QqQrError::Credential(LoginCredentialError::MissingCredentialData) => {
            "credential_data_missing"
        }
        QqQrError::Credential(LoginCredentialError::InvalidCredential(_)) => {
            "credential_material_invalid"
        }
        QqQrError::Credential(LoginCredentialError::InvalidExpiry(_)) => {
            "credential_expiry_invalid"
        }
        QqQrError::Credential(LoginCredentialError::UnexpectedLoginType(_)) => {
            "credential_login_type_mismatch"
        }
        QqQrError::MissingAuthorization => "authorization_state_missing",
        QqQrError::InvalidImage
        | QqQrError::MissingQrsig
        | QqQrError::InvalidCookie
        | QqQrError::ClockBeforeUnixEpoch
        | QqQrError::RandomnessUnavailable
        | QqQrError::ResponseNotUtf8
        | QqQrError::InvalidPollResponse
        | QqQrError::UnrecognizedPollStatus(_) => "unexpected_exchange_state",
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
        } if *global_code == 2001 || *verification_code == Some(2001) => {
            GateClassification::BlockedByRiskControl
        }
        _ => GateClassification::BlockedByProtocol,
    }
}

async fn acquire_disposable_qq_credential(
    client: &QqMusicClient<ReqwestTransport>,
    qr_path: PathBuf,
) -> Option<Credential> {
    let mut session = match client.create_qq_qr().await {
        Ok(session) => session,
        Err(error) => {
            report(classify_qr_error(&error), "qr_bootstrap", "failed");
            return None;
        }
    };
    let Ok(qr_file) = TransientQrFile::create(
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
    eprintln!("FURA_QQ_TYPE2_REFRESH_GATE interaction=SCAN_QR status=READY");

    let deadline = tokio::time::Instant::now() + Duration::from_mins(3);
    loop {
        if tokio::time::Instant::now() >= deadline {
            report(
                GateClassification::BlockedByProtocol,
                "human_interaction",
                "QR session timed out",
            );
            return None;
        }
        match client.poll_qq_qr(&mut session).await {
            Ok(QqQrPollResult::WaitingForScan) => {}
            Ok(QqQrPollResult::ScannedAwaitingConfirmation) => {
                eprintln!("FURA_QQ_TYPE2_REFRESH_GATE interaction=CONFIRM status=WAITING");
            }
            Ok(QqQrPollResult::Authorized) => break,
            Ok(QqQrPollResult::Expired | QqQrPollResult::Refused) => {
                report(
                    GateClassification::BlockedByProtocol,
                    "human_interaction",
                    "QR session ended before authorization",
                );
                return None;
            }
            Err(error) => {
                report(classify_qr_error(&error), "qr_poll", "failed");
                return None;
            }
        }
        tokio::time::sleep(Duration::from_secs(1)).await;
    }
    drop(qr_file);

    match client.exchange_authorized_qq_qr(&mut session).await {
        Ok(credential) => Some(credential),
        Err(error) => {
            report(
                classify_qr_error(&error),
                "qq_login",
                qq_login_failure_detail(&error),
            );
            None
        }
    }
}

async fn refresh_and_verify_once(
    transport: ReqwestTransport,
    credential: &Credential,
) -> Option<Credential> {
    let observed = RefreshObservingTransport::new(transport);
    let client = QqMusicClient::new(observed.clone());
    let refreshed = match client.refresh_credential(credential).await {
        Ok(credential) => credential,
        Err(
            error @ (CredentialRefreshError::RateLimited
            | CredentialRefreshError::RiskControl
            | CredentialRefreshError::SecondaryVerificationRequired
            | CredentialRefreshError::AccountChanged),
        ) => {
            report(
                GateClassification::BlockedByRiskControl,
                "refresh",
                refresh_failure_detail(error),
            );
            return None;
        }
        Err(error) => {
            report(
                GateClassification::BlockedByProtocol,
                "refresh",
                refresh_failure_detail(error),
            );
            return None;
        }
    };

    eprintln!(
        "FURA_QQ_TYPE2_REFRESH_GATE phase=refresh_identity source_encrypted_uin_present={} response_encrypted_uin={} candidate_encrypted_uin_present={}",
        credential.session_secrets().encrypted_uin().is_some(),
        observed.encrypted_identity().label(),
        refreshed.session_secrets().encrypted_uin().is_some(),
    );

    match client.verify_credential(&refreshed).await {
        Ok(_) => {
            report(GateClassification::Pass, "account_verification", "accepted");
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

const fn refresh_failure_detail(error: CredentialRefreshError) -> &'static str {
    match error {
        CredentialRefreshError::NotRefreshable => "not_refreshable",
        CredentialRefreshError::UnsupportedLoginType => "unsupported_login_type",
        CredentialRefreshError::Network => "network",
        CredentialRefreshError::RateLimited => "rate_limited",
        CredentialRefreshError::CredentialRejected => "credential_rejected",
        CredentialRefreshError::RiskControl => "risk_control",
        CredentialRefreshError::SecondaryVerificationRequired => "secondary_verification",
        CredentialRefreshError::ProtocolUnavailable => "protocol_unavailable",
        CredentialRefreshError::InvalidResponse => "invalid_response",
        CredentialRefreshError::MalformedResponse => "malformed_response",
        CredentialRefreshError::UpstreamRejected => "upstream_rejected",
        CredentialRefreshError::InvalidCredential => "invalid_credential",
        CredentialRefreshError::InvalidExpiry => "invalid_expiry",
        CredentialRefreshError::UnexpectedLoginType => "unexpected_login_type",
        CredentialRefreshError::IncompleteRotation => "incomplete_rotation",
        CredentialRefreshError::AccountChanged => "account_changed",
    }
}

/// Human-operated, disposable QQ `loginType=2` refresh gate.
///
/// The ignored Debug-only gate creates a private transient QR image, performs
/// no stored-credential read, sends at most one refresh request, then performs
/// exactly one account verification. It never prints or persists identity or
/// credential material. It must not be run until the Human explicitly starts
/// and completes the disposable session.
#[tokio::test]
#[ignore = "Human-operated disposable QQ Type 2 session; protocol gate only"]
async fn bounded_disposable_qq_type_two_refresh_gate() {
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

    let Ok(transport) = ReqwestTransport::new() else {
        report(
            GateClassification::ImplementationDefect,
            "preflight",
            "native HTTPS transport unavailable",
        );
        return;
    };
    let client = QqMusicClient::new(transport.clone());
    let Some(credential) = acquire_disposable_qq_credential(&client, qr_path).await else {
        return;
    };
    let _ = refresh_and_verify_once(transport, &credential).await;
}

async fn disposable_qq_session(
    gate: &str,
    qr_path_env: &str,
) -> Option<(ReqwestTransport, Credential)> {
    if !cfg!(debug_assertions) || std::env::var(gate).as_deref() != Ok("1") {
        eprintln!("{gate} result=NOT_RUN reason=debug_and_explicit_opt_in_required");
        return None;
    }
    let Some(qr_path) = std::env::var_os(qr_path_env)
        .map(PathBuf::from)
        .filter(|path| path.is_absolute() && path.parent().is_some_and(std::path::Path::is_dir))
    else {
        eprintln!("{gate} result=NOT_RUN reason=private_qr_path_required");
        return None;
    };
    let Ok(transport) = ReqwestTransport::new() else {
        eprintln!("{gate} result=NOT_RUN reason=https_transport_unavailable");
        return None;
    };
    let Some(credential) =
        acquire_disposable_qq_credential(&QqMusicClient::new(transport.clone()), qr_path).await
    else {
        eprintln!("{gate} result=NOT_RUN reason=disposable_login_not_completed");
        return None;
    };
    Some((transport, credential))
}

async fn disposable_user_library_session() -> Option<(ReqwestTransport, Credential)> {
    disposable_qq_session("FURA_QQ_USER_LIBRARY_GATE", "FURA_QQ_USER_LIBRARY_QR_PATH").await
}

/// One fresh Type 2 login; existing production client requests, one call each.
/// No application Provider/Vault, fallback, refresh, retries, or pagination.
#[tokio::test]
#[ignore = "Human-operated disposable QQ User Library first-page compatibility"]
async fn bounded_disposable_qq_user_library_gate() {
    let Some((transport, credential)) = disposable_user_library_session().await else {
        return;
    };
    user_library_gate::run_reads(transport, &credential).await;
}

/// One fresh Type 2 login, one refresh, then the same bounded independent
/// library reads against the verified candidate. No Vault or retry is used.
#[tokio::test]
#[ignore = "Human-operated QQ Type 2 refresh to User Library regression"]
async fn bounded_disposable_qq_user_library_post_refresh_gate() {
    let Some((transport, credential)) = disposable_user_library_session().await else {
        return;
    };
    let Some(refreshed) = refresh_and_verify_once(transport.clone(), &credential).await else {
        return;
    };
    user_library_gate::run_reads(transport, &refreshed).await;
}

/// One fresh Type 2 login, one account verification, one single-MID status
/// read, one two-MID status read, and one at-most-20-page resolver comparison.
/// No Vault, refresh, mutation, retry, or Provider integration is used.
#[tokio::test]
#[ignore = "Human-operated disposable QQ Type 2 Track-like status research gate"]
#[cfg(feature = "track-like-status-research")]
async fn bounded_disposable_qq_track_like_status_gate() {
    const GATE: &str = "FURA_QQ_TRACK_LIKE_STATUS_GATE";
    if !cfg!(debug_assertions) || std::env::var(GATE).as_deref() != Ok("1") {
        eprintln!("{GATE} result=NOT_RUN reason=debug_and_explicit_opt_in_required");
        return;
    }
    let Some((transport, credential)) =
        disposable_qq_session(GATE, "FURA_QQ_TRACK_LIKE_STATUS_QR_PATH").await
    else {
        return;
    };
    let client = QqMusicClient::new(transport);
    match client.verify_credential(&credential).await {
        Ok(_) => eprintln!(
            "FURA_QQ_TRACK_LIKE_STATUS_GATE phase=account_verification request_sent=true http_status=2xx global_code=0 subrequest_code=0 failure=none"
        ),
        Err(error) => {
            eprintln!(
                "FURA_QQ_TRACK_LIKE_STATUS_GATE phase=account_verification request_sent=true http_status=unknown global_code=unknown subrequest_code=unknown failure={}",
                match classify_verification_error(&error) {
                    GateClassification::BlockedByRiskControl => "risk_control",
                    GateClassification::BlockedByProtocol => "protocol",
                    GateClassification::Pass | GateClassification::ImplementationDefect => {
                        "implementation"
                    }
                }
            );
            return;
        }
    }
    let passed = track_like_status_gate::run_queries(&client, &credential).await;
    eprintln!(
        "FURA_QQ_TRACK_LIKE_STATUS_GATE login_type=2 result={}",
        if passed { "PASS" } else { "BLOCKED" }
    );
}

/// One fresh Type 2 login, one account verification, a complete exact Liked
/// snapshot, and exactly one direct read for an existing liked target selected
/// in memory. No identity is logged and no mutation, retry or refresh occurs.
#[tokio::test]
#[ignore = "Human-operated disposable QQ Type 2 Track-like true evidence gate"]
#[cfg(feature = "track-like-status-research")]
async fn bounded_disposable_qq_track_like_true_gate() {
    const GATE: &str = "FURA_QQ_TRACK_LIKE_TRUE_GATE";
    if !cfg!(debug_assertions) || std::env::var(GATE).as_deref() != Ok("1") {
        eprintln!("{GATE} result=NOT_RUN reason=debug_and_explicit_opt_in_required");
        return;
    }
    let Some((transport, credential)) =
        disposable_qq_session(GATE, "FURA_QQ_TRACK_LIKE_TRUE_QR_PATH").await
    else {
        return;
    };
    let client = QqMusicClient::new(transport);
    match client.verify_credential(&credential).await {
        Ok(_) => eprintln!(
            "FURA_QQ_TRACK_LIKE_TRUE_GATE phase=account_verification request_sent=true http_status=2xx global_code=0 subrequest_code=0 failure=none"
        ),
        Err(error) => {
            eprintln!(
                "FURA_QQ_TRACK_LIKE_TRUE_GATE phase=account_verification request_sent=true http_status=unknown global_code=unknown subrequest_code=unknown failure={}",
                match classify_verification_error(&error) {
                    GateClassification::BlockedByRiskControl => "risk_control",
                    GateClassification::BlockedByProtocol => "protocol",
                    GateClassification::Pass | GateClassification::ImplementationDefect => {
                        "implementation"
                    }
                }
            );
            return;
        }
    }
    let passed = track_like_status_gate::run_true_query(&client, &credential).await;
    eprintln!(
        "FURA_QQ_TRACK_LIKE_TRUE_GATE login_type=2 result={}",
        if passed { "PASS" } else { "BLOCKED" }
    );
}

#[test]
fn classification_labels_are_stable_and_diagnostics_safe() {
    assert_eq!(GateClassification::Pass.label(), "PASS");
    assert_eq!(
        GateClassification::BlockedByProtocol.label(),
        "BLOCKED_BY_PROTOCOL"
    );
    assert_eq!(
        GateClassification::BlockedByRiskControl.label(),
        "BLOCKED_BY_RISK_CONTROL"
    );
    assert_eq!(
        GateClassification::ImplementationDefect.label(),
        "IMPLEMENTATION_DEFECT"
    );
    assert_eq!(
        refresh_failure_detail(CredentialRefreshError::NotRefreshable),
        "not_refreshable"
    );
    assert_eq!(
        refresh_failure_detail(CredentialRefreshError::InvalidResponse),
        "invalid_response"
    );
    assert_eq!(
        refresh_failure_detail(CredentialRefreshError::UpstreamRejected),
        "upstream_rejected"
    );
    assert_eq!(
        refresh_failure_detail(CredentialRefreshError::IncompleteRotation),
        "incomplete_rotation"
    );
    assert_eq!(
        refresh_failure_detail(CredentialRefreshError::RiskControl),
        "risk_control"
    );
    assert_eq!(
        classify_qr_error(&QqQrError::Credential(LoginCredentialError::Upstream {
            global_code: 0,
            login_code: Some(20_272),
        })),
        GateClassification::BlockedByRiskControl
    );
    assert_eq!(
        qq_login_failure_detail(&QqQrError::Credential(LoginCredentialError::Upstream {
            global_code: 123_456,
            login_code: Some(654_321),
        },)),
        "credential_upstream_rejected"
    );
    for (presence, label) in [
        (EncryptedIdentityPresence::Unobserved, "unobserved"),
        (EncryptedIdentityPresence::Missing, "missing"),
        (EncryptedIdentityPresence::Null, "null"),
        (EncryptedIdentityPresence::Empty, "empty"),
        (EncryptedIdentityPresence::Present, "present"),
        (EncryptedIdentityPresence::Other, "other"),
    ] {
        assert_eq!(presence.label(), label);
    }
}
