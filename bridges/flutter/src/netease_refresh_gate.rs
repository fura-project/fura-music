//! Opt-in, Rust-only NetEase refresh evidence gate.
//!
//! The default application build has no caller for this executable. It opens
//! one isolated official-Web profile, accepts no credential input, performs no
//! vault I/O, sends at most one refresh, and verifies the candidate against the
//! source account without printing either identity or credential material.

#[cfg(all(target_os = "linux", not(test)))]
#[allow(dead_code)] // The standalone gate uses only the NetEase capture entry.
mod linux_system_chromium;

#[cfg(all(target_os = "linux", not(test)))]
mod live {
    use std::io::{self, Write};
    use std::sync::Arc;
    use std::sync::atomic::{AtomicBool, Ordering};

    use netease_client::{
        Credential, CredentialRefreshError, Error, HttpsTransport, NeteaseClient,
    };
    use zeroize::Zeroize;

    use super::linux_system_chromium::{
        self, CaptureFailure, CapturedNeteaseSession, NeteaseCaptureObservation,
        NeteaseCookieObservation,
    };

    const AUTHORIZE_CAPTURE: &str = "AUTHORIZE ONE NETEASE WEB CAPTURE";
    const AUTHORIZE_REFRESH: &str = "AUTHORIZE ONE NETEASE REFRESH";

    #[derive(Clone, Copy, Debug, Eq, PartialEq)]
    enum Classification {
        Pass,
        BlockedByProtocol,
        BlockedByRiskControl,
        ImplementationDefect,
        NotRun,
    }

