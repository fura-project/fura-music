//! Explicit installed-Chrome evidence against a synthetic official-site surrogate.
//! No live provenance, account authentication, external DNS, media or Range claim.

use super::*;
use kugou_client::{
    Response,
    web_playback_candidate::{CapturedWebRequest, MediaFormat, WebPlaybackResponse, WebQuality},
};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::{ChildStdin, ChildStdout};

const TEST_NAME: &str = "linux_system_chromium::kugou::runtime_tests::offline_installed_chrome_intercept_abort_then_single_rust_tls_replay";
const WORKER: &str = "FURA_KUGOU_OFFLINE_RUNTIME_WORKER";
const HASH: &str = "11111111111111111111111111111111";
const SYNTHETIC_COOKIE: &str = "KugooID=42; t=synthetic-token";
const IO_BOUND: Duration = Duration::from_secs(5);
const CAPTURE_BOUND: Duration = Duration::from_secs(30);
const CLEANUP_BOUND: Duration = Duration::from_secs(35);

type RuntimeResult<T> = Result<T, &'static str>;

// Re-exec avoids process-global environment mutation and never opens a real
// default profile, even to compare its contents. Only synthetic sentinels are read.
#[tokio::test]
#[ignore = "explicit offline installed google-chrome-stable, Python and OpenSSL runtime"]
async fn offline_installed_chrome_intercept_abort_then_single_rust_tls_replay() {
    let result = if env::var(WORKER).as_deref() == Ok("1") {
        run_worker().await
    } else {
        run_isolated_worker().await
    };
    if let Err(category) = result {
        eprintln!("KUGOU_RUNTIME_FAILURE={category}");
        panic!("KUGOU_OFFLINE_RUNTIME_FAILED");
    }
}

async fn run_isolated_worker() -> RuntimeResult<()> {
    let home = tempfile::tempdir().map_err(|_| "ISOLATION_SETUP_FAILED")?;
    let runtime = tempfile::tempdir().map_err(|_| "ISOLATION_SETUP_FAILED")?;
    let sentinel = home.path().join(".config/google-chrome/Default/sentinel");
    std::fs::create_dir_all(sentinel.parent().ok_or("ISOLATION_SETUP_FAILED")?)
        .map_err(|_| "ISOLATION_SETUP_FAILED")?;
    std::fs::write(&sentinel, b"synthetic-default-profile-untouched")
        .map_err(|_| "ISOLATION_SETUP_FAILED")?;
    let output = Command::new(env::current_exe().map_err(|_| "WORKER_UNAVAILABLE")?)
        .args([
            "--exact",
            TEST_NAME,
            "--ignored",
            "--nocapture",
            "--test-threads=1",
        ])
        .env(WORKER, "1")
        .env("HOME", home.path())
        .env("XDG_CONFIG_HOME", home.path().join(".config"))
        .env("CHROME_CONFIG_HOME", home.path().join(".config"))
        .env("XDG_CACHE_HOME", home.path().join(".cache"))
        .env("XDG_DATA_HOME", home.path().join(".local/share"))
        .env("XDG_RUNTIME_DIR", runtime.path())
        .env_remove("FURA_NETEASE_WEB_REFRESH_DEBUG")
        .env_remove("CHROME_USER_FLAGS")
        .env_remove("CHROME_USER_DATA_DIR")
        .stdin(Stdio::null())
        .kill_on_drop(true)
        .output()
        .await
        .map_err(|_| "WORKER_UNAVAILABLE")?;
    // The worker uses only fixed categories. Do not forward arbitrary subprocess
    // diagnostics, panic details, browser output or fixture control messages.
    let diagnostics = String::from_utf8_lossy(&output.stderr);
    for line in diagnostics
        .lines()
        .filter(|line| line.starts_with("KUGOU_RUNTIME_"))
    {
        eprintln!("{line}");
    }
    if !output.status.success()
        || !diagnostics
            .lines()
            .any(|line| line == "KUGOU_RUNTIME_WORKER=FINISHED")
    {
        return Err("ISOLATED_WORKER_FAILED");
    }
    if std::fs::read(&sentinel).map_err(|_| "DEFAULT_PROFILE_CHANGED")?
        != b"synthetic-default-profile-untouched"
        || std::fs::read_dir(sentinel.parent().ok_or("DEFAULT_PROFILE_CHANGED")?)
            .map_err(|_| "DEFAULT_PROFILE_CHANGED")?
            .count()
            != 1
    {
        return Err("DEFAULT_PROFILE_CHANGED");
    }
    if std::fs::read_dir(runtime.path())
        .map_err(|_| "PROFILE_NOT_DELETED")?
        .next()
        .is_some()
    {
        return Err("PROFILE_NOT_DELETED");
    }
    eprintln!("KUGOU_RUNTIME_DEFAULT_PROFILE=UNTOUCHED");
    eprintln!("KUGOU_RUNTIME_RESULT=PASS");
    Ok(())
}

