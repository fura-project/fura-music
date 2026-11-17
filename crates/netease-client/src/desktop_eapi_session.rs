//! Bounded Desktop-EAPI QR/session candidate.
//!
//! This is deliberately separate from the production Official-Web credential
//! family. It has no fallback, reads no stored credential, and never fabricates
//! a refresh cookie. The caller must verify the source and refreshed account
//! before promoting any candidate.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
#[cfg(test)]
use serde_json::json;
use serde_json::{Map, Value};

use crate::{
    Credential, CredentialCookieRotation, CredentialRefreshError, CredentialRefreshObservation,
    Error, MAX_RESPONSE_BYTES, NeteaseClient, NeteaseSessionFamily, Request, Transport,
};

const PROVIDER: &str = "netease-cloud-music";
const IDENTITY_VERSION: u8 = 1;
const MAX_IDENTITY_BYTES: usize = 1024;
const MAX_COOKIE_VALUE_BYTES: usize = 4096;
const MAX_SET_COOKIES: usize = 32;
const MAX_SET_COOKIE_BYTES: usize = 8192;

const KEY_PHYSICAL_URL: &str = "https://interface.music.163.com/eapi/login/qrcode/unikey";
const KEY_SIGNING_PATH: &str = "/api/login/qrcode/unikey";
const POLL_PHYSICAL_URL: &str = "https://interfacepc.music.163.com/eapi/login/qrcode/client/login";
const POLL_SIGNING_PATH: &str = "/api/login/qrcode/client/login";
const REFRESH_PHYSICAL_URL: &str = "https://interface.music.163.com/eapi/login/token/refresh";
const REFRESH_SIGNING_PATH: &str = "/api/login/token/refresh";

const DESKTOP_USER_AGENT: &str = concat!(
    "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 ",
    "(KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 ",
    "NeteaseMusicDesktop/3.1.29.205117"
);
const DESKTOP_OS: &str = "pc";
const DESKTOP_OS_VERSION: &str = "Microsoft-Windows-10-Professional-build-19045-64bit";
const DESKTOP_APP_VERSION: &str = "3.1.29.205117";
const DESKTOP_CHANNEL: &str = "netease";

#[derive(Clone, Eq, PartialEq)]
pub struct DesktopEapiInstallationIdentity {
    device_id: String,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct StoredInstallationIdentityV1 {
    version: u8,
    provider: String,
    device_id: String,
}

impl std::fmt::Debug for DesktopEapiInstallationIdentity {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("DesktopEapiInstallationIdentity([REDACTED])")
    }
}

impl DesktopEapiInstallationIdentity {
    /// Generates one Fura-owned identity. Callers must reuse it for the entire
    /// QR/session lifecycle rather than rotating after a rejection.
    ///
    /// # Errors
    /// Returns a coarse failure if system entropy is unavailable.
    pub fn generate() -> Result<Self, Error> {
        let mut entropy = [0_u8; 26];
        getrandom::fill(&mut entropy).map_err(|_| Error::ProtocolUnavailable)?;
        let device_id = entropy
            .iter()
            .flat_map(|byte| {
                [
                    char::from(b"0123456789ABCDEF"[usize::from(byte >> 4)]),
                    char::from(b"0123456789ABCDEF"[usize::from(byte & 0x0f)]),
                ]
            })
            .collect();
        let value = Self { device_id };
        value.validate()?;
        Ok(value)
    }

