//! Human-operated Level 3 evidence only. The Agent must never run this gate.
//!
//! A Human explicitly approves one QR session, then this test performs bounded,
//! serial, read-only account operations and structural media-source resolution.
//! It proves those selected requests can map for that account at that moment. It
//! does not prove catalog completeness, write behavior, audio-body playback,
//! other regions/member tiers/devices, UI integration or cross-client parity.
use music_domain::{AudioQuality, PlaylistPurpose, TrackSummary};
use netease_client::{Error, HttpsTransport, NeteaseClient, Request, Response, Transport};
use provider_api::{
    AccountSummaryProvider, DailyTracksProvider, FavoriteAlbumsProvider, FavoriteArtistsProvider,
    MediaSourceResolver, PersonalizedPlaylistsProvider, PersonalizedTracksProvider,
    PlaylistDetailsProvider, QrAuthenticationChannel, QrAuthenticationProgress,
    QrAuthenticationProvider, QrAuthenticationSession, UserPlaylistsProvider,
};
use provider_netease::NeteaseProvider;
use std::{
    io::Write,
    sync::atomic::{AtomicBool, AtomicUsize, Ordering},
    time::Duration,
};

const HTTP_BUDGET: usize = 72;

struct Budget {
    http: HttpsTransport,
    calls: AtomicUsize,
    stopped: AtomicBool,
}

impl Transport for Budget {
    async fn send(&self, request: Request) -> Result<Response, Error> {
        if self.stopped.load(Ordering::SeqCst)
            || self.calls.fetch_add(1, Ordering::SeqCst) >= HTTP_BUDGET
        {
            return Err(Error::InputBound);
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
        let response = self.http.send(request).await?;
        let safe_envelope = serde_json::from_slice::<serde_json::Value>(&response.body)
            .ok()
            .and_then(|value| value.get("code").and_then(serde_json::Value::as_i64))
            .is_some_and(|code| matches!(code, 200 | 800 | 801 | 802 | 803));
        if response.status == 429 || (response.status == 200 && !safe_envelope) {
            self.stopped.store(true, Ordering::SeqCst);
        }
        Ok(response)
    }
}

#[tokio::test]
#[ignore = "HUMAN_EVIDENCE_REQUIRED: explicit QR approval and bounded read-only account checks"]
async fn human_account_read_matrix() {
    assert_eq!(
        std::env::var("FURA_NETEASE_HUMAN_ACCOUNT_READS").as_deref(),
        Ok("I_APPROVE_QR_AND_BOUNDED_ACCOUNT_READS")
    );
    let provider = NeteaseProvider::new(NeteaseClient::new(Budget {
        http: HttpsTransport::new().unwrap(),
        calls: AtomicUsize::new(0),
        stopped: AtomicBool::new(false),
    }));
    let mut qr = provider
        .begin_qr_authentication(QrAuthenticationChannel::ProviderDefault)
        .await
        .unwrap();
    let mut file = tempfile::Builder::new()
        .prefix("fura-netease-account-read-qr-")
        .suffix(".png")
        .tempfile()
        .unwrap();
    file.write_all(qr.challenge().image_bytes()).unwrap();
    file.flush().unwrap();
    println!(
        "Human: open the temporary QR image and approve only if intended: {}",
        file.path().display()
    );
    let mut confirmed = false;
    for _ in 0..45 {
        tokio::time::sleep(Duration::from_secs(2)).await;
        match qr.advance().await.unwrap() {
            QrAuthenticationProgress::WaitingForScan
            | QrAuthenticationProgress::ScannedAwaitingConfirmation => {}
            QrAuthenticationProgress::Authenticated => {
                confirmed = true;
                break;
            }
            _ => break,
        }
    }
    assert!(confirmed, "bounded Human QR window did not authenticate");
    drop(file);
    println!("QR and server account verification: PASS");

    provider.account_summary().await.unwrap();
    println!("Account Summary: PASS");

    let playlists = provider.user_playlists().await.unwrap();
    assert!(
        playlists
            .iter()
            .all(|playlist| playlist.ownership() != music_domain::PlaylistOwnership::Unspecified)
    );
    println!("User playlists and ownership relations: PASS");
    let liked = playlists
        .iter()
        .find(|playlist| playlist.purpose() == PlaylistPurpose::LikedSongs)
        .expect("an exact liked-playlist identity is required");
    let ordinary = playlists
        .iter()
        .find(|playlist| playlist.purpose() == PlaylistPurpose::Standard)
        .expect("an ordinary owned or saved playlist is required");

    let liked_page = provider
        .playlist_tracks_page(liked.id().clone(), 0, 20)
        .await
        .unwrap();
    println!("Liked Tracks first bounded page: PASS");
    let ordinary_page = provider
        .playlist_tracks_page(ordinary.id().clone(), 0, 20)
        .await
        .unwrap();
    println!("Ordinary/private Playlist first bounded page: PASS");

    provider.favorite_albums(0, 20).await.unwrap();
    println!("Favorite Albums first bounded page: PASS");
    provider.favorite_artists(0, 20).await.unwrap();
    println!("Favorite Artists first bounded page: PASS");

    let daily = provider.daily_tracks().await.unwrap();
    println!("Daily Tracks: PASS");
    let fm = provider.personalized_tracks().await.unwrap();
    println!("Personal FM: PASS");
    provider.personalized_playlists().await.unwrap();
    println!("Personalized playlists: PASS");

    let seed: TrackSummary = liked_page
        .tracks()
        .first()
        .or_else(|| ordinary_page.tracks().first())
        .or_else(|| daily.first())
        .or_else(|| fm.first())
        .cloned()
        .expect("one exact readable Track is required for source authorization");
    provider
        .media_source_resolver()
        .resolve_media(seed.id().clone(), AudioQuality::Standard)
        .await
        .unwrap();
    println!("Authenticated standard source authorization and mapping: PASS");
    provider.sign_out();
    println!("Human account read matrix: PASS; no audio body was fetched");
}
