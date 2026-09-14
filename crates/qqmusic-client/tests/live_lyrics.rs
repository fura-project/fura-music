use qqmusic_client::{QqMusicClient, ReqwestTransport};

/// Opt-in compatibility probe using a public song MID and no account material.
/// It retains and prints no ciphertext or lyric text.
#[tokio::test]
#[ignore = "live QQ Music service; run explicitly with QQMUSIC_LIVE_TESTS=1"]
async fn decrypts_and_parses_an_anonymous_cloud_qrc_shape() {
    if std::env::var("QQMUSIC_LIVE_TESTS").as_deref() != Ok("1") {
        eprintln!("skipped: set QQMUSIC_LIVE_TESTS=1 for the live request");
        return;
    }

    let client = QqMusicClient::new(ReqwestTransport::new().expect("native HTTPS transport"));
    let lyrics = client
        .lyrics(None, "003w2xz20QlUZt", 0)
        .await
        .expect("current anonymous QRC request/decrypt/parse shape");

    assert!(!lyrics.original().is_empty());
    assert!(
        lyrics
            .original()
            .iter()
            .any(|line| !line.segments().is_empty())
    );
}

/// Opt-in regression coverage for public catalog tracks that previously
/// reached the client but were rejected by the safe QRC parser. The probe
/// searches by public metadata and retains or prints neither lyric text nor
/// encrypted payloads.
#[tokio::test]
#[ignore = "live QQ Music service; run explicitly with QQMUSIC_LIVE_TESTS=1"]
async fn parses_reported_public_lyric_regressions() {
    if std::env::var("QQMUSIC_LIVE_TESTS").as_deref() != Ok("1") {
        eprintln!("skipped: set QQMUSIC_LIVE_TESTS=1 for the live requests");
        return;
    }

    let client = QqMusicClient::new(ReqwestTransport::new().expect("native HTTPS transport"));
    let samples = [
        ("As It Was", "Harry Styles", 167),
        ("whoa (mind in awe)", "XXXTentacion", 157),
    ];
    let mut failures = Vec::new();

    for (title, artist, duration_seconds) in samples {
        let page = client
            .search_tracks(title, 1, 20)
            .await
            .expect("public catalog search");
        let track = page
            .tracks()
            .iter()
            .find(|track| {
                track.title().eq_ignore_ascii_case(title)
                    && track.duration_seconds() == duration_seconds
                    && track
                        .artists()
                        .iter()
                        .any(|candidate| candidate.name().eq_ignore_ascii_case(artist))
            })
            .expect("reported public catalog track");

        match client
            .lyrics(None, track.song_mid(), track.song_type())
            .await
        {
            Ok(lyrics) if !lyrics.original().is_empty() => {}
            Ok(_) => failures.push((title, "empty parsed document".to_owned())),
            Err(error) => failures.push((title, format!("{error:?}"))),
        }
    }

    assert!(
        failures.is_empty(),
        "public lyric regressions: {failures:?}"
    );
}
