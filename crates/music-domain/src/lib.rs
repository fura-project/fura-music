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

#[cfg(test)]
mod tests {
    use super::ProviderId;

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
}
