use kugou_client::{Response, web_playback_candidate::*};
use music_domain::{ProviderId, TrackId};
use provider_kugou::{provider_id, web_playback_candidate::*};
use serde_json::json;
use std::{
    future::{Future, poll_fn},
    pin::pin,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
    task::Poll,
};

const NOW: u64 = 1_800_000_000;
const HASH: &str = "11111111111111111111111111111111";
fn id() -> TrackId {
    TrackId::new(provider_id(), format!("v1:9:{HASH}:8:180:7")).unwrap()
}
fn captured() -> String {
    format!(
        "https://wwwapi.kugou.com/play/songinfo?srcappid=2919&clientver=20000&clienttime={NOW}&mid=synthetic-mid&uuid=synthetic-uuid&dfid=synthetic-web-dfid&appid=1014&platid=4&hash={HASH}&album_id=7&token=synthetic-token&userid=42&signature=00000000000000000000000000000000"
    )
}
#[derive(Default)]
struct Gate {
    ready: AtomicBool,
    calls: AtomicUsize,
    outcome: AtomicUsize,
}
struct Mock(Arc<Gate>);
impl WebPlaybackTransport for Mock {
    async fn send_web(
        &self,
        request: &CapturedWebRequest,
    ) -> Result<WebPlaybackResponse, WebPlaybackError> {
        self.0.calls.fetch_add(1, Ordering::SeqCst);
        assert_eq!(request.url(), captured());
        assert_eq!(request.cookie_header(), "KugooID=42; t=synthetic-token");
        poll_fn(|_| {
            if self.0.ready.load(Ordering::SeqCst) {
                Poll::Ready(())
            } else {
                Poll::Pending
            }
        })
        .await;
        match self.0.outcome.load(Ordering::SeqCst) {
            1 => Err(WebPlaybackError::Network),
            2 => Err(WebPlaybackError::RiskControl),
            3 => Err(WebPlaybackError::RateLimited),
            _ => Ok(WebPlaybackResponse {
                security_challenge: false,
                response: Response {
                    status: 200,
                    content_type: Some("application/json".into()),
                    body: serde_json::to_vec(&json!({"status":1,"data":{
                    "hash":HASH,"album_audio_id":9,"album_id":7,"privilege":0,"is_free_part":0,
                    "play_url":"https://synthetic-media.kugou.com/a.mp3", "bitrate":128_000,
                    "timelength":180_000,"filesize":2_880_000,"extname":"mp3"}}))
                    .unwrap(),
                },
            }),
        }
    }
}
fn stage(owner: &AuthenticatedStandardCandidate<Mock>) {
    owner
        .stage_official_web_session("https://www.kugou.com/", "KugooID=42; t=synthetic-token")
        .unwrap();
}

#[tokio::test]
async fn missing_foreign_invalid_context_and_expired_capture_make_zero_requests() {
    let gate = Arc::new(Gate::default());
    let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
    assert_eq!(owner.state(), CandidateSessionState::Missing);
    assert_eq!(
        owner
            .resolve_once(&id(), &captured(), "synthetic-media.kugou.com", NOW)
            .await
            .unwrap_err(),
        WebPlaybackError::LoginRequired
    );
    stage(&owner);
    assert_eq!(owner.state(), CandidateSessionState::Pending);
    for provider in ["qq-music", "netease-cloud-music"] {
        let foreign = TrackId::new(ProviderId::new(provider).unwrap(), id().opaque()).unwrap();
        assert_eq!(
            owner
                .resolve_once(&foreign, &captured(), "synthetic-media.kugou.com", NOW)
                .await
                .unwrap_err(),
            WebPlaybackError::InvalidCapture
        );
    }
    let missing_album = TrackId::new(provider_id(), format!("v1:9:{HASH}:8:180:-")).unwrap();
    assert_eq!(
        owner
            .resolve_once(
                &missing_album,
                &captured(),
                "synthetic-media.kugou.com",
                NOW
            )
            .await
            .unwrap_err(),
        WebPlaybackError::ProtocolUnsupported
    );
    assert_eq!(
        owner
            .resolve_once(&id(), &captured(), "synthetic-media.kugou.com", NOW + 301)
            .await
            .unwrap_err(),
        WebPlaybackError::InvalidCapture
    );
    assert_eq!(
        owner
            .resolve_once(
                &id(),
                &captured().replace("userid=42", "userid=43"),
                "synthetic-media.kugou.com",
                NOW
            )
            .await
            .unwrap_err(),
        WebPlaybackError::SessionContextRejected
    );
    assert_eq!(gate.calls.load(Ordering::SeqCst), 0);
    assert!(
        owner
            .stage_official_web_session("https://music.163.com/", "MUSIC_U=foreign")
            .is_err()
    );
    assert_eq!(owner.state(), CandidateSessionState::Pending);
}

