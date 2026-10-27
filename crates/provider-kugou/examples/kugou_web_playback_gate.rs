//! Manual-only tool. Never accesses a browser, vault, profile or account itself.
use kugou_client::web_playback_candidate::{WebPlaybackError, WebPlaybackHttpsTransport};
use music_domain::TrackId;
use provider_kugou::{provider_id, web_playback_candidate::AuthenticatedStandardCandidate};
use serde::Deserialize;
use std::io::{self, Read};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Input {
    authorization: String,
    account_confirmed_by_human: bool,
    official_origin: String,
    cookie_header: String,
    captured_songinfo_url: String,
    track_opaque: String,
    approved_media_host: String,
    probe_range: bool,
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    if std::env::args().nth(1).as_deref() != Some("--human-authorized-once") {
        println!("KUGOU_GATE result=NOT_RUN reason=EXPLICIT_HUMAN_AUTHORIZATION_REQUIRED");
        return;
    }
    match run().await {
        Ok(range) => println!(
            "KUGOU_GATE result=PASS scope=STANDARD_SOURCE_ONLY https_source=true range_verified={range} account_summary_verified=false production_enabled=false"
        ),
        Err(error) => {
            println!("KUGOU_GATE result=BLOCKED reason={error:?} production_enabled=false");
            std::process::exit(1);
        }
    }
}

async fn run() -> Result<bool, WebPlaybackError> {
    let mut bytes = Vec::new();
    io::stdin()
        .take(32_769)
        .read_to_end(&mut bytes)
        .map_err(|_| WebPlaybackError::InvalidCapture)?;
    if bytes.len() > 32_768 {
        return Err(WebPlaybackError::InvalidCapture);
    }
    let input: Result<Input, _> = serde_json::from_slice(&bytes);
    bytes.fill(0);
    let input = input.map_err(|_| WebPlaybackError::InvalidCapture)?;
    if input.authorization != "I_AUTHORIZE_ONE_KUGOU_WEB_REQUEST"
        || !input.account_confirmed_by_human
    {
        return Err(WebPlaybackError::InvalidCapture);
    }
    let transport = WebPlaybackHttpsTransport::new()?;
    let probe = WebPlaybackHttpsTransport::new()?;
    let owner = AuthenticatedStandardCandidate::new(transport);
    owner.stage_official_web_session(&input.official_origin, &input.cookie_header)?;
    let track = TrackId::new(provider_id(), input.track_opaque)
        .map_err(|_| WebPlaybackError::InvalidCapture)?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| WebPlaybackError::InvalidCapture)?
        .as_secs();
    let source = owner
        .resolve_once(
            &track,
            &input.captured_songinfo_url,
            &input.approved_media_host,
            now,
        )
        .await?;
    if input.probe_range {
        probe.probe_range(source).await?;
    }
    owner.clear();
    Ok(input.probe_range)
}
