//! Disconnected Rust-caller gate. Never exported through FRB or a production Provider.
//! The caller owns the current Fura TrackId and explicit Human request authority.

use super::*;
use base64::{Engine as _, engine::general_purpose::STANDARD};
use kugou_client::web_playback_candidate::{
    CapturePresence, OfficialWebCapture, ProfileCookie, WebPlaybackError,
    WebPlaybackHttpsTransport, WebPlaybackTransport,
};
use kugou_client::web_playback_candidate::{StandardWebSource, songinfo_stages::IdentityPresence};
use music_domain::TrackId;
use provider_kugou::web_playback_candidate::AuthenticatedStandardCandidate;
use provider_kugou::web_playback_candidate::{BoundCapture, CaptureAttempt, Stage1Progress};
use std::collections::BTreeMap;

const OFFICIAL_PAGE: &str = "https://www.kugou.com/";
const MAX_ATTACHED_TARGETS: usize = 32;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum GateFailure {
    HumanAuthorizationRequired,
    Browser(CaptureFailure),
    Cdp(CaptureFailure, CdpPhase, CdpTargetKind),
    TargetDetached(CdpPhase, CdpTargetKind),
    ProfileCookieCaptureInvalid,
    Playback(WebPlaybackError),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum CdpPhase {
    AutoAttach,
    FetchEnable,
    PageEnable,
    BypassServiceWorker,
    ChildAutoAttach,
    ResumeTarget,
    Navigate,
    ProfileCookies,
    FetchAbort,
    FetchFulfill,
    FetchContinue,
    Event,
}

#[derive(Clone, Copy, Debug, Default, Eq, Ord, PartialEq, PartialOrd)]
pub(crate) enum CdpTargetKind {
    Browser,
    Page,
    Iframe,
    Worker,
    SharedWorker,
    ServiceWorker,
    #[default]
    Other,
}

impl CdpTargetKind {
    fn from_cdp(value: &str) -> Self {
        match value {
            "page" => Self::Page,
            "iframe" => Self::Iframe,
            "worker" => Self::Worker,
            "shared_worker" => Self::SharedWorker,
            "service_worker" => Self::ServiceWorker,
            _ => Self::Other,
        }
    }

    const fn label(self) -> &'static str {
        match self {
            Self::Browser => "BROWSER",
            Self::Page => "PAGE",
            Self::Iframe => "IFRAME",
            Self::Worker => "WORKER",
            Self::SharedWorker => "SHARED_WORKER",
            Self::ServiceWorker => "SERVICE_WORKER",
            Self::Other => "OTHER",
        }
    }
}

impl CdpPhase {
    const fn label(self) -> &'static str {
        match self {
            Self::AutoAttach => "AUTO_ATTACH",
            Self::FetchEnable => "FETCH_ENABLE",
            Self::PageEnable => "PAGE_ENABLE",
            Self::BypassServiceWorker => "BYPASS_SERVICE_WORKER",
            Self::ChildAutoAttach => "CHILD_AUTO_ATTACH",
            Self::ResumeTarget => "RESUME_TARGET",
            Self::Navigate => "NAVIGATE",
            Self::ProfileCookies => "PROFILE_COOKIES",
            Self::FetchAbort => "FETCH_ABORT",
            Self::FetchFulfill => "FETCH_FULFILL",
            Self::FetchContinue => "FETCH_CONTINUE",
            Self::Event => "EVENT",
        }
    }
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
    human_authorized_songinfo_stages: bool,
    is_current: impl Fn() -> bool,
    approve_one_range: impl FnOnce(&str) -> bool,
) -> Result<bool, GateFailure> {
    let result = run_gate_attempt(
        owner,
        id,
        human_authorized_songinfo_stages,
        is_current,
        approve_one_range,
    )
    .await;
    report_line(&result_diagnostic(result));
    result
}

