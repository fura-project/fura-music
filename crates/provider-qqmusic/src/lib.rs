//! QQ Music provider mapping layer.

use music_domain::ProviderId;
use provider_api::{MusicProvider, ProviderDescriptor};
use qqmusic_client::QqMusicClient;

#[derive(Debug)]
pub struct QqMusicProvider<T> {
    client: QqMusicClient<T>,
}

impl<T> QqMusicProvider<T> {
    #[must_use]
    pub const fn new(client: QqMusicClient<T>) -> Self {
        Self { client }
    }

    #[must_use]
    pub const fn client(&self) -> &QqMusicClient<T> {
        &self.client
    }
}

impl<T> MusicProvider for QqMusicProvider<T> {
    fn descriptor(&self) -> ProviderDescriptor {
        ProviderDescriptor {
            id: ProviderId::new("qq-music").expect("static provider id is valid"),
            display_name: "QQ Music".into(),
            // Capabilities are added only when their behavior is implemented.
            capabilities: Vec::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::QqMusicProvider;
    use provider_api::MusicProvider;
    use qqmusic_client::QqMusicClient;

    #[test]
    fn bootstrap_descriptor_does_not_claim_unimplemented_capabilities() {
        let provider = QqMusicProvider::new(QqMusicClient::new(()));
        let descriptor = provider.descriptor();

        assert_eq!(descriptor.id.as_str(), "qq-music");
        assert_eq!(descriptor.display_name, "QQ Music");
        assert!(descriptor.capabilities.is_empty());
    }
}
