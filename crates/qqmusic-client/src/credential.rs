use std::fmt;

use serde::{Deserialize, Serialize};

const LEGACY_CREDENTIAL_PERSISTENCE_VERSION: u64 = 1;
const CREDENTIAL_PERSISTENCE_VERSION: u64 = 2;
const CREDENTIAL_ROTATION_VERSION: u64 = 1;

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
    expires_at_unix_seconds: u64,
}

/// Opaque OAuth expiry value returned by QQ login and required unchanged by
/// the login-type-2 refresh request.
///
/// This is deliberately separate from [`CredentialExpiry`]. QQ responses can
/// carry both `expired_at` and the music-key lifetime pair, and current direct
/// clients treat them as independent protocol fields rather than equivalent
/// timestamps.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CredentialRefreshExpiry(u64);

impl CredentialRefreshExpiry {
    /// # Errors
    ///
    /// Zero denotes an absent protocol value and cannot authorize refresh.
    pub const fn new(value: u64) -> Result<Self, InvalidCredentialExpiry> {
        if value == 0 {
            Err(InvalidCredentialExpiry)
        } else {
            Ok(Self(value))
        }
    }

    #[must_use]
    pub const fn value(self) -> u64 {
        self.0
    }
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
            expires_at_unix_seconds: created_at_unix_seconds + lifetime_seconds,
        })
    }

    /// Builds expiry metadata from the absolute timestamp returned by some QQ
    /// login and refresh envelopes.
    ///
    /// # Errors
    ///
    /// Rejects zero and the Unix epoch's first second. Version-one secure
    /// storage normalizes absolute expiry to a one-second origin plus the
    /// remaining lifetime, so both components must stay non-zero.
    pub const fn from_expires_at(
        expires_at_unix_seconds: u64,
    ) -> Result<Self, InvalidCredentialExpiry> {
        if expires_at_unix_seconds <= 1 {
            return Err(InvalidCredentialExpiry);
        }
        Ok(Self {
            expires_at_unix_seconds,
        })
    }

    #[must_use]
    pub const fn expires_at_unix_seconds(self) -> u64 {
        self.expires_at_unix_seconds
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
    refresh_expiry: Option<CredentialRefreshExpiry>,
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
        if !music_id.bytes().all(|byte| byte.is_ascii_digit()) {
            return Err(InvalidCredential::InvalidMusicId);
        }
        if music_key.trim().is_empty() {
            return Err(InvalidCredential::MissingMusicKey);
        }
        if !music_key.bytes().all(is_cookie_octet) {
            return Err(InvalidCredential::UnsafeMusicKey);
        }

        Ok(Self {
            music_id,
            music_key,
            login_type,
            expiry: None,
            refresh_expiry: None,
            session_secrets: CredentialSessionSecrets::default(),
        })
    }

    #[must_use]
    pub fn with_expiry(mut self, expiry: CredentialExpiry) -> Self {
        self.expiry = Some(expiry);
        self
    }

    #[must_use]
    pub fn with_refresh_expiry(mut self, refresh_expiry: CredentialRefreshExpiry) -> Self {
        self.refresh_expiry = Some(refresh_expiry);
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

    /// Returns the absolute protocol expiry when the login response supplied
    /// reliable lifetime metadata.
    #[must_use]
    pub const fn expires_at_unix_seconds(&self) -> Option<u64> {
        match self.expiry {
            Some(expiry) => Some(expiry.expires_at_unix_seconds()),
            None => None,
        }
    }

    /// Returns the opaque OAuth expiry value required by QQ Type 2 refresh.
    /// It is not used to infer the music-key's local validity.
    #[must_use]
    pub const fn refresh_expiry_value(&self) -> Option<u64> {
        match self.refresh_expiry {
            Some(expiry) => Some(expiry.value()),
            None => None,
        }
    }

    /// Returns whether both credentials belong to the same QQ Music account.
    ///
    /// This comparison deliberately stays in Rust so platform storage code can
    /// coordinate opaque documents without learning account identifiers.
    #[must_use]
    pub fn same_account_as(&self, other: &Self) -> bool {
        self.music_id == other.music_id
    }

    /// Returns whether reliable local expiry metadata says a refresh checkpoint
    /// is due. Credentials without expiry metadata are never guessed to be due.
    #[must_use]
    pub fn refresh_due_at(&self, now_unix_seconds: u64, safety_window_seconds: u64) -> bool {
        let Some(expiry) = self.expiry else {
            return false;
        };
        expiry
            .expires_at_unix_seconds()
            .saturating_sub(safety_window_seconds)
            <= now_unix_seconds
    }

    pub(crate) fn musicu_cookie_header(&self) -> String {
        let music_id = self.music_id();
        let music_key = self.music_key();
        let login_type = self.login_type().value();
        let wechat = if self.login_type() == LoginType::WECHAT {
            format!(" wxuin={music_id};")
        } else {
            String::new()
        };
        format!(
            "uin={music_id}; qqmusic_key={music_key}; qm_keyst={music_key}; tmeLoginType={login_type};{wechat}"
        )
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
            created_at_unix_seconds: 1,
            lifetime_seconds: expiry.expires_at_unix_seconds() - 1,
        });
        let secrets = &self.session_secrets;
        let document = StoredCredentialV2 {
            version: CREDENTIAL_PERSISTENCE_VERSION,
            music_id: self.music_id.clone(),
            music_key: self.music_key.clone(),
            login_type: self.login_type.value(),
            expiry,
            refresh_expiry_value: self.refresh_expiry_value(),
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
        match header.version {
            LEGACY_CREDENTIAL_PERSISTENCE_VERSION => {
                let document: StoredCredentialV1 = serde_json::from_slice(bytes)
                    .map_err(|_| CredentialPersistenceError::InvalidDocument)?;
                decode_stored_credential(StoredCredentialParts::from_legacy(document))
            }
            CREDENTIAL_PERSISTENCE_VERSION => {
                let document: StoredCredentialV2 = serde_json::from_slice(bytes)
                    .map_err(|_| CredentialPersistenceError::InvalidDocument)?;
                decode_stored_credential(StoredCredentialParts::from_current(document))
            }
            version => Err(CredentialPersistenceError::UnsupportedVersion(version)),
        }
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

/// Opaque, versioned crash-recovery document for one credential rotation.
///
/// Flutter may persist these bytes, but must never decode or log them. The
/// source document prevents a staged candidate from replacing a different or
/// newer account after a crash.
#[derive(Clone, Eq, PartialEq)]
pub struct CredentialRotation {
    source: Credential,
    candidate: Credential,
}

impl CredentialRotation {
    /// # Errors
    ///
    /// Rejects a candidate for a different account.
    pub fn new(source: Credential, candidate: Credential) -> Result<Self, CredentialRotationError> {
        if !source.same_account_as(&candidate) {
            return Err(CredentialRotationError::AccountChanged);
        }
        Ok(Self { source, candidate })
    }

    #[must_use]
    pub const fn source(&self) -> &Credential {
        &self.source
    }

    #[must_use]
    pub const fn candidate(&self) -> &Credential {
        &self.candidate
    }

    /// # Errors
    ///
    /// Returns a diagnostics-safe persistence error without exposing content.
    pub fn encode_for_secure_storage(&self) -> Result<Vec<u8>, CredentialRotationError> {
        let document = StoredCredentialRotationV1 {
            version: CREDENTIAL_ROTATION_VERSION,
            source: self
                .source
                .encode_for_secure_storage()
                .map_err(CredentialRotationError::Credential)?,
            candidate: self
                .candidate
                .encode_for_secure_storage()
                .map_err(CredentialRotationError::Credential)?,
        };
        serde_json::to_vec(&document).map_err(|_| CredentialRotationError::Serialize)
    }

    /// # Errors
    ///
    /// Malformed, unsupported, cross-account, or invalid embedded credentials
    /// are rejected without retaining the input bytes.
    pub fn decode_from_secure_storage(bytes: &[u8]) -> Result<Self, CredentialRotationError> {
        let header: StoredCredentialHeader =
            serde_json::from_slice(bytes).map_err(|_| CredentialRotationError::InvalidDocument)?;
        if header.version != CREDENTIAL_ROTATION_VERSION {
            return Err(CredentialRotationError::UnsupportedVersion(header.version));
        }
        let document: StoredCredentialRotationV1 =
            serde_json::from_slice(bytes).map_err(|_| CredentialRotationError::InvalidDocument)?;
        let source = Credential::decode_from_secure_storage(&document.source)
            .map_err(CredentialRotationError::Credential)?;
        let candidate = Credential::decode_from_secure_storage(&document.candidate)
            .map_err(CredentialRotationError::Credential)?;
        Self::new(source, candidate)
    }
}

impl fmt::Debug for CredentialRotation {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CredentialRotation")
            .field(
                "same_account",
                &self.source.same_account_as(&self.candidate),
            )
            .finish_non_exhaustive()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CredentialRotationError {
    Serialize,
    InvalidDocument,
    UnsupportedVersion(u64),
    Credential(CredentialPersistenceError),
    AccountChanged,
}

impl fmt::Display for CredentialRotationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Serialize => formatter.write_str("could not serialize credential rotation"),
            Self::InvalidDocument => formatter.write_str("credential rotation is malformed"),
            Self::UnsupportedVersion(version) => {
                write!(
                    formatter,
                    "credential rotation version {version} is unsupported"
                )
            }
            Self::Credential(error) => error.fmt(formatter),
            Self::AccountChanged => formatter.write_str("credential rotation changed account"),
        }
    }
}