fn result_diagnostic(result: Result<bool, GateFailure>) -> String {
    match result {
        Ok(range) => format!(
            "KUGOU_GATE result=STANDARD_SOURCE_ONLY range_verified={range} account_summary_verified=false production_enabled=false"
        ),
        Err(error) => {
            let (category, phase): (&str, Option<CdpPhase>) = match error {
                GateFailure::HumanAuthorizationRequired => {
                    ("EXPLICIT_HUMAN_AUTHORIZATION_REQUIRED", None)
                }
                GateFailure::Playback(WebPlaybackError::OfficialWebTrackIdentityUnproven) => {
                    ("OFFICIAL_WEB_TRACK_IDENTITY_UNPROVEN", None)
                }
                GateFailure::Playback(WebPlaybackError::RiskControl) => ("RISK_CONTROL", None),
                GateFailure::Playback(WebPlaybackError::RateLimited) => ("RATE_LIMITED", None),
                GateFailure::Playback(WebPlaybackError::Replaced) => ("REPLACED", None),
                GateFailure::Playback(WebPlaybackError::AttemptConsumed) => {
                    ("ATTEMPT_CONSUMED", None)
                }
                GateFailure::Playback(WebPlaybackError::PreviewOnly) => ("PREVIEW_ONLY", None),
                GateFailure::Playback(WebPlaybackError::MembershipOrPurchaseRequired) => {
                    ("MEMBERSHIP_OR_PURCHASE_REQUIRED", None)
                }
                GateFailure::Playback(WebPlaybackError::RightsUnavailable) => {
                    ("RIGHTS_UNAVAILABLE", None)
                }
                GateFailure::Playback(WebPlaybackError::LoginRequired) => ("LOGIN_REQUIRED", None),
                GateFailure::Playback(WebPlaybackError::SessionContextRejected) => {
                    ("SESSION_CONTEXT_REJECTED", None)
                }
                GateFailure::Playback(WebPlaybackError::NewMediaHostRequiresApproval) => {
                    ("NEW_MEDIA_HOST_REQUIRES_APPROVAL", None)
                }
                GateFailure::Playback(WebPlaybackError::Network) => ("NETWORK", None),
                GateFailure::Playback(WebPlaybackError::ServiceUnavailable) => {
                    ("SERVICE_UNAVAILABLE", None)
                }
                GateFailure::Playback(WebPlaybackError::UpstreamRejected) => {
                    ("UPSTREAM_REJECTED", None)
                }
                GateFailure::Playback(WebPlaybackError::ProtocolUnsupported) => {
                    ("PROTOCOL_UNSUPPORTED", None)
                }
                GateFailure::Playback(WebPlaybackError::InvalidCapture) => {
                    ("INVALID_CAPTURE", None)
                }
                GateFailure::Playback(WebPlaybackError::InvalidResponse) => {
                    ("INVALID_RESPONSE", None)
                }
                GateFailure::Playback(WebPlaybackError::ResponseBound) => ("RESPONSE_BOUND", None),
                GateFailure::Playback(WebPlaybackError::OfficialWebStage1IdentityUnproven) => {
                    ("OFFICIAL_WEB_STAGE1_IDENTITY_UNPROVEN", None)
                }
                GateFailure::Playback(WebPlaybackError::Stage1ResponseIdentityMismatch) => {
                    ("STAGE1_RESPONSE_IDENTITY_MISMATCH", None)
                }
                GateFailure::Playback(WebPlaybackError::Stage1EncodedIdMissing) => {
                    ("STAGE1_ENCODED_ID_MISSING", None)
                }
                GateFailure::Playback(WebPlaybackError::OfficialWebSecondStageNotObserved) => {
                    ("OFFICIAL_WEB_SECOND_STAGE_NOT_OBSERVED", None)
                }
                GateFailure::Playback(WebPlaybackError::OfficialWebEncodedIdentityMismatch) => {
                    ("OFFICIAL_WEB_ENCODED_IDENTITY_MISMATCH", None)
                }
                GateFailure::Playback(WebPlaybackError::Stage2ResponseIdentityMismatch) => {
                    ("STAGE2_RESPONSE_IDENTITY_MISMATCH", None)
                }
                GateFailure::Playback(WebPlaybackError::OfficialWebStage2ProvenanceUnproven) => {
                    ("OFFICIAL_WEB_STAGE2_PROVENANCE_UNPROVEN", None)
                }
                GateFailure::Playback(WebPlaybackError::Stage1ResponseReplayUnsupported) => {
                    ("STAGE1_RESPONSE_REPLAY_UNSUPPORTED", None)
                }
                GateFailure::Playback(WebPlaybackError::Stage1ResponseEncodingUnsupported) => {
                    ("STAGE1_RESPONSE_ENCODING_UNSUPPORTED", None)
                }
                GateFailure::Playback(
                    WebPlaybackError::Stage1ResponseCookieMutationUnsupported,
                ) => ("STAGE1_RESPONSE_COOKIE_MUTATION_UNSUPPORTED", None),
                GateFailure::Browser(CaptureFailure::BrowserUnavailable) => {
                    ("BROWSER_UNAVAILABLE", None)
                }
                GateFailure::Browser(CaptureFailure::BrowserLaunchFailed) => {
                    ("BROWSER_LAUNCH_FAILED", None)
                }
                GateFailure::Browser(CaptureFailure::ProfileSetupFailed) => {
                    ("PROFILE_SETUP_FAILED", None)
                }
                GateFailure::Browser(CaptureFailure::DevtoolsUnavailable) => {
                    ("CDP_UNAVAILABLE", None)
                }
                GateFailure::Browser(CaptureFailure::DevtoolsInvalid) => {
                    return cdp_diagnostic(
                        "CDP_PROTOCOL_INVALID",
                        CdpPhase::Event,
                        CdpTargetKind::Browser,
                    );
                }
                GateFailure::Browser(CaptureFailure::OfficialTargetUnavailable) => {
                    ("OFFICIAL_TARGET_UNAVAILABLE", None)
                }
                GateFailure::Browser(CaptureFailure::BrowserClosed) => ("BROWSER_CLOSED", None),
                GateFailure::Browser(CaptureFailure::InvalidCredential)
                | GateFailure::ProfileCookieCaptureInvalid => {
                    ("PROFILE_COOKIE_CAPTURE_INVALID", None)
                }
                GateFailure::Browser(CaptureFailure::Cancelled) => ("CANCELLED", None),
                GateFailure::Browser(CaptureFailure::TimedOut) => ("TIMED_OUT", None),
                GateFailure::Browser(CaptureFailure::CleanupFailed) => ("CLEANUP_FAILED", None),
                GateFailure::Cdp(CaptureFailure::DevtoolsInvalid, phase, target) => {
                    return cdp_diagnostic("CDP_PROTOCOL_INVALID", phase, target);
                }
                GateFailure::Cdp(CaptureFailure::DevtoolsUnavailable, phase, target) => {
                    return cdp_diagnostic("CDP_UNAVAILABLE", phase, target);
                }
                GateFailure::Cdp(CaptureFailure::BrowserClosed, phase, target) => {
                    return cdp_diagnostic("BROWSER_CLOSED", phase, target);
                }
                GateFailure::Cdp(error, _, _) => return result_diagnostic(Err(error.into())),
                GateFailure::TargetDetached(phase, target) => {
                    return cdp_diagnostic("CDP_TARGET_DETACHED", phase, target);
                }
            };
            if let Some(phase) = phase {
                format!(
                    "KUGOU_GATE result=BLOCKED reason={category} cdp_phase={} production_enabled=false",
                    phase.label()
                )
            } else {
                format!("KUGOU_GATE result=BLOCKED reason={category} production_enabled=false")
            }
        }
    }
}

