pub mod album;
pub mod artist;
pub mod authentication;
pub mod bootstrap;
pub mod comments;
pub mod favorite_albums;
pub mod favorite_artists;
pub mod library;
pub mod lyrics;
pub mod media;
pub mod music_video;
pub mod new_albums;
pub mod new_songs;
pub mod queue;
pub mod rankings;
pub mod recommendations;
pub mod search;
pub mod track_likes;

fn domain_track_id(provider_id: &str, opaque_track_id: &str) -> Result<music_domain::TrackId, ()> {
    let provider = music_domain::ProviderId::new(provider_id).map_err(|_| ())?;
    music_domain::TrackId::new(provider, opaque_track_id).map_err(|_| ())
}
