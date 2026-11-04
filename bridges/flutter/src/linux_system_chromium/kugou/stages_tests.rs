//! Offline CDP lifecycle negatives. Actual browser JS/fulfillment is separately
//! exercised by the installed-Chromium two-stage runtime, not simulated here.
use super::test_support::*;
use super::*;
use kugou_client::{
    Response,
    web_playback_candidate::{
        CapturedWebRequest, WebPlaybackResponse, songinfo_stages::Stage1WireResponse,
    },
};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, AtomicUsize, Ordering},
};

const ENCODED: &str = "synthetic-server-opaque-id";
const SECOND: &str = "synthetic-second-request";
const THIRD: &str = "synthetic-third-request";
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Case {
    Normal,
    DirectResponse,
    WrongHash,
    WrongFirstProvenance,
    WrongSecondProvenance,
    WrongResponseHash,
    ConflictingRecording,
    MissingEncoded,
    DifferentSecond,
    NoSecond,
    Stage1Retry,
    ThirdRequest,
    CancelDuringFirst,
    CancelAfterFulfill,
    WrongFinalIdentity,
}
struct State {
    case: Case,
    active: AtomicBool,
    cleaned: AtomicBool,
    first: AtomicUsize,
    second: AtomicUsize,
    browser: AtomicUsize,
}
impl State {
    fn new(case: Case) -> Self {
        Self {
            case,
            active: AtomicBool::new(true),
            cleaned: AtomicBool::new(false),
            first: AtomicUsize::new(0),
            second: AtomicUsize::new(0),
            browser: AtomicUsize::new(0),
        }
    }
}
struct Mock(Arc<State>);
impl WebPlaybackTransport for Mock {
    async fn send_stage1(
        &self,
        request: &CapturedWebRequest,
    ) -> Result<Stage1WireResponse, WebPlaybackError> {
        self.0.first.fetch_add(1, Ordering::SeqCst);
        assert_eq!(self.0.browser.load(Ordering::SeqCst), 0);
        assert!(!self.0.cleaned.load(Ordering::SeqCst));
        assert_eq!(
            request.url(),
            format!("https://wwwapi.kugou.com/play/songinfo?hash={HASH}")
        );
        if self.0.case == Case::CancelDuringFirst {
            self.0.active.store(false, Ordering::SeqCst);
            return std::future::pending().await;
        }
        let mut data = json!({"hash":HASH,"album_audio_id":9,"encode_album_audio_id":ENCODED});
        match self.0.case {
            Case::WrongResponseHash => data["hash"] = json!("22222222222222222222222222222222"),
            Case::ConflictingRecording => data["album_audio_id"] = json!(10),
            Case::DirectResponse => {
                data = json!({"hash":HASH,"album_audio_id":9,"privilege":0,"is_free_part":0,"play_url":"https://offline-media.example.org/a.mp3","bitrate":128000,"timelength":180000,"filesize":2880000,"extname":"mp3"})
            }
            Case::MissingEncoded => {
                data.as_object_mut()
                    .unwrap()
                    .remove("encode_album_audio_id");
            }
            _ => (),
        }
        let body = serde_json::to_vec(&json!({"status":1,"data":data})).unwrap();
        Ok(Stage1WireResponse::new(
            WebPlaybackResponse {
                response: Response {
                    status: 200,
                    content_type: Some("application/json".into()),
                    body,
                },
                security_challenge: false,
            },
            vec![
                ("Content-Type".into(), "application/json".into()),
                (
                    "Access-Control-Allow-Origin".into(),
                    "https://www.kugou.com".into(),
                ),
            ],
        ))
    }
    async fn send_web(
        &self,
        request: &CapturedWebRequest,
    ) -> Result<WebPlaybackResponse, WebPlaybackError> {
        assert!(
            self.0.cleaned.load(Ordering::SeqCst),
            "cleanup must precede Stage 2 replay"
        );
        self.0.second.fetch_add(1, Ordering::SeqCst);
        assert_eq!(self.0.first.load(Ordering::SeqCst), 1);
        assert_eq!(
            request.url(),
            format!("https://wwwapi.kugou.com/play/songinfo?encode_album_audio_id={ENCODED}")
        );
        let mut data = json!({"privilege":0,"is_free_part":0,"play_url":"https://offline-media.example.org/a.mp3","bitrate":128000,"timelength":180000,"filesize":2880000,"extname":"mp3"});
        if self.0.case == Case::WrongFinalIdentity {
            data["hash"] = json!("22222222222222222222222222222222");
        }
        Ok(WebPlaybackResponse {
            response: Response {
                status: 200,
                content_type: Some("application/json".into()),
                body: serde_json::to_vec(&json!({"status":1,"data":data})).unwrap(),
            },
            security_challenge: false,
        })
    }
}

