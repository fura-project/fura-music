use music_domain::{PlaylistId, TrackId};
use netease_client::{Error, NeteaseClient, Request, Response, Transport};
use provider_api::{
    LibraryMutationError, PlaylistCreationProvider, PlaylistTrackMutationProvider,
    QrAuthenticationProvider, RecentHistoryProvider, TrackLikeMutationProvider, UserLibraryError,
};
use provider_netease::{NeteaseProvider, provider_id};
use serde_json::{Value, json};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use tokio::sync::Notify;

enum Reply {
    Json(Value),
    Failure(Error),
    Blocked {
        started: Arc<Notify>,
        release: Arc<Notify>,
        value: Value,
    },
}

struct RecordingTransport {
    replies: Mutex<VecDeque<Reply>>,
    urls: Arc<Mutex<Vec<String>>>,
}

impl Transport for RecordingTransport {
    fn send(
        &self,
        request: Request,
    ) -> impl std::future::Future<Output = Result<Response, Error>> + Send {
        self.urls.lock().unwrap().push(request.url().to_owned());
        let reply = self.replies.lock().unwrap().pop_front();
        async move {
            let value = match reply.expect("unexpected hidden request") {
                Reply::Json(value) => value,
                Reply::Failure(error) => return Err(error),
                Reply::Blocked {
                    started,
                    release,
                    value,
                } => {
                    started.notify_one();
                    release.notified().await;
                    value
                }
            };
            Ok(Response {
                status: 200,
                body: serde_json::to_vec(&value).unwrap(),
                set_cookies: vec![],
            })
        }
    }
}

fn account() -> Value {
    json!({
        "code":200,
        "account":{"id":42},
        "profile":{"userId":42,"nickname":"Synthetic user","avatarUrl":null}
    })
}

fn credential() -> Vec<u8> {
    serde_json::to_vec(&json!({
        "version":1,
        "provider":"netease-cloud-music",
        "music_u":"synthetic-session",
        "csrf":"synthetic-csrf"
    }))
    .unwrap()
}

fn song(id: u64, name: Option<&str>) -> Value {
    let mut value = json!({
        "id":id,
        "name":name.unwrap_or_default(),
        "ar":[{"id":2,"name":"Artist"}],
        "al":{"id":3,"name":"Album"},
        "dt":123_000
    });
    if name.is_none() {
        value.as_object_mut().unwrap().remove("name");
    }
    value
}

fn recent_row(id: u64, name: Option<&str>, play_time: u64) -> Value {
    json!({
        "resourceId":id.to_string(),
        "resourceType":"SONG",
        "playTime":play_time,
        "data":song(id,name)
    })
}

async fn build_provider(
    replies: Vec<Reply>,
) -> (
    Arc<NeteaseProvider<RecordingTransport>>,
    Arc<Mutex<Vec<String>>>,
) {
    let urls = Arc::new(Mutex::new(Vec::new()));
    let provider = Arc::new(NeteaseProvider::new(NeteaseClient::new(
        RecordingTransport {
            replies: Mutex::new(replies.into()),
            urls: Arc::clone(&urls),
        },
    )));
    provider.import_credential(&credential()).unwrap();
    provider.verify_pending_credential().await.unwrap();
    (provider, urls)
}

fn track(id: &str) -> TrackId {
    TrackId::new(provider_id(), id).unwrap()
}

fn playlist(id: &str) -> PlaylistId {
    PlaylistId::new(provider_id(), id).unwrap()
}

fn user_playlists() -> Value {
    json!({
        "code":200,
        "more":false,
        "playlist":[
            {
                "id":100,
                "name":"Liked",
                "coverImgUrl":null,
                "trackCount":1,
                "specialType":5,
                "creator":{"userId":42}
            },
            {
                "id":101,
                "name":"Owned",
                "coverImgUrl":null,
                "trackCount":1,
                "specialType":0,
                "creator":{"userId":42}
            },
            {
                "id":102,
                "name":"Saved",
                "coverImgUrl":null,
                "trackCount":1,
                "specialType":0,
                "creator":{"userId":77}
            }
        ]
    })
}

