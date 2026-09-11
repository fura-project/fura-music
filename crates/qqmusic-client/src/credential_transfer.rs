use std::fmt;

use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use chacha20poly1305::{
    XChaCha20Poly1305, XNonce,
    aead::{Aead, KeyInit, Payload},
};
use getrandom::fill;
use serde::{Deserialize, Serialize};
use zeroize::{Zeroize, Zeroizing};

use crate::{Credential, CredentialPersistenceError};

const TRANSFER_VERSION: u32 = 1;
const TRANSFER_PROVIDER: &str = "qqmusic";
const SESSION_ID_BYTES: usize = 16;
const TRANSFER_KEY_BYTES: usize = 32;
const NONCE_BYTES: usize = 24;
const MAX_BUNDLE_BYTES: usize = 32 * 1024;
const MAX_SECRET_DOCUMENT_BYTES: usize = 1024;
const MAX_AGE_SECONDS: u64 = 10 * 60;
const MAX_FUTURE_SKEW_SECONDS: u64 = 60;

/// Encrypted credential material for the development-only cross-device
/// compatibility experiment.
///
/// The bundle and transfer secret must travel through separate Human-controlled
/// channels. Possession of both is equivalent to possession of the credential.
pub struct CredentialTransferPackage {
    encrypted_bundle: Vec<u8>,
    transfer_secret: Zeroizing<Vec<u8>>,
}

/// Parsed transfer result. It remains an unauthenticated candidate until the
/// provider completes its normal server verification.
#[derive(Clone, Eq, PartialEq)]
pub struct CredentialTransferImport {
    credential: Credential,
    session_id: String,
}

impl CredentialTransferImport {
    #[must_use]
    pub fn session_id(&self) -> &str {
        &self.session_id
    }

    #[must_use]
    pub fn into_credential(self) -> Credential {
        self.credential
    }
}

impl fmt::Debug for CredentialTransferImport {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CredentialTransferImport")
            .field("credential", &self.credential)
            .field("session_id", &"[REDACTED]")
            .finish()
    }
}

impl CredentialTransferPackage {
    #[must_use]
    pub fn encrypted_bundle(&self) -> &[u8] {
        &self.encrypted_bundle
    }

    /// Returns key material for the explicit development transfer harness.
    /// Never log it, put it in a QR code, or store it beside the bundle.
    #[must_use]
    pub fn transfer_secret(&self) -> &[u8] {
        &self.transfer_secret
    }

    #[must_use]
    pub fn into_parts(self) -> (Vec<u8>, Zeroizing<Vec<u8>>) {
        (self.encrypted_bundle, self.transfer_secret)
    }
}

impl fmt::Debug for CredentialTransferPackage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CredentialTransferPackage")
            .field("encrypted_bundle_bytes", &self.encrypted_bundle.len())
            .field("transfer_secret", &"[REDACTED]")
            .finish()
    }
}

