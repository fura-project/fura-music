use qqmusic_client::{QqMusicClient, QqQrPollResult, ReqwestTransport};

/// Opt-in live test. It creates only an unconfirmed, short-lived QQ Web QR
/// session and never scans it, authorizes it, or accesses an account.
#[tokio::test]
#[ignore = "live QQ service; run explicitly with QQMUSIC_LIVE_TESTS=1"]
async fn creates_and_polls_unconfirmed_qq_web_qr() {
    if std::env::var("QQMUSIC_LIVE_TESTS").as_deref() != Ok("1") {
        eprintln!("skipped: set QQMUSIC_LIVE_TESTS=1 for the live request");
        return;
    }

    let transport = ReqwestTransport::new().expect("native HTTPS transport");
    let client = QqMusicClient::new(transport);
    let mut session = client
        .create_qq_qr()
        .await
        .expect("QQ Web QR bootstrap remains compatible");

    assert!(session.image().bytes().len() > 100);
    let poll = client
        .poll_qq_qr(&mut session)
        .await
        .expect("unconfirmed QQ Web QR polling remains compatible");
    assert_eq!(poll, QqQrPollResult::WaitingForScan);
}
