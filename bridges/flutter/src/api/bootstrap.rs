use provider_api::MusicProvider;
use provider_qqmusic::QqMusicProvider;
use qqmusic_client::QqMusicClient;

/// Presentation-safe startup information used to prove the bridge boundary.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BootstrapStatus {
    pub core_version: String,
    pub provider: ProviderStatus,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProviderStatus {
    pub id: String,
    pub display_name: String,
    pub implemented_capabilities: Vec<String>,
}

#[flutter_rust_bridge::frb(sync)]
pub fn bootstrap_status() -> BootstrapStatus {
    let provider = QqMusicProvider::new(QqMusicClient::new(()));
    let descriptor = provider.descriptor();

    BootstrapStatus {
        core_version: env!("CARGO_PKG_VERSION").into(),
        provider: ProviderStatus {
            id: descriptor.id.to_string(),
            display_name: descriptor.display_name,
            implemented_capabilities: descriptor
                .capabilities
                .into_iter()
                .map(|capability| format!("{capability:?}"))
                .collect(),
        },
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

        assert_eq!(status.provider.id, "qq-music");
        assert_eq!(status.provider.display_name, "QQ Music");
        assert_eq!(
            status.provider.implemented_capabilities,
            [
                "Search",
                "Authentication",
                "UserLibrary",
                "Lyrics",
                "MediaResolution"
            ]
        );
    }
}
