use std::fmt;

/// Numeric QQ Music login type carried by musicu requests.
///
/// Unknown non-zero values are preserved because this is a protocol identity,
/// not a product feature enum.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct LoginType(u32);

impl LoginType {
    pub const WECHAT: Self = Self(1);
    pub const QQ: Self = Self(2);
    pub const QQ_MUSIC_APP: Self = Self(6);

    /// # Errors
    ///
    /// Returns [`InvalidLoginType`] for zero, which represents no login type in
    /// observed QQ Music responses rather than an authenticated credential.
    pub const fn new(value: u32) -> Result<Self, InvalidLoginType> {
        if value == 0 {
            Err(InvalidLoginType)
        } else {
            Ok(Self(value))
        }
    }

    #[must_use]
    pub const fn value(self) -> u32 {
        self.0
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidLoginType;

impl fmt::Display for InvalidLoginType {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("QQ Music login type must be non-zero")
    }
}

impl std::error::Error for InvalidLoginType {}

/// Locally supplied lifetime metadata for a QQ Music key.
///
/// This metadata can prove that a key is locally expired. It cannot prove that
/// an otherwise unexpired key is still accepted by QQ Music.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CredentialExpiry {
    created_at_unix_seconds: u64,
    lifetime_seconds: u64,
}

impl CredentialExpiry {
    /// # Errors
    ///
    /// Returns [`InvalidCredentialExpiry`] for a zero timestamp/lifetime or a
    /// timestamp whose end would overflow `u64`.
    pub const fn new(
        created_at_unix_seconds: u64,
        lifetime_seconds: u64,
    ) -> Result<Self, InvalidCredentialExpiry> {
        if created_at_unix_seconds == 0
            || lifetime_seconds == 0
            || created_at_unix_seconds
                .checked_add(lifetime_seconds)
                .is_none()
        {
            return Err(InvalidCredentialExpiry);
        }

        Ok(Self {
            created_at_unix_seconds,
            lifetime_seconds,
        })
    }

    #[must_use]
    pub const fn expires_at_unix_seconds(self) -> u64 {
        // The constructor proves this addition cannot overflow.
        self.created_at_unix_seconds + self.lifetime_seconds
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidCredentialExpiry;

impl fmt::Display for InvalidCredentialExpiry {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("credential timestamps must be non-zero and representable")
    }
}

impl std::error::Error for InvalidCredentialExpiry {}

/// The minimum credential required to authenticate QQ Music protocol calls.
///
/// Accessors intentionally make secret use explicit. Do not log or expose this
/// type through the Flutter bridge.
#[derive(Clone, Eq, PartialEq)]
pub struct Credential {
    music_id: String,
    music_key: String,
    login_type: LoginType,
    expiry: Option<CredentialExpiry>,
}

impl Credential {
    /// # Errors
    ///
    /// Returns [`InvalidCredential`] when either required string is empty or
    /// whitespace-only.
    pub fn new(
        music_id: impl Into<String>,
        music_key: impl Into<String>,
        login_type: LoginType,
    ) -> Result<Self, InvalidCredential> {
        let music_id = music_id.into();
        let music_id = music_id.trim().to_owned();
        let music_key = music_key.into();

        if music_id.is_empty() {
            return Err(InvalidCredential::MissingMusicId);
        }
        if music_key.trim().is_empty() {
            return Err(InvalidCredential::MissingMusicKey);
        }

        Ok(Self {
            music_id,
            music_key,
            login_type,
            expiry: None,
        })
    }

    #[must_use]
    pub fn with_expiry(mut self, expiry: CredentialExpiry) -> Self {
        self.expiry = Some(expiry);
        self
    }

    /// Returns sensitive account identity for protocol construction only.
    #[must_use]
    pub fn music_id(&self) -> &str {
        &self.music_id
    }

    /// Returns the secret key for protocol construction only.
    #[must_use]
    pub fn music_key(&self) -> &str {
        &self.music_key
    }

    #[must_use]
    pub const fn login_type(&self) -> LoginType {
        self.login_type
    }

    #[must_use]
    pub const fn local_validity_at(&self, now_unix_seconds: u64) -> LocalCredentialValidity {
        let Some(expiry) = self.expiry else {
            return LocalCredentialValidity::Unknown;
        };
        let expires_at_unix_seconds = expiry.expires_at_unix_seconds();

        if now_unix_seconds >= expires_at_unix_seconds {
            LocalCredentialValidity::Expired {
                expired_at_unix_seconds: expires_at_unix_seconds,
            }
        } else {
            LocalCredentialValidity::NotExpired {
                expires_at_unix_seconds,
            }
        }
    }
}

impl fmt::Debug for Credential {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("Credential")
            .field("music_id", &Redacted)
            .field("music_key", &Redacted)
            .field("login_type", &self.login_type)
            .field("expiry", &self.expiry)
            .finish()
    }
}

