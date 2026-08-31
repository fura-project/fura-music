use qqmusic_client::{QqMusicClient, ReqwestTransport};

/// Opt-in compatibility probe using only bounded public catalog identities and
/// the anonymous related-Track operation. It retains no Track content,
/// identity, artwork, response body, or account material.
#[tokio::test]
#[ignore = "live QQ Music service; run explicitly with QQMUSIC_LIVE_TESTS=1"]
async fn finds_related_tracks_for_one_public_seed() {
    if std::env::var("QQMUSIC_LIVE_TESTS").as_deref() != Ok("1") {
        eprintln!("skipped: set QQMUSIC_LIVE_TESTS=1 for the live request");
        return;
    }

    let client = QqMusicClient::new(ReqwestTransport::new().expect("native HTTPS transport"));
    let mut found_related_tracks = false;
    // Stable public catalog identities from feeluown-qqmusic's published,
    // sanitized cgi_get_track_info fixture. They are not account-derived.
    for track_id in [
        214_982_607,
        277_845_939,
        250_659_505,
        101_091_484,
        718_477,
        5_303_143,
        718_486,
        5_800,
    ] {
        let related = client
            .related_tracks(track_id)
            .await
            .expect("related-Track response shape remains compatible");
        if !related.tracks().is_empty() {
            found_related_tracks = true;
            break;
        }
    }
    assert!(
        found_related_tracks,
        "bounded public seed set returned no related Track set"
    );
}