    impl Classification {
        const fn label(self) -> &'static str {
            match self {
                Self::Pass => "PASS",
                Self::BlockedByProtocol => "BLOCKED_BY_PROTOCOL",
                Self::BlockedByRiskControl => "BLOCKED_BY_RISK_CONTROL",
                Self::ImplementationDefect => "IMPLEMENTATION_DEFECT",
                Self::NotRun => "NOT_RUN",
            }
        }
    }

    fn report(classification: Classification, phase: &str, detail: &str) {
        eprintln!(
            "FURA_NETEASE_REFRESH_GATE classification={} phase={phase} detail={detail}",
            classification.label()
        );
    }

    fn approve(prompt: &str) -> bool {
        println!("Type exactly: {prompt}");
        print!("> ");
        if io::stdout().flush().is_err() {
            return false;
        }
        let mut input = String::new();
        io::stdin()
            .read_line(&mut input)
            .is_ok_and(|_| input.trim() == prompt)
    }

    const fn classify_account_error(error: Error) -> Classification {
        match error {
            Error::RateLimited
            | Error::SecurityVerificationRequired
            | Error::SecondaryVerificationRequired
            | Error::VerificationRejected
            | Error::AccountRestricted => Classification::BlockedByRiskControl,
            Error::CredentialRejected | Error::AuthenticationRequired => {
                Classification::BlockedByProtocol
            }
            Error::TemporaryNetworkFailure
            | Error::ProtocolUnavailable
            | Error::ResponseShapeMismatch
            | Error::ResponseBound
            | Error::InputBound
            | Error::UpstreamUnknown
            | Error::EntitlementDenied
            | Error::CopyrightRestricted
            | Error::RegionRestricted
            | Error::TrackUnavailable => Classification::BlockedByProtocol,
        }
    }

    const fn classify_refresh_error(error: CredentialRefreshError) -> Classification {
        match error {
            CredentialRefreshError::RateLimited
            | CredentialRefreshError::RiskControl
            | CredentialRefreshError::SecondaryVerificationRequired => {
                Classification::BlockedByRiskControl
            }
            CredentialRefreshError::NotRefreshable
            | CredentialRefreshError::Network
            | CredentialRefreshError::CredentialRejected
            | CredentialRefreshError::ProtocolUnavailable
            | CredentialRefreshError::InvalidResponse
            | CredentialRefreshError::IncompleteRotation
            | CredentialRefreshError::NoRotation => Classification::BlockedByProtocol,
        }
    }

    const fn capture_detail(failure: CaptureFailure) -> &'static str {
        match failure {
            CaptureFailure::BrowserUnavailable => "BROWSER_UNAVAILABLE",
            CaptureFailure::BrowserLaunchFailed => "BROWSER_LAUNCH_FAILED",
            CaptureFailure::ProfileSetupFailed => "PROFILE_SETUP_FAILED",
            CaptureFailure::DevtoolsUnavailable => "DEVTOOLS_UNAVAILABLE",
            CaptureFailure::DevtoolsInvalid => "DEVTOOLS_INVALID",
            CaptureFailure::OfficialTargetUnavailable => "OFFICIAL_TARGET_UNAVAILABLE",
            CaptureFailure::BrowserClosed => "BROWSER_CLOSED",
            CaptureFailure::InvalidCredential => "INVALID_CREDENTIAL",
            CaptureFailure::TimedOut => "TIMED_OUT",
            CaptureFailure::Cancelled => "CANCELLED",
            CaptureFailure::CleanupFailed => "CLEANUP_FAILED",
        }
    }

    async fn capture_once() -> Result<CapturedNeteaseSession, CaptureFailure> {
        let current = Arc::new(AtomicBool::new(true));
        let signal_current = Arc::clone(&current);
        let cancellation = tokio::spawn(async move {
            let interrupt = tokio::signal::ctrl_c().await;
            if interrupt.is_ok() {
                signal_current.store(false, Ordering::SeqCst);
            }
        });
        let captured =
            linux_system_chromium::capture_netease_session(|| current.load(Ordering::SeqCst)).await;
        cancellation.abort();
        let _ = cancellation.await;
        captured
    }

    fn report_cookie_observation(name: &str, value: NeteaseCookieObservation) {
        eprintln!(
            "FURA_NETEASE_REFRESH_GATE phase=login_capture cookie={name} present={} domain_music={} domain_parent_163={} path_root={} path_non_root={} expiry_present={} http_only={} secure={}",
            value.present,
            value.music_domain,
            value.parent_163_domain,
            value.root_path,
            value.non_root_path,
            value.expiry_present,
            value.http_only,
            value.secure,
        );
    }

    fn report_capture_observation(value: NeteaseCaptureObservation) {
        for (name, observation) in [
            ("MUSIC_U", value.music_u),
            ("MUSIC_R_U", value.music_r_u),
            ("CSRF", value.csrf),
            ("OS", value.os),
            ("APPVER", value.appver),
            ("BUILDVER", value.buildver),
            ("DEVICE_ID", value.device_id),
            ("NMTID", value.nmtid),
            ("WNMCID", value.wnmcid),
            ("NTES_NUID", value.ntes_nuid),
            ("REMEMBER_ME", value.remember_me),
            ("ANTI_CHEAT_TOKEN", value.anti_cheat_token),
        ] {
            report_cookie_observation(name, observation);
        }
    }

    pub async fn run() {
        eprintln!("FURA_NETEASE_REFRESH_GATE vault_read=false vault_write=false refresh_budget=1");
        if !approve(AUTHORIZE_CAPTURE) {
            report(Classification::NotRun, "capture_authority", "DECLINED");
            return;
        }
        eprintln!("FURA_NETEASE_REFRESH_GATE interaction=OFFICIAL_WEB_LOGIN status=READY");
        let mut captured = match capture_once().await {
            Ok(captured) => captured,
            Err(failure) => {
                report(
                    Classification::ImplementationDefect,
                    "browser_capture",
                    capture_detail(failure),
                );
                return;
            }
        };
        report_capture_observation(captured.observation);
        let mut bytes = captured.take_credential();
        let credential = Credential::from_browser_cookie_header(&bytes);
        bytes.zeroize();
        let credential = match credential {
            Ok(credential) => credential,
            Err(_) => {
                report(
                    Classification::ImplementationDefect,
                    "credential_parse",
                    "INVALID_CAPTURE",
                );
                return;
            }
        };
        eprintln!(
            "FURA_NETEASE_REFRESH_GATE phase=refresh_material observed_music_r_u={}",
            credential.has_refresh_material()
        );
        if !credential.has_refresh_material() {
            report(
                Classification::BlockedByProtocol,
                "refresh_material",
                "MUSIC_R_U_MISSING",
            );
            return;
        }
        if !approve(AUTHORIZE_REFRESH) {
            report(Classification::NotRun, "refresh_authority", "DECLINED");
            return;
        }

        let transport = match HttpsTransport::new() {
            Ok(transport) => transport,
            Err(_) => {
                report(
                    Classification::ImplementationDefect,
                    "transport",
                    "UNAVAILABLE",
                );
                return;
            }
        };
        let client = NeteaseClient::new(transport);
        let source_account = match client.account(&credential).await {
            Ok(account) => account,
            Err(error) => {
                report(
                    classify_account_error(error),
                    "source_verification",
                    "FAILED",
                );
                return;
            }
        };
        let (candidate, refresh_observation) =
            match client.refresh_credential_observed(&credential).await {
                Ok(candidate) => candidate,
                Err(error) => {
                    report(classify_refresh_error(error), "refresh", "FAILED");
                    return;
                }
            };
        eprintln!(
            "FURA_NETEASE_REFRESH_GATE phase=refresh_response outer=accepted business=accepted music_u_rotation={} music_r_u_rotation={} csrf_rotation={} candidate_next_refreshable={}",
            refresh_observation.music_u.label(),
            refresh_observation.music_r_u.label(),
            refresh_observation.csrf.label(),
            refresh_observation.candidate_next_refreshable,
        );
        match client.account(&candidate).await {
            Ok(account) if account.id == source_account.id => {
                report(Classification::Pass, "account_verification", "ACCEPTED");
            }
            Ok(_) => report(
                Classification::BlockedByRiskControl,
                "account_verification",
                "ACCOUNT_MISMATCH",
            ),
            Err(error) => report(
                classify_account_error(error),
                "account_verification",
                "FAILED",
            ),
        }
    }
}

#[cfg(all(target_os = "linux", not(test)))]
fn main() {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build();
    match runtime {
        Ok(runtime) => runtime.block_on(live::run()),
        Err(_) => eprintln!(
            "FURA_NETEASE_REFRESH_GATE classification=IMPLEMENTATION_DEFECT phase=runtime detail=UNAVAILABLE"
        ),
    }
}

#[cfg(any(not(target_os = "linux"), test))]
fn main() {
    println!("FURA_NETEASE_REFRESH_GATE classification=NOT_RUN phase=platform detail=UNSUPPORTED");
}
