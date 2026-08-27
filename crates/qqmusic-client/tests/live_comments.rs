use qqmusic_client::{QqMusicClient, ReqwestTransport};

const PUBLIC_SONG_ID: u64 = 361_947_418;

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
        assert!(!comment_debug.contains(comment.comment_id()));
        assert!(!comment_debug.contains(comment.author_display_name()));
        assert!(!comment_debug.contains(comment.content()));
    }
}
