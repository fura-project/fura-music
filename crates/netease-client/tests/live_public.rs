//! Serial anonymous compatibility evidence. Never reads cookies or account files.
use netease_client::{Error, HttpsTransport, NeteaseClient, Request, Response, Transport};
struct ShapeTransport(HttpsTransport);
fn shape(v: &serde_json::Value, depth: u8) -> serde_json::Value {
    if depth == 0 {
        return serde_json::json!(match v {
            serde_json::Value::Null => "null",
            serde_json::Value::String(_) => "string",
            serde_json::Value::Number(_) => "number",
            serde_json::Value::Bool(_) => "bool",
            serde_json::Value::Array(_) => "array",
            serde_json::Value::Object(_) => "object",
        });
    }
    match v {
        serde_json::Value::Object(o) => o
            .iter()
            .take(32)
            .map(|(k, v)| (k.clone(), shape(v, depth - 1)))
            .collect(),
        serde_json::Value::Array(a) => {
            serde_json::json!({"length":a.len(),"first":a.first().map(|v|shape(v,depth-1))})
        }
        _ => shape(v, 0),
    }
}
impl Transport for ShapeTransport {
    async fn send(&self, r: Request) -> Result<Response, Error> {
        let r = self.0.send(r).await?;
        if std::env::var("FURA_NETEASE_SHAPE_DIAGNOSTIC").as_deref() == Ok("1") {
            match serde_json::from_slice::<serde_json::Value>(&r.body) {
                Ok(v) => {
                    println!("anonymous structural diagnostic: {}", shape(&v, 6));
                    if let Some(rows) = v
                        .pointer("/result/songs")
                        .and_then(serde_json::Value::as_array)
                    {
                        for row in rows {
                            let s = serde_json::from_value::<netease_client::Song>(row.clone());
                            match s {
                                Ok(s) => println!(
                                    "validation: song_id_valid={} title_valid={} album_id_valid={} album_name_valid={} artist_ids_valid={} artist_names_valid={} duration_valid={}",
                                    s.id > 0,
                                    !s.name.trim().is_empty(),
                                    s.album.id > 0,
                                    !s.album.name.trim().is_empty(),
                                    s.artists.iter().all(|a| a.id > 0),
                                    s.artists.iter().all(|a| !a.name.trim().is_empty()),
                                    s.duration <= 86_400_000
                                ),
                                Err(_) => println!("typed decode failed"),
                            }
                        }
                    }
                }
                Err(_) => println!(
                    "anonymous structural diagnostic: HTTP {}, non-JSON, bytes={}",
                    r.status,
                    r.body.len()
                ),
            }
        }
        Ok(r)
    }
}
#[tokio::test]
#[ignore = "explicit anonymous read-only compatibility observation; one HTTP request"]
async fn anonymous_track_search() {
    assert_eq!(
        std::env::var("FURA_NETEASE_PUBLIC_PROBE").as_deref(),
        Ok("1")
    );
    let client = NeteaseClient::new(ShapeTransport(HttpsTransport::new().unwrap()));
    match client.search_tracks("Mozart", 0, 3).await {
        Ok(page) => {
            assert!(!page.items.is_empty());
            println!(
                "NETEASE search: public rows={}, continuation={}",
                page.items.len(),
                page.more
            );
        }
        Err(error) => panic!("NETEASE search STOP: {error}"),
    }
}

#[tokio::test]
#[ignore = "explicit anonymous serial catalog observation; hard maximum 16 HTTPS requests"]
async fn anonymous_catalog_slice() {
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    struct Budget {
        http: ShapeTransport,
        count: AtomicUsize,
        stop: AtomicBool,
    }
    impl Transport for Budget {
        async fn send(&self, r: Request) -> Result<Response, Error> {
            if self.stop.load(Ordering::SeqCst) || self.count.fetch_add(1, Ordering::SeqCst) >= 16 {
                return Err(Error::InputBound);
            }
            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
            let response = self.http.send(r).await?;
            if response.status == 429 {
                self.stop.store(true, Ordering::SeqCst);
            }
            // Known risk outcomes stop this entire observation, not just one capability.
            if let Ok(v) = serde_json::from_slice::<serde_json::Value>(&response.body)
                && v.get("code").and_then(serde_json::Value::as_i64) != Some(200)
            {
                self.stop.store(true, Ordering::SeqCst);
            }
            Ok(response)
        }
    }
    fn report<T>(name: &str, r: Result<T, Error>) -> Option<T> {
        match r {
            Ok(value) => {
                println!("{name}: PASS");
                Some(value)
            }
            Err(e) => {
                println!("{name}: STOP {e}");
                None
            }
        }
    }
    assert_eq!(
        std::env::var("FURA_NETEASE_PUBLIC_PROBE").as_deref(),
        Ok("1")
    );
    let client = NeteaseClient::new(Budget {
        http: ShapeTransport(HttpsTransport::new().unwrap()),
        count: AtomicUsize::new(0),
        stop: AtomicBool::new(false),
    });
    let tracks = report("track search", client.search_tracks("Mozart", 0, 1).await);
    let artists = report("artist search", client.search_artists("Mozart", 0, 1).await);
    let albums = report("album search", client.search_albums("Mozart", 0, 1).await);
    let playlists = report(
        "playlist search",
        client.search_playlists("Mozart", 0, 3).await,
    );
    if let Some(track) = tracks.as_ref().and_then(|p| p.items.first()) {
        report("song detail", client.songs(&[track.id]).await);
        report("lyrics", client.lyrics(track.id).await);
        report("standard media", client.media(track.id).await);
    }
    if let Some(album) = albums.as_ref().and_then(|p| p.items.first()) {
        report("album content", client.album(album.id).await);
    }
    if let Some(artist) = artists.as_ref().and_then(|p| p.items.first()) {
        report("artist tracks", client.artist_tracks(artist.id, 0, 3).await);
        report("artist albums", client.artist_albums(artist.id, 0, 3).await);
    }
    if let Some(playlist) = playlists
        .as_ref()
        .and_then(|p| p.items.iter().find(|p| p.track_count <= 1000))
    {
        report(
            "public playlist",
            client.playlist_page(playlist.id, 0, 3).await,
        );
    }
    report("rankings", client.rankings().await);
    report("public recommendations", client.recommendations(3).await);
    // The individual coarse outcomes are evidence, not a blanket all-capabilities assertion.
    assert!(tracks.is_some());
}
