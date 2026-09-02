use qqmusic_client::{QqMusicClient, ReqwestTransport};

/// Opt-in compatibility probe using a public song MID and no account material.
/// It retains and prints no ciphertext or lyric text.
#[tokio::test]
#[ignore = "live QQ Music service; run explicitly with QQMUSIC_LIVE_TESTS=1"]
async fn decrypts_and_parses_an_anonymous_cloud_qrc_shape() {
    if std::env::var("QQMUSIC_LIVE_TESTS").as_deref() != Ok("1") {
        eprintln!("skipped: set QQMUSIC_LIVE_TESTS=1 for the live request");
        return;
    }

    let client = QqMusicClient::new(ReqwestTransport::new().expect("native HTTPS transport"));
    let lyrics = client
        .lyrics(None, "003w2xz20QlUZt", 0)
        .await
        .expect("current anonymous QRC request/decrypt/parse shape");

    assert!(!lyrics.original().is_empty());
    assert!(
        lyrics
            .original()
            .iter()
            .any(|line| !line.segments().is_empty())
    );
}