#[tokio::test]
async fn recent_history_is_one_bounded_raw_cursor_snapshot() {
    let (provider, urls) = build_provider(vec![
        Reply::Json(account()),
        Reply::Json(json!({
            "code":200,
            "data":{
                "total":100,
                "list":[
                    recent_row(1,Some("First"),1_700_000_000_001_u64),
                    recent_row(2,None,1_700_000_000_002_u64),
                    recent_row(1,Some("First again"),1_700_000_000_003_u64)
                ]
            }
        })),
    ])
    .await;

    let first = provider.recent_tracks_page(0, 2).await.unwrap();
    assert_eq!(
        (first.offset(), first.next_offset(), first.total()),
        (0, 2, 3)
    );
    assert!(!first.total_is_exact());
    assert!(first.has_more());
    assert_eq!(first.omitted_track_count(), 1);
    assert_eq!(first.tracks()[0].id().opaque(), "1");

    let second = provider.recent_tracks_page(2, 2).await.unwrap();
    assert_eq!(
        (second.offset(), second.next_offset(), second.total()),
        (2, 3, 3)
    );
    assert!(!second.has_more());
    assert_eq!(second.tracks()[0].id().opaque(), "1");
    let urls = urls.lock().unwrap();
    assert_eq!(urls.len(), 2, "later pages must stay inside the snapshot");
    assert!(urls[1].ends_with("play-record/song/list"));
}

#[tokio::test]
async fn recent_history_rejects_malformed_envelopes_and_old_account_results() {
    let (provider, urls) = build_provider(vec![
        Reply::Json(account()),
        Reply::Json(json!({"code":200,"data":{"list":[]}})),
    ])
    .await;
    assert_eq!(
        provider.recent_tracks_page(0, 25).await,
        Err(UserLibraryError::InvalidResponse)
    );
    assert_eq!(urls.lock().unwrap().len(), 2);

    let started = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    let (provider, urls) = build_provider(vec![
        Reply::Json(account()),
        Reply::Blocked {
            started: Arc::clone(&started),
            release,
            value: json!({"code":200,"data":{"total":0,"list":[]}}),
        },
    ])
    .await;
    let request_provider = Arc::clone(&provider);
    let request = tokio::spawn(async move { request_provider.recent_tracks_page(0, 25).await });
    started.notified().await;
    provider.sign_out();
    assert_eq!(request.await.unwrap(), Err(UserLibraryError::Replaced));
    assert_eq!(
        urls.lock().unwrap().len(),
        2,
        "the replaced read is not retried"
    );
}

#[tokio::test]
async fn track_like_is_desired_state_single_request_and_maps_unknown_outcomes() {
    let (provider, urls) = build_provider(vec![
        Reply::Json(account()),
        Reply::Json(json!({"code":200})),
    ])
    .await;
    provider.set_track_liked(track("9"), true).await.unwrap();
    assert_eq!(urls.lock().unwrap().len(), 2);
    assert!(urls.lock().unwrap()[1].ends_with("song/like"));

    let (provider, urls) = build_provider(vec![
        Reply::Json(account()),
        Reply::Failure(Error::TemporaryNetworkFailure),
    ])
    .await;
    assert_eq!(
        provider.set_track_liked(track("9"), false).await,
        Err(LibraryMutationError::NetworkOutcomeUnknown)
    );
    assert_eq!(urls.lock().unwrap().len(), 2, "writes are never retried");
}

#[tokio::test]
async fn track_like_classifies_service_credential_malformed_and_replacement() {
    for (reply, expected) in [
        (
            json!({"code":500}),
            LibraryMutationError::ServiceUnavailable,
        ),
        (
            json!({}),
            LibraryMutationError::InvalidResponseOutcomeUnknown,
        ),
    ] {
        let (provider, urls) =
            build_provider(vec![Reply::Json(account()), Reply::Json(reply)]).await;
        assert_eq!(
            provider.set_track_liked(track("9"), true).await,
            Err(expected)
        );
        assert_eq!(
            urls.lock().unwrap().len(),
            2,
            "classified writes are not retried"
        );
    }

    let (provider, urls) = build_provider(vec![
        Reply::Json(account()),
        Reply::Json(json!({"code":301})),
    ])
    .await;
    assert_eq!(
        provider.set_track_liked(track("9"), false).await,
        Err(LibraryMutationError::CredentialRejected)
    );
    assert!(!provider.has_authenticated_credential());
    assert_eq!(urls.lock().unwrap().len(), 2);

    let started = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    let (provider, urls) = build_provider(vec![
        Reply::Json(account()),
        Reply::Blocked {
            started: Arc::clone(&started),
            release,
            value: json!({"code":200}),
        },
    ])
    .await;
    let request_provider = Arc::clone(&provider);
    let request =
        tokio::spawn(async move { request_provider.set_track_liked(track("9"), true).await });
    started.notified().await;
    provider.sign_out();
    assert_eq!(request.await.unwrap(), Err(LibraryMutationError::Replaced));
    assert_eq!(
        urls.lock().unwrap().len(),
        2,
        "the replaced write is not retried"
    );
}