    fn validate(&self) -> Result<(), Error> {
        if self.device_id.len() != 52
            || !self
                .device_id
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'A'..=b'F').contains(&byte))
        {
            return Err(Error::ResponseShapeMismatch);
        }
        Ok(())
    }

    /// Opaque installation-scoped bytes. Account logout must not delete this
    /// document if the Desktop-EAPI family is later promoted.
    ///
    /// # Errors
    /// Rejects an invalid internal identity.
    pub fn export(&self) -> Result<Vec<u8>, Error> {
        self.validate()?;
        let bytes = serde_json::to_vec(&StoredInstallationIdentityV1 {
            version: IDENTITY_VERSION,
            provider: PROVIDER.into(),
            device_id: self.device_id.clone(),
        })
        .map_err(|_| Error::ResponseShapeMismatch)?;
        if bytes.len() > MAX_IDENTITY_BYTES {
            return Err(Error::ResponseBound);
        }
        Ok(bytes)
    }

    /// Imports only the independently stored installation identity.
    ///
    /// # Errors
    /// Rejects malformed, foreign, future-version or oversized documents.
    pub fn import(bytes: &[u8]) -> Result<Self, Error> {
        if bytes.len() > MAX_IDENTITY_BYTES {
            return Err(Error::ResponseBound);
        }
        let stored: StoredInstallationIdentityV1 =
            serde_json::from_slice(bytes).map_err(|_| Error::ResponseShapeMismatch)?;
        if stored.version != IDENTITY_VERSION || stored.provider != PROVIDER {
            return Err(Error::ResponseShapeMismatch);
        }
        let value = Self {
            device_id: stored.device_id,
        };
        value.validate()?;
        Ok(value)
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "each bool is an independently observed secret-free Set-Cookie attribute"
)]
pub struct DesktopEapiCookieObservation {
    pub present: bool,
    pub music_domain: bool,
    pub parent_163_domain: bool,
    pub root_path: bool,
    pub non_root_path: bool,
    pub expiry_present: bool,
    pub http_only: bool,
    pub secure: bool,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct DesktopEapiSessionObservation {
    pub music_u: DesktopEapiCookieObservation,
    pub music_r_u: DesktopEapiCookieObservation,
    pub csrf: DesktopEapiCookieObservation,
    pub nmtid: DesktopEapiCookieObservation,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DesktopEapiCookieRotation {
    Absent,
    Inserted,
    Updated,
    Deleted,
    Unchanged,
}

impl DesktopEapiCookieRotation {
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::Absent => "absent",
            Self::Inserted => "inserted",
            Self::Updated => "updated",
            Self::Deleted => "deleted",
            Self::Unchanged => "unchanged",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DesktopEapiRefreshObservation {
    pub music_u: DesktopEapiCookieRotation,
    pub music_r_u: DesktopEapiCookieRotation,
    pub csrf: DesktopEapiCookieRotation,
    pub nmtid: DesktopEapiCookieRotation,
    pub candidate_next_refreshable: bool,
}

#[derive(Clone, Default, Eq, PartialEq)]
struct SessionCookies {
    values: BTreeMap<&'static str, String>,
    observation: DesktopEapiSessionObservation,
}

impl std::fmt::Debug for SessionCookies {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("DesktopEapiSessionCookies([REDACTED])")
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct DesktopEapiQrKey {
    key: String,
    identity: DesktopEapiInstallationIdentity,
    cookies: SessionCookies,
}

impl std::fmt::Debug for DesktopEapiQrKey {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("DesktopEapiQrKey([REDACTED])")
    }
}

impl DesktopEapiQrKey {
    fn login_url(&self) -> Result<url::Url, Error> {
        let mut url = url::Url::parse("https://music.163.com/login")
            .map_err(|_| Error::ProtocolUnavailable)?;
        url.query_pairs_mut().append_pair("codekey", &self.key);
        Ok(url)
    }

    /// Official short-lived confirmation URL. Callers must not log it.
    ///
    /// # Errors
    /// Rejects an invalid fixed URL construction.
    pub fn external_confirmation_url(&self) -> Result<String, Error> {
        self.login_url().map(Into::into)
    }

    /// Encodes the short-lived official login URL without exposing the key.
    ///
    /// # Errors
    /// Returns a coarse local encoding failure.
    pub fn image_png(&self) -> Result<Vec<u8>, Error> {
        let url = self.login_url()?;
        let code = qrcode::QrCode::new(url.as_str()).map_err(|_| Error::ProtocolUnavailable)?;
        let width = code.width();
        let pixels = (width + 8) * 4;
        let mut image = vec![255; pixels * pixels];
        for y in 0..width {
            for x in 0..width {
                if code[(x, y)] == qrcode::Color::Dark {
                    for dy in 0..4 {
                        for dx in 0..4 {
                            image[((y + 4) * 4 + dy) * pixels + (x + 4) * 4 + dx] = 0;
                        }
                    }
                }
            }
        }
        let mut output = Vec::new();
        let size = u32::try_from(pixels).map_err(|_| Error::ResponseBound)?;
        {
            let mut encoder = png::Encoder::new(&mut output, size, size);
            encoder.set_color(png::ColorType::Grayscale);
            encoder.set_depth(png::BitDepth::Eight);
            let mut writer = encoder
                .write_header()
                .map_err(|_| Error::ProtocolUnavailable)?;
            writer
                .write_image_data(&image)
                .map_err(|_| Error::ProtocolUnavailable)?;
        }
        Ok(output)
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct DesktopEapiSessionCandidate {
    identity: DesktopEapiInstallationIdentity,
    cookies: SessionCookies,
}

impl std::fmt::Debug for DesktopEapiSessionCandidate {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("DesktopEapiSessionCandidate([REDACTED])")
    }
}

impl DesktopEapiSessionCandidate {
    fn validate(&self) -> Result<(), Error> {
        self.identity.validate()?;
        let music_u = self
            .cookies
            .values
            .get("MUSIC_U")
            .ok_or(Error::AuthenticationRequired)?;
        if music_u.is_empty()
            || self.cookies.values.len() > 4
            || self.cookies.values.values().any(|value| {
                value.is_empty()
                    || value.len() > MAX_COOKIE_VALUE_BYTES
                    || !value.bytes().all(|byte| {
                        byte.is_ascii_graphic() && !matches!(byte, b';' | b',' | b'"' | b'\\')
                    })
            })
        {
            return Err(Error::ResponseShapeMismatch);
        }
        Ok(())
    }

    #[must_use]
    pub fn observation(&self) -> DesktopEapiSessionObservation {
        self.cookies.observation
    }

    #[must_use]
    pub fn has_music_u(&self) -> bool {
        self.cookies.values.contains_key("MUSIC_U")
    }

    #[must_use]
    pub fn has_music_r_u(&self) -> bool {
        self.cookies.values.contains_key("MUSIC_R_U")
    }

    #[must_use]
    pub fn has_csrf(&self) -> bool {
        self.cookies.values.contains_key("__csrf")
    }

    #[must_use]
    pub fn has_nmtid(&self) -> bool {
        self.cookies.values.contains_key("NMTID")
    }

    #[must_use]
    pub fn is_next_refreshable(&self) -> bool {
        self.validate().is_ok()
    }

    fn from_credential(
        credential: &Credential,
        identity: &DesktopEapiInstallationIdentity,
    ) -> Result<Self, Error> {
        if credential.session_family != NeteaseSessionFamily::DesktopEapi {
            return Err(Error::AuthenticationRequired);
        }
        let mut values = BTreeMap::new();
        values.insert("MUSIC_U", credential.music_u.clone());
        if let Some(value) = &credential.music_r_u {
            values.insert("MUSIC_R_U", value.clone());
        }
        if !credential.csrf.is_empty() {
            values.insert("__csrf", credential.csrf.clone());
        }
        if let Some(value) = &credential.nmtid {
            values.insert("NMTID", value.clone());
        }
        let value = Self {
            identity: identity.clone(),
            cookies: SessionCookies {
                values,
                observation: DesktopEapiSessionObservation::default(),
            },
        };
        value.validate()?;
        Ok(value)
    }

    /// Promotes only this explicit Desktop-EAPI candidate to Credential V3.
    ///
    /// # Errors
    /// Rejects missing or malformed session material.
    pub fn into_credential(self) -> Result<Credential, Error> {
        self.validate()?;
        Credential::from_desktop_eapi_material(
            self.cookies
                .values
                .get("MUSIC_U")
                .cloned()
                .ok_or(Error::AuthenticationRequired)?,
            self.cookies.values.get("MUSIC_R_U").cloned(),
            self.cookies
                .values
                .get("__csrf")
                .cloned()
                .unwrap_or_default(),
            self.cookies.values.get("NMTID").cloned(),
        )
    }
}

pub enum DesktopEapiQrPoll {
    Waiting,
    Scanned,
    Expired,
    Confirmed(DesktopEapiSessionCandidate),
}

impl std::fmt::Debug for DesktopEapiQrPoll {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(match self {
            Self::Waiting => "Waiting",
            Self::Scanned => "Scanned",
            Self::Expired => "Expired",
            Self::Confirmed(_) => "Confirmed([REDACTED])",
        })
    }
}

fn allowlisted_cookie_name(name: &str) -> Option<&'static str> {
    match name {
        "MUSIC_U" => Some("MUSIC_U"),
        "MUSIC_R_U" => Some("MUSIC_R_U"),
        "__csrf" | "__csrf_token" => Some("__csrf"),
        "NMTID" => Some("NMTID"),
        _ => None,
    }
}

fn observation_for<'a>(
    observation: &'a mut DesktopEapiSessionObservation,
    name: &str,
) -> &'a mut DesktopEapiCookieObservation {
    match name {
        "MUSIC_U" => &mut observation.music_u,
        "MUSIC_R_U" => &mut observation.music_r_u,
        "__csrf" => &mut observation.csrf,
        "NMTID" => &mut observation.nmtid,
        _ => unreachable!(),
    }
}