/// Creates an authenticated, short-lived transfer document from the existing
/// QQ Music credential model. Credential plaintext never leaves this Rust
/// function.
///
/// # Errors
///
/// Returns a diagnostics-safe error when secure randomness, serialization, or
/// encryption is unavailable.
pub fn export_encrypted_credential_bundle(
    credential: &Credential,
    issued_at_unix_seconds: u64,
) -> Result<CredentialTransferPackage, CredentialTransferError> {
    if issued_at_unix_seconds == 0 {
        return Err(CredentialTransferError::InvalidTimestamp);
    }

    let mut session_id = [0_u8; SESSION_ID_BYTES];
    let mut key = Zeroizing::new([0_u8; TRANSFER_KEY_BYTES]);
    let mut nonce = [0_u8; NONCE_BYTES];
    fill(&mut session_id).map_err(|_| CredentialTransferError::RandomnessUnavailable)?;
    fill(key.as_mut()).map_err(|_| CredentialTransferError::RandomnessUnavailable)?;
    fill(&mut nonce).map_err(|_| CredentialTransferError::RandomnessUnavailable)?;

    let session_id = URL_SAFE_NO_PAD.encode(session_id);
    let nonce_document = URL_SAFE_NO_PAD.encode(nonce);
    let nonce = XNonce::from(nonce);
    let associated_data = associated_data(issued_at_unix_seconds, &session_id);
    let plaintext = Zeroizing::new(
        credential
            .encode_for_secure_storage()
            .map_err(CredentialTransferError::Credential)?,
    );
    let cipher = XChaCha20Poly1305::new_from_slice(key.as_ref())
        .map_err(|_| CredentialTransferError::EncryptionFailed)?;
    let ciphertext = cipher
        .encrypt(
            &nonce,
            Payload {
                msg: plaintext.as_slice(),
                aad: associated_data.as_bytes(),
            },
        )
        .map_err(|_| CredentialTransferError::EncryptionFailed)?;

    let bundle = TransferBundleV1 {
        version: TRANSFER_VERSION,
        provider: TRANSFER_PROVIDER.to_owned(),
        issued_at_unix_seconds,
        session_id: session_id.clone(),
        nonce: nonce_document,
        ciphertext: URL_SAFE_NO_PAD.encode(ciphertext),
    };
    let encrypted_bundle =
        serde_json::to_vec(&bundle).map_err(|_| CredentialTransferError::SerializationFailed)?;
    if encrypted_bundle.len() > MAX_BUNDLE_BYTES {
        return Err(CredentialTransferError::BundleTooLarge);
    }

    let secret = TransferSecretV1 {
        version: TRANSFER_VERSION,
        session_id,
        key: URL_SAFE_NO_PAD.encode(key.as_ref()),
    };
    let transfer_secret = Zeroizing::new(
        serde_json::to_vec(&secret).map_err(|_| CredentialTransferError::SerializationFailed)?,
    );

    Ok(CredentialTransferPackage {
        encrypted_bundle,
        transfer_secret,
    })
}

/// Decrypts a development transfer bundle and revalidates the existing
/// credential invariants. The returned credential is only a candidate; callers
/// must still perform QQ Music server verification before authentication.
///
/// # Errors
///
/// Rejects malformed, oversized, expired, future-dated, mismatched, or
/// tampered documents without revealing which secret field was invalid.
pub fn import_encrypted_credential_bundle(
    encrypted_bundle: &[u8],
    transfer_secret: &[u8],
    now_unix_seconds: u64,
) -> Result<CredentialTransferImport, CredentialTransferError> {
    if encrypted_bundle.len() > MAX_BUNDLE_BYTES {
        return Err(CredentialTransferError::BundleTooLarge);
    }
    if transfer_secret.len() > MAX_SECRET_DOCUMENT_BYTES {
        return Err(CredentialTransferError::InvalidSecret);
    }

    let header: TransferBundleHeader = serde_json::from_slice(encrypted_bundle)
        .map_err(|_| CredentialTransferError::InvalidBundle)?;
    validate_header(header.version, &header.provider)?;
    validate_time(header.issued_at_unix_seconds, now_unix_seconds)?;

    let bundle: TransferBundleV1 = serde_json::from_slice(encrypted_bundle)
        .map_err(|_| CredentialTransferError::InvalidBundle)?;
    let secret: TransferSecretV1 = serde_json::from_slice(transfer_secret)
        .map_err(|_| CredentialTransferError::InvalidSecret)?;
    if secret.version != TRANSFER_VERSION || secret.session_id != bundle.session_id {
        return Err(CredentialTransferError::PairingSessionMismatch);
    }

    let key = decode_exact::<TRANSFER_KEY_BYTES>(&secret.key)
        .ok_or(CredentialTransferError::InvalidSecret)?;
    let key = Zeroizing::new(key);
    let nonce =
        decode_exact::<NONCE_BYTES>(&bundle.nonce).ok_or(CredentialTransferError::InvalidBundle)?;
    let nonce = XNonce::from(nonce);
    let ciphertext = URL_SAFE_NO_PAD
        .decode(bundle.ciphertext)
        .map_err(|_| CredentialTransferError::InvalidBundle)?;
    let associated_data = associated_data(bundle.issued_at_unix_seconds, &bundle.session_id);
    let cipher = XChaCha20Poly1305::new_from_slice(key.as_ref())
        .map_err(|_| CredentialTransferError::InvalidSecret)?;
    let plaintext = Zeroizing::new(
        cipher
            .decrypt(
                &nonce,
                Payload {
                    msg: ciphertext.as_slice(),
                    aad: associated_data.as_bytes(),
                },
            )
            .map_err(|_| CredentialTransferError::AuthenticationFailed)?,
    );
    let credential = Credential::decode_from_secure_storage(plaintext.as_slice())
        .map_err(CredentialTransferError::Credential)?;
    Ok(CredentialTransferImport {
        credential,
        session_id: bundle.session_id,
    })
}