fn stage_event(second: bool, case: Case) -> Value {
    let mut event = paused();
    let url = if second {
        if case == Case::Stage1Retry {
            format!("https://wwwapi.kugou.com/play/songinfo?hash={HASH}")
        } else {
            format!(
                "https://wwwapi.kugou.com/play/songinfo?encode_album_audio_id={}",
                if case == Case::DifferentSecond {
                    "synthetic-other-id"
                } else {
                    ENCODED
                }
            )
        }
    } else {
        format!(
            "https://wwwapi.kugou.com/play/songinfo?hash={}",
            if case == Case::WrongHash {
                "22222222222222222222222222222222"
            } else {
                HASH
            }
        )
    };
    event["params"]["request"]["url"] = json!(url);
    event["params"]["requestId"] = json!(if second { SECOND } else { REQUEST });
    event
}

async fn peer(state: Arc<State>) -> (CdpClient, TestTask, Arc<Mutex<Vec<Value>>>) {
    let trace = Arc::new(Mutex::new(Vec::new()));
    let recorded = trace.clone();
    let (cdp,task)=cdp_peer(move|mut socket|async move {
        while let Some(message)=socket.next().await {
            let Message::Text(text)=message.unwrap() else {break;};
            let command:Value=serde_json::from_str(&text).unwrap();
            recorded.lock().unwrap().push(command.clone());
            let mut result=json!({});
            match command["method"].as_str().unwrap() {
                "Target.setAutoAttach" if command.get("sessionId").is_none()=>send_json(&mut socket,json!({"method":"Target.attachedToTarget","params":{"sessionId":SESSION,"waitingForDebugger":true,"targetInfo":{"targetId":"synthetic-page","type":"page","url":"about:blank"}}})).await,
                "Page.navigate"=> {send_json(&mut socket,frame(if state.case==Case::WrongFirstProvenance {"https://nonofficial.invalid/"} else {OFFICIAL_PAGE})).await;send_json(&mut socket,stage_event(false,state.case)).await;},
                "Storage.getCookies"=>result=json!({"cookies":cookies()}),
                "Fetch.fulfillRequest"=> {
                    assert_eq!(state.first.load(Ordering::SeqCst),1);
                    assert_eq!(state.second.load(Ordering::SeqCst),0);
                    assert_eq!(command["params"]["requestId"],REQUEST);
                    let bytes=STANDARD.decode(command["params"]["body"].as_str().unwrap()).unwrap();
                    let value:Value=serde_json::from_slice(&bytes).unwrap();
                    assert_eq!(value["data"]["encode_album_audio_id"],ENCODED);
                    assert_eq!(command["params"]["responseCode"],200);
                    if state.case==Case::CancelAfterFulfill {state.active.store(false,Ordering::SeqCst);}
                    else if state.case!=Case::NoSecond {
                        if state.case==Case::WrongSecondProvenance {send_json(&mut socket,frame("https://nonofficial.invalid/")).await;}
                        send_json(&mut socket,stage_event(true,state.case)).await;
                        if state.case==Case::ThirdRequest {
                            let mut third=stage_event(true,Case::Normal);third["params"]["requestId"]=json!(THIRD);
                            send_json(&mut socket,third).await;
                        }
                    }
                },
                "Fetch.continueRequest"=> {state.browser.fetch_add(1,Ordering::SeqCst);},
                _=>(),
            }
            send_json(&mut socket,reply(&command,result)).await;
        }
    }).await;
    (cdp, task, trace)
}

