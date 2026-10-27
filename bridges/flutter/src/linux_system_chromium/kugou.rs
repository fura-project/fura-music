//! Disconnected Rust-caller gate. Never exported through FRB or a production Provider.
//! The caller owns the current Fura TrackId and explicit Human request authority.

use super::*;
use kugou_client::web_playback_candidate::{
    CapturePresence, OfficialWebCapture, ProfileCookie, WebPlaybackError,
    WebPlaybackHttpsTransport, WebPlaybackTransport,
};
use music_domain::TrackId;
use provider_kugou::web_playback_candidate::AuthenticatedStandardCandidate;
use std::collections::BTreeMap;

const OFFICIAL_PAGE: &str = "https://www.kugou.com/";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum GateFailure {
    HumanAuthorizationRequired,
    Browser(CaptureFailure),
    Playback(WebPlaybackError),
}

impl From<CaptureFailure> for GateFailure {
    fn from(value: CaptureFailure) -> Self {
        Self::Browser(value)
    }
}
impl From<WebPlaybackError> for GateFailure {
    fn from(value: WebPlaybackError) -> Self {
        Self::Playback(value)
    }
}

/// No secret input. The callback receives only an ephemeral normalized hostname.
/// Human cancellation/relogin/provider replacement must retire the owner and make
/// `is_current` false. Callers must await cleanup, not abort this future/task.
pub(crate) async fn run_gate<T: WebPlaybackTransport>(
    owner: &AuthenticatedStandardCandidate<T>,
    id: &TrackId,
    human_authorized_one_songinfo: bool,
    is_current: impl Fn() -> bool,
    approve_one_range: impl FnOnce(&str) -> bool,
) -> Result<bool, GateFailure> {
    let result = run_gate_attempt(
        owner,
        id,
        human_authorized_one_songinfo,
        is_current,
        approve_one_range,
    )
    .await;
    println!("{}", result_diagnostic(result));
    result
}

fn result_diagnostic(result: Result<bool, GateFailure>) -> String {
    match result {
        Ok(range) => format!(
            "KUGOU_GATE result=STANDARD_SOURCE_ONLY range_verified={range} account_summary_verified=false production_enabled=false"
        ),
        Err(error) => {
            let category = match error {
                GateFailure::HumanAuthorizationRequired => "EXPLICIT_HUMAN_AUTHORIZATION_REQUIRED",
                GateFailure::Playback(WebPlaybackError::OfficialWebTrackIdentityUnproven) => {
                    "OFFICIAL_WEB_TRACK_IDENTITY_UNPROVEN"
                }
                GateFailure::Playback(WebPlaybackError::RiskControl) => "RISK_CONTROL",
                GateFailure::Playback(WebPlaybackError::RateLimited) => "RATE_LIMITED",
                GateFailure::Playback(WebPlaybackError::Replaced) => "REPLACED",
                GateFailure::Playback(WebPlaybackError::AttemptConsumed) => "ATTEMPT_CONSUMED",
                GateFailure::Playback(WebPlaybackError::PreviewOnly) => "PREVIEW_ONLY",
                GateFailure::Playback(WebPlaybackError::MembershipOrPurchaseRequired) => {
                    "MEMBERSHIP_OR_PURCHASE_REQUIRED"
                }
                GateFailure::Playback(WebPlaybackError::RightsUnavailable) => "RIGHTS_UNAVAILABLE",
                GateFailure::Playback(WebPlaybackError::LoginRequired) => "LOGIN_REQUIRED",
                GateFailure::Playback(WebPlaybackError::SessionContextRejected) => {
                    "SESSION_CONTEXT_REJECTED"
                }
                GateFailure::Playback(WebPlaybackError::NewMediaHostRequiresApproval) => {
                    "NEW_MEDIA_HOST_REQUIRES_APPROVAL"
                }
                GateFailure::Playback(WebPlaybackError::Network) => "NETWORK",
                GateFailure::Playback(WebPlaybackError::ServiceUnavailable) => {
                    "SERVICE_UNAVAILABLE"
                }
                GateFailure::Playback(WebPlaybackError::UpstreamRejected) => "UPSTREAM_REJECTED",
                GateFailure::Playback(WebPlaybackError::ProtocolUnsupported) => {
                    "PROTOCOL_UNSUPPORTED"
                }
                GateFailure::Playback(WebPlaybackError::InvalidCapture) => "INVALID_CAPTURE",
                GateFailure::Playback(WebPlaybackError::InvalidResponse) => "INVALID_RESPONSE",
                GateFailure::Playback(WebPlaybackError::ResponseBound) => "RESPONSE_BOUND",
                GateFailure::Browser(CaptureFailure::Cancelled) => "CANCELLED",
                GateFailure::Browser(CaptureFailure::TimedOut) => "TIMED_OUT",
                GateFailure::Browser(CaptureFailure::CleanupFailed) => "CLEANUP_FAILED",
                GateFailure::Browser(_) => "BROWSER_CAPTURE_FAILED",
            };
            format!("KUGOU_GATE result=BLOCKED reason={category} production_enabled=false")
        }
    }
}