#[tokio::test]
async fn playlist_create_returns_owned_identity_and_malformed_success_is_unknown() {
    let (provider, urls) = build_provider(vec![
        Reply::Json(account()),
        Reply::Json(json!({"code":200,"playlist":{"id":701,"name":"Server name"}})),
    ])
    .await;
    let created = provider
        .create_playlist(" Requested ".into())
        .await
        .unwrap();
    assert_eq!(created.id().opaque(), "701");
    assert_eq!(created.title(), "Server name");
    assert_eq!(created.ownership(), music_domain::PlaylistOwnership::Owned);
    assert!(urls.lock().unwrap()[1].ends_with("playlist/create"));

    let (provider, _) = build_provider(vec![
        Reply::Json(account()),
        Reply::Json(json!({"code":200,"playlist":{}})),
    ])
    .await;
    assert_eq!(
        provider.create_playlist("Fixture".into()).await,
        Err(LibraryMutationError::InvalidResponseOutcomeUnknown)
    );

    let (provider, urls) = build_provider(vec![
        Reply::Json(account()),
        Reply::Failure(Error::TemporaryNetworkFailure),
    ])
    .await;
    assert_eq!(
        provider.create_playlist("Fixture".into()).await,
        Err(LibraryMutationError::NetworkOutcomeUnknown)
    );
    assert_eq!(urls.lock().unwrap().len(), 2, "create is never retried");
}

#[tokio::test]
async fn playlist_track_write_requires_authoritative_owned_non_liked_target() {
    let (provider, urls) = build_provider(vec![
        Reply::Json(account()),
        Reply::Json(user_playlists()),
        Reply::Json(json!({"code":502})),
    ])
    .await;
    provider
        .set_playlist_track_membership(playlist("101"), track("9"), true)
        .await
        .unwrap();
    {
        let urls = urls.lock().unwrap();
        assert_eq!(urls.len(), 3, "already-present add is not retried");
        assert!(urls[1].ends_with("user/playlist"));
        assert!(urls[2].ends_with("playlist/manipulate/tracks"));
    }

    for rejected in ["100", "102", "999"] {
        let (provider, urls) =
            build_provider(vec![Reply::Json(account()), Reply::Json(user_playlists())]).await;
        assert_eq!(
            provider
                .set_playlist_track_membership(playlist(rejected), track("9"), false)
                .await,
            Err(LibraryMutationError::InvalidRequest)
        );
        assert_eq!(urls.lock().unwrap().len(), 2, "invalid target never writes");
    }

    let (provider, urls) = build_provider(vec![
        Reply::Json(account()),
        Reply::Json(user_playlists()),
        Reply::Json(json!({"code":502})),
    ])
    .await;
    assert_eq!(
        provider
            .set_playlist_track_membership(playlist("101"), track("9"), false)
            .await,
        Err(LibraryMutationError::ServiceUnavailable)
    );
    assert_eq!(urls.lock().unwrap().len(), 3, "remove 502 is not retried");
}

#[tokio::test]
async fn malformed_and_foreign_identities_stop_before_write_transport() {
    let (provider, urls) = build_provider(vec![Reply::Json(account())]).await;
    let foreign = TrackId::new(music_domain::ProviderId::new("qq-music").unwrap(), "9").unwrap();
    assert_eq!(
        provider.set_track_liked(foreign, true).await,
        Err(LibraryMutationError::InvalidRequest)
    );
    assert_eq!(urls.lock().unwrap().len(), 1);
}
