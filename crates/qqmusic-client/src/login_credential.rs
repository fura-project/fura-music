use serde::Deserialize;

use crate::{
    Credential, CredentialExpiry, CredentialRefreshExpiry, CredentialSessionSecrets,
    InvalidCredential, InvalidCredentialExpiry, LoginType,
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
    expired_at: Option<u64>,
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
    let mut envelope: serde_json::Value =
        serde_json::from_slice(bytes).map_err(|_| LoginCredentialError::InvalidJson)?;
    let global_code = envelope
        .get("code")
        .and_then(serde_json::Value::as_i64)
        .ok_or(LoginCredentialError::MissingGlobalCode)?;
    let login_value = envelope
        .get_mut(result_key)
        .ok_or(LoginCredentialError::MissingLoginResult)?;
    normalize_wechat_session_aliases(login_value, login_type);
    let login: LoginResponse = serde_json::from_value(login_value.clone())
        .map_err(|_| LoginCredentialError::InvalidJson)?;
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
    if let Some(value) = raw.expired_at.filter(|value| *value != 0) {
        credential = credential.with_refresh_expiry(
            CredentialRefreshExpiry::new(value).map_err(LoginCredentialError::InvalidExpiry)?,
        );
    }
    Ok(credential)
}

fn normalize_wechat_session_aliases(login: &mut serde_json::Value, login_type: LoginType) {
    if login_type != LoginType::WECHAT {
        return;
    }
    let Some(data) = login
        .get_mut("data")
        .and_then(serde_json::Value::as_object_mut)
    else {
        return;
    };
    for (canonical, aliases) in [
        ("openid", &["psrf_wxopenid", "wxopenid"][..]),
        (
            "refresh_token",
            &["psrf_wxrefresh_token", "wxrefresh_token"][..],
        ),
        ("unionid", &["psrf_wxunionid", "wxunionid"][..]),
    ] {
        // Presence is authoritative even for null/empty values. An explicit
        // deletion must never be replaced by an alias from the same response.
        if data.contains_key(canonical) {
            continue;
        }
        if let Some(value) = aliases.iter().find_map(|alias| data.get(*alias).cloned()) {
            data.insert(canonical.to_owned(), value);
        }
    }
}

fn usable_identifier(value: &str) -> Option<String> {
    let value = value.trim().to_owned();
    (!value.is_empty() && value != "0").then_some(value)
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::decode_login_credential;
    use crate::LoginType;

    #[test]
    fn keeps_music_key_lifetime_and_oauth_refresh_expiry_distinct() {
        let response = json!({
            "code": 0,
            "QQConnectLogin.LoginServer.QQLogin": {
                "code": 0,
                "data": {
                    "str_musicid": "123456",
                    "musickey": "synthetic-key",
                    "loginType": 2,
                    "musickeyCreateTime": 1_900_000_000_u64,
                    "keyExpiresIn": 100_000_000_u64,
                    "expired_at": 1_950_000_000_u64
                }
            }
        });

        let credential = decode_login_credential(
            &serde_json::to_vec(&response).expect("fixture JSON"),
            "QQConnectLogin.LoginServer.QQLogin",
            LoginType::QQ,
        )
        .expect("independent expiry fields are valid");

        assert_eq!(credential.expires_at_unix_seconds(), Some(2_000_000_000));
        assert_eq!(credential.refresh_expiry_value(), Some(1_950_000_000));
    }

    #[test]
    fn rejects_partial_music_key_lifetime_even_with_oauth_refresh_expiry() {
        let response = json!({
            "code": 0,
            "QQConnectLogin.LoginServer.QQLogin": {
                "code": 0,
                "data": {
                    "str_musicid": "123456",
                    "musickey": "synthetic-key",
                    "loginType": 2,
                    "musickeyCreateTime": 1_900_000_000_u64,
                    "expired_at": 1_950_000_000_u64
                }
            }
        });

        assert!(
            decode_login_credential(
                &serde_json::to_vec(&response).expect("fixture JSON"),
                "QQConnectLogin.LoginServer.QQLogin",
                LoginType::QQ,
            )
            .is_err()
        );
    }

    #[test]
    fn normalizes_evidenced_wechat_session_aliases() {
        for prefix in ["psrf_wx", "wx"] {
            let mut data = json!({
                "str_musicid": "123456",
                "musickey": "synthetic-key",
                "loginType": 1
            });
            let object = data.as_object_mut().expect("fixture object");
            object.insert(format!("{prefix}openid"), json!("synthetic-open"));
            object.insert(format!("{prefix}refresh_token"), json!("synthetic-refresh"));
            object.insert(format!("{prefix}unionid"), json!("synthetic-union"));
            let response = json!({
                "code": 0,
                "music.login.LoginServer.Login": {
                    "code": 0,
                    "data": data
                }
            });

            let credential = decode_login_credential(
                &serde_json::to_vec(&response).expect("fixture JSON"),
                "music.login.LoginServer.Login",
                LoginType::WECHAT,
            )
            .expect("evidenced WeChat aliases");
            assert_eq!(
                credential.session_secrets().open_id(),
                Some("synthetic-open")
            );
            assert_eq!(
                credential.session_secrets().refresh_token(),
                Some("synthetic-refresh")
            );
            assert_eq!(
                credential.session_secrets().union_id(),
                Some("synthetic-union")
            );
            assert!(!format!("{credential:?}").contains("synthetic-refresh"));
        }
    }
}
