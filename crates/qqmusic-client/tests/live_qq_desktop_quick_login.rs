use qqmusic_client::{LoginType, QqMusicClient, ReqwestTransport};

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

/// Maintainer-operated end-to-end compatibility check. Authorization proceeds
/// only when desktop QQ exposes exactly one account, so the test never guesses
/// among multiple identities. It neither prints nor persists the credential.
#[tokio::test]
#[ignore = "authorizes the sole local desktop QQ account; run only with explicit maintainer approval"]
async fn authorizes_the_sole_desktop_qq_account_without_persisting() {
    if std::env::var("QQMUSIC_DESKTOP_QUICK_AUTHORIZATION_TEST").as_deref() != Ok("1") {
        eprintln!(
            "skipped: set QQMUSIC_DESKTOP_QUICK_AUTHORIZATION_TEST=1 only with maintainer approval"
        );
        return;
    }

    let transport = ReqwestTransport::new().expect("native HTTPS transport");
    let client = QqMusicClient::new(transport);
    let session = client
        .discover_desktop_qq_accounts()
        .await
        .expect("desktop QQ quick-login discovery remains compatible");
    let accounts = session.accounts();
    assert_eq!(
        accounts.len(),
        1,
        "authorization requires exactly one unambiguous local account"
    );

    let credential = client
        .authorize_desktop_qq_account(&session, accounts[0].selection_id())
        .await
        .expect("desktop QQ authorization and QQ Music exchange remain compatible");

    assert_eq!(credential.login_type(), LoginType::QQ);
    assert!(!credential.music_id().is_empty());
    assert!(!credential.music_key().is_empty());
}
