use qqmusic_client::{QqMusicClient, ReqwestTransport};

const PUBLIC_SONG_MID: &str = "003w2xz20QlUZt";

/// Opt-in compatibility probe using only a public QQ Music song identity.
/// It retains and prints no MV identity, metadata, artwork, or source URI.
#[tokio::test]
#[ignore = "live QQ Music service; run explicitly with QQMUSIC_LIVE_TESTS=1"]
async fn resolves_one_anonymous_track_associated_mv() {
    if std::env::var("QQMUSIC_LIVE_TESTS").as_deref() != Ok("1") {
        eprintln!("skipped: set QQMUSIC_LIVE_TESTS=1 for the live request");
        return;
    }

    let client = QqMusicClient::new(ReqwestTransport::new().expect("native HTTPS transport"));
    let video = client
        .track_music_video(PUBLIC_SONG_MID)
        .await
        .expect("current anonymous Track-to-MV request and mapping shape")
        .expect("selected public Track still exposes an associated MV");

    assert!(!video.title().trim().is_empty());
    assert!(!video.artist_names().is_empty());
    assert!(video.duration_seconds() > 0);
    assert!(video.source_uri().starts_with("https://"));

    let debug = format!("{video:?}");
    for private in [
        video.vid(),
        video.title(),
        video.source_uri(),
        video.artwork_uri().unwrap_or_default(),
    ]
    .into_iter()
    .chain(video.artist_names().iter().map(String::as_str))
    .filter(|value| !value.is_empty())
    {
        assert!(!debug.contains(private));
    }
}
