use music_domain::{AudioQuality, PlaylistId, PlaylistPurpose, TrackId};
use netease_client::{Credential, Error, NeteaseClient, Request, Response, Transport};
use provider_api::*;
use provider_netease::{NeteaseProvider, provider_id};
use serde_json::{Value, json};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicUsize, Ordering},
};
use tokio::sync::Notify;
enum Reply {
    Json(Value),
    Confirmed,
    Failure(Error),
    Blocked(Arc<Notify>, Arc<Notify>, Value),
}
struct Fake {
    replies: Mutex<std::collections::VecDeque<Reply>>,
    calls: Arc<AtomicUsize>,
    auth_calls: Arc<AtomicUsize>,
}
impl Transport for Fake {
    async fn send(&self, r: Request) -> Result<Response, Error> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        if let Some(cookie) = r.cookie() {
            assert!(cookie.contains("synthetic"));
            self.auth_calls.fetch_add(1, Ordering::SeqCst);
        }
        let reply = self
            .replies
            .lock()
            .unwrap()
            .pop_front()
            .expect("unexpected request");
        let mut cookies = vec![];
        let value = match reply {
            Reply::Json(v) => v,
            Reply::Failure(e) => return Err(e),
            Reply::Confirmed => {
                cookies = vec![
                    "MUSIC_U=synthetic-session; Secure; HttpOnly".into(),
                    "__csrf=synthetic-csrf; Secure".into(),
                ];
                json!({"code":803})
            }
            Reply::Blocked(start, release, v) => {
                start.notify_one();
                release.notified().await;
                v
            }
        };
        Ok(Response {
            status: 200,
            body: serde_json::to_vec(&value).unwrap(),
            set_cookies: cookies,
        })
    }
}
fn provider(
    replies: Vec<Reply>,
) -> (
    Arc<NeteaseProvider<Fake>>,
    Arc<AtomicUsize>,
    Arc<AtomicUsize>,
) {
    let c = Arc::new(AtomicUsize::new(0));
    let a = Arc::new(AtomicUsize::new(0));
    (
        Arc::new(NeteaseProvider::new(NeteaseClient::new(Fake {
            replies: Mutex::new(replies.into()),
            calls: c.clone(),
            auth_calls: a.clone(),
        }))),
        c,
        a,
    )
}
fn account() -> Value {
    json!({"code":200,"account":{"id":42},"profile":{"userId":42,"nickname":"Synthetic user","avatarUrl":"https://fixture.invalid/avatar"}})
}
fn credential() -> Vec<u8> {
    serde_json::to_vec(&json!({"version":1,"provider":"netease-cloud-music","music_u":"synthetic-session","csrf":"synthetic-csrf"})).unwrap()
}
fn key() -> Reply {
    Reply::Json(json!({"code":200,"unikey":"synthetic-qr-key"}))
}
fn song() -> Value {
    json!({"id":1,"name":"Fixture","ar":[{"id":2,"name":"Artist"}],"al":{"id":3,"name":"Album"},"dt":123_000})
}
#[tokio::test]
async fn restore_requires_verification_and_preserves_transient_candidate() {
    let (p, c, _) = provider(vec![
        Reply::Failure(Error::TemporaryNetworkFailure),
        Reply::Json(account()),
    ]);
    p.import_credential(&credential()).unwrap();
    assert!(!p.has_authenticated_credential());
    assert!(p.export_credential().unwrap().is_none());
    assert_eq!(
        p.verify_restored_credential().await,
        Err(AccountSummaryError::Network)
    );
    assert!(!p.has_authenticated_credential());
    p.verify_restored_credential().await.unwrap();
    assert!(p.has_authenticated_credential());
    assert_eq!(
        Credential::import(&p.export_credential().unwrap().unwrap()).unwrap(),
        Credential::import(&credential()).unwrap()
    );
    assert_eq!(c.load(Ordering::SeqCst), 2);
    p.sign_out();
    assert!(!p.has_authenticated_credential());
    assert!(p.export_credential().unwrap().is_none());
}
#[test]
fn credential_documents_reject_foreign_versions_injections_and_oversize() {
    let bytes = credential();
    let c = Credential::import(&bytes).unwrap();
    assert_eq!(format!("{c:?}"), "NetEaseCredential([REDACTED])");
    for (key, value) in [
        ("version", json!(2)),
        ("provider", json!("qq-music")),
        ("music_u", json!("bad\r\nCookie: injected")),
        ("csrf", json!("bad;evil")),
        ("music_u", json!("")),
    ] {
        let mut v: Value = serde_json::from_slice(&bytes).unwrap();
        v[key] = value;
        assert!(Credential::import(&serde_json::to_vec(&v).unwrap()).is_err());
    }
    assert!(Credential::import(&vec![b'x'; 8193]).is_err());
}
#[tokio::test]
async fn qr_wait_scan_confirm_and_account_validation_are_one_generation() {
    let (p, c, a) = provider(vec![
        key(),
        Reply::Json(json!({"code":801})),
        Reply::Json(json!({"code":802})),
        Reply::Confirmed,
        Reply::Json(account()),
    ]);
    let mut qr = p
        .begin_qr_authentication(QrAuthenticationChannel::ProviderDefault)
        .await
        .unwrap();
    assert!(
        qr.challenge()
            .image_bytes()
            .starts_with(b"\x89PNG\r\n\x1a\n")
    );
    assert!(!format!("{:?}", qr.challenge()).contains("synthetic"));
    assert_eq!(
        qr.advance().await.unwrap(),
        QrAuthenticationProgress::WaitingForScan
    );
    assert!(!p.has_authenticated_credential());
    assert_eq!(
        qr.advance().await.unwrap(),
        QrAuthenticationProgress::ScannedAwaitingConfirmation
    );
    assert!(!p.has_authenticated_credential());
    assert_eq!(
        qr.advance().await.unwrap(),
        QrAuthenticationProgress::Authenticated
    );
    assert!(p.has_authenticated_credential());
    assert!(!qr.is_active());
    assert_eq!(
        qr.advance().await,
        Err(AuthenticationError::SessionFinished)
    );
    assert_eq!((c.load(Ordering::SeqCst), a.load(Ordering::SeqCst)), (5, 1));
    drop(qr);
    assert!(p.has_authenticated_credential());
}
#[tokio::test]
async fn cancel_old_qr_cannot_cancel_new_attempt_and_drop_invalidates_active_attempt() {
    let (p, _, _) = provider(vec![key(), key(), Reply::Json(json!({"code":801}))]);
    let old = p
        .begin_qr_authentication(QrAuthenticationChannel::ProviderDefault)
        .await
        .unwrap();
    let mut new = p
        .begin_qr_authentication(QrAuthenticationChannel::ProviderDefault)
        .await
        .unwrap();
    assert!(!old.cancel());
    assert!(!old.is_active());
    drop(old);
    assert!(new.is_active());
    assert_eq!(
        new.advance().await.unwrap(),
        QrAuthenticationProgress::WaitingForScan
    );
    assert!(new.cancel());
    assert_eq!(new.advance().await, Err(AuthenticationError::Replaced));
}
#[tokio::test(start_paused = true)]
async fn deadline_spans_creation_and_polling_and_does_not_send_after_expiry() {
    let (p, c, _) = provider(vec![key()]);
    let mut qr = p
        .begin_qr_authentication(QrAuthenticationChannel::ProviderDefault)
        .await
        .unwrap();
    tokio::time::advance(std::time::Duration::from_secs(181)).await;
    assert_eq!(
        qr.advance().await.unwrap(),
        QrAuthenticationProgress::TimedOut
    );
    assert_eq!(c.load(Ordering::SeqCst), 1);
    assert!(!p.has_authenticated_credential());
}
#[tokio::test]
async fn rejection_clears_only_the_exact_owner_and_unknown_codes_retain_it() {
    let (p, _, _) = provider(vec![
        Reply::Json(account()),
        Reply::Json(json!({"code":9999})),
        Reply::Json(json!({"code":301})),
    ]);
    p.import_credential(&credential()).unwrap();
    p.verify_restored_credential().await.unwrap();
    assert!(matches!(
        p.account_summary().await,
        Err(AccountSummaryError::ServiceUnavailable)
    ));
    assert!(p.has_authenticated_credential());
    assert!(matches!(
        p.account_summary().await,
        Err(AccountSummaryError::CredentialRejected)
    ));
    assert!(!p.has_authenticated_credential());
}
#[tokio::test]
async fn late_restore_and_rejection_cannot_overwrite_replacement_credential() {
    let start = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    let (p, _, _) = provider(vec![
        Reply::Blocked(start.clone(), release.clone(), json!({"code":301})),
        Reply::Json(account()),
    ]);
    p.import_credential(&credential()).unwrap();
    let other = p.clone();
    let old = tokio::spawn(async move { other.verify_restored_credential().await });
    start.notified().await;
    p.sign_out();
    p.import_credential(&credential()).unwrap();
    p.verify_restored_credential().await.unwrap();
    assert_eq!(old.await.unwrap(), Err(AccountSummaryError::Replaced));
    assert!(p.has_authenticated_credential());
    release.notify_one();
}
#[tokio::test]
async fn blocked_qr_poll_is_dropped_after_signout() {
    let start = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    let (p, _, _) = provider(vec![
        key(),
        Reply::Blocked(start.clone(), release.clone(), json!({"code":801})),
    ]);
    let mut qr = p
        .begin_qr_authentication(QrAuthenticationChannel::ProviderDefault)
        .await
        .unwrap();
    let task = tokio::spawn(async move { qr.advance().await });
    start.notified().await;
    p.sign_out();
    assert_eq!(task.await.unwrap(), Err(AuthenticationError::Replaced));
    assert!(!p.has_authenticated_credential());
}
#[tokio::test]
async fn account_library_liked_and_recommendations_remain_exact_and_bounded() {
    let playlist =
        json!({"id":4,"name":"Liked","trackCount":2,"specialType":5,"creator":{"userId":42}});
    let (p, _, a) = provider(vec![
        Reply::Json(account()),
        Reply::Json(account()),
        Reply::Json(json!({"code":200,"playlist":[playlist],"more":false})),
        Reply::Json(json!({"code":200,"ids":[1,5]})),
        Reply::Json(json!({"code":200,"songs":[song()]})),
        Reply::Json(json!({"code":200,"data":{"dailySongs":[song()]}})),
        Reply::Json(json!({"code":200,"data":[song()]})),
        Reply::Json(json!({"code":200,"recommend":[]})),
    ]);
    p.import_credential(&credential()).unwrap();
    p.verify_restored_credential().await.unwrap();
    assert_eq!(
        p.account_summary().await.unwrap().display_name(),
        "Synthetic user"
    );
    let rows = p.user_playlists().await.unwrap();
    assert_eq!(rows[0].purpose(), PlaylistPurpose::LikedSongs);
    assert_eq!(rows[0].id().opaque(), "liked:42:4");
    let page = p
        .playlist_tracks_page(PlaylistId::new(provider_id(), "liked:42:4").unwrap(), 0, 2)
        .await
        .unwrap();
    assert_eq!(page.next_offset(), 2);
    assert_eq!(page.omitted_track_count(), 1);
    assert_eq!(p.daily_tracks().await.unwrap()[0].id().opaque(), "1");
    assert_eq!(p.personalized_tracks().await.unwrap().len(), 1);
    assert!(p.personalized_playlists().await.unwrap().is_empty());
    assert_eq!(a.load(Ordering::SeqCst), 8);
}
#[tokio::test]
async fn authenticated_media_rejection_clears_session_without_source_substitution() {
    let (p, c, a) = provider(vec![
        Reply::Json(account()),
        Reply::Json(json!({"code":301})),
    ]);
    p.import_credential(&credential()).unwrap();
    p.verify_restored_credential().await.unwrap();
    assert!(matches!(
        p.media_source_resolver()
            .resolve_media(
                TrackId::new(provider_id(), "1").unwrap(),
                AudioQuality::Standard
            )
            .await,
        Err(MediaResolutionError::CredentialRejected)
    ));
    assert!(!p.has_authenticated_credential());
    assert_eq!((c.load(Ordering::SeqCst), a.load(Ordering::SeqCst)), (2, 2));
}
#[tokio::test]
async fn qr_terminal_states_and_retry_budget_never_install_a_credential() {
    for (replies, expected) in [
        (
            vec![key(), Reply::Json(json!({"code":800}))],
            Ok(QrAuthenticationProgress::Expired),
        ),
        (
            vec![key(), Reply::Json(json!({"code":803}))],
            Err(AuthenticationError::InvalidResponse),
        ),
        (
            vec![key(), Reply::Json(json!({"code":9876}))],
            Err(AuthenticationError::ServiceUnavailable),
        ),
    ] {
        let (p, _, _) = provider(replies);
        let mut qr = p
            .begin_qr_authentication(QrAuthenticationChannel::ProviderDefault)
            .await
            .unwrap();
        assert_eq!(qr.advance().await, expected);
        assert!(!qr.is_active());
        assert!(!p.has_authenticated_credential());
    }
    let (p, c, _) = provider(vec![
        key(),
        Reply::Failure(Error::TemporaryNetworkFailure),
        Reply::Failure(Error::TemporaryNetworkFailure),
        Reply::Failure(Error::TemporaryNetworkFailure),
    ]);
    let mut qr = p
        .begin_qr_authentication(QrAuthenticationChannel::ProviderDefault)
        .await
        .unwrap();
    for _ in 0..2 {
        assert_eq!(qr.advance().await, Err(AuthenticationError::Network));
        assert!(qr.is_active());
    }
    assert_eq!(
        qr.advance().await,
        Err(AuthenticationError::TooManyNetworkFailures)
    );
    assert!(!qr.is_active());
    assert_eq!(c.load(Ordering::SeqCst), 4);
}
#[tokio::test]
async fn signed_out_account_reads_and_non_native_channel_make_no_requests() {
    let (p, c, _) = provider(vec![]);
    assert!(p.user_playlists().await.is_err());
    assert!(p.daily_tracks().await.is_err());
    assert!(p.personalized_tracks().await.is_err());
    assert!(p.favorite_albums(0, 10).await.is_err());
    assert!(p.favorite_artists(0, 10).await.is_err());
    assert!(
        p.begin_qr_authentication(QrAuthenticationChannel::Qq)
            .await
            .is_err()
    );
    assert_eq!(c.load(Ordering::SeqCst), 0);
}
#[tokio::test]
async fn favorite_pages_map_to_existing_domain_and_malformed_continuation_stops() {
    let (p, _, _) = provider(vec![
        Reply::Json(account()),
        Reply::Json(json!({"code":200,"data":[{"id":3,"name":"Album"}],"count":1,"hasMore":false})),
        Reply::Json(
            json!({"code":200,"data":[{"id":2,"name":"Artist"}],"count":1,"hasMore":false}),
        ),
        Reply::Json(json!({"code":200,"data":[],"count":2,"hasMore":true})),
    ]);
    p.import_credential(&credential()).unwrap();
    p.verify_restored_credential().await.unwrap();
    assert_eq!(
        p.favorite_albums(0, 1).await.unwrap().albums()[0]
            .id()
            .opaque(),
        "3"
    );
    assert_eq!(
        p.favorite_artists(0, 1).await.unwrap().artists()[0]
            .id()
            .opaque(),
        "2"
    );
    assert!(matches!(
        p.favorite_albums(0, 1).await,
        Err(UserLibraryError::InvalidResponse)
    ));
    assert!(p.has_authenticated_credential());
}
#[tokio::test]
async fn authenticated_media_success_uses_explicit_cookie_and_returns_actual_standard_quality() {
    let (p, _, a) = provider(vec![
        Reply::Json(account()),
        Reply::Json(
            json!({"code":200,"data":[{"id":1,"code":200,"url":"https://fixture.invalid/source","type":"mp3","expi":600,"freeTrialInfo":null,"level":"standard"}]}),
        ),
    ]);
    p.import_credential(&credential()).unwrap();
    p.verify_restored_credential().await.unwrap();
    let source = p
        .media_source_resolver()
        .resolve_media(
            TrackId::new(provider_id(), "1").unwrap(),
            AudioQuality::Lossless,
        )
        .await
        .unwrap();
    assert_eq!(source.quality(), AudioQuality::Standard);
    assert_eq!(a.load(Ordering::SeqCst), 2);
}
#[tokio::test]
async fn new_qr_generation_drops_previous_authenticated_read() {
    let start = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    let (p, _, _) = provider(vec![
        Reply::Json(account()),
        Reply::Blocked(start.clone(), release.clone(), json!({"code":301})),
        key(),
        Reply::Confirmed,
        Reply::Json(account()),
    ]);
    p.import_credential(&credential()).unwrap();
    p.verify_restored_credential().await.unwrap();
    let other = p.clone();
    let old = tokio::spawn(async move { other.account_summary().await });
    start.notified().await;
    let mut qr = p
        .begin_qr_authentication(QrAuthenticationChannel::ProviderDefault)
        .await
        .unwrap();
    assert!(!p.has_authenticated_credential());
    assert_eq!(
        qr.advance().await.unwrap(),
        QrAuthenticationProgress::Authenticated
    );
    assert!(matches!(
        old.await.unwrap(),
        Err(AccountSummaryError::Replaced)
    ));
    assert!(p.has_authenticated_credential());
}
#[tokio::test]
async fn cancellation_handle_interrupts_borrowed_poll_without_signing_out_another_generation() {
    let start = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    let (p, _, _) = provider(vec![
        key(),
        Reply::Blocked(start.clone(), release.clone(), json!({"code":801})),
        key(),
    ]);
    let mut qr = p
        .begin_qr_authentication(QrAuthenticationChannel::ProviderDefault)
        .await
        .unwrap();
    let cancel = qr.cancellation_handle();
    let task = tokio::spawn(async move { qr.advance().await });
    start.notified().await;
    assert!(cancel.cancel());
    assert_eq!(task.await.unwrap(), Err(AuthenticationError::Replaced));
    let next = p
        .begin_qr_authentication(QrAuthenticationChannel::ProviderDefault)
        .await
        .unwrap();
    assert!(!cancel.cancel());
    assert!(next.is_active());
}
#[tokio::test]
async fn liked_route_retains_actual_playlist_identity_and_rejects_other_owners() {
    let (p, c, _) = provider(vec![
        Reply::Json(account()),
        Reply::Json(
            json!({"code":200,"playlist":[{"id":4,"name":"Liked","trackCount":0,"specialType":5,"creator":{"userId":42}}],"more":false}),
        ),
    ]);
    p.import_credential(&credential()).unwrap();
    p.verify_restored_credential().await.unwrap();
    let rows = p.user_playlists().await.unwrap();
    assert_eq!(rows[0].id().opaque(), "liked:42:4");
    for opaque in [
        "liked:43:4",
        "liked:42:5",
        "liked:042:4",
        "liked:42:4:extra",
    ] {
        assert!(matches!(
            p.playlist_tracks_page(PlaylistId::new(provider_id(), opaque).unwrap(), 0, 1)
                .await,
            Err(UserLibraryError::InvalidResponse)
        ));
    }
    assert_eq!(c.load(Ordering::SeqCst), 2);
}