async fn run_gate_attempt<T: WebPlaybackTransport>(
    owner: &AuthenticatedStandardCandidate<T>,
    id: &TrackId,
    human_authorized_one_songinfo: bool,
    is_current: impl Fn() -> bool,
    approve_one_range: impl FnOnce(&str) -> bool,
) -> Result<bool, GateFailure> {
    if !human_authorized_one_songinfo {
        return Err(GateFailure::HumanAuthorizationRequired);
    }
    // Admission is synchronous and spent before browser startup or any await.
    let attempt = owner.begin_capture(id)?;
    let generation_current = owner.capture_current_check(&attempt);
    let current = || is_current() && generation_current();
    let capture = capture_official_request(&current).await?;
    let presence = capture.presence();
    let bound = owner.finish_capture(attempt, capture, unix_seconds()?)?;
    report_presence(presence);
    if !current() {
        owner.clear();
        return Err(WebPlaybackError::Replaced.into());
    }
    let source = owner.resolve_captured_once(bound).await?;
    if !current() {
        owner.clear();
        return Err(WebPlaybackError::Replaced.into());
    }
    println!("NEW_MEDIA_HOST_REQUIRES_APPROVAL");
    if !approve_one_range(source.media_host()) {
        return Ok(false);
    }
    if !current() {
        owner.clear();
        return Err(WebPlaybackError::Replaced.into());
    }
    let approval = source.approve_media_host();
    let result = WebPlaybackHttpsTransport::new()?
        .probe_range(source, approval)
        .await;
    accept_range_result(owner, &current, result)?;
    Ok(true)
}

fn accept_range_result<T>(
    owner: &AuthenticatedStandardCandidate<T>,
    is_current: &impl Fn() -> bool,
    result: Result<(), WebPlaybackError>,
) -> Result<(), GateFailure> {
    if !is_current() {
        owner.clear();
        return Err(WebPlaybackError::Replaced.into());
    }
    result.map_err(Into::into)
}

fn unix_seconds() -> Result<u64, WebPlaybackError> {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|time| time.as_secs())
        .map_err(|_| WebPlaybackError::InvalidCapture)
}

fn presence_diagnostic(presence: CapturePresence) -> String {
    format!(
        "KUGOU_CAPTURE_SOURCE=OFFICIAL_WEB\nHAS_SIGNATURE={}\nHAS_MID={}\nHAS_DFID={}\nHAS_USERID={}\nHAS_TOKEN={}",
        u8::from(presence.signature),
        u8::from(presence.mid),
        u8::from(presence.dfid),
        u8::from(presence.userid),
        u8::from(presence.token)
    )
}

fn report_presence(presence: CapturePresence) {
    println!("{}", presence_diagnostic(presence));
}

async fn capture_official_request(
    is_current: impl Fn() -> bool,
) -> Result<OfficialWebCapture, GateFailure> {
    if !is_current() {
        return Err(CaptureFailure::Cancelled.into());
    }
    let browser = discover_browser()?;
    // Start blank. No official page can issue songinfo before Fetch is armed.
    let mut running = start_browser_at(&browser, &is_current, "about:blank", &[]).await?;
    let mut cdp = None;
    let capture = async {
        let endpoint = discover_websocket_endpoint(running.port, &running.websocket_path).await?;
        cdp = Some(CdpClient::connect(endpoint).await?);
        let client = cdp.as_mut().ok_or(CaptureFailure::DevtoolsUnavailable)?;
        capture_in_browser(client, &mut running.child, &is_current, OFFICIAL_PAGE).await
    }
    .await;
    // A successful abort is not enough: browser exit/profile cleanup must also
    // succeed before any captured material is admitted for Rust replay.
    shutdown_browser(&mut running, cdp.as_mut()).await?;
    capture
}