#[tokio::test]
async fn current_exact_source_is_one_shot_and_never_advertises_authenticated() {
    let gate = Arc::new(Gate::default());
    gate.ready.store(true, Ordering::SeqCst);
    let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
    stage(&owner);
    let source = owner
        .resolve_once(&id(), &captured(), "synthetic-media.kugou.com", NOW)
        .await
        .unwrap();
    assert_eq!(source.url(), "https://synthetic-media.kugou.com/a.mp3");
    assert_eq!(owner.state(), CandidateSessionState::AttemptConsumed);
    stage(&owner); // Restaging does not reopen the experiment's request budget.
    assert_eq!(
        owner
            .resolve_once(&id(), &captured(), "synthetic-media.kugou.com", NOW)
            .await
            .unwrap_err(),
        WebPlaybackError::AttemptConsumed
    );
    assert_eq!(gate.calls.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn logout_provider_switch_account_replacement_and_relogin_dominate_late_results() {
    for replacement in 0..4 {
        for outcome in 0..4 {
            let gate = Arc::new(Gate::default());
            gate.outcome.store(outcome, Ordering::SeqCst);
            let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
            stage(&owner);
            let track = id();
            let url = captured();
            let mut pending =
                pin!(owner.resolve_once(&track, &url, "synthetic-media.kugou.com", NOW));
            assert!(
                poll_fn(|cx| Poll::Ready(pending.as_mut().poll(cx)))
                    .await
                    .is_pending()
            );
            match replacement {
                0 | 1 => owner.clear(), // logout / leaving this provider owner
                2 => owner
                    .stage_official_web_session("https://www.kugou.com/", "KugooID=43; t=new-token")
                    .unwrap(),
                _ => stage(&owner), // even same-account relogin invalidates old work
            }
            gate.ready.store(true, Ordering::SeqCst);
            assert_eq!(pending.await.unwrap_err(), WebPlaybackError::Replaced);
            assert_eq!(gate.calls.load(Ordering::SeqCst), 1);
        }
    }
}

#[tokio::test]
async fn concurrent_dropped_and_failed_attempts_do_not_retry_or_reopen_budget() {
    for outcome in 0..4 {
        let gate = Arc::new(Gate::default());
        gate.outcome.store(outcome, Ordering::SeqCst);
        let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
        stage(&owner);
        let track = id();
        let url = captured();
        {
            let mut pending =
                pin!(owner.resolve_once(&track, &url, "synthetic-media.kugou.com", NOW));
            assert!(
                poll_fn(|cx| Poll::Ready(pending.as_mut().poll(cx)))
                    .await
                    .is_pending()
            );
            assert_eq!(
                owner
                    .resolve_once(&track, &url, "synthetic-media.kugou.com", NOW)
                    .await
                    .unwrap_err(),
                WebPlaybackError::AttemptConsumed
            );
            // Drop/cancel while transport is pending. No spawned task survives.
        }
        stage(&owner);
        assert_eq!(
            owner
                .resolve_once(&track, &url, "synthetic-media.kugou.com", NOW)
                .await
                .unwrap_err(),
            WebPlaybackError::AttemptConsumed
        );
        assert_eq!(gate.calls.load(Ordering::SeqCst), 1);
    }
}

#[tokio::test]
async fn risk_and_rate_limit_are_sticky_and_network_failure_is_not_logout() {
    for (outcome, expected) in [
        (1, WebPlaybackError::Network),
        (2, WebPlaybackError::RiskControl),
        (3, WebPlaybackError::RateLimited),
    ] {
        let gate = Arc::new(Gate::default());
        gate.ready.store(true, Ordering::SeqCst);
        gate.outcome.store(outcome, Ordering::SeqCst);
        let owner = AuthenticatedStandardCandidate::new(Mock(gate.clone()));
        stage(&owner);
        assert_eq!(
            owner
                .resolve_once(&id(), &captured(), "synthetic-media.kugou.com", NOW)
                .await
                .unwrap_err(),
            expected
        );
        let state = if outcome == 1 {
            CandidateSessionState::AttemptConsumed
        } else {
            CandidateSessionState::Halted
        };
        assert_eq!(owner.state(), state);
        stage(&owner);
        assert_eq!(owner.state(), state);
        assert_eq!(gate.calls.load(Ordering::SeqCst), 1);
    }
}