impl SessionCookies {
    fn absorb_set_cookies(&mut self, set_cookies: &[String]) -> Result<(), Error> {
        if set_cookies.len() > MAX_SET_COOKIES
            || set_cookies
                .iter()
                .any(|cookie| cookie.len() > MAX_SET_COOKIE_BYTES)
        {
            return Err(Error::ResponseBound);
        }
        let mut response_values = BTreeMap::<&'static str, Option<String>>::new();
        for set_cookie in set_cookies {
            let mut parts = set_cookie.split(';');
            let Some((raw_name, raw_value)) = parts.next().and_then(|part| part.split_once('='))
            else {
                return Err(Error::ResponseShapeMismatch);
            };
            let Some(name) = allowlisted_cookie_name(raw_name.trim()) else {
                continue;
            };
            let value = raw_value.trim();
            if value.len() > MAX_COOKIE_VALUE_BYTES {
                return Err(Error::ResponseBound);
            }
            let mut deleted = value.is_empty();
            let mut cookie_observation = DesktopEapiCookieObservation {
                present: true,
                ..DesktopEapiCookieObservation::default()
            };
            for attribute in parts.map(str::trim) {
                if attribute.eq_ignore_ascii_case("httponly") {
                    cookie_observation.http_only = true;
                    continue;
                }
                if attribute.eq_ignore_ascii_case("secure") {
                    cookie_observation.secure = true;
                    continue;
                }
                let Some((attribute_name, attribute_value)) = attribute.split_once('=') else {
                    continue;
                };
                if attribute_name.eq_ignore_ascii_case("domain") {
                    match attribute_value.trim().to_ascii_lowercase().as_str() {
                        "music.163.com" | ".music.163.com" => {
                            cookie_observation.music_domain = true;
                        }
                        "163.com" | ".163.com" => {
                            cookie_observation.parent_163_domain = true;
                        }
                        _ => return Err(Error::ResponseShapeMismatch),
                    }
                } else if attribute_name.eq_ignore_ascii_case("path") {
                    if attribute_value.trim() == "/" {
                        cookie_observation.root_path = true;
                    } else if attribute_value.trim().starts_with('/') {
                        cookie_observation.non_root_path = true;
                    } else {
                        return Err(Error::ResponseShapeMismatch);
                    }
                } else if attribute_name.eq_ignore_ascii_case("max-age") {
                    cookie_observation.expiry_present = true;
                    let seconds = attribute_value
                        .trim()
                        .parse::<i64>()
                        .map_err(|_| Error::ResponseShapeMismatch)?;
                    deleted |= seconds <= 0;
                } else if attribute_name.eq_ignore_ascii_case("expires") {
                    cookie_observation.expiry_present = true;
                }
            }
            let target = observation_for(&mut self.observation, name);
            target.present = true;
            target.music_domain |= cookie_observation.music_domain;
            target.parent_163_domain |= cookie_observation.parent_163_domain;
            target.root_path |= cookie_observation.root_path;
            target.non_root_path |= cookie_observation.non_root_path;
            target.expiry_present |= cookie_observation.expiry_present;
            target.http_only |= cookie_observation.http_only;
            target.secure |= cookie_observation.secure;

            let response_value = (!deleted).then(|| value.to_owned());
            if let Some(existing) = response_values.get(name) {
                if existing.as_deref() != response_value.as_deref() {
                    return Err(Error::ResponseShapeMismatch);
                }
            } else {
                response_values.insert(name, response_value);
            }
        }
        for (name, value) in response_values {
            if let Some(value) = value {
                self.values.insert(name, value);
            } else {
                self.values.remove(name);
            }
        }
        Ok(())
    }

    fn absorb_body_cookie(&mut self, body_cookie: Option<&str>) -> Result<(), Error> {
        let Some(body_cookie) = body_cookie else {
            return Ok(());
        };
        if body_cookie.len() > 32 * 1024 {
            return Err(Error::ResponseBound);
        }
        let pairs = body_cookie
            .split(';')
            .map(str::trim)
            .filter(|part| !part.is_empty());
        for (index, pair) in pairs.enumerate() {
            if index >= 128 {
                return Err(Error::ResponseBound);
            }
            let Some((raw_name, raw_value)) = pair.split_once('=') else {
                continue;
            };
            let Some(name) = allowlisted_cookie_name(raw_name.trim()) else {
                continue;
            };
            let value = raw_value.trim();
            if value.is_empty() || value.len() > MAX_COOKIE_VALUE_BYTES {
                continue;
            }
            if let Some(existing) = self.values.get(name) {
                if existing != value {
                    return Err(Error::ResponseShapeMismatch);
                }
            } else {
                self.values.insert(name, value.into());
            }
            observation_for(&mut self.observation, name).present = true;
        }
        Ok(())
    }
}

