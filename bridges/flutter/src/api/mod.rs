pub mod album;
pub mod album_favorites;
pub mod artist;
pub mod authentication;
pub mod bootstrap;
pub mod comments;
pub mod favorite_albums;
pub mod favorite_artists;
pub mod library;
pub mod listening;
pub mod lyrics;
pub mod media;
pub mod music_video;
pub mod netease_authentication;
pub mod new_albums;
pub mod new_songs;
pub mod playlist_creation;
pub mod playlist_deletion;
pub mod playlist_tracks;
pub mod queue;
pub mod rankings;
pub mod recommendations;
mod remote_mutation;
pub mod search;
pub mod track_likes;

use provider_api::BuiltInProvider;

pub(crate) fn built_in_provider(provider_id: &str) -> Result<BuiltInProvider, ()> {
    BuiltInProvider::ALL
        .into_iter()
        .find(|provider| provider.id().as_str() == provider_id)
        .ok_or(())
}

macro_rules! with_native_provider {
    ($provider_id:expr, |$provider:ident| $body:block, $unavailable:expr) => {{
        match $crate::api::built_in_provider($provider_id) {
            Ok(provider_api::BuiltInProvider::QQMusic) => {
                match $crate::api::authentication::native_qq_music_provider() {
                    Ok($provider) => $body,
                    Err(()) => $unavailable,
                }
            }
            Ok(provider_api::BuiltInProvider::NetEaseCloudMusic) => {
                match $crate::native_netease::native_netease_provider() {
                    Ok($provider) => $body,
                    Err(()) => $unavailable,
                }
            }
            Err(()) => $unavailable,
        }
    }};
}

pub(crate) use with_native_provider;

fn domain_track_id(provider_id: &str, opaque_track_id: &str) -> Result<music_domain::TrackId, ()> {
    let provider = music_domain::ProviderId::new(provider_id).map_err(|_| ())?;
    music_domain::TrackId::new(provider, opaque_track_id).map_err(|_| ())
}

fn domain_playlist_id(
    provider_id: &str,
    opaque_playlist_id: &str,
) -> Result<music_domain::PlaylistId, ()> {
    let provider = music_domain::ProviderId::new(provider_id).map_err(|_| ())?;
    music_domain::PlaylistId::new(provider, opaque_playlist_id).map_err(|_| ())
}

fn domain_album_id(provider_id: &str, opaque_album_id: &str) -> Result<music_domain::AlbumId, ()> {
    let provider = music_domain::ProviderId::new(provider_id).map_err(|_| ())?;
    music_domain::AlbumId::new(provider, opaque_album_id).map_err(|_| ())
}

#[cfg(test)]
mod tests {
    use super::{built_in_provider, domain_album_id, domain_playlist_id, domain_track_id};
    use provider_api::BuiltInProvider;

    #[test]
    fn built_in_dispatch_is_exact_and_has_no_fallback() {
        assert_eq!(built_in_provider("qq-music"), Ok(BuiltInProvider::QQMusic));
        assert_eq!(
            built_in_provider("netease-cloud-music"),
            Ok(BuiltInProvider::NetEaseCloudMusic)
        );
        assert!(built_in_provider("QQ Music").is_err());
        assert!(built_in_provider("netease").is_err());
        assert!(built_in_provider("unknown-provider").is_err());
    }

    #[test]
    fn identical_opaque_entities_remain_provider_owned() {
        let qq_track = domain_track_id("qq-music", "123").expect("QQ Track");
        let netease_track = domain_track_id("netease-cloud-music", "123").expect("NetEase Track");
        assert_ne!(qq_track, netease_track);
        assert_eq!(qq_track.provider().as_str(), "qq-music");
        assert_eq!(netease_track.provider().as_str(), "netease-cloud-music");

        let qq_playlist = domain_playlist_id("qq-music", "123").expect("QQ Playlist");
        let netease_playlist =
            domain_playlist_id("netease-cloud-music", "123").expect("NetEase Playlist");
        assert_ne!(qq_playlist, netease_playlist);

        let qq_album = domain_album_id("qq-music", "123").expect("QQ Album");
        let netease_album = domain_album_id("netease-cloud-music", "123").expect("NetEase Album");
        assert_ne!(qq_album, netease_album);
    }
}