impl std::error::Error for CredentialRotationError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Credential(error) => Some(error),
            Self::Serialize
            | Self::InvalidDocument
            | Self::UnsupportedVersion(_)
            | Self::AccountChanged => None,
        }
    }
}

const fn is_cookie_octet(byte: u8) -> bool {
    matches!(
        byte,
        0x21 | 0x23..=0x2B | 0x2D..=0x3A | 0x3C..=0x5B | 0x5D..=0x7E
    )
}

pub(crate) const fn is_credential_rejection_code(code: i64) -> bool {
    matches!(code, 1_000 | 104_400 | 104_401)
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
struct StoredCredentialV2 {
    version: u64,
    music_id: String,
    music_key: String,
    login_type: u32,
    expiry: Option<StoredCredentialExpiry>,
    refresh_expiry_value: Option<u64>,
    open_id: Option<String>,
    access_token: Option<String>,
    refresh_token: Option<String>,
    refresh_key: Option<String>,
    union_id: Option<String>,
    encrypted_uin: Option<String>,
}

struct StoredCredentialParts {
    music_id: String,
    music_key: String,
    raw_login_type: u32,
    stored_expiry: Option<StoredCredentialExpiry>,
    stored_refresh_expiry_value: Option<u64>,
    open_id: Option<String>,
    access_token: Option<String>,
    refresh_token: Option<String>,
    refresh_key: Option<String>,
    union_id: Option<String>,
    encrypted_uin: Option<String>,
    migrate_legacy_qq_expiry: bool,
}

impl StoredCredentialParts {
    fn from_legacy(document: StoredCredentialV1) -> Self {
        Self {
            music_id: document.music_id,
            music_key: document.music_key,
            raw_login_type: document.login_type,
            stored_expiry: document.expiry,
            stored_refresh_expiry_value: None,
            open_id: document.open_id,
            access_token: document.access_token,
            refresh_token: document.refresh_token,
            refresh_key: document.refresh_key,
            union_id: document.union_id,
            encrypted_uin: document.encrypted_uin,
            migrate_legacy_qq_expiry: true,
        }
    }

    fn from_current(document: StoredCredentialV2) -> Self {
        Self {
            music_id: document.music_id,
            music_key: document.music_key,
            raw_login_type: document.login_type,
            stored_expiry: document.expiry,
            stored_refresh_expiry_value: document.refresh_expiry_value,
            open_id: document.open_id,
            access_token: document.access_token,
            refresh_token: document.refresh_token,
            refresh_key: document.refresh_key,
            union_id: document.union_id,
            encrypted_uin: document.encrypted_uin,
            migrate_legacy_qq_expiry: false,
        }
    }
}

fn decode_stored_credential(
    document: StoredCredentialParts,
) -> Result<Credential, CredentialPersistenceError> {
    let login_type = LoginType::new(document.raw_login_type)
        .map_err(CredentialPersistenceError::InvalidLoginType)?;
    let expiry = document
        .stored_expiry
        .map(|expiry| {
            CredentialExpiry::new(expiry.created_at_unix_seconds, expiry.lifetime_seconds)
                .map_err(CredentialPersistenceError::InvalidExpiry)
        })
        .transpose()?;
    let legacy_refresh_expiry_value =
        if document.migrate_legacy_qq_expiry && login_type == LoginType::QQ {
            expiry.map(CredentialExpiry::expires_at_unix_seconds)
        } else {
            None
        };
    let refresh_expiry = document
        .stored_refresh_expiry_value
        .or(legacy_refresh_expiry_value)
        .map(CredentialRefreshExpiry::new)
        .transpose()
        .map_err(CredentialPersistenceError::InvalidExpiry)?;

    let mut credential = Credential::new(document.music_id, document.music_key, login_type)
        .map_err(CredentialPersistenceError::InvalidCredential)?;
    if let Some(expiry) = expiry {
        credential = credential.with_expiry(expiry);
    }
    if let Some(refresh_expiry) = refresh_expiry {
        credential = credential.with_refresh_expiry(refresh_expiry);
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

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct StoredCredentialRotationV1 {
    version: u64,
    source: Vec<u8>,
    candidate: Vec<u8>,
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
            .field("refresh_expiry_present", &self.refresh_expiry.is_some())
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
    InvalidMusicId,
    MissingMusicKey,
    UnsafeMusicKey,
}

impl fmt::Display for InvalidCredential {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::MissingMusicId => formatter.write_str("credential music id is required"),
            Self::InvalidMusicId => {
                formatter.write_str("credential music id must contain only ASCII digits")
            }
            Self::MissingMusicKey => formatter.write_str("credential music key is required"),
            Self::UnsafeMusicKey => {
                formatter.write_str("credential music key is not safe for protocol transport")
            }
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
        Credential, CredentialExpiry, CredentialPersistenceError, CredentialRefreshExpiry,
        CredentialRestorePlan, CredentialRotation, CredentialRotationError,
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
        assert_eq!(
            Credential::new("12;3", "key", LoginType::QQ),
            Err(InvalidCredential::InvalidMusicId),
        );
        assert_eq!(
            Credential::new("123", "key\r\nInjected: value", LoginType::QQ),
            Err(InvalidCredential::UnsafeMusicKey),
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
        assert!(debug.contains("refresh_expiry_present: false"));
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
        assert!(!credential.refresh_due_at(999, 300));
        assert!(credential.refresh_due_at(1_000, 300));
        assert!(
            !Credential::new("1", "key", LoginType::QQ)
                .expect("credential without expiry")
                .refresh_due_at(u64::MAX, u64::MAX)
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
        assert!(CredentialExpiry::from_expires_at(1).is_err());
        assert_eq!(
            CredentialExpiry::from_expires_at(1_300)
                .expect("absolute expiry")
                .expires_at_unix_seconds(),
            1_300
        );
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
            .with_refresh_expiry(CredentialRefreshExpiry::new(1_250).expect("valid refresh expiry"))
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
        assert!(format!("{decoded:?}").contains("refresh_expiry_present: true"));
        assert!(!format!("{decoded:?}").contains("1250"));
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
            .replace("\"version\":2", "\"version\":3,\"future_field\":true");
        assert_eq!(
            Credential::decode_from_secure_storage(future.as_bytes()),
            Err(CredentialPersistenceError::UnsupportedVersion(3)),
        );
    }

    #[test]
    fn legacy_qq_storage_migrates_the_single_expiry_without_losing_refreshability() {
        let legacy = serde_json::json!({
            "version": 1,
            "music_id": "123456789",
            "music_key": "Q_H_L_super-secret",
            "login_type": 2,
            "expiry": {
                "created_at_unix_seconds": 1,
                "lifetime_seconds": 1_999_999_999_u64
            },
            "open_id": "synthetic-open",
            "access_token": "synthetic-access",
            "refresh_token": "synthetic-refresh",
            "refresh_key": "synthetic-refresh-key",
            "union_id": null,
            "encrypted_uin": null
        });

        let credential = Credential::decode_from_secure_storage(
            &serde_json::to_vec(&legacy).expect("legacy fixture JSON"),
        )
        .expect("version-one QQ credential migration");

        assert_eq!(credential.expires_at_unix_seconds(), Some(2_000_000_000));
        assert_eq!(credential.refresh_expiry_value(), Some(2_000_000_000));
    }

    #[test]
    fn rotation_document_is_opaque_versioned_same_account_and_redacted() {
        let source = credential();
        let candidate = Credential::new(
            source.music_id(),
            "Q_H_L_rotated-secret",
            source.login_type(),
        )
        .expect("candidate");
        let rotation = CredentialRotation::new(source.clone(), candidate.clone())
            .expect("same-account rotation");
        let encoded = rotation
            .encode_for_secure_storage()
            .expect("encode rotation");
        let decoded =
            CredentialRotation::decode_from_secure_storage(&encoded).expect("decode rotation");
        assert_eq!(decoded.source(), &source);
        assert_eq!(decoded.candidate(), &candidate);
        let debug = format!("{decoded:?}");
        assert!(!debug.contains(source.music_id()));
        assert!(!debug.contains("rotated-secret"));
        assert_eq!(
            CredentialRotation::new(
                source,
                Credential::new("999", "key", LoginType::QQ).expect("other account")
            ),
            Err(CredentialRotationError::AccountChanged)
        );
        assert_eq!(
            CredentialRotation::decode_from_secure_storage(b"not-json"),
            Err(CredentialRotationError::InvalidDocument)
        );
    }
}
