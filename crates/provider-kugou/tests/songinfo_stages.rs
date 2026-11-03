use kugou_client::{
    Response,
    web_playback_candidate::{songinfo_stages::*, *},
};
use music_domain::TrackId;
use provider_kugou::{provider_id, web_playback_candidate::*};
use serde_json::json;
use std::{
    future::{Future, poll_fn},
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
    task::Poll,
};
const NOW: u64 = 1_800_000_000;
const HASH: &str = "11111111111111111111111111111111";
const ENCODED: &str = "synthetic-server-issued-id";
fn id() -> TrackId {
    TrackId::new(provider_id(), format!("v1:9:{HASH}:8:180:7")).unwrap()
}
fn capture(second: bool, encoded: &str) -> OfficialWebCapture {
    let mut url = url::Url::parse("https://wwwapi.kugou.com/play/songinfo").unwrap();
    url.query_pairs_mut().append_pair(
        if second {
            "encode_album_audio_id"
        } else {
            "hash"
        },
        if second { encoded } else { HASH },
    );
    let cookies: Vec<_> = [("KugooID", "42"), ("t", "synthetic-token")]
        .into_iter()
        .map(|(name, value)| ProfileCookie {
            name: name.into(),
            value: value.into(),
            domain: ".kugou.com".into(),
            path: "/".into(),
            secure: true,
        })
        .collect();
    let headers: Vec<_> = [
        ("User-Agent", "SyntheticOfficialBrowser/1"),
        ("Origin", "https://www.kugou.com"),
        ("Referer", "https://www.kugou.com/"),
    ]
    .into_iter()
    .map(|(k, v)| (k.into(), v.into()))
    .collect();
    if second {
        OfficialWebCapture::from_stage2_cdp(url.as_str(), "GET", &headers, &cookies, NOW)
    } else {
        OfficialWebCapture::from_stage1_cdp(url.as_str(), "GET", &headers, &cookies, NOW)
    }
    .unwrap()
}
#[derive(Default)]
struct State {
    first: AtomicUsize,
    second: AtomicUsize,
    ready: AtomicBool,
    error: AtomicUsize,
}
struct Mock(Arc<State>);
impl WebPlaybackTransport for Mock {
    async fn send_stage1(
        &self,
        request: &CapturedWebRequest,
    ) -> Result<Stage1WireResponse, WebPlaybackError> {
        self.0.first.fetch_add(1, Ordering::SeqCst);
        assert_eq!(
            url::Url::parse(request.url())
                .unwrap()
                .query_pairs()
                .collect::<Vec<_>>(),
            [("hash".into(), HASH.into())]
        );
        poll_fn(|_| {
            if self.0.ready.load(Ordering::SeqCst) {
                Poll::Ready(())
            } else {
                Poll::Pending
            }
        })
        .await;
        match self.0.error.load(Ordering::SeqCst) {
            1 => return Err(WebPlaybackError::Network),
            2 => return Err(WebPlaybackError::RiskControl),
            3 => return Err(WebPlaybackError::RateLimited),
            _ => (),
        }
        let body=serde_json::to_vec(&json!({"status":1,"data":{"hash":HASH,"encode_album_audio_id":ENCODED,"album_audio_id":9}})).unwrap();
        Ok(Stage1WireResponse::new(
            WebPlaybackResponse {
                response: Response {
                    status: 200,
                    content_type: Some("application/json".into()),
                    body,
                },
                security_challenge: false,
            },
            vec![("Content-Type".into(), "application/json".into())],
        ))
    }
    fn send_web(
        &self,
        request: &CapturedWebRequest,
    ) -> impl Future<Output = Result<WebPlaybackResponse, WebPlaybackError>> + Send {
        self.0.second.fetch_add(1, Ordering::SeqCst);
        assert_eq!(self.0.first.load(Ordering::SeqCst), 1);
        assert_eq!(
            url::Url::parse(request.url())
                .unwrap()
                .query_pairs()
                .collect::<Vec<_>>(),
            [("encode_album_audio_id".into(), ENCODED.into())]
        );
        std::future::ready(Ok(WebPlaybackResponse{response:Response{status:200,content_type:Some("application/json".into()),body:serde_json::to_vec(&json!({"status":1,"data":{
                "privilege":0,"is_free_part":0,"play_url":"https://offline-media.example.org/synthetic.mp3","bitrate":128_000,"timelength":180_000,"filesize":2_880_000,"extname":"mp3",
        }})).unwrap()},security_challenge:false}))
    }
}
fn setup() -> (AuthenticatedStandardCandidate<Mock>, Arc<State>) {
    let state = Arc::new(State::default());
    state.ready.store(true, Ordering::SeqCst);
    (
        AuthenticatedStandardCandidate::new(Mock(state.clone())),
        state,
    )
}
fn first(owner: &AuthenticatedStandardCandidate<Mock>) -> BoundStage1 {
    let attempt = owner.begin_capture(&id()).unwrap();
    owner.bind_stage1(attempt, capture(false, ""), NOW).unwrap()
}
async fn continuation(owner: &AuthenticatedStandardCandidate<Mock>) -> Box<Stage1Continuation> {
    let Stage1Progress::Continue(continuation) =
        owner.resolve_stage1_once(first(owner)).await.unwrap()
    else {
        panic!("expected synthetic continuation")
    };
    continuation
}