async fn execute(
    case: Case,
    cleanup: bool,
) -> (
    Result<StandardWebSource, GateFailure>,
    Arc<State>,
    Vec<Value>,
) {
    let state = Arc::new(State::new(case));
    let owner = AuthenticatedStandardCandidate::new(Mock(state.clone()));
    let attempt = owner.begin_capture(&track_id()).unwrap();
    let generation = owner.capture_current_check(&attempt);
    let current = || state.active.load(Ordering::SeqCst) && generation();
    let (mut cdp, mut task, trace) = peer(state.clone()).await;
    let mut child = Command::new("sleep")
        .arg("60")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .unwrap();
    let progress = timeout(
        Duration::from_secs(8),
        capture_stages_in_browser(
            &owner,
            attempt,
            &mut cdp,
            &mut child,
            &current,
            OFFICIAL_PAGE,
            Duration::from_millis(80),
        ),
    )
    .await
    .unwrap();
    child.start_kill().unwrap();
    child.wait().await.unwrap();
    state.cleaned.store(true, Ordering::SeqCst);
    let source = source_after_cleanup(
        &owner,
        progress,
        if cleanup {
            Ok(())
        } else {
            Err(CaptureFailure::CleanupFailed)
        },
        &current,
    )
    .await;
    let _ = cdp.socket.close(None).await;
    task.join().await;
    let commands = trace.lock().unwrap().clone();
    assert_eq!(state.browser.load(Ordering::SeqCst), 0);
    assert!(state.first.load(Ordering::SeqCst) <= 1);
    assert!(state.second.load(Ordering::SeqCst) <= 1);
    (source, state, commands)
}

#[tokio::test]
async fn pause_fulfill_second_abort_and_cleanup_precede_the_only_two_replays() {
    let (result, state, trace) = execute(Case::Normal, true).await;
    assert_eq!(result.unwrap().media_host(), "offline-media.example.org");
    assert_eq!(state.first.load(Ordering::SeqCst), 1);
    assert_eq!(state.second.load(Ordering::SeqCst), 1);
    let fulfilled = trace
        .iter()
        .filter(|command| command["method"] == "Fetch.fulfillRequest")
        .collect::<Vec<_>>();
    assert_eq!(fulfilled.len(), 1);
    let aborts = trace
        .iter()
        .filter(|command| command["method"] == "Fetch.failRequest")
        .collect::<Vec<_>>();
    assert_eq!(aborts.len(), 1);
    assert_eq!(aborts[0]["params"]["requestId"], SECOND);
}

#[tokio::test]
async fn full_direct_response_is_one_branch_without_second_stage_or_fallback() {
    let (result, state, trace) = execute(Case::DirectResponse, true).await;
    assert_eq!(result.unwrap().media_host(), "offline-media.example.org");
    assert_eq!(state.first.load(Ordering::SeqCst), 1);
    assert_eq!(state.second.load(Ordering::SeqCst), 0);
    assert!(
        !trace
            .iter()
            .any(|command| command["method"] == "Fetch.fulfillRequest")
    );
    assert!(
        trace
            .iter()
            .any(|command| command["method"] == "Fetch.failRequest"
                && command["params"]["requestId"] == REQUEST)
    );
}