fn request_id() -> Result<String, Error> {
    let millis = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| Error::ProtocolUnavailable)?
        .as_millis();
    let mut entropy = [0_u8; 2];
    getrandom::fill(&mut entropy).map_err(|_| Error::ProtocolUnavailable)?;
    let suffix = u16::from_le_bytes(entropy) % 10_000;
    Ok(format!("{millis}_{suffix:04}"))
}

fn auth_header(
    identity: &DesktopEapiInstallationIdentity,
    cookies: &SessionCookies,
) -> Result<Map<String, Value>, Error> {
    identity.validate()?;
    let build_version = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| Error::ProtocolUnavailable)?
        .as_secs()
        .to_string();
    let mut fields = Map::from_iter([
        ("osver".into(), Value::String(DESKTOP_OS_VERSION.into())),
        ("deviceId".into(), Value::String(identity.device_id.clone())),
        ("os".into(), Value::String(DESKTOP_OS.into())),
        ("appver".into(), Value::String(DESKTOP_APP_VERSION.into())),
        ("versioncode".into(), Value::String("140".into())),
        ("mobilename".into(), Value::String(String::new())),
        ("buildver".into(), Value::String(build_version)),
        ("resolution".into(), Value::String("1920x1080".into())),
        (
            "__csrf".into(),
            Value::String(cookies.values.get("__csrf").cloned().unwrap_or_default()),
        ),
        ("channel".into(), Value::String(DESKTOP_CHANNEL.into())),
        ("requestId".into(), Value::String(request_id()?)),
    ]);
    for name in ["MUSIC_U", "NMTID"] {
        if let Some(value) = cookies.values.get(name) {
            fields.insert(name.into(), Value::String(value.clone()));
        }
    }
    Ok(fields)
}

fn header_cookie(header: &Map<String, Value>) -> Result<String, Error> {
    header
        .iter()
        .map(|(name, value)| {
            value
                .as_str()
                .map(|value| format!("{name}={value}"))
                .ok_or(Error::ResponseShapeMismatch)
        })
        .collect::<Result<Vec<_>, _>>()
        .map(|parts| parts.join("; "))
}

fn decode_eapi_response(body: &[u8]) -> Result<Value, Error> {
    if body.len() > MAX_RESPONSE_BYTES {
        return Err(Error::ResponseBound);
    }
    if let Ok(value) = serde_json::from_slice(body) {
        return Ok(value);
    }
    let decoded = crate::crypto::eapi_response(body)?;
    serde_json::from_slice(&decoded).map_err(|_| Error::ResponseShapeMismatch)
}

fn response_code(value: &Value) -> Result<i64, Error> {
    value
        .get("code")
        .and_then(|code| {
            code.as_i64()
                .or_else(|| code.as_str().and_then(|text| text.parse().ok()))
        })
        .ok_or(Error::ResponseShapeMismatch)
}

fn classify_code(code: i64, authenticated: bool) -> Result<(), Error> {
    match code {
        200 => Ok(()),
        301 if authenticated => Err(Error::CredentialRejected),
        301 => Err(Error::AuthenticationRequired),
        406 | 429 => Err(Error::RateLimited),
        -460 | 8821 => Err(Error::SecurityVerificationRequired),
        8830 => Err(Error::SecondaryVerificationRequired),
        _ => Err(Error::UpstreamUnknown),
    }
}

async fn send_eapi<T: Transport>(
    client: &NeteaseClient<T>,
    physical_url: &'static str,
    signing_path: &'static str,
    mut payload: Map<String, Value>,
    identity: &DesktopEapiInstallationIdentity,
    cookies: &SessionCookies,
) -> Result<(Value, Vec<String>), Error> {
    let header = auth_header(identity, cookies)?;
    let cookie = header_cookie(&header)?;
    payload.insert("e_r".into(), Value::Bool(false));
    payload.insert("header".into(), Value::Object(header));
    let text = serde_json::to_string(&Value::Object(payload)).map_err(|_| Error::InputBound)?;
    let response = client
        .transport
        .send(Request {
            url: physical_url.into(),
            form: crate::crypto::eapi(signing_path, &text)?,
            cookie: Some(cookie),
            headers: vec![
                ("User-Agent".into(), DESKTOP_USER_AGENT.into()),
                (
                    "Content-Type".into(),
                    "application/x-www-form-urlencoded".into(),
                ),
            ],
        })
        .await?;
    match response.status {
        200 => {}
        406 | 429 => return Err(Error::RateLimited),
        _ => return Err(Error::ProtocolUnavailable),
    }
    Ok((decode_eapi_response(&response.body)?, response.set_cookies))
}

fn rotation(
    before: &BTreeMap<&'static str, String>,
    after: &BTreeMap<&'static str, String>,
    name: &'static str,
    mentioned: bool,
) -> DesktopEapiCookieRotation {
    if !mentioned {
        return DesktopEapiCookieRotation::Absent;
    }
    match (before.get(name), after.get(name)) {
        (None, Some(_)) => DesktopEapiCookieRotation::Inserted,
        (Some(old), Some(new)) if old == new => DesktopEapiCookieRotation::Unchanged,
        (Some(_), Some(_)) => DesktopEapiCookieRotation::Updated,
        (Some(_) | None, None) => DesktopEapiCookieRotation::Deleted,
    }
}

impl<T: Transport> NeteaseClient<T> {
    /// Starts one Desktop-EAPI/type-3 QR family with no Web fallback.
    ///
    /// # Errors
    /// Fails closed on transport, risk, protocol, body or key-shape errors.
    pub async fn desktop_eapi_qr_key(
        &self,
        identity: &DesktopEapiInstallationIdentity,
    ) -> Result<DesktopEapiQrKey, Error> {
        let mut cookies = SessionCookies::default();
        let (value, set_cookies) = send_eapi(
            self,
            KEY_PHYSICAL_URL,
            KEY_SIGNING_PATH,
            Map::from_iter([("type".into(), Value::from(3))]),
            identity,
            &cookies,
        )
        .await?;
        classify_code(response_code(&value)?, false)?;
        cookies.absorb_set_cookies(&set_cookies)?;
        let key = value
            .get("unikey")
            .or_else(|| value.pointer("/data/unikey"))
            .and_then(Value::as_str)
            .filter(|key| !key.is_empty() && key.len() <= 4096)
            .ok_or(Error::ResponseShapeMismatch)?;
        Ok(DesktopEapiQrKey {
            key: key.into(),
            identity: identity.clone(),
            cookies,
        })
    }

