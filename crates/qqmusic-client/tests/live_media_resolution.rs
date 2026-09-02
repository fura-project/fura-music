use qqmusic_client::{
    QqMusicAudioQuality, QqMusicClient, QqMusicMediaError, QqMusicNewSongCategory, ReqwestTransport,
};

/// Opt-in compatibility probe using only a bounded public new-song collection
/// and an anonymous `uin=0` media context. It retains no Track content, source
/// URL, vkey, or response body. Search is intentionally not a prerequisite:
/// QQ may independently rate-limit Search with result code 2001.
#[tokio::test]
#[ignore = "live QQ Music service; run explicitly with QQMUSIC_LIVE_TESTS=1"]
async fn resolves_one_public_catalog_track_without_account() {
    if std::env::var("QQMUSIC_LIVE_TESTS").as_deref() != Ok("1") {
        eprintln!("skipped: set QQMUSIC_LIVE_TESTS=1 for the live request");
        return;
    }

    let client = QqMusicClient::new(ReqwestTransport::new().expect("native HTTPS transport"));
    let dispatch = client
        .cdn_dispatch()
        .await
        .expect("QQ Music CDN dispatch remains compatible");
    assert!(dispatch.base_count() > 0);
    assert!(dispatch.expiration_seconds() > 0);

    let collection = client
        .new_songs(QqMusicNewSongCategory::Latest)
        .await
        .expect("bounded public new-song collection remains compatible");
    let mut found_source = false;
    for track in collection.tracks().iter().take(10) {
        match client
            .anonymous_standard_mp3_source(track.song_mid(), track.file_media_mid(), &dispatch)
            .await
        {
            Ok(source) => {
                assert_eq!(source.quality(), QqMusicAudioQuality::Standard);
                assert!(source.valid_for_seconds() > 0);
                found_source = true;
                break;
            }
            Err(QqMusicMediaError::Unavailable { .. } | QqMusicMediaError::Rejected { .. }) => {}
            Err(error) => panic!("anonymous media response shape changed: {error:?}"),
        }
    }
    assert!(
        found_source,
        "bounded public catalog sample returned no anonymously playable Track"
    );
}