fn private_playlist() -> Value {
    json!({"code":200,"playlist":{"id":4,"name":"Private fixture","trackCount":2,"trackIds":[{"id":1},{"id":7}]}})
}
#[tokio::test]
async fn authenticated_playlist_keeps_credentials_across_both_bounded_requests() {
    let (p, calls, auth_calls) = provider(vec![
        Reply::Json(account()),
        Reply::Json(private_playlist()),
        Reply::Json(json!({"code":200,"songs":[song()]})),
    ]);
    p.import_credential(&credential()).unwrap();
    p.verify_restored_credential().await.unwrap();
    let page = p
        .playlist_tracks_page(PlaylistId::new(provider_id(), "4").unwrap(), 0, 2)
        .await
        .unwrap();
    assert_eq!(page.next_offset(), 2);
    assert_eq!(page.omitted_track_count(), 1);
    assert_eq!(page.tracks()[0].id().opaque(), "1");
    assert_eq!(
        (
            calls.load(Ordering::SeqCst),
            auth_calls.load(Ordering::SeqCst)
        ),
        (3, 3)
    );
}
#[tokio::test]
async fn replacing_playlist_session_drops_metadata_and_prevents_detail_request() {
    let start = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    let (p, calls, _) = provider(vec![
        Reply::Json(account()),
        Reply::Blocked(start.clone(), release, private_playlist()),
    ]);
    p.import_credential(&credential()).unwrap();
    p.verify_restored_credential().await.unwrap();
    let reader = p.clone();
    let task = tokio::spawn(async move {
        reader
            .playlist_tracks_page(PlaylistId::new(provider_id(), "4").unwrap(), 0, 2)
            .await
    });
    start.notified().await;
    p.sign_out();
    assert_eq!(task.await.unwrap(), Err(UserLibraryError::Replaced));
    assert_eq!(calls.load(Ordering::SeqCst), 2);
}
#[tokio::test]
async fn private_playlist_rejection_never_retries_as_anonymous() {
    let (p, calls, auth_calls) = provider(vec![
        Reply::Json(account()),
        Reply::Json(json!({"code":301})),
    ]);
    p.import_credential(&credential()).unwrap();
    p.verify_restored_credential().await.unwrap();
    assert_eq!(
        p.playlist_tracks_page(PlaylistId::new(provider_id(), "4").unwrap(), 0, 2)
            .await,
        Err(UserLibraryError::CredentialRejected)
    );
    assert!(!p.has_authenticated_credential());
    assert_eq!(
        (
            calls.load(Ordering::SeqCst),
            auth_calls.load(Ordering::SeqCst)
        ),
        (2, 2)
    );
}