struct Fixture {
    child: Child,
    input: ChildStdin,
    output: BufReader<ChildStdout>,
    _certificates: TempDir,
}

impl Fixture {
    async fn start() -> RuntimeResult<Self> {
        let certificates = tempfile::tempdir().map_err(|_| "FIXTURE_SETUP_FAILED")?;
        let mut child = Command::new("python3")
            .arg(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/src/linux_system_chromium/kugou/runtime_fixture.py"
            ))
            .arg(certificates.path())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .map_err(|_| "FIXTURE_UNAVAILABLE")?;
        let input = child.stdin.take().ok_or("FIXTURE_CONTROL_FAILED")?;
        let output = BufReader::new(child.stdout.take().ok_or("FIXTURE_CONTROL_FAILED")?);
        Ok(Self {
            child,
            input,
            output,
            _certificates: certificates,
        })
    }

    async fn message(&mut self, bound: Duration) -> RuntimeResult<Value> {
        let mut line = String::new();
        let size = timeout(bound, self.output.read_line(&mut line))
            .await
            .map_err(|_| "FIXTURE_CONTROL_TIMEOUT")?
            .map_err(|_| "FIXTURE_CONTROL_FAILED")?;
        if size == 0 || size > 16 * 1024 {
            return Err("FIXTURE_CONTROL_FAILED");
        }
        serde_json::from_str(&line).map_err(|_| "FIXTURE_CONTROL_FAILED")
    }

    async fn counts(&mut self, replayed: bool) -> RuntimeResult<()> {
        timeout(IO_BOUND, self.input.write_all(b"COUNTS\n"))
            .await
            .map_err(|_| "FIXTURE_CONTROL_TIMEOUT")?
            .map_err(|_| "FIXTURE_CONTROL_FAILED")?;
        let counts = self.message(IO_BOUND).await?;
        if counts
            != json!({"page":1, "api":u8::from(replayed), "rust":u8::from(replayed),
            "browser":0, "range":0, "rejected":0})
        {
            return Err(if replayed {
                "REPLAY_REQUEST_COUNT_INVALID"
            } else {
                "BROWSER_REQUEST_ESCAPED_ABORT"
            });
        }
        Ok(())
    }

    async fn stop(&mut self) -> RuntimeResult<()> {
        let stopped = timeout(IO_BOUND, async {
            self.input.write_all(b"STOP\n").await?;
            self.child.wait().await
        })
        .await;
        if matches!(stopped, Ok(Ok(status)) if status.success()) {
            return Ok(());
        }
        self.child
            .start_kill()
            .map_err(|_| "FIXTURE_CLEANUP_FAILED")?;
        timeout(IO_BOUND, self.child.wait())
            .await
            .map_err(|_| "FIXTURE_CLEANUP_FAILED")?
            .map_err(|_| "FIXTURE_CLEANUP_FAILED")?;
        Err("FIXTURE_CLEANUP_FAILED")
    }
}

struct LoopbackTlsTransport(reqwest::Client);

impl WebPlaybackTransport for LoopbackTlsTransport {
    async fn send_web(
        &self,
        request: &CapturedWebRequest,
    ) -> Result<WebPlaybackResponse, WebPlaybackError> {
        let expected = format!(
            "https://wwwapi.kugou.com/play/songinfo?hash={HASH}&album_id=7&album_audio_id=9&mid=synthetic-mid&dfid=synthetic-dfid&userid=42&token=synthetic-token&signature=00000000000000000000000000000000"
        );
        if request.url() != expected || request.cookie_header() != SYNTHETIC_COOKIE {
            return Err(WebPlaybackError::InvalidCapture);
        }
        let mut replay = self
            .0
            .get(request.url())
            .header("Cookie", request.cookie_header())
            .header("X-Synthetic-Owner", "Rust");
        for (name, value) in request.replay_headers() {
            replay = replay.header(name, value);
        }
        let mut response = replay.send().await.map_err(|_| WebPlaybackError::Network)?;
        let status = response.status().as_u16();
        let content_type = response
            .headers()
            .get("Content-Type")
            .and_then(|value| value.to_str().ok())
            .map(str::to_owned);
        let mut body = Vec::new();
        while let Some(chunk) = response
            .chunk()
            .await
            .map_err(|_| WebPlaybackError::Network)?
        {
            if body.len() + chunk.len() > 16 * 1024 {
                return Err(WebPlaybackError::ResponseBound);
            }
            body.extend_from_slice(&chunk);
        }
        Ok(WebPlaybackResponse {
            response: Response {
                status,
                content_type,
                body,
            },
            security_challenge: false,
        })
    }
}