fn cdp_diagnostic(category: &str, phase: CdpPhase, target: CdpTargetKind) -> String {
    format!(
        "KUGOU_GATE result=BLOCKED reason={category} cdp_phase={} cdp_target={} production_enabled=false",
        phase.label(),
        target.label()
    )
}

fn cdp_failure(error: CaptureFailure, phase: CdpPhase, target: CdpTargetKind) -> GateFailure {
    GateFailure::Cdp(error, phase, target)
}

async fn cdp_phase_command(
    cdp: &mut CdpClient,
    session: Option<&str>,
    method: &str,
    params: Value,
    phase: CdpPhase,
    target: CdpTargetKind,
) -> Result<Value, GateFailure> {
    let result = cdp.session_command(session, method, params).await;
    if let Some(session) = session
        && cdp.take_detached_session(session)
    {
        return Err(GateFailure::TargetDetached(phase, target));
    }
    result.map_err(|error| cdp_failure(error, phase, target))
}

async fn run_gate_attempt<T: WebPlaybackTransport>(
    owner: &AuthenticatedStandardCandidate<T>,
    id: &TrackId,
    human_authorized_songinfo_stages: bool,
    is_current: impl Fn() -> bool,
    approve_one_range: impl FnOnce(&str) -> bool,
) -> Result<bool, GateFailure> {
    if !human_authorized_songinfo_stages {
        return Err(GateFailure::HumanAuthorizationRequired);
    }
    // Admission is synchronous and spent before browser startup or any await.
    let attempt = owner.begin_capture(id)?;
    let generation_current = owner.capture_current_check(&attempt);
    let current = || is_current() && generation_current();
    let source = capture_official_stages(owner, attempt, &current).await?;
    finish_source_gate(owner, source, &current, approve_one_range).await
}

async fn finish_source_gate<T: WebPlaybackTransport>(
    owner: &AuthenticatedStandardCandidate<T>,
    source: StandardWebSource,
    current: &impl Fn() -> bool,
    approve_one_range: impl FnOnce(&str) -> bool,
) -> Result<bool, GateFailure> {
    if !current() {
        owner.clear();
        return Err(WebPlaybackError::Replaced.into());
    }
    report_line("NEW_MEDIA_HOST_REQUIRES_APPROVAL");
    let approved = approve_one_range(source.media_host());
    if !current() {
        owner.clear();
        return Err(WebPlaybackError::Replaced.into());
    }
    if !approved {
        return Ok(false);
    }
    let approval = source.approve_media_host();
    let result = WebPlaybackHttpsTransport::new()?
        .probe_range(source, approval)
        .await;
    accept_range_result(owner, current, result)?;
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
    report_line(&presence_diagnostic(presence));
}

