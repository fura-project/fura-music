//! Small, UI-free provider contracts.

use music_domain::ProviderId;

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum ProviderCapability {
    Authentication,
    Catalog,
    Recommendations,
    UserLibrary,
    PlaylistMutation,
    Lyrics,
    MediaResolution,
}

/// Describes behavior that is implemented now, not planned future behavior.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProviderDescriptor {
    pub id: ProviderId,
    pub display_name: String,
    pub capabilities: Vec<ProviderCapability>,
}

/// Baseline contract shared by every approved provider implementation.
pub trait MusicProvider {
    fn descriptor(&self) -> ProviderDescriptor;
}

#[cfg(test)]
mod tests {
    use super::{MusicProvider, ProviderCapability, ProviderDescriptor};
    use music_domain::ProviderId;

    struct LibraryOnlyProvider;

    impl MusicProvider for LibraryOnlyProvider {
        fn descriptor(&self) -> ProviderDescriptor {
            ProviderDescriptor {
                id: ProviderId::new("local").expect("static provider id"),
                display_name: "Local".into(),
                capabilities: vec![ProviderCapability::Catalog],
            }
        }
    }

    #[test]
    fn providers_can_truthfully_expose_partial_capabilities() {
        let descriptor = LibraryOnlyProvider.descriptor();
        assert_eq!(descriptor.id.as_str(), "local");
        assert_eq!(descriptor.capabilities, [ProviderCapability::Catalog]);
    }
}