fn validate_header(version: u32, provider: &str) -> Result<(), CredentialTransferError> {
    if version != TRANSFER_VERSION {
        return Err(CredentialTransferError::UnsupportedVersion);
    }
    if provider != TRANSFER_PROVIDER {
        return Err(CredentialTransferError::UnsupportedProvider);
    }
    Ok(())
}

fn validate_time(issued_at: u64, now: u64) -> Result<(), CredentialTransferError> {
    if issued_at == 0 || now == 0 {
        return Err(CredentialTransferError::InvalidTimestamp);
    }
    if issued_at > now.saturating_add(MAX_FUTURE_SKEW_SECONDS) {
        return Err(CredentialTransferError::NotYetValid);
    }
    if now.saturating_sub(issued_at) > MAX_AGE_SECONDS {
        return Err(CredentialTransferError::Expired);
    }
    Ok(())
}

fn associated_data(issued_at: u64, session_id: &str) -> String {
    format!("{TRANSFER_VERSION}\n{TRANSFER_PROVIDER}\n{issued_at}\n{session_id}")
}

fn decode_exact<const N: usize>(value: &str) -> Option<[u8; N]> {
    let decoded = URL_SAFE_NO_PAD.decode(value).ok()?;
    decoded.try_into().ok()
}

#[derive(Deserialize)]
struct TransferBundleHeader {
    version: u32,
    provider: String,
    issued_at_unix_seconds: u64,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct TransferBundleV1 {
    version: u32,
    provider: String,
    issued_at_unix_seconds: u64,
    session_id: String,
    nonce: String,
    ciphertext: String,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct TransferSecretV1 {
    version: u32,
    session_id: String,
    key: String,
}

impl Drop for TransferSecretV1 {
    fn drop(&mut self) {
        self.key.zeroize();
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CredentialTransferError {
    RandomnessUnavailable,
    SerializationFailed,
    EncryptionFailed,
    InvalidBundle,
    BundleTooLarge,
    UnsupportedVersion,
    UnsupportedProvider,
    InvalidSecret,
    PairingSessionMismatch,
    InvalidTimestamp,
    NotYetValid,
    Expired,
    AuthenticationFailed,
    Credential(CredentialPersistenceError),
}

impl fmt::Display for CredentialTransferError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::RandomnessUnavailable => formatter.write_str("secure randomness is unavailable"),
            Self::SerializationFailed => {
                formatter.write_str("credential transfer serialization failed")
            }
            Self::EncryptionFailed => formatter.write_str("credential transfer encryption failed"),
            Self::InvalidBundle => formatter.write_str("credential transfer bundle is malformed"),
            Self::BundleTooLarge => formatter.write_str("credential transfer bundle is too large"),
            Self::UnsupportedVersion => {
                formatter.write_str("credential transfer version is unsupported")
            }
            Self::UnsupportedProvider => {
                formatter.write_str("credential transfer provider is unsupported")
            }
            Self::InvalidSecret => formatter.write_str("credential transfer secret is malformed"),
            Self::PairingSessionMismatch => {
                formatter.write_str("credential transfer pairing session does not match")
            }
            Self::InvalidTimestamp => {
                formatter.write_str("credential transfer timestamp is invalid")
            }
            Self::NotYetValid => formatter.write_str("credential transfer is not yet valid"),
            Self::Expired => formatter.write_str("credential transfer has expired"),
            Self::AuthenticationFailed => {
                formatter.write_str("credential transfer authentication failed")
            }
            Self::Credential(error) => error.fmt(formatter),
        }
    }
}

impl std::error::Error for CredentialTransferError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Credential(error) => Some(error),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use serde_json::Value;

    use super::{
        CredentialTransferError, export_encrypted_credential_bundle,
        import_encrypted_credential_bundle,
    };
    use crate::{Credential, LoginType};

