use netease_client::NeteaseClient;
use provider_api::{BuiltInProvider, MusicProvider};
use provider_netease::NeteaseProvider;
use provider_qqmusic::QqMusicProvider;
use qqmusic_client::QqMusicClient;

/// Presentation-safe startup information used to prove the bridge boundary.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BootstrapStatus {
    pub core_version: String,
    pub providers: Vec<ProviderStatus>,
    pub default_provider_id: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProviderStatus {
    pub id: String,
    pub display_name: String,
    pub implemented_capabilities: Vec<String>,
}

#[flutter_rust_bridge::frb(sync)]
pub fn bootstrap_status() -> BootstrapStatus {
    let qq = QqMusicProvider::new(QqMusicClient::new(()));
    let netease = NeteaseProvider::new(NeteaseClient::new(()));

    BootstrapStatus {
        core_version: env!("CARGO_PKG_VERSION").into(),
        providers: [qq.descriptor(), netease.descriptor()]
            .into_iter()
            .map(|descriptor| ProviderStatus {
                id: descriptor.id.to_string(),
                display_name: descriptor.display_name,
                implemented_capabilities: descriptor
                    .capabilities
                    .into_iter()
                    .map(|capability| format!("{capability:?}"))
                    .collect(),
            })
            .collect(),
        default_provider_id: BuiltInProvider::QQMusic.id().to_string(),
    }
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[cfg(test)]
mod tests {
    use super::bootstrap_status;

    #[test]
    fn bridge_exposes_project_state_without_raw_provider_types() {
        let status = bootstrap_status();

        assert_eq!(status.default_provider_id, "qq-music");
        assert_eq!(status.providers.len(), 2);
        assert_eq!(status.providers[0].id, "qq-music");
        assert_eq!(status.providers[0].display_name, "QQ Music");
        assert_eq!(
            status.providers[0].implemented_capabilities,
            [
                "Search",
                "Catalog",
                "Recommendations",
                "Authentication",
                "UserLibrary",
                "RecentHistoryRead",
                "TrackLikeMutation",
                "AlbumFavoriteMutation",
                "PlaylistTrackMutation",
                "PlaylistCreation",
                "PlaylistDeletion",
                "PlaylistMutation",
                "Lyrics",
                "Comments",
                "MusicVideo"
            ]
        );
        assert_eq!(status.providers[1].id, "netease-cloud-music");
        assert_eq!(status.providers[1].display_name, "NetEase Cloud Music");
        assert_eq!(
            status.providers[1].implemented_capabilities,
            [
                "Search",
                "Catalog",
                "Recommendations",
                "Lyrics",
                "Authentication",
                "UserLibrary",
                "RecentHistoryRead",
                "TrackLikeMutation",
                "PlaylistTrackMutation",
                "PlaylistCreation",
                "Comments",
                "MusicVideo"
            ]
        );
    }
}