fn write_diagnostic(writer: &mut impl std::io::Write, text: &str) {
    // Output failure must not unwind and detach Fetch while a browser request
    // is paused. The session owner, not a logger, still owns cleanup and budgets.
    let _ = writeln!(writer, "{text}");
}

fn report_line(text: &str) {
    write_diagnostic(&mut std::io::stdout().lock(), text);
}

fn browser_network_fence_args() -> Vec<String> {
    vec![
        "--no-proxy-server".to_owned(),
        "--disable-quic".to_owned(),
        "--dns-over-https-mode=off".to_owned(),
        "--host-resolver-rules=MAP wwwapi.kugou.com ~NOTFOUND".to_owned(),
    ]
}

async fn capture_official_request(
    is_current: impl Fn() -> bool,
) -> Result<OfficialWebCapture, GateFailure> {
    if !is_current() {
        return Err(CaptureFailure::Cancelled.into());
    }
    let browser = discover_browser()?;
    // Start blank. No official page can issue songinfo before Fetch is armed.
    let mut running = start_browser_at(
        &browser,
        &is_current,
        "about:blank",
        &browser_network_fence_args(),
    )
    .await?;
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
    kind: CdpTargetKind,
    official_root: bool,
    official_frames: BTreeSet<String>,
}

struct Interceptor {
    targets: BTreeMap<String, AttachedTarget>,
    navigated: bool,
    #[cfg(test)]
    observed_target_kinds: BTreeSet<CdpTargetKind>,
    #[cfg(test)]
    attach_count: usize,
    #[cfg(test)]
    detach_count: usize,
    #[cfg(test)]
    peak_target_count: usize,
}

#[derive(Clone, Copy, PartialEq)]
enum CaptureMode {
    LegacyDirect,
    Stage1,
    Stage2,
}

struct PausedCapture {
    capture: OfficialWebCapture,
    session: String,
    request: String,
    target: CdpTargetKind,
}
impl PausedCapture {
    async fn abort(&self, cdp: &mut CdpClient) -> Result<(), GateFailure> {
        cdp_phase_command(
            cdp,
            Some(&self.session),
            "Fetch.failRequest",
            json!({"requestId":self.request,"errorReason":"Aborted"}),
            CdpPhase::FetchAbort,
            self.target,
        )
        .await?;
        Ok(())
    }
}

impl Interceptor {
    async fn target_command(
        cdp: &mut CdpClient,
        session: &str,
        target_id: &str,
        method: &str,
        params: Value,
        phase: CdpPhase,
        kind: CdpTargetKind,
    ) -> Result<Option<Value>, GateFailure> {
        let original =
            match cdp_phase_command(cdp, Some(session), method, params, phase, kind).await {
                Ok(value) => return Ok(Some(value)),
                Err(error @ GateFailure::Cdp(CaptureFailure::DevtoolsInvalid, _, _)) => error,
                Err(error) => return Err(error),
            };

        // Real pages create and remove OOPIF targets while their attach setup is
        // still in flight. A protocol error is benign only when a browser-level,
        // standard Target query proves that the exact target has already gone or
        // is no longer attached. An unsupported command on a live target remains
        // a fixed CDP_PROTOCOL_INVALID failure.
        match cdp
            .session_command(None, "Target.getTargetInfo", json!({"targetId": target_id}))
            .await
        {
            Ok(info) => {
                let actual = field(&info["targetInfo"], "targetId")
                    .map_err(|error| cdp_failure(error, phase, kind))?;
                let attached = info["targetInfo"]["attached"].as_bool();
                if actual != target_id || attached.is_none() {
                    return Err(GateFailure::Cdp(
                        CaptureFailure::DevtoolsInvalid,
                        phase,
                        kind,
                    ));
                }
                if attached == Some(false) {
                    cdp.take_detached_session(session);
                    return Ok(None);
                }
                Err(original)
            }
            Err(CaptureFailure::DevtoolsInvalid) => {
                cdp.take_detached_session(session);
                Ok(None)
            }
            Err(error) => Err(cdp_failure(error, phase, kind)),
        }
    }

    async fn arm(cdp: &mut CdpClient) -> Result<Self, GateFailure> {
        cdp.retain_events = true;
        cdp_phase_command(
            cdp,
            None,
            "Target.setAutoAttach",
            auto_attach_params(),
            CdpPhase::AutoAttach,
            CdpTargetKind::Browser,
        )
        .await?;
        Ok(Self {
            targets: BTreeMap::new(),
            navigated: false,
            #[cfg(test)]
            observed_target_kinds: BTreeSet::new(),
            #[cfg(test)]
            attach_count: 0,
            #[cfg(test)]
            detach_count: 0,
            #[cfg(test)]
            peak_target_count: 0,
        })
    }

