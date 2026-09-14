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
            // Conservatively stop the whole window on every non-success envelope.
            if let Ok(v) = serde_json::from_slice::<serde_json::Value>(&response.body)
                && v.get("code").and_then(serde_json::Value::as_i64) != Some(200)
            {
                self.stop.store(true, Ordering::SeqCst);
            }
            Ok(response)
        }
    }
    fn report<T>(name: &str, result: Result<T, Error>) -> T {
        match result {
            Ok(value) => {
                println!("{name}: PASS");
                value
            }
            Err(error) => panic!("{name}: STOP {error}"),
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
    let track = tracks.items.first().expect("public Track sample required");
    report("song detail", client.songs(&[track.id]).await);
    report("lyrics", client.lyrics(track.id).await);
    report("standard media", client.media(track.id).await);
    let album = albums.items.first().expect("public Album sample required");
    report("album content", client.album(album.id).await);
    let artist = artists
        .items
        .first()
        .expect("public Artist sample required");
    report("artist tracks", client.artist_tracks(artist.id, 0, 3).await);
    report("artist albums", client.artist_albums(artist.id, 0, 3).await);
    let playlist = playlists
        .items
        .iter()
        .find(|p| p.track_count <= 1000)
        .expect("bounded public Playlist sample required");
    report(
        "public playlist",
        client.playlist_page(playlist.id, 0, 3).await,
    );
    report("rankings", client.rankings().await);
    report("public recommendations", client.recommendations(3).await);
    // Every attempted capability must succeed; this remains evidence for these samples only.
    assert!(!tracks.items.is_empty());
}

#[tokio::test]
#[ignore = "explicit anonymous Cloud Search artwork probe; at most 3 HTTPS requests"]
async fn anonymous_cloud_search_includes_track_artwork() {
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct Budget {
        http: HttpsTransport,
        calls: AtomicUsize,
    }

    impl Transport for Budget {
        async fn send(&self, request: Request) -> Result<Response, Error> {
            if self.calls.fetch_add(1, Ordering::SeqCst) >= 1 {
                return Err(Error::InputBound);
            }
            self.http.send(request).await
        }
    }

    assert_eq!(
        std::env::var("FURA_NETEASE_ARTWORK_PROBE").as_deref(),
        Ok("1")
    );
    let client = NeteaseClient::new(Budget {
        http: HttpsTransport::new().unwrap(),
        calls: AtomicUsize::new(0),
    });
    let page = client
        .search_tracks("Mozart", 0, 1)
        .await
        .expect("anonymous Cloud Search result");
    let track = page.items.first().expect("public Track sample required");
    let mut artwork = url::Url::parse(
        track
            .album
            .artwork
            .as_deref()
            .expect("public Track artwork required"),
    )
    .expect("public Track artwork should parse");
    artwork
        .set_scheme("https")
        .expect("NetEase artwork should support HTTPS");
    let image_client = reqwest::Client::builder()
        .https_only(true)
        .redirect(reqwest::redirect::Policy::limited(3))
        .build()
        .unwrap();
    let current_policy = image_client
        .get(artwork.as_str())
        .header("Referer", "https://music.163.com/")
        .header("User-Agent", "Mozilla/5.0")
        .send()
        .await
        .expect("current artwork request policy should reach the CDN");
    println!(
        "artwork current-policy status={} final_host={}",
        current_policy.status().as_u16(),
        current_policy.url().host_str().unwrap_or("missing")
    );
    let browser_policy = image_client
        .get(artwork.as_str())
        .header("Referer", "https://music.163.com/")
        .header(
            "User-Agent",
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
        )
        .header("Accept", "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8")
        .send()
        .await
        .expect("browser artwork request policy should reach the CDN");
    println!(
        "artwork browser-policy status={} final_host={}",
        browser_policy.status().as_u16(),
        browser_policy.url().host_str().unwrap_or("missing")
    );
    assert!(browser_policy.status().is_success());
}

#[tokio::test]
#[ignore = "explicit anonymous Cloud Search response-shape probe; exactly 1 HTTPS request"]
async fn anonymous_cloud_search_query_shape() {
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct Budget {
        http: ShapeTransport,
        calls: AtomicUsize,
    }

    impl Transport for Budget {
        async fn send(&self, request: Request) -> Result<Response, Error> {
            if self.calls.fetch_add(1, Ordering::SeqCst) >= 1 {
                return Err(Error::InputBound);
            }
            self.http.send(request).await
        }
    }

    assert_eq!(
        std::env::var("FURA_NETEASE_QUERY_SHAPE_PROBE").as_deref(),
        Ok("1")
    );
    let query =
        std::env::var("FURA_NETEASE_PUBLIC_QUERY").expect("FURA_NETEASE_PUBLIC_QUERY is required");
    let client = NeteaseClient::new(Budget {
        http: ShapeTransport(HttpsTransport::new().unwrap()),
        calls: AtomicUsize::new(0),
    });
    let page = client
        .search_tracks(&query, 0, 30)
        .await
        .expect("anonymous Cloud Search response should decode and validate");
    assert!(!page.items.is_empty());
}

#[tokio::test]
#[ignore = "explicit anonymous Peace of Mind lyric compatibility probe; exactly 1 HTTPS request"]
async fn anonymous_peace_of_mind_lyrics() {
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct Budget {
        http: HttpsTransport,
        calls: AtomicUsize,
    }

    impl Transport for Budget {
        async fn send(&self, request: Request) -> Result<Response, Error> {
            if self.calls.fetch_add(1, Ordering::SeqCst) >= 1 {
                return Err(Error::InputBound);
            }
            self.http.send(request).await
        }
    }

    assert_eq!(
        std::env::var("FURA_NETEASE_PEACE_LYRIC_PROBE").as_deref(),
        Ok("1")
    );
    let client = NeteaseClient::new(Budget {
        http: HttpsTransport::new().unwrap(),
        calls: AtomicUsize::new(0),
    });
    let lyrics = client
        .lyrics(1_447_233_166)
        .await
        .expect("Peace of Mind lyrics should decode safely");
    assert!(!lyrics.lines.is_empty());
}

#[tokio::test]
#[ignore = "explicit anonymous QR start/poll compatibility probe; exactly 2 HTTPS requests"]
async fn anonymous_qr_start_and_waiting_state() {
    use netease_client::QrPoll;
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct Budget {
        http: HttpsTransport,
        calls: AtomicUsize,
    }

    impl Transport for Budget {
        async fn send(&self, request: Request) -> Result<Response, Error> {
            if self.calls.fetch_add(1, Ordering::SeqCst) >= 2 {
                return Err(Error::InputBound);
            }
            self.http.send(request).await
        }
    }

    assert_eq!(std::env::var("FURA_NETEASE_QR_PROBE").as_deref(), Ok("1"));
    let client = NeteaseClient::new(Budget {
        http: HttpsTransport::new().unwrap(),
        calls: AtomicUsize::new(0),
    });
    let mut key = client.qr_key().await.expect("anonymous QR key");
    let png = key.image_png().expect("local QR PNG");
    assert!(png.starts_with(b"\x89PNG\r\n\x1a\n"));
    assert!(matches!(
        client.qr_poll(&mut key).await,
        Ok(QrPoll::Waiting)
    ));
}

#[tokio::test]
#[ignore = "explicit anonymous serial read-parity observation; hard maximum 9 HTTPS requests"]
async fn anonymous_read_parity_slice() {
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    struct Budget {
        http: HttpsTransport,
        count: AtomicUsize,
        stop: AtomicBool,
    }
    impl Transport for Budget {
        async fn send(&self, request: Request) -> Result<Response, Error> {
            if self.stop.load(Ordering::SeqCst) || self.count.fetch_add(1, Ordering::SeqCst) >= 9 {
                return Err(Error::InputBound);
            }
            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
            let response = self.http.send(request).await?;
            if response.status == 429 {
                self.stop.store(true, Ordering::SeqCst);
            }
            if let Ok(value) = serde_json::from_slice::<serde_json::Value>(&response.body)
                && value.get("code").and_then(serde_json::Value::as_i64) != Some(200)
            {
                self.stop.store(true, Ordering::SeqCst);
            }
            Ok(response)
        }
    }
    fn report<T>(name: &str, result: Result<T, Error>) -> T {
        match result {
            Ok(value) => {
                println!("{name}: PASS");
                value
            }
            Err(error) => panic!("{name}: STOP {error}"),
        }
    }
    assert_eq!(
        std::env::var("FURA_NETEASE_READ_PARITY_PROBE").as_deref(),
        Ok("1")
    );
    let client = NeteaseClient::new(Budget {
        http: HttpsTransport::new().unwrap(),
        count: AtomicUsize::new(0),
        stop: AtomicBool::new(false),
    });
    let tracks = report(
        "MV-seed search",
        client.search_tracks("Jay Chou", 0, 10).await,
    );
    let track = tracks
        .items
        .iter()
        .find(|track| track.mv_id > 0)
        .expect("bounded public MV-associated sample required");
    report("comments", client.comments(track.id, 0, 3).await);
    report("related Tracks", client.related_tracks(track.id).await);
    report(
        "new songs",
        client.new_songs(netease_client::NewSongArea::All).await,
    );
    report(
        "new Albums",
        client
            .new_albums(netease_client::NewAlbumArea::Japan, 0, 3)
            .await,
    );
    report("associated MV", client.music_video(track.id).await)
        .expect("selected exact Track must retain its MV association");
}

#[tokio::test]
#[ignore = "explicit anonymous large-playlist observation; hard maximum 3 HTTPS requests"]
async fn anonymous_playlist_above_one_thousand() {
    use std::sync::atomic::{AtomicUsize, Ordering};
    struct Budget {
        http: HttpsTransport,
        count: AtomicUsize,
    }
    impl Transport for Budget {
        async fn send(&self, request: Request) -> Result<Response, Error> {
            if self.count.fetch_add(1, Ordering::SeqCst) >= 3 {
                return Err(Error::InputBound);
            }
            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
            let response = self.http.send(request).await?;
            if response.status == 429 {
                return Err(Error::RateLimited);
            }
            if let Ok(value) = serde_json::from_slice::<serde_json::Value>(&response.body)
                && value.get("code").and_then(serde_json::Value::as_i64) != Some(200)
            {
                return Err(Error::UpstreamUnknown);
            }
            Ok(response)
        }
    }
    assert_eq!(
        std::env::var("FURA_NETEASE_LARGE_PLAYLIST_PROBE").as_deref(),
        Ok("1")
    );
    let client = NeteaseClient::new(Budget {
        http: HttpsTransport::new().unwrap(),
        count: AtomicUsize::new(0),
    });
    let playlists = client
        .search_playlists("Chinese music", 0, 30)
        .await
        .expect("playlist search must pass");
    let playlist = playlists
        .items
        .iter()
        .find(|playlist| playlist.track_count > 1000)
        .expect("public playlist above the former 1,000-row ceiling required");
    let page = client
        .playlist_page(playlist.id, 1000, 1)
        .await
        .expect("large public playlist window must pass");
    assert_eq!(page.offset, 1000);
    assert_eq!(page.next, 1001);
    assert!(page.total > 1000);
    println!("large public Playlist: PASS");
}
