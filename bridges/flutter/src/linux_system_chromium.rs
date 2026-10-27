//! Linux-only, isolated Chromium-family handoff for NetEase official login.
//!
//! This module never inspects a user's normal browser profile. Every attempt
//! owns a fresh `0700` profile and a loopback-only, ephemeral CDP endpoint.
//! Only `MUSIC_U`, independent optional `MUSIC_R_U` and optional `__csrf`
//! are retained from `Storage.getCookies`.

use std::collections::BTreeSet;
use std::collections::VecDeque;
use std::env;
use std::fs::Metadata;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::{Duration, Instant};

use futures_util::{SinkExt, StreamExt};
use nix::errno::Errno;
use nix::sys::signal::{Signal, kill};
use nix::unistd::Pid;
use serde::Deserialize;
use serde_json::{Value, json};
use tempfile::{Builder as TempDirBuilder, TempDir};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::process::{Child, Command};
use tokio::time::{sleep, timeout};
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream, connect_async, tungstenite::Message};
use url::{Host, Url};
use zeroize::Zeroize;

#[cfg(any(test, feature = "kugou-cdp-gate"))]
#[allow(dead_code)] // Deliberately disconnected Rust caller entry, not an FRB API.
pub(crate) mod kugou;

const OFFICIAL_LOGIN_URL: &str = "https://music.163.com/#/login";
const STARTUP_TIMEOUT: Duration = Duration::from_secs(20);
const TARGET_TIMEOUT: Duration = Duration::from_secs(20);
const ATTEMPT_TIMEOUT: Duration = Duration::from_secs(5 * 60);
const CDP_COMMAND_TIMEOUT: Duration = Duration::from_secs(15);
const CLEAN_CLOSE_TIMEOUT: Duration = Duration::from_secs(10);
const TERMINATION_TIMEOUT: Duration = Duration::from_secs(5);
const POLL_INTERVAL: Duration = Duration::from_millis(500);
const HTTP_RESPONSE_LIMIT: u64 = 64 * 1024;
const DEVTOOLS_FILE_LIMIT: u64 = 4096;
const CDP_PATH_LIMIT: usize = 256;
const CDP_RESPONSE_LIMIT: usize = 2 * 1024 * 1024;

type CdpSocket = WebSocketStream<MaybeTlsStream<TcpStream>>;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum CaptureFailure {
    BrowserUnavailable,
    BrowserLaunchFailed,
    ProfileSetupFailed,
    DevtoolsUnavailable,
    DevtoolsInvalid,
    OfficialTargetUnavailable,
    BrowserClosed,
    InvalidCredential,
    TimedOut,
    Cancelled,
    CleanupFailed,
}

#[derive(Clone, Debug)]
struct BrowserCandidate {
    binary: PathBuf,
}

struct RunningBrowser {
    child: Child,
    profile: Option<TempDir>,
    profile_path: PathBuf,
    port: u16,
    websocket_path: String,
}

struct CdpClient {
    socket: CdpSocket,
    next_id: u64,
    retain_events: bool,
    events: VecDeque<Value>,
    event_bytes: usize,
}

#[derive(Deserialize)]
struct CdpCookie {
    name: String,
    value: String,
    domain: String,
}

impl Drop for CdpCookie {
    fn drop(&mut self) {
        self.value.zeroize();
    }
}

/// Performs the cheap, non-mutating part of browser discovery.
pub(crate) fn is_supported() -> bool {
    discover_browser().is_ok()
}

/// Opens the official page in a fresh native browser profile and returns the
/// minimal Cookie header entirely within Rust.
pub(crate) async fn capture_netease_credential(
    is_current: impl Fn() -> bool,
) -> Result<Vec<u8>, CaptureFailure> {
    if !is_current() {
        return Err(CaptureFailure::Cancelled);
    }
    let browser = discover_browser()?;
    diagnostic("discover", "browser_ready");
    let mut running = start_browser(&browser, &is_current).await?;
    diagnostic("launch", "browser_started");

    let mut cdp = None;
    let capture = async {
        let websocket = discover_websocket_endpoint(running.port, &running.websocket_path).await?;
        cdp = Some(CdpClient::connect(websocket).await?);
        diagnostic("cdp", "connected");
        let client = cdp.as_mut().ok_or(CaptureFailure::DevtoolsUnavailable)?;
        wait_for_official_target(client, &mut running.child, &is_current).await?;
        diagnostic("target", "official_page_ready");
        wait_for_credential(client, &mut running.child, &is_current).await
    }
    .await;

    diagnostic("cleanup", "started");
    let cleanup = shutdown_browser(&mut running, cdp.as_mut()).await;
    diagnostic(
        "cleanup",
        if cleanup.is_ok() {
            "complete"
        } else {
            "failed"
        },
    );
    if cleanup.is_err() {
        if let Ok(mut credential) = capture {
            credential.zeroize();
        }
        return Err(CaptureFailure::CleanupFailed);
    }
    capture
}

