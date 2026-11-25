use qqmusic_client::{QqMusicClient, QqMusicNewSongCategory, ReqwestTransport};

/// Bounded anonymous read-only structural gate for `music.pf_song_detail_svr/get_song_detail_yqq`
/// with numeric `song_id`. Uses 2 anonymous public requests total (no account, no cookie,
/// no printed titles/identities/bodies).
#[tokio::test]
#[ignore = "opt-in live anonymous QQ Music track-detail structural check"]
async fn anonymous_track_detail_by_numeric_id_matches_public_catalog_identity() {
    assert_eq!(
        std::env::var("FURA_QQ_LIVE_TRACK_DETAIL_TEST").as_deref(),
        Ok("1"),
        "set FURA_QQ_LIVE_TRACK_DETAIL_TEST=1 to run the bounded live anonymous track-detail gate"
    );
    let client = QqMusicClient::new(ReqwestTransport::new().expect("reqwest transport"));
    let collection = client
        .new_songs(QqMusicNewSongCategory::Latest)
        .await
        .expect("public new songs");
    let sample = collection
        .tracks()
        .first()
        .expect("at least one public track");

    let recovered = client
        .recover_omitted_track_by_identity(sample.track_id(), sample.song_type())
        .await
        .expect("track_detail_by_id request")
        .expect("public track detail present");

    assert_eq!(recovered.track_id(), sample.track_id());
    assert_eq!(recovered.song_type(), sample.song_type());
    assert_eq!(recovered.song_mid(), sample.song_mid());
}