    fn credential() -> Credential {
        Credential::new("123456789", "Q_H_L_fixture-secret", LoginType::QQ)
            .expect("fixture credential")
    }

    #[test]
    fn encrypted_bundle_round_trips_without_exposing_plaintext() {
        let package = export_encrypted_credential_bundle(&credential(), 10_000).expect("export");
        let debug = format!("{package:?}");
        assert!(!debug.contains("fixture-secret"));
        assert!(
            !package
                .encrypted_bundle()
                .windows(b"fixture-secret".len())
                .any(|window| window == b"fixture-secret")
        );

        let restored = import_encrypted_credential_bundle(
            package.encrypted_bundle(),
            package.transfer_secret(),
            10_030,
        )
        .expect("import");
        assert_eq!(restored.into_credential(), credential());
    }

    #[test]
    fn rejects_version_and_provider_mismatch() {
        let package = export_encrypted_credential_bundle(&credential(), 10_000).expect("export");
        let mut version: Value =
            serde_json::from_slice(package.encrypted_bundle()).expect("bundle json");
        version["version"] = 2.into();
        assert_eq!(
            import_encrypted_credential_bundle(
                &serde_json::to_vec(&version).expect("json"),
                package.transfer_secret(),
                10_010,
            ),
            Err(CredentialTransferError::UnsupportedVersion),
        );

        let mut provider: Value =
            serde_json::from_slice(package.encrypted_bundle()).expect("bundle json");
        provider["provider"] = "other".into();
        assert_eq!(
            import_encrypted_credential_bundle(
                &serde_json::to_vec(&provider).expect("json"),
                package.transfer_secret(),
                10_010,
            ),
            Err(CredentialTransferError::UnsupportedProvider),
        );
    }

    #[test]
    fn rejects_tampering_wrong_secret_and_wrong_pairing_session() {
        let package = export_encrypted_credential_bundle(&credential(), 10_000).expect("export");
        let mut tampered: Value =
            serde_json::from_slice(package.encrypted_bundle()).expect("bundle json");
        tampered["ciphertext"] = "AA".into();
        assert_eq!(
            import_encrypted_credential_bundle(
                &serde_json::to_vec(&tampered).expect("json"),
                package.transfer_secret(),
                10_010,
            ),
            Err(CredentialTransferError::AuthenticationFailed),
        );

        let mut metadata: Value =
            serde_json::from_slice(package.encrypted_bundle()).expect("bundle json");
        metadata["issued_at_unix_seconds"] = 10_001.into();
        assert_eq!(
            import_encrypted_credential_bundle(
                &serde_json::to_vec(&metadata).expect("json"),
                package.transfer_secret(),
                10_010,
            ),
            Err(CredentialTransferError::AuthenticationFailed),
        );

        let other = export_encrypted_credential_bundle(&credential(), 10_000).expect("other");
        assert_eq!(
            import_encrypted_credential_bundle(
                package.encrypted_bundle(),
                other.transfer_secret(),
                10_010,
            ),
            Err(CredentialTransferError::PairingSessionMismatch),
        );

        let mut wrong_key: Value =
            serde_json::from_slice(package.transfer_secret()).expect("secret json");
        wrong_key["key"] = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA".into();
        assert_eq!(
            import_encrypted_credential_bundle(
                package.encrypted_bundle(),
                &serde_json::to_vec(&wrong_key).expect("json"),
                10_010,
            ),
            Err(CredentialTransferError::AuthenticationFailed),
        );
    }

    #[test]
    fn rejects_expired_future_and_oversized_documents() {
        let package = export_encrypted_credential_bundle(&credential(), 10_000).expect("export");
        assert_eq!(
            import_encrypted_credential_bundle(
                package.encrypted_bundle(),
                package.transfer_secret(),
                10_601,
            ),
            Err(CredentialTransferError::Expired),
        );
        assert_eq!(
            import_encrypted_credential_bundle(
                package.encrypted_bundle(),
                package.transfer_secret(),
                9_939,
            ),
            Err(CredentialTransferError::NotYetValid),
        );
        assert_eq!(
            import_encrypted_credential_bundle(
                &vec![b'x'; 32 * 1024 + 1],
                package.transfer_secret(),
                10_010,
            ),
            Err(CredentialTransferError::BundleTooLarge),
        );
    }
}
