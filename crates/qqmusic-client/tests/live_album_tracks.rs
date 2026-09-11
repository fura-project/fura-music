use qqmusic_client::{QqMusicClient, ReqwestTransport};

const PUBLIC_ALBUM_MID: &str = "004Ws4fG3pT6eA";
const CANONICAL_TRACK_IDS: [u64; 13] = [
    105_539_537,
    105_539_538,
    105_539_539,
    105_539_540,
    105_539_541,
    105_539_542,
    105_539_543,
    105_539_544,
    105_539_545,
    105_539_546,
    105_539_547,
    105_539_548,
    105_539_549,
];

/// Opt-in compatibility probe using only one stable public QQ Music Album.
/// It retains and prints no Album or Track names, artwork, or response body.
#[tokio::test]
#[ignore = "live QQ Music service; run explicitly with QQMUSIC_LIVE_TESTS=1"]
async fn requests_and_maps_canonical_album_track_order() {
    if std::env::var("QQMUSIC_LIVE_TESTS").as_deref() != Ok("1") {
        eprintln!("skipped: set QQMUSIC_LIVE_TESTS=1 for the live request");
        return;
    }

    let client = QqMusicClient::new(ReqwestTransport::new().expect("native HTTPS transport"));
    let page = client
        .album_tracks(PUBLIC_ALBUM_MID, 0, 30)
        .await
        .expect("current public Album request and mapping shape");

    let track_ids = page
        .tracks()
        .iter()
        .map(qqmusic_client::QqMusicTrackSummary::track_id)
        .collect::<Vec<_>>();
    assert_eq!(track_ids, CANONICAL_TRACK_IDS);
    assert_eq!(page.offset(), 0);
    assert_eq!(page.total(), 13);
    assert!(!page.has_more());

    let page_debug = format!("{page:?}");
    assert!(!page_debug.contains(PUBLIC_ALBUM_MID));
    for track_id in CANONICAL_TRACK_IDS {
        assert!(!page_debug.contains(&track_id.to_string()));
    }
}