#[tokio::test]
async fn cancellation_in_a_declining_range_prompt_dominates_source_success() {
    let (source, state, _) = execute(Case::Normal, true).await;
    let owner = AuthenticatedStandardCandidate::new(Mock(state.clone()));
    let active = AtomicBool::new(true);
    let result = finish_source_gate(
        &owner,
        source.unwrap(),
        &|| active.load(Ordering::SeqCst),
        |_| {
            active.store(false, Ordering::SeqCst);
            owner.clear();
            false
        },
    )
    .await;
    assert_eq!(
        result.unwrap_err(),
        GateFailure::Playback(WebPlaybackError::Replaced)
    );
    assert_eq!(state.first.load(Ordering::SeqCst), 1);
    assert_eq!(state.second.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn wrong_first_hash_stops_before_first_upstream_and_is_aborted() {
    let (result, state, trace) = execute(Case::WrongHash, true).await;
    assert_eq!(
        result.unwrap_err(),
        GateFailure::Playback(WebPlaybackError::OfficialWebStage1IdentityUnproven)
    );
    assert_eq!(state.first.load(Ordering::SeqCst), 0);
    assert!(
        trace
            .iter()
            .any(|command| command["method"] == "Fetch.failRequest")
    );
}

#[tokio::test]
async fn each_stage_requires_current_official_frame_provenance() {
    for (case, first, error) in [
        (
            Case::WrongFirstProvenance,
            0,
            WebPlaybackError::OfficialWebStage1IdentityUnproven,
        ),
        (
            Case::WrongSecondProvenance,
            1,
            WebPlaybackError::OfficialWebStage2ProvenanceUnproven,
        ),
    ] {
        let (result, state, trace) = execute(case, true).await;
        assert_eq!(result.unwrap_err(), GateFailure::Playback(error));
        assert_eq!(state.first.load(Ordering::SeqCst), first);
        assert_eq!(state.second.load(Ordering::SeqCst), 0);
        assert!(
            trace
                .iter()
                .any(|command| command["method"] == "Fetch.failRequest")
        );
    }
}

#[tokio::test]
async fn bad_first_response_identity_or_missing_encoded_value_is_never_fulfilled() {
    for (case, error) in [
        (
            Case::WrongResponseHash,
            WebPlaybackError::Stage1ResponseIdentityMismatch,
        ),
        (
            Case::ConflictingRecording,
            WebPlaybackError::Stage1ResponseIdentityMismatch,
        ),
        (
            Case::MissingEncoded,
            WebPlaybackError::Stage1EncodedIdMissing,
        ),
    ] {
        let (result, state, trace) = execute(case, true).await;
        assert_eq!(result.unwrap_err(), GateFailure::Playback(error));
        assert_eq!(state.first.load(Ordering::SeqCst), 1);
        assert_eq!(state.second.load(Ordering::SeqCst), 0);
        assert!(
            !trace
                .iter()
                .any(|command| command["method"] == "Fetch.fulfillRequest")
        );
    }
}

#[tokio::test]
async fn second_encoded_mismatch_and_first_stage_retry_are_aborted_without_upstream() {
    for case in [Case::DifferentSecond, Case::Stage1Retry] {
        let (result, state, trace) = execute(case, true).await;
        assert_eq!(
            result.unwrap_err(),
            GateFailure::Playback(WebPlaybackError::OfficialWebEncodedIdentityMismatch)
        );
        assert_eq!(state.first.load(Ordering::SeqCst), 1);
        assert_eq!(state.second.load(Ordering::SeqCst), 0);
        assert!(
            trace
                .iter()
                .any(|command| command["method"] == "Fetch.failRequest"
                    && command["params"]["requestId"] == SECOND)
        );
    }
}

#[tokio::test]
async fn absent_second_request_is_a_specific_bounded_failure_not_fallback() {
    let (result, state, _) = execute(Case::NoSecond, true).await;
    assert_eq!(
        result.unwrap_err(),
        GateFailure::Playback(WebPlaybackError::OfficialWebSecondStageNotObserved)
    );
    assert_eq!(state.first.load(Ordering::SeqCst), 1);
    assert_eq!(state.second.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn third_songinfo_is_rejected_and_does_not_create_a_third_budget() {
    let (result, state, trace) = execute(Case::ThirdRequest, true).await;
    assert_eq!(
        result.unwrap_err(),
        GateFailure::Playback(WebPlaybackError::AttemptConsumed)
    );
    assert_eq!(state.first.load(Ordering::SeqCst), 1);
    assert_eq!(state.second.load(Ordering::SeqCst), 0);
    assert!(
        trace
            .iter()
            .any(|command| command["method"] == "Fetch.failRequest"
                && command["params"]["requestId"] == THIRD)
    );
}

#[tokio::test]
async fn cancellation_during_first_or_between_stages_never_replays_second() {
    for case in [Case::CancelDuringFirst, Case::CancelAfterFulfill] {
        let (result, state, _) = execute(case, true).await;
        assert!(matches!(
            result,
            Err(GateFailure::Playback(WebPlaybackError::Replaced))
                | Err(GateFailure::Browser(CaptureFailure::Cancelled))
        ));
        assert_eq!(state.first.load(Ordering::SeqCst), 1);
        assert_eq!(state.second.load(Ordering::SeqCst), 0);
    }
}

#[tokio::test]
async fn cleanup_failure_prevents_second_replay_and_final_identity_remains_strict() {
    let (result, state, _) = execute(Case::Normal, false).await;
    assert_eq!(
        result.unwrap_err(),
        GateFailure::Browser(CaptureFailure::CleanupFailed)
    );
    assert_eq!(state.second.load(Ordering::SeqCst), 0);
    let (result, state, _) = execute(Case::WrongFinalIdentity, true).await;
    assert_eq!(
        result.unwrap_err(),
        GateFailure::Playback(WebPlaybackError::Stage2ResponseIdentityMismatch)
    );
    assert_eq!(state.second.load(Ordering::SeqCst), 1);
}

#[test]
fn fixed_stage_diagnostics_and_specific_failures_never_format_sensitive_values() {
    for mode in [CaptureMode::Stage1, CaptureMode::Stage2] {
        let text = identity_diagnostic(
            mode,
            IdentityPresence::request(&format!(
                "https://wwwapi.kugou.com/play/songinfo?hash={HASH}&encode_album_audio_id={ENCODED}&token=synthetic-token"
            )),
        );
        for forbidden in [HASH, ENCODED, "synthetic-token", "https://", "hash="] {
            assert!(!text.contains(forbidden));
        }
        assert!(text.contains("HAS_HASH=1"));
        assert!(text.contains("HAS_ENCODE_ALBUM_AUDIO_ID=1"));
    }
    for (error, category) in [
        (
            WebPlaybackError::OfficialWebStage1IdentityUnproven,
            "OFFICIAL_WEB_STAGE1_IDENTITY_UNPROVEN",
        ),
        (
            WebPlaybackError::Stage1ResponseIdentityMismatch,
            "STAGE1_RESPONSE_IDENTITY_MISMATCH",
        ),
        (
            WebPlaybackError::Stage1EncodedIdMissing,
            "STAGE1_ENCODED_ID_MISSING",
        ),
        (
            WebPlaybackError::OfficialWebSecondStageNotObserved,
            "OFFICIAL_WEB_SECOND_STAGE_NOT_OBSERVED",
        ),
        (
            WebPlaybackError::OfficialWebEncodedIdentityMismatch,
            "OFFICIAL_WEB_ENCODED_IDENTITY_MISMATCH",
        ),
        (
            WebPlaybackError::Stage2ResponseIdentityMismatch,
            "STAGE2_RESPONSE_IDENTITY_MISMATCH",
        ),
    ] {
        assert_eq!(
            result_diagnostic(Err(error.into())),
            format!("KUGOU_GATE result=BLOCKED reason={category} production_enabled=false")
        );
    }
}

#[test]
fn broken_diagnostic_output_does_not_unwind_a_paused_browser_owner() {
    struct BrokenOutput;
    impl std::io::Write for BrokenOutput {
        fn write(&mut self, _: &[u8]) -> std::io::Result<usize> {
            Err(std::io::ErrorKind::BrokenPipe.into())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Err(std::io::ErrorKind::BrokenPipe.into())
        }
    }
    let diagnostic = identity_diagnostic(
        CaptureMode::Stage1,
        IdentityPresence::request("https://synthetic.invalid/?hash=redacted"),
    );
    write_diagnostic(&mut BrokenOutput, &diagnostic);
}
