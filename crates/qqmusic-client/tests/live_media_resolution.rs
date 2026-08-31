use qqmusic_client::{QqMusicAudioQuality, QqMusicClient, QqMusicMediaError, ReqwestTransport};

/// Opt-in compatibility probe using only a bounded public Search page and an
/// anonymous `uin=0` media context. It retains no Track content, source URL,
/// vkey, or response body.
#[tokio::test]
#[ignore = "live QQ Music service; run explicitly with QQMUSIC_LIVE_TESTS=1"]
async fn resolves_one_public_search_result_without_account() {
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

    let page = client
        .search_tracks("Coldplay", 1, 10)
        .await
        .expect("bounded public Search remains compatible");
    let mut found_source = false;
    for track in page.tracks() {
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
        "bounded public Search page returned no anonymously playable Track"
    );
}