struct Redacted;

impl fmt::Debug for Redacted {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("[REDACTED]")
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum InvalidCredential {
    MissingMusicId,
    MissingMusicKey,
}

impl fmt::Display for InvalidCredential {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::MissingMusicId => formatter.write_str("credential music id is required"),
            Self::MissingMusicKey => formatter.write_str("credential music key is required"),
        }
    }
}

impl std::error::Error for InvalidCredential {}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LocalCredentialValidity {
    /// No usable lifetime metadata was returned; ask QQ Music.
    Unknown,
    /// The local clock has not reached the advertised expiry. Server
    /// verification is still required.
    NotExpired {
        expires_at_unix_seconds: u64,
    },
    Expired {
        expired_at_unix_seconds: u64,
    },
}

/// Safe next action after loading an optional credential from future storage.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CredentialRestorePlan {
    SignedOut,
    VerifyWithServer(Credential),
    LocallyExpired(Credential),
}

impl CredentialRestorePlan {
    #[must_use]
    pub fn from_loaded(credential: Option<Credential>, now_unix_seconds: u64) -> Self {
        let Some(credential) = credential else {
            return Self::SignedOut;
        };

        match credential.local_validity_at(now_unix_seconds) {
            LocalCredentialValidity::Expired { .. } => Self::LocallyExpired(credential),
            LocalCredentialValidity::Unknown | LocalCredentialValidity::NotExpired { .. } => {
                Self::VerifyWithServer(credential)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        Credential, CredentialExpiry, CredentialRestorePlan, InvalidCredential,
        LocalCredentialValidity, LoginType,
    };

    fn credential() -> Credential {
        Credential::new("123456789", "Q_H_L_super-secret", LoginType::QQ)
            .expect("fixture credential is valid")
    }

    #[test]
    fn login_type_rejects_only_the_observed_empty_value() {
        assert!(LoginType::new(0).is_err());
        assert_eq!(LoginType::new(42).expect("opaque type").value(), 42);
    }

    #[test]
    fn credential_requires_both_core_fields() {
        assert_eq!(
            Credential::new(" ", "key", LoginType::QQ),
            Err(InvalidCredential::MissingMusicId),
        );
        assert_eq!(
            Credential::new("123", "\n", LoginType::QQ),
            Err(InvalidCredential::MissingMusicKey),
        );
    }

    #[test]
    fn credential_debug_output_redacts_account_and_key() {
        let debug = format!("{:?}", credential());

        assert!(!debug.contains("123456789"));
        assert!(!debug.contains("Q_H_L_super-secret"));
        assert_eq!(debug.matches("[REDACTED]").count(), 2);
    }

    #[test]
    fn missing_expiry_metadata_is_unknown_not_valid() {
        assert_eq!(
            credential().local_validity_at(1_000),
            LocalCredentialValidity::Unknown,
        );
    }

    #[test]
    fn local_expiry_uses_an_inclusive_boundary() {
        let expiry = CredentialExpiry::new(1_000, 300).expect("valid expiry");
        let credential = credential().with_expiry(expiry);

        assert_eq!(
            credential.local_validity_at(1_299),
            LocalCredentialValidity::NotExpired {
                expires_at_unix_seconds: 1_300,
            },
        );
        assert_eq!(
            credential.local_validity_at(1_300),
            LocalCredentialValidity::Expired {
                expired_at_unix_seconds: 1_300,
            },
        );
    }

    #[test]
    fn invalid_expiry_metadata_is_rejected() {
        assert!(CredentialExpiry::new(0, 300).is_err());
        assert!(CredentialExpiry::new(1_000, 0).is_err());
        assert!(CredentialExpiry::new(u64::MAX, 1).is_err());
    }

    #[test]
    fn absent_credential_restores_to_signed_out() {
        assert_eq!(
            CredentialRestorePlan::from_loaded(None, 1_000),
            CredentialRestorePlan::SignedOut,
        );
    }

    #[test]
    fn present_credential_requires_server_verification() {
        assert!(matches!(
            CredentialRestorePlan::from_loaded(Some(credential()), 1_000),
            CredentialRestorePlan::VerifyWithServer(_),
        ));
    }

    #[test]
    fn locally_expired_credential_is_not_silently_discarded() {
        let expiry = CredentialExpiry::new(1_000, 300).expect("valid expiry");
        let credential = credential().with_expiry(expiry);

        assert!(matches!(
            CredentialRestorePlan::from_loaded(Some(credential), 1_300),
            CredentialRestorePlan::LocallyExpired(_),
        ));
    }

    #[test]
    fn restore_plan_debug_output_keeps_nested_credential_redacted() {
        let debug = format!(
            "{:?}",
            CredentialRestorePlan::from_loaded(Some(credential()), 1_000),
        );

        assert!(!debug.contains("123456789"));
        assert!(!debug.contains("Q_H_L_super-secret"));
    }
}