fn discover_browser() -> Result<BrowserCandidate, CaptureFailure> {
    const CANDIDATES: [&str; 4] = [
        "google-chrome-stable",
        "google-chrome",
        "chromium",
        "chromium-browser",
    ];
    for name in CANDIDATES {
        let Some(found) = find_in_path(name) else {
            continue;
        };
        let Ok(binary) = std::fs::canonicalize(found) else {
            continue;
        };
        let Ok(metadata) = std::fs::metadata(&binary) else {
            continue;
        };
        if valid_system_browser_binary(&binary, &metadata) {
            return Ok(BrowserCandidate { binary });
        }
    }
    Err(CaptureFailure::BrowserUnavailable)
}

fn find_in_path(name: &str) -> Option<PathBuf> {
    let path = env::var_os("PATH")?;
    env::split_paths(&path)
        .map(|directory| directory.join(name))
        .find(|candidate| candidate.is_file())
}

fn valid_system_browser_binary(path: &Path, metadata: &Metadata) -> bool {
    path.is_absolute()
        && metadata.is_file()
        && metadata.permissions().mode() & 0o111 != 0
        && metadata.uid() == 0
        && (path.starts_with("/usr") || path.starts_with("/opt"))
}

async fn start_browser(
    browser: &BrowserCandidate,
    is_current: &impl Fn() -> bool,
) -> Result<RunningBrowser, CaptureFailure> {
    start_browser_at(browser, is_current, OFFICIAL_LOGIN_URL, &[]).await
}