    async fn handle(
        &mut self,
        cdp: &mut CdpClient,
        event: Value,
        entry: &str,
    ) -> Result<Option<OfficialWebCapture>, GateFailure> {
        Ok(self
            .observe(cdp, event, entry, CaptureMode::LegacyDirect)
            .await?
            .map(|paused| paused.capture))
    }

    #[cfg(test)]
    fn report_runtime_target_evidence(&self) {
        for (kind, label) in [
            (CdpTargetKind::Page, "PAGE"),
            (CdpTargetKind::Iframe, "IFRAME"),
            (CdpTargetKind::Worker, "WORKER"),
            (CdpTargetKind::SharedWorker, "SHARED_WORKER"),
            (CdpTargetKind::ServiceWorker, "SERVICE_WORKER"),
        ] {
            eprintln!(
                "KUGOU_RUNTIME_TARGET_{label}={}",
                if self.observed_target_kinds.contains(&kind) {
                    "OBSERVED"
                } else {
                    "NOT_OBSERVED"
                }
            );
        }
        eprintln!("KUGOU_RUNTIME_TARGET_ATTACH_COUNT={}", self.attach_count);
        eprintln!("KUGOU_RUNTIME_TARGET_DETACH_COUNT={}", self.detach_count);
        eprintln!("KUGOU_RUNTIME_TARGET_PEAK_COUNT={}", self.peak_target_count);
    }

    #[cfg(test)]
    fn validate_multitarget_runtime_evidence(&self) -> Result<(), GateFailure> {
        if ![
            CdpTargetKind::Page,
            CdpTargetKind::Iframe,
            CdpTargetKind::Worker,
            CdpTargetKind::SharedWorker,
            CdpTargetKind::ServiceWorker,
        ]
        .iter()
        .all(|kind| self.observed_target_kinds.contains(kind))
            || self.attach_count <= 32
            || self.detach_count == 0
            || self.peak_target_count >= MAX_ATTACHED_TARGETS
        {
            return Err(GateFailure::Cdp(
                CaptureFailure::DevtoolsInvalid,
                CdpPhase::Event,
                CdpTargetKind::Browser,
            ));
        }
        Ok(())
    }

