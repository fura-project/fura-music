use qqmusic_client::{QqMusicClient, ReqwestTransport};

const PUBLIC_SONG_ID: u64 = 361_947_418;
const STALE_TOTAL_REPLY_SONG_ID: u64 = 387_383_752;
const STALE_TOTAL_SHORT_PAGE_SONG_ID: u64 = 712_025_774;

/// Opt-in compatibility probe using only a public QQ Music song identity.
/// It retains and prints no comment identity, author name, or comment text.
#[tokio::test]
#[ignore = "live QQ Music service; run explicitly with QQMUSIC_LIVE_TESTS=1"]
async fn maps_one_anonymous_read_only_comment_page() {
    if std::env::var("QQMUSIC_LIVE_TESTS").as_deref() != Ok("1") {
        eprintln!("skipped: set QQMUSIC_LIVE_TESTS=1 for the live request");
        return;
    }

    let client = QqMusicClient::new(ReqwestTransport::new().expect("native HTTPS transport"));
    let page = client
        .track_comments(PUBLIC_SONG_ID, 0, 20)
        .await
        .expect("current anonymous comment request and mapping shape");

    assert_eq!(page.offset(), 0);
    assert!(page.latest_comments().len() <= 20);
    assert!(page.hot_comments().len() <= 100);
    let latest_count = u32::try_from(page.latest_comments().len()).expect("bounded page size");
    assert!(page.total() >= latest_count);
    assert!(!page.latest_comments().is_empty());

    let page_debug = format!("{page:?}");
    assert!(!page_debug.contains(&PUBLIC_SONG_ID.to_string()));
    for comment in page.hot_comments().iter().chain(page.latest_comments()) {
        let comment_debug = format!("{comment:?}");
        assert!(comment_debug.contains("comment_id: \"[REDACTED]\""));
        assert!(comment_debug.contains("author_display_name: \"[REDACTED]\""));
        assert!(comment_debug.contains("content: \"[REDACTED]\""));
    }
}

/// Opt-in regression for two public response shapes observed in the legacy
/// endpoint: a stale total with nested reply content, and a later short page
/// whose stale total cannot be used as the terminal boundary.
#[tokio::test]
#[ignore = "live QQ Music service; run explicitly with QQMUSIC_LIVE_TESTS=1"]
async fn maps_stale_totals_nested_replies_and_a_short_terminal_page() {
    if std::env::var("QQMUSIC_LIVE_TESTS").as_deref() != Ok("1") {
        eprintln!("skipped: set QQMUSIC_LIVE_TESTS=1 for the live request");
        return;
    }

    let client = QqMusicClient::new(ReqwestTransport::new().expect("native HTTPS transport"));
    let first = client
        .track_comments(STALE_TOTAL_REPLY_SONG_ID, 0, 20)
        .await
        .expect("stale-total nested-reply page remains readable");
    assert_eq!(first.offset(), 0);
    assert!(first.has_more());
    assert_eq!(first.total(), 21);
    assert_eq!(first.latest_comments().len(), 20);

    let second = client
        .track_comments(STALE_TOTAL_REPLY_SONG_ID, 20, 20)
        .await
        .expect("stale-total continuation remains readable");
    assert_eq!(second.offset(), 20);
    assert!(second.has_more());
    assert_eq!(second.total(), 41);
    assert_eq!(second.latest_comments().len(), 20);

    let terminal = client
        .track_comments(STALE_TOTAL_SHORT_PAGE_SONG_ID, 20, 20)
        .await
        .expect("short stale-total page remains readable");
    assert_eq!(terminal.offset(), 20);
    assert!(!terminal.has_more());
    assert_eq!(terminal.total(), 28);
    assert!(terminal.latest_comments().len() <= 8);

    for page in [&first, &second, &terminal] {
        let debug = format!("{page:?}");
        assert!(!debug.contains(&STALE_TOTAL_REPLY_SONG_ID.to_string()));
        assert!(!debug.contains(&STALE_TOTAL_SHORT_PAGE_SONG_ID.to_string()));
    }
}