    /// Polls the exact Desktop-EAPI QR family. The physical poll host and
    /// signing path are fixed; there is no alternate host or Web fallback.
    ///
    /// # Errors
    /// Fails closed on unknown/risk codes and malformed or missing session
    /// material.
    pub async fn desktop_eapi_qr_poll(
        &self,
        key: &mut DesktopEapiQrKey,
    ) -> Result<DesktopEapiQrPoll, Error> {
        let (value, set_cookies) = send_eapi(
            self,
            POLL_PHYSICAL_URL,
            POLL_SIGNING_PATH,
            Map::from_iter([
                ("key".into(), Value::String(key.key.clone())),
                ("type".into(), Value::from(3)),
            ]),
            &key.identity,
            &key.cookies,
        )
        .await?;
        key.cookies.absorb_set_cookies(&set_cookies)?;
        key.cookies
            .absorb_body_cookie(value.get("cookie").and_then(Value::as_str))?;
        match response_code(&value)? {
            800 => Ok(DesktopEapiQrPoll::Expired),
            801 => Ok(DesktopEapiQrPoll::Waiting),
            802 => Ok(DesktopEapiQrPoll::Scanned),
            803 => {
                let candidate = DesktopEapiSessionCandidate {
                    identity: key.identity.clone(),
                    cookies: key.cookies.clone(),
                };
                Ok(DesktopEapiQrPoll::Confirmed(candidate))
            }
            code => {
                classify_code(code, false)?;
                Err(Error::UpstreamUnknown)
            }
        }
    }

    /// Sends exactly one Desktop-EAPI refresh candidate. `MUSIC_R_U` is
    /// deliberately omitted from the request because the selected live-backed
    /// desktop contract identifies the session by `MUSIC_U` plus the stable
    /// installation/header context. Any response-issued R is still retained.
    ///
    /// # Errors
    /// Fails closed on risk/rejection, malformed response or invalid session
    /// rotation. This method never retries.
    pub async fn refresh_desktop_eapi_candidate_observed(
        &self,
        candidate: &DesktopEapiSessionCandidate,
    ) -> Result<(DesktopEapiSessionCandidate, DesktopEapiRefreshObservation), Error> {
        candidate.validate()?;
        let before = candidate.cookies.values.clone();
        let (value, set_cookies) = send_eapi(
            self,
            REFRESH_PHYSICAL_URL,
            REFRESH_SIGNING_PATH,
            Map::new(),
            &candidate.identity,
            &candidate.cookies,
        )
        .await?;
        classify_code(response_code(&value)?, true)?;
        let business_code = value
            .get("bizCode")
            .and_then(|code| {
                code.as_i64()
                    .or_else(|| code.as_str().and_then(|text| text.parse().ok()))
            })
            .ok_or(Error::ResponseShapeMismatch)?;
        classify_code(business_code, true)?;

        let mut refreshed = candidate.clone();
        let before_observation = refreshed.cookies.observation;
        refreshed.cookies.absorb_set_cookies(&set_cookies)?;
        refreshed.validate()?;
        let after = &refreshed.cookies.values;
        let mentioned = |name: &str| {
            let before = match name {
                "MUSIC_U" => before_observation.music_u,
                "MUSIC_R_U" => before_observation.music_r_u,
                "__csrf" => before_observation.csrf,
                "NMTID" => before_observation.nmtid,
                _ => unreachable!(),
            };
            let after = match name {
                "MUSIC_U" => refreshed.cookies.observation.music_u,
                "MUSIC_R_U" => refreshed.cookies.observation.music_r_u,
                "__csrf" => refreshed.cookies.observation.csrf,
                "NMTID" => refreshed.cookies.observation.nmtid,
                _ => unreachable!(),
            };
            after != before
                || set_cookies.iter().any(|cookie| {
                    cookie.split_once('=').is_some_and(|(cookie_name, _)| {
                        allowlisted_cookie_name(cookie_name.trim()) == Some(name)
                    })
                })
        };
        let observation = DesktopEapiRefreshObservation {
            music_u: rotation(&before, after, "MUSIC_U", mentioned("MUSIC_U")),
            music_r_u: rotation(&before, after, "MUSIC_R_U", mentioned("MUSIC_R_U")),
            csrf: rotation(&before, after, "__csrf", mentioned("__csrf")),
            nmtid: rotation(&before, after, "NMTID", mentioned("NMTID")),
            candidate_next_refreshable: refreshed.is_next_refreshable(),
        };
        Ok((refreshed, observation))
    }

    /// Performs an ordinary account read for a disposable Desktop-EAPI
    /// candidate. Raw session material stays inside the Client.
    ///
    /// # Errors
    /// Returns the existing account-read classifications.
    pub async fn desktop_eapi_candidate_account(
        &self,
        candidate: &DesktopEapiSessionCandidate,
    ) -> Result<crate::Account, Error> {
        candidate.validate()?;
        let cookie = format!(
            "MUSIC_U={}; __csrf={}",
            candidate
                .cookies
                .values
                .get("MUSIC_U")
                .ok_or(Error::AuthenticationRequired)?,
            candidate
                .cookies
                .values
                .get("__csrf")
                .map(String::as_str)
                .unwrap_or_default(),
        );
        let credential = crate::Credential::from_browser_cookie_header(cookie.as_bytes())?;
        self.account(&credential).await
    }

