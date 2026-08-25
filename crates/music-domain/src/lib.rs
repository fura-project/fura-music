//! Provider-independent music domain types.

use std::fmt;

/// Stable provider identity used by core domain objects.
///
/// This is intentionally not an enum: domain identity must not require a
/// central source edit if a future, approved provider is introduced.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct ProviderId(String);

impl ProviderId {
    /// Builds an identity from a stable, non-empty lowercase ASCII key.
    ///
    /// # Errors
    ///
    /// Returns [`InvalidProviderId`] when the key is empty or contains anything
    /// other than lowercase ASCII letters, digits, or `-`.
    pub fn new(value: impl Into<String>) -> Result<Self, InvalidProviderId> {
        let value = value.into();
        let valid = !value.is_empty()
            && value
                .bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-');

        if valid {
            Ok(Self(value))
        } else {
            Err(InvalidProviderId)
        }
    }

    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for ProviderId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidProviderId;

impl fmt::Display for InvalidProviderId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("provider id must be a non-empty lowercase ASCII key")
    }
}

impl std::error::Error for InvalidProviderId {}

/// Provider-scoped playlist identity. The opaque value is interpreted only by
/// the owning provider and must not be parsed by presentation code.
#[derive(Clone, Eq, Hash, PartialEq)]
pub struct PlaylistId {
    provider: ProviderId,
    opaque: String,
}

impl PlaylistId {
    /// # Errors
    ///
    /// Returns [`InvalidPlaylistId`] when the provider-owned value is empty or
    /// whitespace-only.
    pub fn new(provider: ProviderId, opaque: impl Into<String>) -> Result<Self, InvalidPlaylistId> {
        let opaque = opaque.into();
        if opaque.trim().is_empty() {
            return Err(InvalidPlaylistId);
        }
        Ok(Self { provider, opaque })
    }

    #[must_use]
    pub const fn provider(&self) -> &ProviderId {
        &self.provider
    }

    /// Returns the provider-owned identity for routing back to that provider.
    /// Other layers must treat it as opaque.
    #[must_use]
    pub fn opaque(&self) -> &str {
        &self.opaque
    }
}

impl fmt::Debug for PlaylistId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PlaylistId")
            .field("provider", &self.provider)
            .field("opaque", &"[REDACTED]")
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidPlaylistId;

impl fmt::Display for InvalidPlaylistId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("playlist identity must have a non-empty provider value")
    }
}

impl std::error::Error for InvalidPlaylistId {}

/// Minimum provider-independent data required to present a playlist row.
#[derive(Clone, Eq, PartialEq)]
pub struct PlaylistSummary {
    id: PlaylistId,
    title: String,
    artwork_uri: Option<String>,
    track_count: Option<u32>,
}

impl PlaylistSummary {
    /// # Errors
    ///
    /// Returns [`InvalidPlaylistSummary`] when the title is empty or
    /// whitespace-only.
    pub fn new(id: PlaylistId, title: impl Into<String>) -> Result<Self, InvalidPlaylistSummary> {
        let title = title.into();
        if title.trim().is_empty() {
            return Err(InvalidPlaylistSummary);
        }
        Ok(Self {
            id,
            title,
            artwork_uri: None,
            track_count: None,
        })
    }

    #[must_use]
    pub fn with_artwork_uri(mut self, artwork_uri: Option<String>) -> Self {
        self.artwork_uri = artwork_uri.filter(|value| !value.trim().is_empty());
        self
    }

    #[must_use]
    pub const fn with_track_count(mut self, track_count: Option<u32>) -> Self {
        self.track_count = track_count;
        self
    }

    #[must_use]
    pub const fn id(&self) -> &PlaylistId {
        &self.id
    }

    #[must_use]
    pub fn title(&self) -> &str {
        &self.title
    }

    #[must_use]
    pub fn artwork_uri(&self) -> Option<&str> {
        self.artwork_uri.as_deref()
    }

    #[must_use]
    pub const fn track_count(&self) -> Option<u32> {
        self.track_count
    }
}

impl fmt::Debug for PlaylistSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PlaylistSummary")
            .field("id", &self.id)
            .field("title", &"[REDACTED]")
            .field("has_artwork", &self.artwork_uri.is_some())
            .field("track_count", &self.track_count)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidPlaylistSummary;

impl fmt::Display for InvalidPlaylistSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("playlist summary title must not be empty")
    }
}

impl std::error::Error for InvalidPlaylistSummary {}

#[cfg(test)]
mod tests {
    use super::{PlaylistId, PlaylistSummary, ProviderId};

    #[test]
    fn provider_id_accepts_stable_keys() {
        let id = ProviderId::new("qq-music").expect("valid provider id");
        assert_eq!(id.as_str(), "qq-music");
    }

    #[test]
    fn provider_id_rejects_display_names_and_empty_values() {
        for value in ["", "QQMusic", "qq music", "qq_music"] {
            assert!(ProviderId::new(value).is_err(), "accepted {value:?}");
        }
    }

    #[test]
    fn playlist_identity_is_provider_scoped_and_opaque() {
        let id = PlaylistId::new(
            ProviderId::new("qq-music").expect("provider"),
            "owned:7001:201",
        )
        .expect("playlist ID");

        assert_eq!(id.provider().as_str(), "qq-music");
        assert_eq!(id.opaque(), "owned:7001:201");
        assert!(!format!("{id:?}").contains("7001"));
        assert!(PlaylistId::new(ProviderId::new("qq-music").expect("provider"), "   ").is_err());
    }

    #[test]
    fn playlist_summary_keeps_optional_display_metadata_honest() {
        let id = PlaylistId::new(
            ProviderId::new("qq-music").expect("provider"),
            "owned:7001:201",
        )
        .expect("playlist ID");
        let summary = PlaylistSummary::new(id, "Synthetic favorites")
            .expect("summary")
            .with_artwork_uri(Some("https://example.invalid/cover.jpg".into()))
            .with_track_count(Some(42));

        assert_eq!(summary.title(), "Synthetic favorites");
        assert_eq!(summary.track_count(), Some(42));
        assert_eq!(
            summary.artwork_uri(),
            Some("https://example.invalid/cover.jpg")
        );
        assert!(!format!("{summary:?}").contains("Synthetic favorites"));
    }
}
