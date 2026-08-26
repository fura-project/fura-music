use qqmusic_client::{Credential, LoginType, QqMusicClient, QqMusicMediaError, ReqwestTransport};

/// Opt-in compatibility probe using only a public song MID and a deliberately
/// non-account credential. It retains no source URL, vkey, or response body.
#[tokio::test]
#[ignore = "live QQ Music service; run explicitly with QQMUSIC_LIVE_TESTS=1"]
async fn resolves_dispatch_and_parses_a_non_account_vkey_outcome() {
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

    let non_account = Credential::new(
        "0",
        "not-a-real-account-key",
        LoginType::new(1).expect("login type"),
    )
    .expect("synthetic non-account credential");
    match client
        .standard_mp3_source(&non_account, "003w2xz20QlUZt", None, &dispatch)
        .await
    {
        Ok(source) => assert!(source.valid_for_seconds() > 0),
        Err(QqMusicMediaError::Unavailable { .. } | QqMusicMediaError::Rejected { .. }) => {}
        Err(error) => panic!("non-account media response shape changed: {error:?}"),
    }
}
