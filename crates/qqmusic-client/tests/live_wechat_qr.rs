use qqmusic_client::{QqMusicClient, ReqwestTransport};

/// Opt-in live test. It creates only an unconfirmed, short-lived QR session and
/// never scans it or accesses an account.
#[tokio::test]
#[ignore = "live QQ/WeChat service; run explicitly with QQMUSIC_LIVE_TESTS=1"]
async fn creates_unconfirmed_wechat_qr() {
    if std::env::var("QQMUSIC_LIVE_TESTS").as_deref() != Ok("1") {
        eprintln!("skipped: set QQMUSIC_LIVE_TESTS=1 for the live request");
        return;
    }

    let transport = ReqwestTransport::new().expect("native HTTPS transport");
    let client = QqMusicClient::new(transport);
    let session = client
        .create_wechat_qr()
        .await
        .expect("QQ Music WeChat QR bootstrap remains compatible");

    assert!(!session.identifier().is_empty());
    assert!(session.image().bytes().len() > 100);
}
