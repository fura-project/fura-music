use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::time::Duration;

use qqmusic_client::{
    Credential, CredentialRefreshError, CredentialVerificationError, LoginCredentialError,
    QqMusicClient, QqQrError, QqQrPollResult, QrImageMediaType, ReqwestTransport,
};

const ENABLE_ENV: &str = "FURA_QQ_TYPE2_REFRESH_PROTOCOL_GATE";
const QR_PATH_ENV: &str = "FURA_QQ_TYPE2_REFRESH_QR_PATH";

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

    let deadline = tokio::time::Instant::now() + Duration::from_secs(180);
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
            report(classify_qr_error(&error), "qq_login", "failed");
            None
        }
    }
}

async fn refresh_and_verify_once(
    client: &QqMusicClient<ReqwestTransport>,
    credential: &Credential,
) {
    let refreshed = match client.refresh_credential(credential).await {
        Ok(credential) => credential,
        Err(
            CredentialRefreshError::RateLimited
            | CredentialRefreshError::RiskControl
            | CredentialRefreshError::SecondaryVerificationRequired
            | CredentialRefreshError::AccountChanged,
        ) => {
            report(
                GateClassification::BlockedByRiskControl,
                "refresh",
                "risk-control or account boundary",
            );
            return;
        }
        Err(_) => {
            report(
                GateClassification::BlockedByProtocol,
                "refresh",
                "request was not accepted or material was incomplete",
            );
            return;
        }
    };

    match client.verify_credential(&refreshed).await {
        Ok(_) => report(GateClassification::Pass, "account_verification", "accepted"),
        Err(error) => report(
            classify_verification_error(&error),
            "account_verification",
            "failed",
        ),
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
    let client = QqMusicClient::new(transport);
    let Some(credential) = acquire_disposable_qq_credential(&client, qr_path).await else {
        return;
    };
    refresh_and_verify_once(&client, &credential).await;
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
        classify_qr_error(&QqQrError::Credential(LoginCredentialError::Upstream {
            global_code: 0,
            login_code: Some(20_272),
        })),
        GateClassification::BlockedByRiskControl
    );
}
