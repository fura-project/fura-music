pub mod authentication;
pub mod bootstrap;
pub mod library;
pub mod lyrics;
pub mod media;
pub mod queue;
pub mod search;

fn domain_track_id(provider_id: &str, opaque_track_id: &str) -> Result<music_domain::TrackId, ()> {
    let provider = music_domain::ProviderId::new(provider_id).map_err(|_| ())?;
    music_domain::TrackId::new(provider, opaque_track_id).map_err(|_| ())
}