#[derive(Default)]
struct AttachedTarget {
    page: bool,
    official_root: bool,
    official_frames: BTreeSet<String>,
}

struct Interceptor {
    targets: BTreeMap<String, AttachedTarget>,
    navigated: bool,
}

impl Interceptor {
    async fn arm(cdp: &mut CdpClient) -> Result<Self, CaptureFailure> {
        cdp.retain_events = true;
        cdp.command("Target.setAutoAttach", auto_attach_params())
            .await?;
        Ok(Self {
            targets: BTreeMap::new(),
            navigated: false,
        })
    }

    async fn handle(
        &mut self,
        cdp: &mut CdpClient,
        mut event: Value,
        entry: &str,
    ) -> Result<Option<OfficialWebCapture>, GateFailure> {
        let method = event
            .get("method")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_owned();
        if method == "Target.attachedToTarget" {
            let params = &event["params"];
            let session = field(params, "sessionId")?.to_owned();
            let kind = field(&params["targetInfo"], "type")?;
            if self.targets.len() >= 32 || self.targets.contains_key(&session) {
                return Err(CaptureFailure::DevtoolsInvalid.into());
            }
            let page = matches!(kind, "page" | "iframe");
            self.targets.insert(
                session.clone(),
                AttachedTarget {
                    page,
                    ..Default::default()
                },
            );
            // All targets are paused on creation. Arm interception BEFORE resume,
            // including workers/popups; only proved official page frames can replay.
            cdp.session_command(
                Some(&session),
                "Fetch.enable",
                json!({
                    "patterns": [{"urlPattern": "*://*/play/songinfo*", "requestStage": "Request"}]
                }),
            )
            .await?;
            if page {
                cdp.session_command(Some(&session), "Page.enable", json!({}))
                    .await?;
                cdp.session_command(
                    Some(&session),
                    "Network.setBypassServiceWorker",
                    json!({"bypass": true}),
                )
                .await?;
                cdp.session_command(Some(&session), "Target.setAutoAttach", auto_attach_params())
                    .await?;
            }
            cdp.session_command(Some(&session), "Runtime.runIfWaitingForDebugger", json!({}))
                .await?;
            if kind == "page" && !self.navigated {
                self.navigated = true;
                cdp.session_command(Some(&session), "Page.navigate", json!({"url": entry}))
                    .await?;
            }
            return Ok(None);
        }
        if method == "Target.detachedFromTarget" {
            if let Some(session) = event["params"]["sessionId"].as_str() {
                self.targets.remove(session);
            }
            return Ok(None);
        }
        let Some(session) = event
            .get("sessionId")
            .and_then(Value::as_str)
            .map(str::to_owned)
        else {
            return Ok(None);
        };
        let Some(target) = self.targets.get_mut(&session) else {
            // A different CDP session/attempt can never provide capture provenance.
            if method == "Fetch.requestPaused" {
                return Err(CaptureFailure::DevtoolsInvalid.into());
            }
            return Ok(None);
        };
        match method.as_str() {
            "Page.frameNavigated" => {
                let frame = &event["params"]["frame"];
                let id = field(frame, "id")?.to_owned();
                let official = official_page(field(frame, "url")?);
                if frame.get("parentId").is_none() {
                    target.official_root = official;
                    target.official_frames.clear();
                }
                target.official_frames.remove(&id);
                if official {
                    target.official_frames.insert(id);
                }
            }
            "Page.frameDetached" => {
                target
                    .official_frames
                    .remove(field(&event["params"], "frameId")?);
            }
            "Fetch.requestPaused" => {
                let params = &mut event["params"];
                let request_id = field(params, "requestId")?.to_owned();
                let raw = field(&params["request"], "url")?;
                let parsed = Url::parse(raw).map_err(|_| WebPlaybackError::InvalidCapture)?;
                let candidate = parsed.path().starts_with("/play/songinfo");
                if !candidate {
                    cdp.session_command(
                        Some(&session),
                        "Fetch.continueRequest",
                        json!({"requestId": request_id}),
                    )
                    .await?;
                    return Ok(None);
                }
                // Abort first, even for wrong identity/method/host/source. Never
                // disable Fetch or continue a candidate, including after capture.
                cdp.session_command(
                    Some(&session),
                    "Fetch.failRequest",
                    json!({
                        "requestId": request_id, "errorReason": "Aborted"
                    }),
                )
                .await?;
                if parsed.scheme() != "https"
                    || parsed.host_str() != Some("wwwapi.kugou.com")
                    || parsed.path() != "/play/songinfo"
                    || parsed.port().is_some()
                    || params.get("responseStatusCode").is_some()
                    || params.get("responseErrorReason").is_some()
                    || field(&params["request"], "method")? != "GET"
                    || params["request"].get("postData").is_some()
                    || params["request"]["hasPostData"].as_bool() == Some(true)
                {
                    return Err(WebPlaybackError::InvalidCapture.into());
                }
                let frame = field(params, "frameId")?;
                if !target.page
                    || !target.official_root
                    || !target.official_frames.contains(frame)
                    || !matches!(params["resourceType"].as_str(), Some("XHR" | "Fetch"))
                {
                    return Err(WebPlaybackError::OfficialWebTrackIdentityUnproven.into());
                }
                let raw = field(&params["request"], "url")?;
                let headers = params["request"]["headers"]
                    .as_object()
                    .ok_or(CaptureFailure::DevtoolsInvalid)?
                    .iter()
                    .map(|(name, value)| {
                        Ok((
                            name.clone(),
                            value
                                .as_str()
                                .ok_or(CaptureFailure::DevtoolsInvalid)?
                                .to_owned(),
                        ))
                    })
                    .collect::<Result<Vec<_>, CaptureFailure>>()?;
                let mut result = cdp.command("Storage.getCookies", json!({})).await?;
                let cookies = profile_cookies(result["cookies"].take())?;
                let capture =
                    OfficialWebCapture::from_cdp(raw, "GET", &headers, &cookies, unix_seconds()?);
                return Ok(Some(capture?));
            }
            _ => (),
        }
        Ok(None)
    }
}

