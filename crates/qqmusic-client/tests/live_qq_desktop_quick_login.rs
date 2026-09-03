use qqmusic_client::{QqMusicClient, ReqwestTransport};

/// Maintainer-operated local compatibility check. It asks a running desktop QQ
/// client only for the account-choice list, records no identity, and never
/// requests or exchanges an authorization ticket.
#[tokio::test]
#[ignore = "reads local desktop QQ account choices; run explicitly as the maintainer"]
async fn discovers_running_desktop_qq_without_authorizing() {
    if std::env::var("QQMUSIC_DESKTOP_QUICK_LOGIN_TEST").as_deref() != Ok("1") {
        eprintln!(
            "skipped: set QQMUSIC_DESKTOP_QUICK_LOGIN_TEST=1 for the maintainer-operated check"
        );
        return;
    }

    let transport = ReqwestTransport::new().expect("native HTTPS transport");
    let client = QqMusicClient::new(transport);
    let session = client
        .discover_desktop_qq_accounts()
        .await
        .expect("desktop QQ quick-login discovery remains compatible");

    assert!(session.accounts().len() <= 10);
}
