use std::fmt;

use serde::{Deserialize, Serialize};

const CREDENTIAL_PERSISTENCE_VERSION: u64 = 1;

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

/// Optional secret material returned with a QQ Music credential.
///
/// These fields are retained for future refresh and authenticated protocol
/// work, but are never printed by `Debug`. Empty upstream strings normalize to
/// absence.
#[derive(Clone, Default, Eq, PartialEq)]
pub struct CredentialSessionSecrets {
    open_id: Option<String>,
    access_token: Option<String>,
    refresh_token: Option<String>,
    refresh_key: Option<String>,
    union_id: Option<String>,
    encrypted_uin: Option<String>,
}

impl CredentialSessionSecrets {
    #[must_use]
    pub fn new(
        open_id: Option<String>,
        access_token: Option<String>,
        refresh_token: Option<String>,
        refresh_key: Option<String>,
        union_id: Option<String>,
        encrypted_uin: Option<String>,
    ) -> Self {
        Self {
            open_id: non_empty(open_id),
            access_token: non_empty(access_token),
            refresh_token: non_empty(refresh_token),
            refresh_key: non_empty(refresh_key),
            union_id: non_empty(union_id),
            encrypted_uin: non_empty(encrypted_uin),
        }
    }

    #[must_use]
    pub fn open_id(&self) -> Option<&str> {
        self.open_id.as_deref()
    }

    #[must_use]
    pub fn access_token(&self) -> Option<&str> {
        self.access_token.as_deref()
    }

    #[must_use]
    pub fn refresh_token(&self) -> Option<&str> {
        self.refresh_token.as_deref()
    }

    #[must_use]
    pub fn refresh_key(&self) -> Option<&str> {
        self.refresh_key.as_deref()
    }

    #[must_use]
    pub fn union_id(&self) -> Option<&str> {
        self.union_id.as_deref()
    }

    #[must_use]
    pub fn encrypted_uin(&self) -> Option<&str> {
        self.encrypted_uin.as_deref()
    }
}

impl fmt::Debug for CredentialSessionSecrets {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CredentialSessionSecrets")
            .field("open_id_present", &self.open_id.is_some())
            .field("access_token_present", &self.access_token.is_some())
            .field("refresh_token_present", &self.refresh_token.is_some())
            .field("refresh_key_present", &self.refresh_key.is_some())
            .field("union_id_present", &self.union_id.is_some())
            .field("encrypted_uin_present", &self.encrypted_uin.is_some())
            .finish()
    }
}