fn auto_attach_params() -> Value {
    json!({"autoAttach": true, "waitForDebuggerOnStart": true, "flatten": true,
        "filter": [{"type": "page"}, {"type": "iframe"}, {"type": "worker"},
            {"type": "service_worker"}, {"type": "shared_worker"}, {"exclude": true}]})
}

fn field<'a>(value: &'a Value, name: &str) -> Result<&'a str, CaptureFailure> {
    value
        .get(name)
        .and_then(Value::as_str)
        .ok_or(CaptureFailure::DevtoolsInvalid)
}

fn official_page(raw: &str) -> bool {
    Url::parse(raw).is_ok_and(|url| {
        url.scheme() == "https"
            && url.host_str() == Some("www.kugou.com")
            && url.port().is_none()
            && url.username().is_empty()
            && url.password().is_none()
    })
}

fn profile_cookies(value: Value) -> Result<Vec<ProfileCookie>, CaptureFailure> {
    let cookies = value.as_array().ok_or(CaptureFailure::DevtoolsInvalid)?;
    if cookies.len() > 2048 {
        return Err(CaptureFailure::InvalidCredential);
    }
    cookies
        .iter()
        .map(|cookie| {
            Ok(ProfileCookie {
                name: field(cookie, "name")?.to_owned(),
                value: field(cookie, "value")?.to_owned(),
                domain: field(cookie, "domain")?.to_owned(),
                path: field(cookie, "path")?.to_owned(),
                secure: cookie
                    .get("secure")
                    .and_then(Value::as_bool)
                    .ok_or(CaptureFailure::DevtoolsInvalid)?,
            })
        })
        .collect()
}

async fn capture_in_browser(
    cdp: &mut CdpClient,
    child: &mut Child,
    is_current: &impl Fn() -> bool,
    entry: &str,
) -> Result<OfficialWebCapture, GateFailure> {
    let mut interceptor = Interceptor::arm(cdp).await?;
    let deadline = Instant::now() + ATTEMPT_TIMEOUT;
    loop {
        require_active(child, is_current)?;
        if Instant::now() >= deadline {
            return Err(CaptureFailure::TimedOut.into());
        }
        if let Some(event) = cdp.next_event().await?
            && let Some(capture) = interceptor.handle(cdp, event, entry).await?
        {
            require_active(child, is_current)?;
            return Ok(capture);
        }
    }
}

#[cfg(test)]
mod tests;

#[cfg(test)]
mod runtime_tests;
