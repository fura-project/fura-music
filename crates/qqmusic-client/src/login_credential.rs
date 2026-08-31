use serde::Deserialize;

use crate::{
    Credential, CredentialExpiry, CredentialSessionSecrets, InvalidCredential,
    InvalidCredentialExpiry, LoginType,
};

#[derive(Debug)]
pub enum LoginCredentialError {
    InvalidJson,
    MissingGlobalCode,
    MissingLoginResult,
    Upstream {
        global_code: i64,
        login_code: Option<i64>,
    },
    MissingCredentialData,
    InvalidCredential(InvalidCredential),
    InvalidExpiry(InvalidCredentialExpiry),
    UnexpectedLoginType(u32),
}

impl std::fmt::Display for LoginCredentialError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidJson => formatter.write_str("login response is not valid JSON"),
            Self::MissingGlobalCode => formatter.write_str("login response has no global code"),
            Self::MissingLoginResult => formatter.write_str("login response has no named result"),
            Self::Upstream {
                global_code,
                login_code,
            } => write!(
                formatter,
                "login failed with global code {global_code} and result code {login_code:?}"
            ),
            Self::MissingCredentialData => formatter.write_str("login response has no credential"),
            Self::InvalidCredential(error) => error.fmt(formatter),
            Self::InvalidExpiry(error) => error.fmt(formatter),
            Self::UnexpectedLoginType(value) => {
                write!(formatter, "login response returned unexpected type {value}")
            }
        }
    }
}

impl std::error::Error for LoginCredentialError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::InvalidCredential(error) => Some(error),
            Self::InvalidExpiry(error) => Some(error),
            _ => None,
        }
    }
}

#[derive(Deserialize)]
struct LoginEnvelope {
    code: Option<i64>,
    #[serde(flatten)]
    calls: std::collections::HashMap<String, LoginResponse>,
}

#[derive(Deserialize)]
struct LoginResponse {
    code: Option<i64>,
    data: Option<RawCredential>,
}

#[derive(Deserialize, Default)]
struct RawCredential {
    #[serde(default)]
    musicid: Option<ProtocolIdentifier>,
    #[serde(default)]
    str_musicid: String,
    #[serde(default)]
    musickey: String,
    #[serde(default, rename = "loginType")]
    login_type: Option<u32>,
    #[serde(default, rename = "musickeyCreateTime")]
    created_at: Option<u64>,
    #[serde(default, rename = "keyExpiresIn")]
    lifetime: Option<u64>,
    #[serde(default)]
    openid: Option<String>,
    #[serde(default)]
    access_token: Option<String>,
    #[serde(default)]
    refresh_token: Option<String>,
    #[serde(default)]
    refresh_key: Option<String>,
    #[serde(default)]
    unionid: Option<String>,
    #[serde(default, rename = "encryptUin")]
    encrypted_uin: Option<String>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum ProtocolIdentifier {
    String(String),
    Unsigned(u64),
    Signed(i64),
}

impl ProtocolIdentifier {
    fn into_nonzero_string(self) -> Option<String> {
        match self {
            Self::String(value) => usable_identifier(&value),
            Self::Unsigned(0) | Self::Signed(i64::MIN..=0) => None,
            Self::Unsigned(value) => Some(value.to_string()),
            Self::Signed(value) => Some(value.to_string()),
        }
    }
}

pub(crate) fn decode_login_credential(
    bytes: &[u8],
    result_key: &str,
    login_type: LoginType,
) -> Result<Credential, LoginCredentialError> {
    let mut envelope: LoginEnvelope =
        serde_json::from_slice(bytes).map_err(|_| LoginCredentialError::InvalidJson)?;
    let global_code = envelope
        .code
        .ok_or(LoginCredentialError::MissingGlobalCode)?;
    let login = envelope
        .calls
        .remove(result_key)
        .ok_or(LoginCredentialError::MissingLoginResult)?;
    if global_code != 0 || login.code != Some(0) {
        return Err(LoginCredentialError::Upstream {
            global_code,
            login_code: login.code,
        });
    }

    let raw = login
        .data
        .ok_or(LoginCredentialError::MissingCredentialData)?;
    if raw
        .login_type
        .is_some_and(|value| value != 0 && value != login_type.value())
    {
        return Err(LoginCredentialError::UnexpectedLoginType(
            raw.login_type.expect("checked as Some"),
        ));
    }
    let music_id = usable_identifier(&raw.str_musicid)
        .or_else(|| {
            raw.musicid
                .and_then(ProtocolIdentifier::into_nonzero_string)
        })
        .ok_or(LoginCredentialError::InvalidCredential(
            InvalidCredential::MissingMusicId,
        ))?;
    let mut credential = Credential::new(music_id, raw.musickey, login_type)
        .map_err(LoginCredentialError::InvalidCredential)?
        .with_session_secrets(CredentialSessionSecrets::new(
            raw.openid,
            raw.access_token,
            raw.refresh_token,
            raw.refresh_key,
            raw.unionid,
            raw.encrypted_uin,
        ));

    match (raw.created_at.unwrap_or(0), raw.lifetime.unwrap_or(0)) {
        (0, 0) => {}
        (created_at, lifetime) => {
            let expiry = CredentialExpiry::new(created_at, lifetime)
                .map_err(LoginCredentialError::InvalidExpiry)?;
            credential = credential.with_expiry(expiry);
        }
    }
    Ok(credential)
}

fn usable_identifier(value: &str) -> Option<String> {
    let value = value.trim().to_owned();
    (!value.is_empty() && value != "0").then_some(value)
}