    async fn observe(
        &mut self,
        cdp: &mut CdpClient,
        mut event: Value,
        entry: &str,
        mode: CaptureMode,
    ) -> Result<Option<PausedCapture>, GateFailure> {
        let method = event
            .get("method")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_owned();
        if method == "Target.attachedToTarget" {
            let params = &event["params"];
            let session = field(params, "sessionId")?.to_owned();
            let kind = field(&params["targetInfo"], "type")?;
            let target_kind = CdpTargetKind::from_cdp(kind);
            let page = kind == "page";
            // The owned browser is launched at about:blank before auto-attach.
            // Chromium may report the pre-existing app target as not waiting,
            // so the first page is armed in place before the only navigation.
            let initial_blank_page = target_kind == CdpTargetKind::Page && !self.navigated;
            let waiting_for_debugger =
                params.get("waitingForDebugger").and_then(Value::as_bool) == Some(true);
            if page && !initial_blank_page && !waiting_for_debugger {
                return Err(GateFailure::Cdp(
                    CaptureFailure::DevtoolsInvalid,
                    CdpPhase::AutoAttach,
                    target_kind,
                ));
            }
            let target_id = field(&params["targetInfo"], "targetId")?.to_owned();
            if self.targets.len() >= MAX_ATTACHED_TARGETS || self.targets.contains_key(&session) {
                return Err(CaptureFailure::DevtoolsInvalid.into());
            }
            self.targets.insert(
                session.clone(),
                AttachedTarget {
                    page,
                    kind: target_kind,
                    ..Default::default()
                },
            );
            #[cfg(test)]
            {
                self.observed_target_kinds.insert(target_kind);
                self.attach_count += 1;
                self.peak_target_count = self.peak_target_count.max(self.targets.len());
            }
            if !page {
                // OOPIF targets do not consistently expose Fetch. The parent
                // page is already armed for its own and in-process frame traffic;
                // an OOPIF is never accepted capture provenance, and the exact
                // API-host DNS fence blocks its songinfo traffic before network.
                if target_kind == CdpTargetKind::Iframe && waiting_for_debugger {
                    let _ = Self::target_command(
                        cdp,
                        &session,
                        &target_id,
                        "Runtime.runIfWaitingForDebugger",
                        json!({}),
                        CdpPhase::ResumeTarget,
                        target_kind,
                    )
                    .await?;
                    self.targets.remove(&session);
                    return Ok(None);
                }
                // Worker targets are never accepted capture provenance. Current
                // Chromium does not expose Fetch on dedicated workers and may
                // attach service workers without a debugger pause. Keep every
                // worker class paused for the lifetime of this gate. Resuming it
                // could make a worker-originated Fetch appear on the official
                // page session and falsely satisfy frame provenance.
                self.targets.remove(&session);
                return Ok(None);
            }
            // All targets are paused on creation. Arm interception BEFORE resume,
            // for page/frame targets; only proved official page frames can replay.
            if Self::target_command(
                cdp,
                &session,
                &target_id,
                "Fetch.enable",
                json!({
                    "patterns": [{"urlPattern": "*://*/play/songinfo*", "requestStage": "Request"}]
                }),
                CdpPhase::FetchEnable,
                target_kind,
            )
            .await?
            .is_none()
            {
                self.targets.remove(&session);
                return Ok(None);
            }
            if page {
                if Self::target_command(
                    cdp,
                    &session,
                    &target_id,
                    "Page.enable",
                    json!({}),
                    CdpPhase::PageEnable,
                    target_kind,
                )
                .await?
                .is_none()
                {
                    self.targets.remove(&session);
                    return Ok(None);
                }
                if Self::target_command(
                    cdp,
                    &session,
                    &target_id,
                    "Network.setBypassServiceWorker",
                    json!({"bypass": true}),
                    CdpPhase::BypassServiceWorker,
                    target_kind,
                )
                .await?
                .is_none()
                {
                    self.targets.remove(&session);
                    return Ok(None);
                }
                if Self::target_command(
                    cdp,
                    &session,
                    &target_id,
                    "Target.setAutoAttach",
                    auto_attach_params(),
                    CdpPhase::ChildAutoAttach,
                    target_kind,
                )
                .await?
                .is_none()
                {
                    self.targets.remove(&session);
                    return Ok(None);
                }
            }
            if waiting_for_debugger
                && Self::target_command(
                    cdp,
                    &session,
                    &target_id,
                    "Runtime.runIfWaitingForDebugger",
                    json!({}),
                    CdpPhase::ResumeTarget,
                    target_kind,
                )
                .await?
                .is_none()
            {
                self.targets.remove(&session);
                return Ok(None);
            }
            if kind == "page" && !self.navigated {
                self.navigated = true;
                if Self::target_command(
                    cdp,
                    &session,
                    &target_id,
                    "Page.navigate",
                    json!({"url": entry}),
                    CdpPhase::Navigate,
                    target_kind,
                )
                .await?
                .is_none()
                {
                    self.targets.remove(&session);
                    return Ok(None);
                }
            }
            return Ok(None);
        }
        if method == "Target.detachedFromTarget" {
            if let Some(session) = event["params"]["sessionId"].as_str() {
                self.targets.remove(session);
                #[cfg(test)]
                {
                    self.detach_count += 1;
                }
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
                    cdp_phase_command(
                        cdp,
                        Some(&session),
                        "Fetch.continueRequest",
                        json!({"requestId": request_id}),
                        CdpPhase::FetchContinue,
                        target.kind,
                    )
                    .await?;
                    return Ok(None);
                }
                // The legacy direct-profile test path always aborts first. V2
                // keeps a validated first request paused for Rust/fulfillment.
                if mode == CaptureMode::LegacyDirect {
                    cdp_phase_command(
                        cdp,
                        Some(&session),
                        "Fetch.failRequest",
                        json!({
                            "requestId": request_id, "errorReason": "Aborted"
                        }),
                        CdpPhase::FetchAbort,
                        target.kind,
                    )
                    .await?;
                }
                let captured: Result<OfficialWebCapture, GateFailure> = async {
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
                    let raw = field(&params["request"], "url")?;
                    if mode != CaptureMode::LegacyDirect {
                        report_line(&identity_diagnostic(mode, IdentityPresence::request(raw)));
                    }
                    let frame = field(params, "frameId")?;
                    if !target.page
                        || !target.official_root
                        || !target.official_frames.contains(frame)
                        || !matches!(params["resourceType"].as_str(), Some("XHR" | "Fetch"))
                    {
                        return Err(match mode {
                            CaptureMode::LegacyDirect => {
                                WebPlaybackError::OfficialWebTrackIdentityUnproven
                            }
                            CaptureMode::Stage1 => {
                                WebPlaybackError::OfficialWebStage1IdentityUnproven
                            }
                            CaptureMode::Stage2 => {
                                WebPlaybackError::OfficialWebStage2ProvenanceUnproven
                            }
                        }
                        .into());
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
                    let mut result = cdp_phase_command(
                        cdp,
                        None,
                        "Storage.getCookies",
                        json!({}),
                        CdpPhase::ProfileCookies,
                        CdpTargetKind::Browser,
                    )
                    .await?;
                    let cookies = profile_cookies(result["cookies"].take())
                        .map_err(|_| GateFailure::ProfileCookieCaptureInvalid)?;
                    let capture = match mode {
                        CaptureMode::LegacyDirect => OfficialWebCapture::from_cdp(
                            raw,
                            "GET",
                            &headers,
                            &cookies,
                            unix_seconds()?,
                        ),
                        CaptureMode::Stage1 => OfficialWebCapture::from_stage1_cdp(
                            raw,
                            "GET",
                            &headers,
                            &cookies,
                            unix_seconds()?,
                        ),
                        CaptureMode::Stage2 => OfficialWebCapture::from_stage2_cdp(
                            raw,
                            "GET",
                            &headers,
                            &cookies,
                            unix_seconds()?,
                        ),
                    }?;
                    report_presence(capture.presence());
                    Ok(capture)
                }
                .await;
                if captured.is_err() && mode != CaptureMode::LegacyDirect {
                    cdp_phase_command(
                        cdp,
                        Some(&session),
                        "Fetch.failRequest",
                        json!({"requestId":request_id,"errorReason":"Aborted"}),
                        CdpPhase::FetchAbort,
                        target.kind,
                    )
                    .await?;
                }
                return Ok(Some(PausedCapture {
                    capture: captured?,
                    session,
                    request: request_id,
                    target: target.kind,
                }));
            }
            _ => (),
        }
        Ok(None)
    }
}

