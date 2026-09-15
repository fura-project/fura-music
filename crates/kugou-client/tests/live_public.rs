//! Opt-in anonymous compatibility evidence. Never reads cookies or account files.

use kugou_client::{HttpsTransport, KuGouClient};

/// Performs exactly one bounded, unsigned public Track Search request. The
/// query, response body, titles and identities are never printed or retained.
#[tokio::test]
#[ignore = "live KuGou service; run explicitly with FURA_KUGOU_PUBLIC_PROBE=1"]
async fn anonymous_track_search_shape() {
    assert_eq!(std::env::var("FURA_KUGOU_PUBLIC_PROBE").as_deref(), Ok("1"));
    let client = KuGouClient::new(HttpsTransport::new().expect("bounded native HTTPS transport"));
    let page = client
        .search_tracks("周杰伦", 1, 1)
        .await
        .expect("current unsigned public Track Search shape");

    assert_eq!(page.page, 1);
    assert_eq!(page.items.len(), 1);
    assert!(page.total >= 1);
    assert!(!page.items[0].mix_song_id.is_empty());
    assert!(!page.items[0].title.is_empty());
    println!("anonymous_track_search_shape: PASS");
}