async fn start_browser_at(
    browser: &BrowserCandidate,
    is_current: &impl Fn() -> bool,
    entry: &str,
    extra_args: &[String],
) -> Result<RunningBrowser, CaptureFailure> {
    let profile = create_profile()?;
    let profile_path = profile.path().to_path_buf();
    let child = Command::new(&browser.binary)
        .arg(format!("--app={entry}"))
        .arg(format!("--user-data-dir={}", profile_path.display()))
        .arg("--remote-debugging-address=127.0.0.1")
        .arg("--remote-debugging-port=0")
        .arg("--no-first-run")
        .arg("--no-default-browser-check")
        .args(extra_args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .map_err(|_| CaptureFailure::BrowserLaunchFailed)?;
    let mut running = RunningBrowser {
        child,
        profile: Some(profile),
        profile_path,
        port: 0,
        websocket_path: String::new(),
    };
    match wait_for_devtools_active_port(&running.profile_path, &mut running.child, is_current).await
    {
        Ok((port, websocket_path)) => {
            running.port = port;
            running.websocket_path = websocket_path;
            Ok(running)
        }
        Err(error) => match shutdown_browser(&mut running, None).await {
            Ok(()) => Err(error),
            Err(_) => Err(CaptureFailure::CleanupFailed),
        },
    }
}

fn create_profile() -> Result<TempDir, CaptureFailure> {
    let base = env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .filter(|path| runtime_base_is_safe(path))
        .unwrap_or_else(env::temp_dir);
    let profile = TempDirBuilder::new()
        .prefix("fura-netease-login-")
        .tempdir_in(base)
        .map_err(|_| CaptureFailure::ProfileSetupFailed)?;
    std::fs::set_permissions(profile.path(), std::fs::Permissions::from_mode(0o700))
        .map_err(|_| CaptureFailure::ProfileSetupFailed)?;
    let metadata =
        std::fs::metadata(profile.path()).map_err(|_| CaptureFailure::ProfileSetupFailed)?;
    if metadata.permissions().mode() & 0o777 != 0o700 || profile.path().starts_with("/home") {
        return Err(CaptureFailure::ProfileSetupFailed);
    }
    Ok(profile)
}

fn runtime_base_is_safe(path: &Path) -> bool {
    let Ok(metadata) = std::fs::metadata(path) else {
        return false;
    };
    let Ok(process_metadata) = std::fs::metadata("/proc/self") else {
        return false;
    };
    metadata.is_dir()
        && metadata.uid() == process_metadata.uid()
        && metadata.permissions().mode() & 0o077 == 0
}

async fn wait_for_devtools_active_port(
    profile: &Path,
    child: &mut Child,
    is_current: &impl Fn() -> bool,
) -> Result<(u16, String), CaptureFailure> {
    let path = profile.join("DevToolsActivePort");
    let deadline = Instant::now() + STARTUP_TIMEOUT;
    loop {
        require_active(child, is_current)?;
        if Instant::now() >= deadline {
            return Err(CaptureFailure::DevtoolsUnavailable);
        }
        if let Ok(file) = tokio::fs::File::open(&path).await {
            let mut bytes = Vec::new();
            file.take(DEVTOOLS_FILE_LIMIT + 1)
                .read_to_end(&mut bytes)
                .await
                .map_err(|_| CaptureFailure::DevtoolsInvalid)?;
            if bytes.len() as u64 > DEVTOOLS_FILE_LIMIT {
                return Err(CaptureFailure::DevtoolsInvalid);
            }
            let text = String::from_utf8(bytes).map_err(|_| CaptureFailure::DevtoolsInvalid)?;
            let mut lines = text.lines();
            let port = lines
                .next()
                .ok_or(CaptureFailure::DevtoolsInvalid)?
                .parse::<u16>()
                .map_err(|_| CaptureFailure::DevtoolsInvalid)?;
            let websocket_path = lines
                .next()
                .ok_or(CaptureFailure::DevtoolsInvalid)?
                .to_owned();
            if port == 0 || lines.next().is_some() || !valid_websocket_path(&websocket_path) {
                return Err(CaptureFailure::DevtoolsInvalid);
            }
            return Ok((port, websocket_path));
        }
        sleep(Duration::from_millis(50)).await;
    }
}

fn valid_websocket_path(path: &str) -> bool {
    let Some(token) = path.strip_prefix("/devtools/browser/") else {
        return false;
    };
    !token.is_empty()
        && path.len() <= CDP_PATH_LIMIT
        && token
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
}

async fn discover_websocket_endpoint(
    port: u16,
    expected_path: &str,
) -> Result<Url, CaptureFailure> {
    let body = http_get(port, "/json/version").await?;
    let value: Value =
        serde_json::from_slice(&body).map_err(|_| CaptureFailure::DevtoolsInvalid)?;
    let raw = value
        .get("webSocketDebuggerUrl")
        .and_then(Value::as_str)
        .ok_or(CaptureFailure::DevtoolsInvalid)?;
    validate_websocket_endpoint(raw, port, expected_path)
}

fn validate_websocket_endpoint(
    raw: &str,
    port: u16,
    expected_path: &str,
) -> Result<Url, CaptureFailure> {
    let url = Url::parse(raw).map_err(|_| CaptureFailure::DevtoolsInvalid)?;
    let loopback = matches!(
        url.host(),
        Some(Host::Ipv4(address)) if address == std::net::Ipv4Addr::LOCALHOST
    ) || matches!(url.host(), Some(Host::Domain(domain)) if domain == "localhost");
    if url.scheme() != "ws"
        || !loopback
        || url.port() != Some(port)
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
        || url.path() != expected_path
        || !valid_websocket_path(url.path())
    {
        return Err(CaptureFailure::DevtoolsInvalid);
    }
    Ok(url)
}

async fn http_get(port: u16, path: &str) -> Result<Vec<u8>, CaptureFailure> {
    let mut stream = timeout(
        Duration::from_secs(3),
        TcpStream::connect((std::net::Ipv4Addr::LOCALHOST, port)),
    )
    .await
    .map_err(|_| CaptureFailure::DevtoolsUnavailable)?
    .map_err(|_| CaptureFailure::DevtoolsUnavailable)?;
    let request = format!(
        "GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nConnection: close\r\nAccept: application/json\r\n\r\n"
    );
    stream
        .write_all(request.as_bytes())
        .await
        .map_err(|_| CaptureFailure::DevtoolsUnavailable)?;
    let mut response = Vec::new();
    let deadline = Instant::now() + Duration::from_secs(3);
    loop {
        if Instant::now() >= deadline {
            return Err(CaptureFailure::DevtoolsUnavailable);
        }
        let mut chunk = [0_u8; 8192];
        let read = timeout(Duration::from_millis(500), stream.read(&mut chunk))
            .await
            .map_err(|_| CaptureFailure::DevtoolsUnavailable)?
            .map_err(|_| CaptureFailure::DevtoolsUnavailable)?;
        if read == 0 {
            break;
        }
        response.extend_from_slice(&chunk[..read]);
        if response.len() as u64 > HTTP_RESPONSE_LIMIT {
            return Err(CaptureFailure::DevtoolsInvalid);
        }
        if http_response_complete(&response)? {
            break;
        }
    }
    let separator = response
        .windows(4)
        .position(|bytes| bytes == b"\r\n\r\n")
        .ok_or(CaptureFailure::DevtoolsInvalid)?;
    let header = &response[..separator];
    if !header.starts_with(b"HTTP/1.1 200 ") && !header.starts_with(b"HTTP/1.0 200 ") {
        return Err(CaptureFailure::DevtoolsInvalid);
    }
    Ok(response[separator + 4..].to_vec())
}

fn http_response_complete(response: &[u8]) -> Result<bool, CaptureFailure> {
    let Some(separator) = response.windows(4).position(|bytes| bytes == b"\r\n\r\n") else {
        return Ok(false);
    };
    let header =
        std::str::from_utf8(&response[..separator]).map_err(|_| CaptureFailure::DevtoolsInvalid)?;
    let content_length = header.lines().find_map(|line| {
        let (name, value) = line.split_once(':')?;
        name.eq_ignore_ascii_case("content-length")
            .then(|| value.trim().parse::<usize>().ok())
            .flatten()
    });
    Ok(content_length.is_some_and(|length| response.len() >= separator + 4 + length))
}

impl CdpClient {
    async fn connect(url: Url) -> Result<Self, CaptureFailure> {
        let (socket, _) = timeout(Duration::from_secs(5), connect_async(url.as_str()))
            .await
            .map_err(|_| CaptureFailure::DevtoolsUnavailable)?
            .map_err(|_| CaptureFailure::DevtoolsUnavailable)?;
        Ok(Self {
            socket,
            next_id: 1,
            retain_events: false,
            events: VecDeque::new(),
            event_bytes: 0,
        })
    }

    async fn command(&mut self, method: &str, params: Value) -> Result<Value, CaptureFailure> {
        self.session_command(None, method, params).await
    }

    async fn session_command(
        &mut self,
        session: Option<&str>,
        method: &str,
        params: Value,
    ) -> Result<Value, CaptureFailure> {
        let id = self.next_id;
        self.next_id = self
            .next_id
            .checked_add(1)
            .ok_or(CaptureFailure::DevtoolsInvalid)?;
        let mut command = json!({"id": id, "method": method, "params": params});
        if let Some(session) = session {
            command["sessionId"] = json!(session);
        }
        timeout(
            CDP_COMMAND_TIMEOUT,
            self.socket.send(Message::Text(command.to_string().into())),
        )
        .await
        .map_err(|_| CaptureFailure::DevtoolsUnavailable)?
        .map_err(|_| CaptureFailure::BrowserClosed)?;
        timeout(CDP_COMMAND_TIMEOUT, async {
            while let Some(message) = self.socket.next().await {
                let message = message.map_err(|_| CaptureFailure::BrowserClosed)?;
                let Message::Text(text) = message else {
                    if matches!(message, Message::Close(_)) {
                        return Err(CaptureFailure::BrowserClosed);
                    }
                    continue;
                };
                if text.len() > CDP_RESPONSE_LIMIT {
                    return Err(CaptureFailure::DevtoolsInvalid);
                }
                let mut value: Value = serde_json::from_str(text.as_ref())
                    .map_err(|_| CaptureFailure::DevtoolsInvalid)?;
                if value.get("id").and_then(Value::as_u64) != Some(id) {
                    if self.retain_events && value.get("method").is_some() {
                        self.queue_event(value, text.len())?;
                    }
                    continue;
                }
                if value.get("sessionId").and_then(Value::as_str) != session {
                    return Err(CaptureFailure::DevtoolsInvalid);
                }
                if value.get("error").is_some() {
                    #[cfg(test)]
                    if self.retain_events {
                        let phase = match method {
                            "Target.setAutoAttach" => "AUTO_ATTACH",
                            "Fetch.enable" => "FETCH_ENABLE",
                            "Fetch.failRequest" => "FETCH_ABORT",
                            "Page.enable" => "PAGE_ENABLE",
                            "Page.navigate" => "NAVIGATE",
                            "Network.setBypassServiceWorker" => "BYPASS_WORKER",
                            "Runtime.runIfWaitingForDebugger" => "RESUME",
                            "Storage.getCookies" => "PROFILE_COOKIES",
                            _ => "OTHER",
                        };
                        eprintln!("KUGOU_RUNTIME_CDP_ERROR_PHASE={phase}");
                    }
                    return Err(CaptureFailure::DevtoolsInvalid);
                }
                return value
                    .get_mut("result")
                    .map(Value::take)
                    .ok_or(CaptureFailure::DevtoolsInvalid);
            }
            Err(CaptureFailure::BrowserClosed)
        })
        .await
        .map_err(|_| CaptureFailure::DevtoolsUnavailable)?
    }

    fn queue_event(&mut self, value: Value, size: usize) -> Result<(), CaptureFailure> {
        if self.events.len() >= 128 || self.event_bytes.saturating_add(size) > CDP_RESPONSE_LIMIT {
            return Err(CaptureFailure::DevtoolsInvalid);
        }
        self.event_bytes += size;
        self.events.push_back(value);
        Ok(())
    }

    #[cfg(any(test, feature = "kugou-cdp-gate"))]
    async fn next_event(&mut self) -> Result<Option<Value>, CaptureFailure> {
        if let Some(value) = self.events.pop_front() {
            // Account by serialization, conservatively clear only when drained.
            if self.events.is_empty() {
                self.event_bytes = 0;
            }
            return Ok(Some(value));
        }
        timeout(POLL_INTERVAL, async {
            while let Some(message) = self.socket.next().await {
                let message = message.map_err(|_| CaptureFailure::BrowserClosed)?;
                match message {
                    Message::Text(text) => {
                        if text.len() > CDP_RESPONSE_LIMIT {
                            return Err(CaptureFailure::DevtoolsInvalid);
                        }
                        let value: Value = serde_json::from_str(&text)
                            .map_err(|_| CaptureFailure::DevtoolsInvalid)?;
                        if value.get("method").is_some() {
                            return Ok(Some(value));
                        }
                    }
                    Message::Close(_) => return Err(CaptureFailure::BrowserClosed),
                    _ => (),
                }
            }
            Err(CaptureFailure::BrowserClosed)
        })
        .await
        .unwrap_or(Ok(None))
    }

    async fn request_close(&mut self) {
        let id = self.next_id;
        self.next_id = self.next_id.saturating_add(1);
        let _ = timeout(
            Duration::from_secs(1),
            self.socket.send(Message::Text(
                json!({"id": id, "method": "Browser.close", "params": {}})
                    .to_string()
                    .into(),
            )),
        )
        .await;
        // Detaching a Fetch session releases paused requests. KuGou must keep
        // its connection until ALL browser processes are confirmed dead, even
        // when Browser.close is rejected or does not terminate the browser.
        if !self.retain_events {
            let _ = timeout(Duration::from_secs(1), self.socket.close(None)).await;
        }
    }
}

async fn wait_for_official_target(
    cdp: &mut CdpClient,
    child: &mut Child,
    is_current: &impl Fn() -> bool,
) -> Result<(), CaptureFailure> {
    let deadline = Instant::now() + TARGET_TIMEOUT;
    loop {
        require_active(child, is_current)?;
        let result = cdp.command("Target.getTargets", json!({})).await?;
        let targets = result
            .get("targetInfos")
            .and_then(Value::as_array)
            .ok_or(CaptureFailure::DevtoolsInvalid)?;
        if targets.iter().any(|target| {
            let Some(raw) = target.get("url").and_then(Value::as_str) else {
                return false;
            };
            Url::parse(raw).is_ok_and(|url| {
                url.scheme() == "https"
                    && url.host_str() == Some("music.163.com")
                    && url.username().is_empty()
                    && url.password().is_none()
            })
        }) {
            return Ok(());
        }
        if Instant::now() >= deadline {
            return Err(CaptureFailure::OfficialTargetUnavailable);
        }
        sleep(Duration::from_millis(100)).await;
    }
}

async fn wait_for_credential(
    cdp: &mut CdpClient,
    child: &mut Child,
    is_current: &impl Fn() -> bool,
) -> Result<Vec<u8>, CaptureFailure> {
    let deadline = Instant::now() + ATTEMPT_TIMEOUT;
    loop {
        require_active(child, is_current)?;
        let mut result = cdp.command("Storage.getCookies", json!({})).await?;
        let cookies: Vec<CdpCookie> = serde_json::from_value(
            result
                .get_mut("cookies")
                .map(Value::take)
                .ok_or(CaptureFailure::DevtoolsInvalid)?,
        )
        .map_err(|_| CaptureFailure::DevtoolsInvalid)?;
        if let Some(candidate) = credential_candidate(&cookies)? {
            diagnostic("cookie", "candidate_ready");
            return Ok(candidate);
        }
        if Instant::now() >= deadline {
            return Err(CaptureFailure::TimedOut);
        }
        sleep(POLL_INTERVAL).await;
    }
}

fn credential_candidate(cookies: &[CdpCookie]) -> Result<Option<Vec<u8>>, CaptureFailure> {
    let result = build_credential_candidate(cookies);
    if std::env::var("FURA_NETEASE_WEB_REFRESH_DEBUG").as_deref() == Ok("1") {
        eprintln!(
            "{}",
            capture_observation(cookies, matches!(result, Ok(Some(_))))
        );
    }
    result
}

fn capture_observation(cookies: &[CdpCookie], valid: bool) -> String {
    let observed = |name: &str| {
        cookies.iter().any(|cookie| {
            matches!(cookie.domain.as_str(), "music.163.com" | ".music.163.com")
                && cookie.name == name
                && !cookie.value.is_empty()
        })
    };
    format!(
        "FURA_NETEASE_WEB_REFRESH_DEBUG path=linux_isolated_chromium phase=capture observed_music_u={} observed_music_r_u={} observed_csrf={} candidate_valid={valid}",
        observed("MUSIC_U"),
        observed("MUSIC_R_U"),
        observed("__csrf"),
    )
}

pub(crate) fn report_web_account_verification() {
    if std::env::var("FURA_NETEASE_WEB_REFRESH_DEBUG").as_deref() == Ok("1") {
        eprintln!(
            "FURA_NETEASE_WEB_REFRESH_DEBUG path=linux_isolated_chromium phase=account_verification_entered success=true"
        );
    }
}

fn build_credential_candidate(cookies: &[CdpCookie]) -> Result<Option<Vec<u8>>, CaptureFailure> {
    let mut music_u: Option<&str> = None;
    let mut music_r_u: Option<&str> = None;
    let mut csrf: Option<&str> = None;
    for cookie in cookies
        .iter()
        .filter(|cookie| cookie.domain == "music.163.com" || cookie.domain == ".music.163.com")
    {
        let target = match cookie.name.as_str() {
            "MUSIC_U" => &mut music_u,
            "MUSIC_R_U" => &mut music_r_u,
            "__csrf" => &mut csrf,
            _ => continue,
        };
        if let Some(current) = *target {
            if current != cookie.value {
                return Err(CaptureFailure::InvalidCredential);
            }
        } else {
            *target = Some(cookie.value.as_str());
        }
    }
    let Some(music_u) = music_u else {
        return Ok(None);
    };
    if !valid_cookie_value(music_u, 4096)
        || music_r_u.is_some_and(|value| !valid_cookie_value(value, 4096))
        || csrf.is_some_and(|value| !valid_cookie_value(value, 256))
    {
        return Err(CaptureFailure::InvalidCredential);
    }
    let mut candidate = Vec::with_capacity(
        "MUSIC_U=".len() + music_u.len() + csrf.map_or(0, |value| 9 + value.len()),
    );
    candidate.extend_from_slice(b"MUSIC_U=");
    candidate.extend_from_slice(music_u.as_bytes());
    if let Some(music_r_u) = music_r_u {
        candidate.extend_from_slice(b"; MUSIC_R_U=");
        candidate.extend_from_slice(music_r_u.as_bytes());
    }
    if let Some(csrf) = csrf {
        candidate.extend_from_slice(b"; __csrf=");
        candidate.extend_from_slice(csrf.as_bytes());
    }
    if candidate.len() > 8192 {
        candidate.zeroize();
        return Err(CaptureFailure::InvalidCredential);
    }
    Ok(Some(candidate))
}

fn valid_cookie_value(value: &str, max_length: usize) -> bool {
    !value.is_empty()
        && value.len() <= max_length
        && value
            .bytes()
            .all(|byte| byte.is_ascii_graphic() && !matches!(byte, b';' | b',' | b'"' | b'\\'))
}

fn require_active(child: &mut Child, is_current: &impl Fn() -> bool) -> Result<(), CaptureFailure> {
    if !is_current() {
        return Err(CaptureFailure::Cancelled);
    }
    if child
        .try_wait()
        .map_err(|_| CaptureFailure::BrowserClosed)?
        .is_some()
    {
        return Err(CaptureFailure::BrowserClosed);
    }
    Ok(())
}

async fn shutdown_browser(
    running: &mut RunningBrowser,
    mut cdp: Option<&mut CdpClient>,
) -> Result<(), CaptureFailure> {
    if let Some(cdp) = cdp.as_mut() {
        cdp.request_close().await;
    }
    let child_closed = wait_child(&mut running.child, CLEAN_CLOSE_TIMEOUT).await?;
    let profile_closed = wait_for_profile_processes(
        &running.profile_path,
        if child_closed {
            Duration::from_secs(1)
        } else {
            Duration::ZERO
        },
    )
    .await;
    if !child_closed || !profile_closed {
        terminate_profile_processes(&running.profile_path, Signal::SIGTERM)?;
        if !wait_for_profile_processes(&running.profile_path, TERMINATION_TIMEOUT).await {
            terminate_profile_processes(&running.profile_path, Signal::SIGKILL)?;
            if !wait_for_profile_processes(&running.profile_path, TERMINATION_TIMEOUT).await {
                return Err(CaptureFailure::CleanupFailed);
            }
        }
        // Profile scanning is not proof that the owned process exited (for
        // example, a launcher may not retain the profile argument). Reap it
        // explicitly before allowing Fetch detachment or deleting the profile.
        if running
            .child
            .try_wait()
            .map_err(|_| CaptureFailure::CleanupFailed)?
            .is_none()
        {
            running
                .child
                .start_kill()
                .map_err(|_| CaptureFailure::CleanupFailed)?;
        }
        timeout(TERMINATION_TIMEOUT, running.child.wait())
            .await
            .map_err(|_| CaptureFailure::CleanupFailed)?
            .map_err(|_| CaptureFailure::CleanupFailed)?;
    }
    if !wait_for_profile_processes(&running.profile_path, TERMINATION_TIMEOUT).await {
        return Err(CaptureFailure::CleanupFailed);
    }
    running
        .profile
        .take()
        .ok_or(CaptureFailure::CleanupFailed)?
        .close()
        .map_err(|_| CaptureFailure::CleanupFailed)?;
    if running.profile_path.exists() || !profile_processes(&running.profile_path).is_empty() {
        return Err(CaptureFailure::CleanupFailed);
    }
    if let Some(cdp) = cdp
        && cdp.retain_events
    {
        let _ = timeout(Duration::from_secs(1), cdp.socket.close(None)).await;
    }
    Ok(())
}

async fn wait_child(child: &mut Child, duration: Duration) -> Result<bool, CaptureFailure> {
    let deadline = Instant::now() + duration;
    loop {
        if child
            .try_wait()
            .map_err(|_| CaptureFailure::CleanupFailed)?
            .is_some()
        {
            return Ok(true);
        }
        if Instant::now() >= deadline {
            return Ok(false);
        }
        sleep(Duration::from_millis(100)).await;
    }
}

async fn wait_for_profile_processes(profile: &Path, duration: Duration) -> bool {
    let deadline = Instant::now() + duration;
    loop {
        if profile_processes(profile).is_empty() {
            return true;
        }
        if Instant::now() >= deadline {
            return false;
        }
        sleep(Duration::from_millis(100)).await;
    }
}

fn profile_processes(profile: &Path) -> Vec<i32> {
    let needle = profile.as_os_str().as_bytes();
    let Ok(entries) = std::fs::read_dir("/proc") else {
        return Vec::new();
    };
    entries
        .flatten()
        .filter_map(|entry| entry.file_name().to_string_lossy().parse::<i32>().ok())
        .filter(|pid| *pid != std::process::id().cast_signed())
        .filter(|pid| {
            let Ok(bytes) = std::fs::read(format!("/proc/{pid}/cmdline")) else {
                return false;
            };
            bytes
                .split(|byte| *byte == 0)
                .any(|argument| argument.windows(needle.len()).any(|part| part == needle))
        })
        .collect()
}

fn terminate_profile_processes(profile: &Path, signal: Signal) -> Result<(), CaptureFailure> {
    let processes: BTreeSet<i32> = profile_processes(profile).into_iter().collect();
    for pid in processes {
        if let Err(error) = kill(Pid::from_raw(pid), signal)
            && error != Errno::ESRCH
        {
            return Err(CaptureFailure::CleanupFailed);
        }
    }
    Ok(())
}

fn diagnostic(phase: &str, outcome: &str) {
    eprintln!("FURA_DIAGNOSTIC netease_system_browser phase={phase} outcome={outcome}");
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cookie(name: &str, value: &str, domain: &str) -> CdpCookie {
        CdpCookie {
            name: name.to_owned(),
            value: value.to_owned(),
            domain: domain.to_owned(),
        }
    }

    #[test]
    fn endpoint_must_match_loopback_port_and_bootstrap_path() {
        let path = "/devtools/browser/abc-123";
        assert!(
            validate_websocket_endpoint(
                "ws://127.0.0.1:34567/devtools/browser/abc-123",
                34567,
                path
            )
            .is_ok()
        );
        assert!(
            validate_websocket_endpoint(
                "ws://localhost:34567/devtools/browser/abc-123",
                34567,
                path
            )
            .is_ok()
        );
        assert!(
            validate_websocket_endpoint(
                "ws://192.0.2.1:34567/devtools/browser/abc-123",
                34567,
                path
            )
            .is_err()
        );
        assert!(
            validate_websocket_endpoint(
                "ws://127.0.0.1:34568/devtools/browser/abc-123",
                34567,
                path
            )
            .is_err()
        );
        assert!(
            validate_websocket_endpoint("ws://127.0.0.1:34567/devtools/browser/other", 34567, path)
                .is_err()
        );
    }

    #[test]
    fn only_exact_netease_cookie_names_and_domains_form_candidate() {
        let cookies = vec![
            cookie("MUSIC_U", "secret", ".music.163.com"),
            cookie("__csrf", "token", "music.163.com"),
            cookie("MUSIC_U", "foreign", ".163.com"),
            cookie("unrelated", "ignored", ".music.163.com"),
        ];
        assert_eq!(
            credential_candidate(&cookies).expect("valid cookies"),
            Some(b"MUSIC_U=secret; __csrf=token".to_vec())
        );
    }

    #[test]
    fn conflicting_or_malformed_cookie_values_are_rejected() {
        let conflicting = vec![
            cookie("MUSIC_U", "one", "music.163.com"),
            cookie("MUSIC_U", "two", ".music.163.com"),
        ];
        assert_eq!(
            credential_candidate(&conflicting),
            Err(CaptureFailure::InvalidCredential)
        );
        let malformed = vec![cookie("MUSIC_U", "bad;value", "music.163.com")];
        assert_eq!(
            credential_candidate(&malformed),
            Err(CaptureFailure::InvalidCredential)
        );
    }

    #[test]
    fn optional_refresh_material_survives_into_a_v2_candidate_without_invention() {
        for include_r in [false, true] {
            for include_csrf in [false, true] {
                let mut cookies = vec![cookie("MUSIC_U", "synthetic-u", "music.163.com")];
                if include_r {
                    cookies.push(cookie("MUSIC_R_U", "independent-r", ".music.163.com"));
                    cookies.push(cookie("MUSIC_R_U", "independent-r", "music.163.com"));
                }
                if include_csrf {
                    cookies.push(cookie("__csrf", "synthetic-c", "music.163.com"));
                }
                cookies.push(cookie("MUSIC_R_U", "foreign", ".163.com"));
                cookies.push(cookie("MUSIC_U", "foreign", "music.163.com.evil"));
                let bytes = credential_candidate(&cookies).unwrap().unwrap();
                let credential =
                    netease_client::Credential::from_browser_cookie_header(&bytes).unwrap();
                assert_eq!(credential.has_refresh_material(), include_r);
                let document: Value =
                    serde_json::from_slice(&credential.export().unwrap()).unwrap();
                assert_eq!(document["version"], 2);
                assert_eq!(document["music_u"], "synthetic-u");
                assert_eq!(
                    document["music_r_u"],
                    if include_r {
                        json!("independent-r")
                    } else {
                        Value::Null
                    }
                );
                assert_eq!(
                    document["csrf"],
                    if include_csrf { "synthetic-c" } else { "" }
                );
                assert_eq!(
                    capture_observation(&cookies, true),
                    format!(
                        "FURA_NETEASE_WEB_REFRESH_DEBUG path=linux_isolated_chromium phase=capture observed_music_u=true observed_music_r_u={include_r} observed_csrf={include_csrf} candidate_valid=true"
                    )
                );
            }
        }
        assert_eq!(
            credential_candidate(&[cookie("MUSIC_R_U", "only-r", "music.163.com")]),
            Ok(None)
        );
    }

    #[test]
    fn refresh_cookie_conflict_deletion_characters_and_aggregate_bound_fail_closed() {
        for invalid in [
            String::new(),
            "bad;value".into(),
            "bad\r\nvalue".into(),
            "bad\\value".into(),
            "非ASCII".into(),
            "r".repeat(4097),
        ] {
            assert_eq!(
                credential_candidate(&[
                    cookie("MUSIC_U", "u", "music.163.com"),
                    cookie("MUSIC_R_U", &invalid, "music.163.com"),
                ]),
                Err(CaptureFailure::InvalidCredential)
            );
        }
        assert_eq!(
            credential_candidate(&[
                cookie("MUSIC_U", "u", "music.163.com"),
                cookie("MUSIC_R_U", "one", "music.163.com"),
                cookie("MUSIC_R_U", "two", ".music.163.com"),
            ]),
            Err(CaptureFailure::InvalidCredential)
        );
        assert_eq!(
            credential_candidate(&[
                cookie("MUSIC_U", &"u".repeat(4096), "music.163.com"),
                cookie("MUSIC_R_U", &"r".repeat(4096), "music.163.com"),
            ]),
            Err(CaptureFailure::InvalidCredential)
        );
    }

    #[test]
    fn websocket_path_is_narrowly_bounded() {
        assert!(valid_websocket_path("/devtools/browser/a-b-C-123"));
        assert!(!valid_websocket_path("/devtools/page/a-b-C-123"));
        assert!(!valid_websocket_path("/devtools/browser/a_b"));
        assert!(!valid_websocket_path("/devtools/browser/"));
    }
}