async fn run_worker() -> RuntimeResult<()> {
    let installed =
        find_in_path("google-chrome-stable").ok_or("GOOGLE_CHROME_STABLE_UNAVAILABLE")?;
    let browser = discover_browser().map_err(|_| "BROWSER_DISCOVERY_FAILED")?;
    if browser.binary != std::fs::canonicalize(installed).map_err(|_| "BROWSER_DISCOVERY_FAILED")? {
        return Err("WRONG_INSTALLED_BROWSER");
    }
    let mut fixture = Fixture::start().await?;
    let result = run_capture(&mut fixture, &browser).await;
    let cleanup = fixture.stop().await;
    cleanup?;
    result?;
    eprintln!("KUGOU_RUNTIME_SOURCE=SYNTHETIC_OFFICIAL_SITE_SURROGATE");
    eprintln!("KUGOU_RUNTIME_WORKER=FINISHED");
    Ok(())
}

async fn run_capture(fixture: &mut Fixture, browser: &BrowserCandidate) -> RuntimeResult<()> {
    let ready = fixture.message(Duration::from_secs(65)).await?;
    let port = ready["port"]
        .as_u64()
        .and_then(|port| u16::try_from(port).ok())
        .filter(|port| *port != 0)
        .ok_or("FIXTURE_PORT_INVALID")?;
    let spki = ready["spki"]
        .as_str()
        .filter(|value| {
            value.len() == 44
                && value
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'+' | b'/' | b'='))
        })
        .ok_or("FIXTURE_CERTIFICATE_INVALID")?;
    let root = reqwest::Certificate::from_pem(
        ready["root_pem"]
            .as_str()
            .ok_or("FIXTURE_CERTIFICATE_INVALID")?
            .as_bytes(),
    )
    .map_err(|_| "FIXTURE_CERTIFICATE_INVALID")?;
    let address = std::net::SocketAddr::from((std::net::Ipv4Addr::LOCALHOST, port));
    let client = reqwest::Client::builder()
        .https_only(true)
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .retry(reqwest::retry::never())
        .timeout(IO_BOUND)
        .add_root_certificate(root)
        .resolve("wwwapi.kugou.com", address)
        .build()
        .map_err(|_| "TLS_TRANSPORT_SETUP_FAILED")?;
    let owner = AuthenticatedStandardCandidate::new(LoopbackTlsTransport(client));
    let id = TrackId::new(
        provider_kugou::provider_id(),
        format!("v1:9:{HASH}:8:180:7"),
    )
    .map_err(|_| "SYNTHETIC_TRACK_INVALID")?;
    let attempt = owner
        .begin_capture(&id)
        .map_err(|_| "CAPTURE_ADMISSION_FAILED")?;
    if owner.begin_capture(&id).err() != Some(WebPlaybackError::AttemptConsumed) {
        return Err("CAPTURE_BUDGET_NOT_CONSUMED");
    }
    let args = vec![
        "--headless=new".into(),
        "--disable-gpu".into(),
        "--no-proxy-server".into(),
        "--disable-background-networking".into(),
        "--disable-component-update".into(),
        "--disable-sync".into(),
        "--disable-default-apps".into(),
        "--disable-extensions".into(),
        "--disable-quic".into(),
        "--disable-domain-reliability".into(),
        "--disable-client-side-phishing-detection".into(),
        "--safebrowsing-disable-auto-update".into(),
        "--no-pings".into(),
        "--disable-breakpad".into(),
        "--metrics-recording-only".into(),
        "--dns-over-https-mode=off".into(),
        "--password-store=basic".into(),
        "--disable-features=OptimizationHints,MediaRouter,DialMediaRouteProvider".into(),
        format!("--ignore-certificate-errors-spki-list={spki}"),
        format!(
            "--host-resolver-rules=MAP www.kugou.com 127.0.0.1:{port}, MAP wwwapi.kugou.com 127.0.0.1:{port}, MAP * ~NOTFOUND"
        ),
    ];
    let is_current = || owner.is_capture_current(&attempt);
    let mut running = start_browser_at(browser, &is_current, "about:blank", &args)
        .await
        .map_err(|failure| match failure {
            CaptureFailure::CleanupFailed => "BROWSER_STARTUP_CLEANUP_FAILED",
            CaptureFailure::BrowserClosed => "BROWSER_CLOSED_DURING_STARTUP",
            _ => "BROWSER_STARTUP_FAILED",
        })?;
    let mut cdp = None;
    let captured = async {
        let mode = std::fs::metadata(&running.profile_path)
            .map_err(|_| "PROFILE_METADATA_FAILED")?
            .permissions()
            .mode()
            & 0o777;
        if mode != 0o700
            || running
                .profile_path
                .starts_with(env::var_os("HOME").ok_or("ISOLATION_SETUP_FAILED")?)
        {
            return Err("PROFILE_ISOLATION_FAILED");
        }
        let endpoint = discover_websocket_endpoint(running.port, &running.websocket_path)
            .await
            .map_err(|_| "CDP_DISCOVERY_FAILED")?;
        cdp = Some(
            CdpClient::connect(endpoint)
                .await
                .map_err(|_| "CDP_CONNECTION_FAILED")?,
        );
        timeout(
            CAPTURE_BOUND,
            capture_in_browser(
                cdp.as_mut().ok_or("CDP_CONNECTION_FAILED")?,
                &mut running.child,
                &is_current,
                OFFICIAL_PAGE,
            ),
        )
        .await
        .map_err(|_| "BROWSER_CAPTURE_TIMEOUT")?
        .map_err(|failure| match failure {
            GateFailure::Browser(CaptureFailure::DevtoolsInvalid) => "CDP_PROTOCOL_REJECTED",
            GateFailure::Playback(WebPlaybackError::InvalidCapture) => "BROWSER_CAPTURE_INVALID",
            GateFailure::Playback(WebPlaybackError::ProtocolUnsupported) => {
                "BROWSER_HEADERS_UNSUPPORTED"
            }
            GateFailure::Playback(WebPlaybackError::LoginRequired) => {
                "SYNTHETIC_PROFILE_COOKIE_MISSING"
            }
            GateFailure::Playback(WebPlaybackError::OfficialWebTrackIdentityUnproven) => {
                "BROWSER_FRAME_PROVENANCE_UNPROVEN"
            }
            GateFailure::Browser(CaptureFailure::DevtoolsUnavailable) => "CDP_COMMAND_TIMED_OUT",
            GateFailure::Browser(CaptureFailure::BrowserClosed) => "BROWSER_CLOSED_DURING_CAPTURE",
            _ => "BROWSER_CAPTURE_FAILED",
        })
    }
    .await;
    // Never finish/bind/replay until the production shutdown and deletion succeed.
    let cleanup = timeout(CLEANUP_BOUND, shutdown_browser(&mut running, cdp.as_mut())).await;
    if !matches!(cleanup, Ok(Ok(()))) {
        let _ = terminate_profile_processes(&running.profile_path, Signal::SIGKILL);
        let _ = running.child.start_kill();
        let _ = timeout(IO_BOUND, running.child.wait()).await;
        if wait_for_profile_processes(&running.profile_path, IO_BOUND).await
            && let Some(profile) = running.profile.take()
        {
            let _ = profile.close();
        }
        return Err("BROWSER_CLEANUP_FAILED");
    }
    if running.profile_path.exists()
        || running.profile.is_some()
        || !profile_processes(&running.profile_path).is_empty()
        || running
            .child
            .try_wait()
            .map_err(|_| "BROWSER_EXIT_UNPROVEN")?
            .is_none()
    {
        return Err("BROWSER_EXIT_OR_PROFILE_DELETION_UNPROVEN");
    }
    eprintln!("KUGOU_RUNTIME_PROFILE_MODE=0700");
    eprintln!("KUGOU_RUNTIME_BROWSER_EXIT=CONFIRMED");
    eprintln!("KUGOU_RUNTIME_PROFILE=DELETED");
    let capture = captured?;
    fixture.counts(false).await?;
    eprintln!("KUGOU_RUNTIME_BROWSER_API_REQUESTS=ZERO");
    let bound = owner
        .finish_capture(
            attempt,
            capture,
            unix_seconds().map_err(|_| "CLOCK_INVALID")?,
        )
        .map_err(|_| "CAPTURE_BINDING_FAILED")?;
    let source = owner.resolve_captured_once(bound).await.map_err(|error| {
        eprintln!("KUGOU_RUNTIME_REPLAY_CATEGORY={error:?}");
        "RUST_TLS_REPLAY_FAILED"
    })?;
    if source.media_format() != MediaFormat::Mp3
        || source.quality() != Some(WebQuality::Standard)
        || source.media_host() != "offline-media.example.org"
    {
        return Err("SYNTHETIC_SOURCE_INVALID");
    }
    drop(source); // No approval, media request, Range, URL logging or persistence.
    fixture.counts(true).await?;
    eprintln!("KUGOU_RUNTIME_RUST_API_REQUESTS=ONE");
    eprintln!("KUGOU_RUNTIME_TOTAL_API_REQUESTS=ONE");
    eprintln!("KUGOU_RUNTIME_RANGE_REQUESTS=ZERO");
    Ok(())
}