#[tokio::test]
async fn two_separate_budgets_preserve_exact_chain_and_do_not_allow_a_third_capture() {
    let (owner, state) = setup();
    let continuation = continuation(&owner).await;
    assert!(owner.stage1_fulfillment(&continuation).is_ok());
    assert_eq!(state.first.load(Ordering::SeqCst), 1);
    assert_eq!(state.second.load(Ordering::SeqCst), 0);
    let bound = owner
        .bind_stage2(continuation, capture(true, ENCODED), NOW)
        .unwrap();
    assert_eq!(
        owner.resolve_captured_once(bound).await.unwrap().quality(),
        Some(WebQuality::Standard)
    );
    assert_eq!(state.second.load(Ordering::SeqCst), 1);
    assert_eq!(
        owner.begin_capture(&id()).unwrap_err(),
        WebPlaybackError::AttemptConsumed
    );
    owner.clear();
    assert_eq!(
        owner.begin_capture(&id()).unwrap_err(),
        WebPlaybackError::AttemptConsumed
    );
    assert_eq!(MAX_SONGINFO_REQUESTS, 2);
}

#[tokio::test]
async fn failures_never_refund_first_stage_and_risk_or_rate_stops_remain_sticky() {
    for (code, error) in [
        (1, WebPlaybackError::Network),
        (2, WebPlaybackError::RiskControl),
        (3, WebPlaybackError::RateLimited),
    ] {
        let (owner, state) = setup();
        state.error.store(code, Ordering::SeqCst);
        assert_eq!(
            owner.resolve_stage1_once(first(&owner)).await.unwrap_err(),
            error
        );
        assert_eq!(state.first.load(Ordering::SeqCst), 1);
        assert_eq!(state.second.load(Ordering::SeqCst), 0);
        if code == 1 {
            assert_eq!(owner.state(), CandidateSessionState::Pending);
        } else {
            assert_eq!(owner.state(), CandidateSessionState::Halted);
        }
        owner.clear();
        assert_eq!(
            owner.begin_capture(&id()).unwrap_err(),
            if code == 1 {
                WebPlaybackError::AttemptConsumed
            } else {
                WebPlaybackError::RiskControl
            }
        );
    }
}

#[tokio::test]
async fn logout_replacement_and_same_account_relogin_dominate_pending_stage1() {
    for _ in ["logout", "account replacement", "same-account relogin"] {
        let (owner, state) = setup();
        state.ready.store(false, Ordering::SeqCst);
        let mut pending = Box::pin(owner.resolve_stage1_once(first(&owner)));
        assert!(
            poll_fn(|cx| Poll::Ready(pending.as_mut().poll(cx)))
                .await
                .is_pending()
        );
        owner.clear();
        state.ready.store(true, Ordering::SeqCst);
        assert_eq!(pending.await.unwrap_err(), WebPlaybackError::Replaced);
        assert_eq!(state.first.load(Ordering::SeqCst), 1);
        assert_eq!(state.second.load(Ordering::SeqCst), 0);
    }
}

#[tokio::test]
async fn dropped_stage1_is_consumed_and_cannot_restart_or_spawn_late_work() {
    let (owner, state) = setup();
    state.ready.store(false, Ordering::SeqCst);
    let mut pending = Box::pin(owner.resolve_stage1_once(first(&owner)));
    assert!(
        poll_fn(|cx| Poll::Ready(pending.as_mut().poll(cx)))
            .await
            .is_pending()
    );
    drop(pending);
    state.ready.store(true, Ordering::SeqCst);
    assert_eq!(
        owner.begin_capture(&id()).unwrap_err(),
        WebPlaybackError::AttemptConsumed
    );
    assert_eq!(state.first.load(Ordering::SeqCst), 1);
    assert_eq!(state.second.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn continuation_is_owner_generation_and_session_bound_before_fulfill_or_stage2() {
    let (owner, state) = setup();
    let continuation = continuation(&owner).await;
    let (foreign, _) = setup();
    assert_eq!(
        foreign.stage1_fulfillment(&continuation).unwrap_err(),
        WebPlaybackError::Replaced
    );
    assert_eq!(
        foreign
            .bind_stage2(continuation, capture(true, ENCODED), NOW)
            .unwrap_err(),
        WebPlaybackError::Replaced
    );
    assert_eq!(state.second.load(Ordering::SeqCst), 0);
    let (owner, state) = setup();
    let continuation = self::continuation(&owner).await;
    owner.clear();
    assert_eq!(
        owner.stage1_fulfillment(&continuation).unwrap_err(),
        WebPlaybackError::Replaced
    );
    assert_eq!(
        owner
            .bind_stage2(continuation, capture(true, ENCODED), NOW)
            .unwrap_err(),
        WebPlaybackError::Replaced
    );
    assert_eq!(state.second.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn differing_server_issued_identity_never_spends_stage2_network_budget() {
    let (owner, state) = setup();
    let continuation = continuation(&owner).await;
    assert_eq!(
        owner
            .bind_stage2(continuation, capture(true, "synthetic-other-id"), NOW)
            .unwrap_err(),
        WebPlaybackError::OfficialWebEncodedIdentityMismatch
    );
    assert_eq!(state.first.load(Ordering::SeqCst), 1);
    assert_eq!(state.second.load(Ordering::SeqCst), 0);
}