fn non_empty(value: Option<String>) -> Option<String> {
    value.filter(|item| !item.is_empty())
}

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
    session_secrets: CredentialSessionSecrets,
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
            session_secrets: CredentialSessionSecrets::default(),
        })
    }

    #[must_use]
    pub fn with_expiry(mut self, expiry: CredentialExpiry) -> Self {
        self.expiry = Some(expiry);
        self
    }

    #[must_use]
    pub fn with_session_secrets(mut self, session_secrets: CredentialSessionSecrets) -> Self {
        self.session_secrets = session_secrets;
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
    pub const fn session_secrets(&self) -> &CredentialSessionSecrets {
        &self.session_secrets
    }

    /// Serializes the credential for a platform secure-storage adapter.
    ///
    /// The returned bytes contain secrets. They must never be logged, cached,
    /// committed, or written outside an OS-backed secret store.
    ///
    /// # Errors
    ///
    /// Returns [`CredentialPersistenceError::Serialize`] if the versioned
    /// document cannot be encoded.
    pub fn encode_for_secure_storage(&self) -> Result<Vec<u8>, CredentialPersistenceError> {
        let expiry = self.expiry.map(|expiry| StoredCredentialExpiry {
            created_at_unix_seconds: expiry.created_at_unix_seconds,
            lifetime_seconds: expiry.lifetime_seconds,
        });
        let secrets = &self.session_secrets;
        let document = StoredCredentialV1 {
            version: CREDENTIAL_PERSISTENCE_VERSION,
            music_id: self.music_id.clone(),
            music_key: self.music_key.clone(),
            login_type: self.login_type.value(),
            expiry,
            open_id: secrets.open_id.clone(),
            access_token: secrets.access_token.clone(),
            refresh_token: secrets.refresh_token.clone(),
            refresh_key: secrets.refresh_key.clone(),
            union_id: secrets.union_id.clone(),
            encrypted_uin: secrets.encrypted_uin.clone(),
        };

        serde_json::to_vec(&document).map_err(|_| CredentialPersistenceError::Serialize)
    }

    /// Parses a versioned credential document loaded from platform secure
    /// storage and revalidates every domain invariant.
    ///
    /// # Errors
    ///
    /// Returns a precise, diagnostics-safe error for malformed, unsupported,
    /// or invalid credential data. The input bytes are never retained.
    pub fn decode_from_secure_storage(bytes: &[u8]) -> Result<Self, CredentialPersistenceError> {
        let header: StoredCredentialHeader = serde_json::from_slice(bytes)
            .map_err(|_| CredentialPersistenceError::InvalidDocument)?;
        if header.version != CREDENTIAL_PERSISTENCE_VERSION {
            return Err(CredentialPersistenceError::UnsupportedVersion(
                header.version,
            ));
        }

        let document: StoredCredentialV1 = serde_json::from_slice(bytes)
            .map_err(|_| CredentialPersistenceError::InvalidDocument)?;

        let login_type = LoginType::new(document.login_type)
            .map_err(CredentialPersistenceError::InvalidLoginType)?;
        let mut credential = Self::new(document.music_id, document.music_key, login_type)
            .map_err(CredentialPersistenceError::InvalidCredential)?;
        if let Some(expiry) = document.expiry {
            credential = credential.with_expiry(
                CredentialExpiry::new(expiry.created_at_unix_seconds, expiry.lifetime_seconds)
                    .map_err(CredentialPersistenceError::InvalidExpiry)?,
            );
        }

        Ok(
            credential.with_session_secrets(CredentialSessionSecrets::new(
                document.open_id,
                document.access_token,
                document.refresh_token,
                document.refresh_key,
                document.union_id,
                document.encrypted_uin,
            )),
        )
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

#[derive(Deserialize)]
struct StoredCredentialHeader {
    version: u64,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct StoredCredentialV1 {
    version: u64,
    music_id: String,
    music_key: String,
    login_type: u32,
    expiry: Option<StoredCredentialExpiry>,
    open_id: Option<String>,
    access_token: Option<String>,
    refresh_token: Option<String>,
    refresh_key: Option<String>,
    union_id: Option<String>,
    encrypted_uin: Option<String>,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct StoredCredentialExpiry {
    created_at_unix_seconds: u64,
    lifetime_seconds: u64,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CredentialPersistenceError {
    Serialize,
    InvalidDocument,
    UnsupportedVersion(u64),
    InvalidLoginType(InvalidLoginType),
    InvalidCredential(InvalidCredential),
    InvalidExpiry(InvalidCredentialExpiry),
}

impl fmt::Display for CredentialPersistenceError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Serialize => formatter.write_str("could not serialize credential document"),
            Self::InvalidDocument => formatter.write_str("credential document is malformed"),
            Self::UnsupportedVersion(version) => {
                write!(
                    formatter,
                    "credential document version {version} is unsupported"
                )
            }
            Self::InvalidLoginType(error) => error.fmt(formatter),
            Self::InvalidCredential(error) => error.fmt(formatter),
            Self::InvalidExpiry(error) => error.fmt(formatter),
        }
    }
}

impl std::error::Error for CredentialPersistenceError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::InvalidLoginType(error) => Some(error),
            Self::InvalidCredential(error) => Some(error),
            Self::InvalidExpiry(error) => Some(error),
            Self::Serialize | Self::InvalidDocument | Self::UnsupportedVersion(_) => None,
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
            .field("session_secrets", &self.session_secrets)
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
        Credential, CredentialExpiry, CredentialPersistenceError, CredentialRestorePlan,
        CredentialSessionSecrets, InvalidCredential, LocalCredentialValidity, LoginType,
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
        let credential = credential().with_session_secrets(CredentialSessionSecrets::new(
            Some("secret-open-id".into()),
            Some("secret-access-token".into()),
            Some("secret-refresh-token".into()),
            Some("secret-refresh-key".into()),
            Some("secret-union-id".into()),
            Some("secret-encrypted-uin".into()),
        ));
        let debug = format!("{credential:?}");

        assert!(!debug.contains("123456789"));
        assert!(!debug.contains("Q_H_L_super-secret"));
        assert!(!debug.contains("secret-"));
        assert_eq!(debug.matches("[REDACTED]").count(), 2);
        assert!(debug.contains("refresh_token_present: true"));
    }

    #[test]
    fn session_secrets_normalize_empty_protocol_fields() {
        let secrets = CredentialSessionSecrets::new(
            Some(String::new()),
            None,
            Some("refresh-token".into()),
            None,
            None,
            None,
        );

        assert_eq!(secrets.open_id(), None);
        assert_eq!(secrets.refresh_token(), Some("refresh-token"));
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

    #[test]
    fn secure_storage_document_round_trips_all_credential_fields() {
        let original = credential()
            .with_expiry(CredentialExpiry::new(1_000, 300).expect("valid expiry"))
            .with_session_secrets(CredentialSessionSecrets::new(
                Some("secret-open-id".into()),
                Some("secret-access-token".into()),
                Some("secret-refresh-token".into()),
                Some("secret-refresh-key".into()),
                Some("secret-union-id".into()),
                Some("secret-encrypted-uin".into()),
            ));

        let encoded = original
            .encode_for_secure_storage()
            .expect("serialize credential");
        let decoded =
            Credential::decode_from_secure_storage(&encoded).expect("decode versioned credential");

        assert_eq!(decoded, original);
        assert!(!format!("{decoded:?}").contains("secret-"));
    }

    #[test]
    fn secure_storage_document_rejects_malformed_and_future_versions() {
        assert_eq!(
            Credential::decode_from_secure_storage(b"not-json"),
            Err(CredentialPersistenceError::InvalidDocument),
        );

        let encoded = credential()
            .encode_for_secure_storage()
            .expect("serialize credential");
        let future = String::from_utf8(encoded)
            .expect("credential JSON is UTF-8")
            .replace("\"version\":1", "\"version\":2,\"future_field\":true");
        assert_eq!(
            Credential::decode_from_secure_storage(future.as_bytes()),
            Err(CredentialPersistenceError::UnsupportedVersion(2)),
        );
    }
}