fn identity_diagnostic(mode: CaptureMode, presence: IdentityPresence) -> String {
    use kugou_client::web_playback_candidate::songinfo_stages::IdentityStage;
    presence.diagnostic(if mode == CaptureMode::Stage2 {
        IdentityStage::Stage2Request
    } else {
        IdentityStage::Stage1Request
    })
}

enum BrowserProgress {
    Direct(StandardWebSource),
    Stage2(Box<BoundCapture>),
}

async fn source_after_cleanup<T: WebPlaybackTransport>(
    owner: &AuthenticatedStandardCandidate<T>,
    progress: Result<BrowserProgress, GateFailure>,
    cleanup: Result<(), CaptureFailure>,
    is_current: &impl Fn() -> bool,
) -> Result<StandardWebSource, GateFailure> {
    cleanup?;
    if !is_current() {
        owner.clear();
        return Err(WebPlaybackError::Replaced.into());
    }
    match progress? {
        BrowserProgress::Direct(source) => Ok(source),
        BrowserProgress::Stage2(bound) => Ok(owner.resolve_captured_once(*bound).await?),
    }
}

async fn capture_official_stages<T: WebPlaybackTransport>(
    owner: &AuthenticatedStandardCandidate<T>,
    attempt: CaptureAttempt,
    is_current: &impl Fn() -> bool,
) -> Result<StandardWebSource, GateFailure> {
    if !is_current() {
        return Err(CaptureFailure::Cancelled.into());
    }
    let browser = discover_browser()?;
    let mut running = start_browser_at(
        &browser,
        is_current,
        "about:blank",
        &browser_network_fence_args(),
    )
    .await?;
    let mut cdp = None;
    let progress = async {
        let endpoint = discover_websocket_endpoint(running.port, &running.websocket_path).await?;
        cdp = Some(CdpClient::connect(endpoint).await?);
        let client = cdp.as_mut().ok_or(CaptureFailure::DevtoolsUnavailable)?;
        capture_stages_in_browser(
            owner,
            attempt,
            client,
            &mut running.child,
            is_current,
            OFFICIAL_PAGE,
            Duration::from_secs(20),
        )
        .await
    }
    .await;
    let cleanup = shutdown_browser(&mut running, cdp.as_mut()).await;
    source_after_cleanup(owner, progress, cleanup, is_current).await
}

async fn next_stage(
    interceptor: &mut Interceptor,
    cdp: &mut CdpClient,
    child: &mut Child,
    is_current: &impl Fn() -> bool,
    entry: &str,
    mode: CaptureMode,
    deadline: Instant,
) -> Result<PausedCapture, GateFailure> {
    loop {
        require_active(child, is_current)?;
        if Instant::now() >= deadline {
            return Err(if mode == CaptureMode::Stage2 {
                WebPlaybackError::OfficialWebSecondStageNotObserved.into()
            } else {
                CaptureFailure::TimedOut.into()
            });
        }
        if let Some(event) = cdp
            .next_event()
            .await
            .map_err(|error| cdp_failure(error, CdpPhase::Event, CdpTargetKind::Browser))?
            && let Some(paused) = interceptor.observe(cdp, event, entry, mode).await?
        {
            return Ok(paused);
        }
    }
}

