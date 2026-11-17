//! Opt-in, Rust-only NetEase Desktop-EAPI session evidence gate.
//!
//! This executable is absent from default application builds. It creates one
//! disposable QR session with a fresh Fura-owned installation identity, sends
//! at most one refresh, performs one same-account verification operation, and
//! never reads or writes the production credential vault.

#[cfg(all(target_os = "linux", not(test)))]
mod live {
    use std::fs::{self, OpenOptions};
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    use std::path::{Path, PathBuf};
    use std::time::{Duration, Instant};

    use netease_client::{
        DesktopEapiInstallationIdentity, DesktopEapiQrPoll, Error, HttpsTransport, NeteaseClient,
    };

    const AUTHORITY_ARGUMENT: &str = "--authorized-disposable-session";
    const QR_PATH_ENV: &str = "FURA_NETEASE_EAPI_QR_PATH";
    const POLL_INTERVAL: Duration = Duration::from_secs(2);
    const QR_LIFETIME: Duration = Duration::from_secs(180);

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

    struct TransientQr {
        path: PathBuf,
    }

    impl Drop for TransientQr {
        fn drop(&mut self) {
            let _ = fs::remove_file(&self.path);
        }
    }

    fn report(classification: Classification, phase: &str, detail: &str) {
        eprintln!(
            "FURA_NETEASE_EAPI_GATE classification={} phase={phase} detail={detail}",
            classification.label()
        );
    }

    const fn classify_error(error: Error) -> Classification {
        match error {
            Error::RateLimited
            | Error::SecurityVerificationRequired
            | Error::SecondaryVerificationRequired
            | Error::VerificationRejected
            | Error::AccountRestricted => Classification::BlockedByRiskControl,
            Error::TemporaryNetworkFailure
            | Error::ProtocolUnavailable
            | Error::ResponseShapeMismatch
            | Error::AuthenticationRequired
            | Error::CredentialRejected
            | Error::UpstreamUnknown
            | Error::ResponseBound
            | Error::InputBound
            | Error::EntitlementDenied
            | Error::CopyrightRestricted
            | Error::RegionRestricted
            | Error::TrackUnavailable => Classification::BlockedByProtocol,
        }
    }

