use qqmusic_client::{QqMusicClient, ReqwestTransport};

/// Opt-in compatibility probe for the anonymous public-playlist route.
///
/// The probe makes exactly two serial, read-only requests: one bounded public
/// recommendation page and one one-row public playlist-detail page. It proves
/// only that the current anonymous `CgiGetDiss` request and bounded decoder are
/// accepted for one current public sample. It does not prove authenticated,
/// account-owned, liked-song, private, or large-playlist behavior. No playlist
/// identity, title, Track content, response body, Cookie, or account material
/// is logged or persisted.
#[tokio::test]
#[ignore = "live QQ Music service; run explicitly with QQMUSIC_LIVE_TESTS=1"]
async fn loads_one_public_playlist_page_without_account() {
    if std::env::var("QQMUSIC_LIVE_TESTS").as_deref() != Ok("1") {
        eprintln!("skipped: set QQMUSIC_LIVE_TESTS=1 for the live request");
        return;
    }

    let client = QqMusicClient::new(ReqwestTransport::new().expect("native HTTPS transport"));
    let recommendations = client
        .recommended_playlists(0, 3)
        .await
        .expect("bounded anonymous recommendation request remains compatible");
    let playlist = recommendations
        .playlists()
        .iter()
        .find(|playlist| playlist.track_count().is_none_or(|count| count > 0))
        .expect("bounded recommendation sample contains a public playlist");

    let page = client
        .public_playlist_tracks_page(playlist.playlist_id(), 0, 1)
        .await
        .expect("anonymous public playlist detail remains compatible");
    assert_eq!(page.offset(), 0);
    assert!(page.total() as usize >= page.tracks().len());
    assert!(page.tracks().len() <= 1);
    if page.has_more() {
        assert!(!page.tracks().is_empty());
    }
}