async fn capture_stages_in_browser<T: WebPlaybackTransport>(
    owner: &AuthenticatedStandardCandidate<T>,
    attempt: CaptureAttempt,
    cdp: &mut CdpClient,
    child: &mut Child,
    is_current: &impl Fn() -> bool,
    entry: &str,
    second_timeout: Duration,
) -> Result<BrowserProgress, GateFailure> {
    #[cfg(test)]
    let require_multitarget_evidence = [
        "FURA_KUGOU_MULTITARGET_RUNTIME_WORKER",
        "FURA_KUGOU_NO_LEAK_RUNTIME_WORKER",
    ]
    .iter()
    .any(|name| env::var(name).as_deref() == Ok("1"));
    let mut interceptor = Interceptor::arm(cdp).await?;
    let deadline = Instant::now() + ATTEMPT_TIMEOUT;
    let first = next_stage(
        &mut interceptor,
        cdp,
        child,
        is_current,
        entry,
        CaptureMode::Stage1,
        deadline,
    )
    .await?;
    let bound = owner.bind_stage1(attempt, first.capture, unix_seconds()?);
    // Identity errors stop before any upstream IO. The browser never continues.
    if bound.is_err() {
        cdp_phase_command(
            cdp,
            Some(&first.session),
            "Fetch.failRequest",
            json!({"requestId":first.request,"errorReason":"Aborted"}),
            CdpPhase::FetchAbort,
            first.target,
        )
        .await?;
    }
    let upstream = owner.resolve_stage1_once(bound?);
    tokio::pin!(upstream);
    let progress = loop {
        require_active(child, is_current)?;
        tokio::select! {
            result=&mut upstream=>break result?,
            _=sleep(POLL_INTERVAL)=> {if Instant::now()>=deadline {return Err(CaptureFailure::TimedOut.into());}},
        }
    };
    require_active(child, is_current)?;
    match progress {
        Stage1Progress::Direct(source) => {
            cdp_phase_command(
                cdp,
                Some(&first.session),
                "Fetch.failRequest",
                json!({"requestId":first.request,"errorReason":"Aborted"}),
                CdpPhase::FetchAbort,
                first.target,
            )
            .await?;
            Ok(BrowserProgress::Direct(source))
        }
        Stage1Progress::Continue(continuation) => {
            let fulfillment = owner.stage1_fulfillment(&continuation)?;
            let headers = fulfillment
                .headers()
                .iter()
                .map(|(name, value)| json!({"name":name,"value":value}))
                .collect::<Vec<_>>();
            cdp_phase_command(
                cdp,
                Some(&first.session),
                "Fetch.fulfillRequest",
                json!({
                    "requestId":first.request,"responseCode":200,"responseHeaders":headers,"body":STANDARD.encode(fulfillment.body()),
                }),
                CdpPhase::FetchFulfill,
                first.target,
            )
            .await?;
            require_active(child, is_current)?;
            let second = next_stage(
                &mut interceptor,
                cdp,
                child,
                is_current,
                entry,
                CaptureMode::Stage2,
                deadline.min(Instant::now() + second_timeout),
            )
            .await?;
            let bound = owner.bind_stage2(continuation, second.capture, unix_seconds()?);
            // Abort both matching and mismatched identities before cleanup. Never
            // detach Fetch, continue this request, or admit a third request.
            cdp_phase_command(
                cdp,
                Some(&second.session),
                "Fetch.failRequest",
                json!({"requestId":second.request,"errorReason":"Aborted"}),
                CdpPhase::FetchAbort,
                second.target,
            )
            .await?;
            reject_extra_songinfo(cdp).await?;
            #[cfg(test)]
            {
                if require_multitarget_evidence {
                    interceptor.validate_multitarget_runtime_evidence()?;
                }
                interceptor.report_runtime_target_evidence();
            }
            Ok(BrowserProgress::Stage2(Box::new(bound?)))
        }
    }
}

async fn reject_extra_songinfo(cdp: &mut CdpClient) -> Result<(), GateFailure> {
    for _ in 0..128 {
        if cdp.events.is_empty() {
            break;
        }
        if let Some(event) = cdp
            .next_event()
            .await
            .map_err(|error| cdp_failure(error, CdpPhase::Event, CdpTargetKind::Browser))?
            && event["method"] == "Fetch.requestPaused"
        {
            let session = field(&event, "sessionId")?;
            let request = field(&event["params"], "requestId")?;
            cdp_phase_command(
                cdp,
                Some(session),
                "Fetch.failRequest",
                json!({"requestId":request,"errorReason":"Aborted"}),
                CdpPhase::FetchAbort,
                CdpTargetKind::Other,
            )
            .await?;
            return Err(WebPlaybackError::AttemptConsumed.into());
        }
    }
    Ok(())
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
        if let Some(event) = cdp
            .next_event()
            .await
            .map_err(|error| cdp_failure(error, CdpPhase::Event, CdpTargetKind::Browser))?
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
mod test_support;

#[cfg(test)]
mod runtime_tests;

#[cfg(test)]
mod stages_tests;