    const fn error_detail(error: Error) -> &'static str {
        match error {
            Error::AuthenticationRequired => "AUTHENTICATION_REQUIRED",
            Error::CredentialRejected => "CREDENTIAL_REJECTED",
            Error::RateLimited => "RATE_LIMITED",
            Error::SecurityVerificationRequired => "SECURITY_VERIFICATION_REQUIRED",
            Error::SecondaryVerificationRequired => "SECONDARY_VERIFICATION_REQUIRED",
            Error::VerificationRejected => "VERIFICATION_REJECTED",
            Error::AccountRestricted => "ACCOUNT_RESTRICTED",
            Error::ProtocolUnavailable => "PROTOCOL_UNAVAILABLE",
            Error::ResponseShapeMismatch => "RESPONSE_SHAPE_MISMATCH",
            Error::TemporaryNetworkFailure => "TEMPORARY_NETWORK_FAILURE",
            Error::UpstreamUnknown => "UPSTREAM_UNKNOWN",
            Error::InputBound => "INPUT_BOUND",
            Error::ResponseBound => "RESPONSE_BOUND",
            Error::EntitlementDenied => "ENTITLEMENT_DENIED",
            Error::CopyrightRestricted => "COPYRIGHT_RESTRICTED",
            Error::RegionRestricted => "REGION_RESTRICTED",
            Error::TrackUnavailable => "TRACK_UNAVAILABLE",
        }
    }

    fn authorized() -> bool {
        std::env::args().any(|argument| argument == AUTHORITY_ARGUMENT)
    }

    fn qr_output_path() -> Option<PathBuf> {
        let path = std::env::var_os(QR_PATH_ENV).map(PathBuf::from)?;
        if !path.is_absolute()
            || path.extension().and_then(|value| value.to_str()) != Some("png")
            || !path.parent().is_some_and(Path::is_dir)
        {
            return None;
        }
        Some(path)
    }

    fn write_qr(path: PathBuf, bytes: &[u8]) -> Result<TransientQr, ()> {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)
            .map_err(|_| ())?;
        file.write_all(bytes).map_err(|_| ())?;
        file.sync_all().map_err(|_| ())?;
        Ok(TransientQr { path })
    }

    pub async fn run() {
        eprintln!(
            "FURA_NETEASE_EAPI_GATE vault_read=false vault_write=false qr_budget=1 refresh_budget=1 same_account_verification_budget=1 retry=false fallback=false"
        );
        if !authorized() {
            report(Classification::NotRun, "authority", "MISSING");
            return;
        }
        let Some(qr_path) = qr_output_path() else {
            report(
                Classification::ImplementationDefect,
                "qr_output",
                "INVALID_PATH",
            );
            return;
        };
        let identity = match DesktopEapiInstallationIdentity::generate() {
            Ok(identity) => identity,
            Err(error) => {
                report(
                    Classification::ImplementationDefect,
                    "installation_identity",
                    error_detail(error),
                );
                return;
            }
        };
        let transport = match HttpsTransport::new() {
            Ok(transport) => transport,
            Err(error) => {
                report(
                    Classification::ImplementationDefect,
                    "transport",
                    error_detail(error),
                );
                return;
            }
        };
        let client = NeteaseClient::new(transport);
        let mut key = match client.desktop_eapi_qr_key(&identity).await {
            Ok(key) => key,
            Err(error) => {
                report(classify_error(error), "qr_key", error_detail(error));
                return;
            }
        };
        let qr_bytes = match key.image_png() {
            Ok(bytes) => bytes,
            Err(error) => {
                report(
                    Classification::ImplementationDefect,
                    "qr_encode",
                    error_detail(error),
                );
                return;
            }
        };
        let qr_file = match write_qr(qr_path, &qr_bytes) {
            Ok(file) => file,
            Err(()) => {
                report(
                    Classification::ImplementationDefect,
                    "qr_output",
                    "WRITE_FAILED",
                );
                return;
            }
        };
        eprintln!("FURA_NETEASE_EAPI_GATE interaction=SCAN_QR status=READY");
        let started = Instant::now();
        let mut poll_count = 0_u32;
        let candidate = loop {
            if started.elapsed() >= QR_LIFETIME {
                report(Classification::BlockedByProtocol, "qr_login", "TIMED_OUT");
                return;
            }
            poll_count = poll_count.saturating_add(1);
            let poll = tokio::select! {
                result = client.desktop_eapi_qr_poll(&mut key) => result,
                signal = tokio::signal::ctrl_c() => {
                    let _ = signal;
                    report(Classification::NotRun, "qr_login", "CANCELLED");
                    return;
                }
            };
            match poll {
                Ok(DesktopEapiQrPoll::Waiting) => {}
                Ok(DesktopEapiQrPoll::Scanned) => {
                    eprintln!("FURA_NETEASE_EAPI_GATE interaction=CONFIRM_LOGIN status=WAITING");
                }
                Ok(DesktopEapiQrPoll::Expired) => {
                    report(Classification::BlockedByProtocol, "qr_login", "EXPIRED");
                    return;
                }
                Ok(DesktopEapiQrPoll::Confirmed(candidate)) => break candidate,
                Err(error) => {
                    report(classify_error(error), "qr_login", error_detail(error));
                    return;
                }
            }
            tokio::time::sleep(POLL_INTERVAL).await;
        };
        drop(qr_file);
        let observation = candidate.observation();
        eprintln!(
            "FURA_NETEASE_EAPI_GATE phase=qr_login outcome=AUTHENTICATED qr_request_count=1 poll_count={poll_count} music_u_present={} music_r_u_present={} csrf_present={} nmtid_present={}",
            candidate.has_music_u(),
            candidate.has_music_r_u(),
            candidate.has_csrf(),
            candidate.has_nmtid(),
        );
        for (name, value) in [
            ("MUSIC_U", observation.music_u),
            ("MUSIC_R_U", observation.music_r_u),
            ("CSRF", observation.csrf),
            ("NMTID", observation.nmtid),
        ] {
            eprintln!(
                "FURA_NETEASE_EAPI_GATE phase=qr_cookie cookie={name} present={} domain_music={} domain_parent_163={} path_root={} path_non_root={} expiry_present={} http_only={} secure={}",
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
        if !candidate.has_music_u() || !candidate.is_next_refreshable() {
            report(
                Classification::BlockedByProtocol,
                "qr_login",
                "LOGIN_SESSION_MISSING",
            );
            return;
        }

        let source_account = match client.desktop_eapi_candidate_account(&candidate).await {
            Ok(account) => account,
            Err(error) => {
                report(classify_error(error), "source_account", error_detail(error));
                return;
            }
        };
        let (refreshed, refresh) = match client
            .refresh_desktop_eapi_candidate_observed(&candidate)
            .await
        {
            Ok(result) => result,
            Err(error) => {
                report(classify_error(error), "refresh", error_detail(error));
                return;
            }
        };
        eprintln!(
            "FURA_NETEASE_EAPI_GATE phase=refresh_response refresh_request_count=1 music_u_rotation={} music_r_u_rotation={} csrf_rotation={} nmtid_rotation={} candidate_next_refreshable={}",
            refresh.music_u.label(),
            refresh.music_r_u.label(),
            refresh.csrf.label(),
            refresh.nmtid.label(),
            refresh.candidate_next_refreshable,
        );
        if !refresh.candidate_next_refreshable {
            report(
                Classification::BlockedByProtocol,
                "refresh",
                "CANDIDATE_NOT_REFRESHABLE",
            );
            return;
        }
        match client.desktop_eapi_candidate_account(&refreshed).await {
            Ok(account) if account.id == source_account.id => {
                eprintln!(
                    "FURA_NETEASE_EAPI_GATE phase=account_verification account_read_count=2 same_account_verification_count=1 outcome=ACCEPTED"
                );
                report(Classification::Pass, "account_verification", "ACCEPTED");
            }
            Ok(_) => report(
                Classification::BlockedByRiskControl,
                "account_verification",
                "ACCOUNT_MISMATCH",
            ),
            Err(error) => report(
                classify_error(error),
                "account_verification",
                error_detail(error),
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
            "FURA_NETEASE_EAPI_GATE classification=IMPLEMENTATION_DEFECT phase=runtime detail=UNAVAILABLE"
        ),
    }
}

#[cfg(any(not(target_os = "linux"), test))]
fn main() {
    println!("FURA_NETEASE_EAPI_GATE classification=NOT_RUN phase=platform detail=UNSUPPORTED");
}

#[cfg(test)]
mod tests {
    #[test]
    fn gate_is_feature_isolated_secret_safe_and_production_is_family_routed() {
        let manifest = include_str!("../Cargo.toml");
        assert!(manifest.contains("netease-eapi-session-gate = ["));
        assert!(manifest.contains("name = \"netease-eapi-session-gate\""));
        assert!(manifest.contains("required-features = [\"netease-eapi-session-gate\"]"));

        let source = include_str!("netease_eapi_session_gate.rs");
        for forbidden in [
            "format!(\"{candidate:?}\")",
            "format!(\"{identity:?}\")",
            "std::env::var(\"MUSIC_U\")",
            "std::env::var(\"MUSIC_R_U\")",
            "std::env::var(\"__csrf\")",
            "std::env::var(\"NMTID\")",
        ] {
            assert!(!source.contains(forbidden));
        }
        assert!(source.contains("retry=false fallback=false"));
        assert!(source.contains("refresh_budget=1"));
        assert!(source.contains("same_account_verification_budget=1"));

        let production = include_str!("native_netease.rs");
        assert!(production.contains("const fn netease_refresh_activation_enabled() -> bool"));
        assert!(production.contains("true\n}"));

        let client = include_str!("../../../crates/netease-client/src/desktop_eapi_session.rs");
        assert!(client.contains("NeteaseSessionFamily::DesktopEapi"));
        assert!(client.contains("CredentialRefreshError::NotRefreshable"));
    }
}