    /// Production refresh routing for an explicit credential family.
    /// Official-Web credentials are never converted to Desktop-EAPI.
    ///
    /// # Errors
    /// Returns `NotRefreshable` for every unproved family/context and maps the
    /// single Desktop-EAPI request into the existing continuation taxonomy.
    pub async fn refresh_production_credential_observed(
        &self,
        credential: &Credential,
        identity: Option<&DesktopEapiInstallationIdentity>,
    ) -> Result<(Credential, CredentialRefreshObservation), CredentialRefreshError> {
        if credential.session_family() != NeteaseSessionFamily::DesktopEapi {
            return Err(CredentialRefreshError::NotRefreshable);
        }
        let identity = identity.ok_or(CredentialRefreshError::NotRefreshable)?;
        let candidate = DesktopEapiSessionCandidate::from_credential(credential, identity)
            .map_err(crate::auth::map_credential_refresh_transport_error)?;
        let (candidate, observation) = self
            .refresh_desktop_eapi_candidate_observed(&candidate)
            .await
            .map_err(crate::auth::map_credential_refresh_transport_error)?;
        let credential = candidate
            .into_credential()
            .map_err(crate::auth::map_credential_refresh_transport_error)?;
        let rotation = |value: DesktopEapiCookieRotation| match value {
            DesktopEapiCookieRotation::Absent => CredentialCookieRotation::Absent,
            DesktopEapiCookieRotation::Inserted => CredentialCookieRotation::Inserted,
            DesktopEapiCookieRotation::Updated => CredentialCookieRotation::Updated,
            DesktopEapiCookieRotation::Deleted => CredentialCookieRotation::Deleted,
            DesktopEapiCookieRotation::Unchanged => CredentialCookieRotation::Unchanged,
        };
        Ok((
            credential,
            CredentialRefreshObservation {
                music_u: rotation(observation.music_u),
                music_r_u: rotation(observation.music_r_u),
                csrf: rotation(observation.csrf),
                candidate_next_refreshable: observation.candidate_next_refreshable,
            },
        ))
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;

    use aes::cipher::{BlockDecrypt, BlockEncrypt, KeyInit};

    use super::*;
    use crate::Response;

    struct Fake {
        requests: Mutex<Vec<Request>>,
        responses: Mutex<Vec<Result<Response, Error>>>,
    }

    impl Fake {
        fn new(responses: Vec<Result<Response, Error>>) -> Self {
            Self {
                requests: Mutex::new(Vec::new()),
                responses: Mutex::new(responses.into_iter().rev().collect()),
            }
        }
    }

    impl Transport for Fake {
        fn send(
            &self,
            request: Request,
        ) -> impl std::future::Future<Output = Result<Response, Error>> + Send {
            self.requests.lock().unwrap().push(request);
            std::future::ready(
                self.responses
                    .lock()
                    .unwrap()
                    .pop()
                    .expect("bounded fake response"),
            )
        }
    }

    #[allow(
        clippy::needless_pass_by_value,
        clippy::unnecessary_wraps,
        reason = "the fake queue stores transport Results and JSON fixtures are created inline"
    )]
    fn response(value: Value, cookies: &[&str]) -> Result<Response, Error> {
        Ok(Response {
            status: 200,
            body: serde_json::to_vec(&value).unwrap(),
            set_cookies: cookies.iter().map(|cookie| (*cookie).into()).collect(),
        })
    }

    fn identity() -> DesktopEapiInstallationIdentity {
        DesktopEapiInstallationIdentity {
            device_id: "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123".into(),
        }
    }

    fn decrypt_request(request: &Request) -> Value {
        let encoded = request
            .form()
            .iter()
            .find_map(|(name, value)| (name == "params").then_some(value))
            .unwrap();
        let (pairs, remainder) = encoded.as_bytes().as_chunks::<2>();
        assert!(remainder.is_empty());
        let mut bytes = pairs
            .iter()
            .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap())
            .collect::<Vec<_>>();
        let cipher = aes::Aes128::new(b"e82ckenh8dichen8".into());
        for block in bytes.as_chunks_mut::<16>().0 {
            cipher.decrypt_block(block.into());
        }
        let padding = usize::from(*bytes.last().unwrap());
        bytes.truncate(bytes.len() - padding);
        let text = String::from_utf8(bytes).unwrap();
        let (_, tail) = text.split_once("-36cd479b6b5-").unwrap();
        let (json, _) = tail.rsplit_once("-36cd479b6b5-").unwrap();
        serde_json::from_str(json).unwrap()
    }

    async fn confirmed_candidate(
        refresh_response: Result<Response, Error>,
    ) -> (NeteaseClient<Fake>, DesktopEapiSessionCandidate) {
        let fake = Fake::new(vec![
            response(json!({"code":200,"unikey":"synthetic-key"}), &[]),
            response(
                json!({"code":803}),
                &[
                    "MUSIC_U=synthetic-u; Domain=.music.163.com; Path=/; HttpOnly; Secure",
                    "__csrf=synthetic-csrf; Domain=.music.163.com; Path=/",
                    "NMTID=synthetic-nmtid; Domain=.music.163.com; Path=/",
                ],
            ),
            refresh_response,
        ]);
        let client = NeteaseClient::new(fake);
        let mut key = client.desktop_eapi_qr_key(&identity()).await.unwrap();
        let candidate = match client.desktop_eapi_qr_poll(&mut key).await.unwrap() {
            DesktopEapiQrPoll::Confirmed(candidate) => candidate,
            other => panic!("unexpected {other:?}"),
        };
        (client, candidate)
    }

    #[test]
    fn identity_is_bounded_opaque_and_round_trips() {
        let generated = DesktopEapiInstallationIdentity::generate().unwrap();
        assert_eq!(generated.device_id.len(), 52);
        assert!(
            generated
                .device_id
                .bytes()
                .all(|byte| byte.is_ascii_hexdigit())
        );
        let bytes = generated.export().unwrap();
        assert_eq!(
            DesktopEapiInstallationIdentity::import(&bytes).unwrap(),
            generated
        );
        assert_eq!(
            format!("{generated:?}"),
            "DesktopEapiInstallationIdentity([REDACTED])"
        );
    }

    #[tokio::test]
    async fn key_poll_and_refresh_use_fixed_routes_one_identity_and_no_r_request() {
        let (client, candidate) = confirmed_candidate(response(
            json!({"code":200,"bizCode":200}),
            &[
                "MUSIC_U=synthetic-new-u; Domain=.music.163.com; Path=/",
                "MUSIC_R_U=synthetic-new-r; Domain=.music.163.com; Path=/eapi/login/token/refresh",
                "__csrf=synthetic-new-csrf; Domain=.music.163.com; Path=/",
            ],
        ))
        .await;
        let source = candidate.clone().into_credential().unwrap();
        assert_eq!(source.session_family(), NeteaseSessionFamily::DesktopEapi);
        let (refreshed, observation) = client
            .refresh_production_credential_observed(&source, Some(&identity()))
            .await
            .unwrap();
        assert!(refreshed.has_refresh_material());
        assert_eq!(
            refreshed.session_family(),
            NeteaseSessionFamily::DesktopEapi
        );
        assert!(observation.candidate_next_refreshable);
        let requests = client.transport.requests.lock().unwrap();
        assert_eq!(requests.len(), 3);
        assert_eq!(requests[0].url(), KEY_PHYSICAL_URL);
        assert_eq!(requests[1].url(), POLL_PHYSICAL_URL);
        assert_eq!(requests[2].url(), REFRESH_PHYSICAL_URL);
        let bodies = requests.iter().map(decrypt_request).collect::<Vec<_>>();
        assert_eq!(bodies[0]["type"], 3);
        assert_eq!(bodies[1]["type"], 3);
        let device_ids = bodies
            .iter()
            .map(|body| body["header"]["deviceId"].as_str().unwrap())
            .collect::<Vec<_>>();
        assert!(device_ids.windows(2).all(|pair| pair[0] == pair[1]));
        assert_eq!(bodies[2]["header"]["MUSIC_U"], "synthetic-u");
        assert!(bodies[2]["header"].get("MUSIC_R_U").is_none());
        assert!(!requests[2].cookie().unwrap().contains("MUSIC_R_U"));
    }

    #[tokio::test]
    async fn production_routing_never_converts_official_web_to_desktop_eapi() {
        let client = NeteaseClient::new(Fake::new(Vec::new()));
        let credential = Credential::from_browser_cookie_header(
            b"MUSIC_U=official-web-u; MUSIC_R_U=official-web-r; __csrf=csrf",
        )
        .unwrap();
        assert_eq!(
            credential.session_family(),
            NeteaseSessionFamily::OfficialWeb
        );
        assert_eq!(
            client
                .refresh_production_credential_observed(&credential, Some(&identity()))
                .await,
            Err(CredentialRefreshError::NotRefreshable)
        );
        assert!(client.transport.requests.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn qr_states_and_risk_codes_are_distinct_and_never_fallback() {
        for (code, expected) in [(800, "Expired"), (801, "Waiting"), (802, "Scanned")] {
            let client = NeteaseClient::new(Fake::new(vec![
                response(json!({"code":200,"unikey":"key"}), &[]),
                response(json!({"code":code}), &[]),
            ]));
            let mut key = client.desktop_eapi_qr_key(&identity()).await.unwrap();
            assert_eq!(
                format!("{:?}", client.desktop_eapi_qr_poll(&mut key).await.unwrap()),
                expected
            );
            assert_eq!(client.transport.requests.lock().unwrap().len(), 2);
        }
        for (code, error) in [
            (-460, Error::SecurityVerificationRequired),
            (406, Error::RateLimited),
            (8821, Error::SecurityVerificationRequired),
            (8830, Error::SecondaryVerificationRequired),
            (429, Error::RateLimited),
            (499, Error::UpstreamUnknown),
        ] {
            let client = NeteaseClient::new(Fake::new(vec![
                response(json!({"code":200,"unikey":"key"}), &[]),
                response(json!({"code":code}), &[]),
            ]));
            let mut key = client.desktop_eapi_qr_key(&identity()).await.unwrap();
            assert_eq!(
                client.desktop_eapi_qr_poll(&mut key).await.unwrap_err(),
                error
            );
            assert_eq!(client.transport.requests.lock().unwrap().len(), 2);
        }
    }

    #[tokio::test]
    async fn cookie_shapes_preserve_presence_deletion_and_body_fallback() {
        for cookies in [
            vec![
                "MUSIC_U=u; Path=/",
                "MUSIC_R_U=r; Path=/refresh",
                "__csrf=c; Path=/",
            ],
            vec!["MUSIC_U=u; Path=/", "__csrf=c; Path=/"],
            vec!["MUSIC_U=u; Path=/"],
        ] {
            let client = NeteaseClient::new(Fake::new(vec![
                response(json!({"code":200,"unikey":"key"}), &[]),
                response(json!({"code":803}), &cookies),
            ]));
            let mut key = client.desktop_eapi_qr_key(&identity()).await.unwrap();
            let DesktopEapiQrPoll::Confirmed(candidate) =
                client.desktop_eapi_qr_poll(&mut key).await.unwrap()
            else {
                panic!("confirmed");
            };
            assert!(candidate.has_music_u());
        }

        let client = NeteaseClient::new(Fake::new(vec![
            response(json!({"code":200,"unikey":"key"}), &[]),
            response(
                json!({"code":803,"cookie":"MUSIC_U=body-u; __csrf=body-c"}),
                &["MUSIC_R_U=deleted; Max-Age=0; Path=/refresh"],
            ),
        ]));
        let mut key = client.desktop_eapi_qr_key(&identity()).await.unwrap();
        let DesktopEapiQrPoll::Confirmed(candidate) =
            client.desktop_eapi_qr_poll(&mut key).await.unwrap()
        else {
            panic!("confirmed");
        };
        assert!(candidate.has_music_u());
        assert!(!candidate.has_music_r_u());
        assert!(candidate.has_csrf());

        let client = NeteaseClient::new(Fake::new(vec![
            response(json!({"code":200,"unikey":"key"}), &[]),
            response(
                json!({"code":803}),
                &[
                    "MUSIC_U=duplicate-u; Domain=.music.163.com; Path=/",
                    "MUSIC_U=duplicate-u; Domain=.music.163.com; Path=/eapi",
                    "__csrf=deleted; Max-Age=0; Path=/",
                ],
            ),
        ]));
        let mut key = client.desktop_eapi_qr_key(&identity()).await.unwrap();
        let DesktopEapiQrPoll::Confirmed(candidate) =
            client.desktop_eapi_qr_poll(&mut key).await.unwrap()
        else {
            panic!("confirmed");
        };
        assert!(candidate.has_music_u());
        assert!(!candidate.has_csrf());
        assert!(candidate.observation().music_u.root_path);
        assert!(candidate.observation().music_u.non_root_path);

        let client = NeteaseClient::new(Fake::new(vec![
            response(json!({"code":200,"unikey":"key"}), &[]),
            response(json!({"code":803}), &[]),
        ]));
        let mut key = client.desktop_eapi_qr_key(&identity()).await.unwrap();
        let DesktopEapiQrPoll::Confirmed(candidate) =
            client.desktop_eapi_qr_poll(&mut key).await.unwrap()
        else {
            panic!("confirmed");
        };
        assert!(!candidate.has_music_u());
        assert!(!candidate.is_next_refreshable());
        assert_eq!(client.transport.requests.lock().unwrap().len(), 2);
    }

    #[tokio::test]
    #[allow(
        clippy::too_many_lines,
        reason = "one bounded table verifies the complete refresh-delta contract"
    )]
    async fn refresh_delta_supports_no_r_input_partial_rotation_and_explicit_deletion() {
        let cases = [
            (
                vec![
                    "MUSIC_U=new-u; Path=/",
                    "MUSIC_R_U=new-r; Path=/refresh",
                    "__csrf=new-c; Path=/",
                ],
                DesktopEapiCookieRotation::Updated,
                DesktopEapiCookieRotation::Inserted,
                DesktopEapiCookieRotation::Updated,
                true,
            ),
            (
                vec!["MUSIC_U=new-u; Path=/"],
                DesktopEapiCookieRotation::Updated,
                DesktopEapiCookieRotation::Absent,
                DesktopEapiCookieRotation::Absent,
                true,
            ),
            (
                vec!["__csrf=new-c; Path=/"],
                DesktopEapiCookieRotation::Absent,
                DesktopEapiCookieRotation::Absent,
                DesktopEapiCookieRotation::Updated,
                true,
            ),
            (
                vec![],
                DesktopEapiCookieRotation::Absent,
                DesktopEapiCookieRotation::Absent,
                DesktopEapiCookieRotation::Absent,
                true,
            ),
        ];
        for (cookies, u, r, csrf, refreshable) in cases {
            let cookie_refs = cookies.as_slice();
            let (client, candidate) =
                confirmed_candidate(response(json!({"code":200,"bizCode":200}), cookie_refs)).await;
            let (_, observation) = client
                .refresh_desktop_eapi_candidate_observed(&candidate)
                .await
                .unwrap();
            assert_eq!(observation.music_u, u);
            assert_eq!(observation.music_r_u, r);
            assert_eq!(observation.csrf, csrf);
            assert_eq!(observation.candidate_next_refreshable, refreshable);
        }

        let (client, candidate) = confirmed_candidate(response(
            json!({"code":200,"bizCode":200}),
            &["MUSIC_U=; Max-Age=0; Path=/"],
        ))
        .await;
        assert_eq!(
            client
                .refresh_desktop_eapi_candidate_observed(&candidate)
                .await
                .unwrap_err(),
            Error::AuthenticationRequired
        );
        assert_eq!(client.transport.requests.lock().unwrap().len(), 3);

        for deleted_cookie in [
            "MUSIC_R_U=; Max-Age=0; Path=/refresh",
            "__csrf=; Max-Age=0; Path=/",
        ] {
            let (client, candidate) = confirmed_candidate(response(
                json!({"code":200,"bizCode":200}),
                &[deleted_cookie],
            ))
            .await;
            let (refreshed, observation) = client
                .refresh_desktop_eapi_candidate_observed(&candidate)
                .await
                .unwrap();
            if deleted_cookie.starts_with("MUSIC_R_U") {
                assert_eq!(observation.music_r_u, DesktopEapiCookieRotation::Deleted);
                assert!(!refreshed.has_music_r_u());
            } else {
                assert_eq!(observation.csrf, DesktopEapiCookieRotation::Deleted);
                assert!(!refreshed.has_csrf());
            }
            assert!(observation.candidate_next_refreshable);
        }

        let client = NeteaseClient::new(Fake::new(vec![
            response(json!({"code":200,"unikey":"key"}), &[]),
            response(json!({"code":803}), &[]),
        ]));
        let mut key = client.desktop_eapi_qr_key(&identity()).await.unwrap();
        let DesktopEapiQrPoll::Confirmed(candidate) =
            client.desktop_eapi_qr_poll(&mut key).await.unwrap()
        else {
            panic!("confirmed");
        };
        assert_eq!(
            client
                .refresh_desktop_eapi_candidate_observed(&candidate)
                .await
                .unwrap_err(),
            Error::AuthenticationRequired
        );
        assert_eq!(client.transport.requests.lock().unwrap().len(), 2);
    }

    #[test]
    fn encrypted_and_plaintext_eapi_responses_decode_without_relaxing_bounds() {
        let value = json!({"code":200,"bizCode":200});
        let plain = serde_json::to_vec(&value).unwrap();
        assert_eq!(decode_eapi_response(&plain).unwrap(), value);

        let mut encrypted = plain;
        let padding = 16 - encrypted.len() % 16;
        encrypted.extend(std::iter::repeat_n(u8::try_from(padding).unwrap(), padding));
        let cipher = aes::Aes128::new(b"e82ckenh8dichen8".into());
        for block in encrypted.as_chunks_mut::<16>().0 {
            cipher.encrypt_block(block.into());
        }
        assert_eq!(decode_eapi_response(&encrypted).unwrap(), value);
    }
}
