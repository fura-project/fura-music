use crate::catalog::{MAX_COLLECTION_IDENTITIES, bounds, decode, id, text};
use crate::{Error, MAX_RESPONSE_BYTES, NeteaseClient, Playlist, Request, Song, Transport};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    time::{SystemTime, UNIX_EPOCH},
};

const WEB_QR_USER_AGENT: &str =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:152.0) Gecko/20100101 Firefox/152.0";
const MOBILE_LOGIN_USER_AGENT: &str = "neteasemusic/9.5.37 (iPhone; iOS 18.7.2; Scale/3.00)";
const MOBILE_LOGIN_BASE: &str = "https://interface3.music.163.com/eapi/";
const MOBILE_LOGIN_OS: &str = "iPhone OS";
const MOBILE_LOGIN_OS_VERSION: &str = "18.7.2";
const MOBILE_LOGIN_APP_VERSION: &str = "9.5.37";
const MOBILE_LOGIN_BUILD_VERSION: &str = "7010";

fn qr_debug(message: std::fmt::Arguments<'_>) {
    if std::env::var_os("FURA_NETEASE_QR_DEBUG").is_some() {
        eprintln!("FURA_DIAGNOSTIC netease_qr_core {message}");
    }
}

fn sms_debug(message: std::fmt::Arguments<'_>) {
    if std::env::var_os("FURA_NETEASE_SMS_DEBUG").is_some() {
        eprintln!("FURA_DIAGNOSTIC netease_sms_core {message}");
    }
}

fn random_chars(alphabet: &[u8], length: usize) -> Result<String, Error> {
    let ceiling =
        u8::MAX - (u8::MAX % u8::try_from(alphabet.len()).map_err(|_| Error::InputBound)?);
    let mut value = String::with_capacity(length);
    let mut entropy = [0_u8; 64];
    while value.len() < length {
        getrandom::fill(&mut entropy).map_err(|_| Error::ProtocolUnavailable)?;
        for byte in entropy {
            if byte < ceiling {
                value.push(char::from(alphabet[usize::from(byte) % alphabet.len()]));
                if value.len() == length {
                    break;
                }
            }
        }
    }
    Ok(value)
}

fn unix_millis() -> Result<u128, Error> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .map_err(|_| Error::ProtocolUnavailable)
}

fn validate_phone(country_code: &str, phone: &str) -> Result<(), Error> {
    if !(1..=4).contains(&country_code.len())
        || !(4..=20).contains(&phone.len())
        || !country_code.bytes().all(|byte| byte.is_ascii_digit())
        || !phone.bytes().all(|byte| byte.is_ascii_digit())
    {
        return Err(Error::InputBound);
    }
    Ok(())
}

fn validate_sms_code(code: &str) -> Result<(), Error> {
    if !(4..=10).contains(&code.len()) || !code.bytes().all(|byte| byte.is_ascii_digit()) {
        return Err(Error::InputBound);
    }
    Ok(())
}

fn cookie_component(value: &str) -> String {
    url::form_urlencoded::byte_serialize(value.as_bytes()).collect()
}

fn mobile_login_context() -> Result<(String, String), Error> {
    let timestamp = unix_millis()?;
    let device_id = random_chars(b"0123456789ABCDEF", 52)?;
    let request_id_suffix = random_chars(b"0123456789", 4)?;
    let fields = [
        ("osver", MOBILE_LOGIN_OS_VERSION.to_owned()),
        ("deviceId", device_id.clone()),
        ("os", MOBILE_LOGIN_OS.to_owned()),
        ("appver", MOBILE_LOGIN_APP_VERSION.to_owned()),
        ("versioncode", "140".into()),
        ("mobilename", String::new()),
        ("buildver", MOBILE_LOGIN_BUILD_VERSION.into()),
        ("resolution", "1920x1080".into()),
        ("__csrf", String::new()),
        ("channel", "distribution".into()),
        ("requestId", format!("{timestamp}_{request_id_suffix}")),
    ];
    let cookie = fields
        .into_iter()
        .map(|(name, value)| format!("{}={}", cookie_component(name), cookie_component(&value)))
        .collect::<Vec<_>>()
        .join("; ");
    Ok((cookie, device_id))
}

fn mobile_login_headers(device_id: &str) -> Vec<(String, String)> {
    vec![
        ("User-Agent".into(), MOBILE_LOGIN_USER_AGENT.into()),
        ("Referer".into(), "https://music.163.com/".into()),
        (
            "Content-Type".into(),
            "application/x-www-form-urlencoded".into(),
        ),
        ("x-aeapi".into(), "true".into()),
        ("x-os".into(), MOBILE_LOGIN_OS.into()),
        ("x-osver".into(), MOBILE_LOGIN_OS_VERSION.into()),
        ("x-appver".into(), MOBILE_LOGIN_APP_VERSION.into()),
        ("x-buildver".into(), MOBILE_LOGIN_BUILD_VERSION.into()),
        ("x-deviceid".into(), device_id.into()),
        ("x-sdeviceid".into(), device_id.into()),
    ]
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

fn web_qr_context() -> Result<(String, String), Error> {
    let timestamp = unix_millis()?;
    let nuid = random_chars(b"0123456789abcdef", 32)?;
    let session = random_chars(
        b"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_",
        190,
    )?;
    let nmtid = format!(
        "00{}",
        random_chars(
            b"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_",
            39,
        )?
    );
    let wnmcid = format!(
        "{}.{}.01.0",
        random_chars(b"abcdefghijklmnopqrstuvwxyz", 6)?,
        timestamp
    );
    let cookie = [
        ("JSESSIONID-WYYY", session),
        ("_iuqxldmzr_", "33".into()),
        ("_ntes_nnid", format!("{nuid}%2C{timestamp}")),
        ("_ntes_nuid", nuid),
        ("NMTID", nmtid),
        ("WEVNSM", "1.0.0".into()),
        ("WNMCID", wnmcid),
    ]
    .into_iter()
    .map(|(name, value)| format!("{name}={value}"))
    .collect::<Vec<_>>()
    .join("; ");
    let chain_id = format!(
        "v1_unknown-{}_web_login_{timestamp}",
        random_chars(b"0123456789", 6)?
    );
    Ok((cookie, chain_id))
}

fn web_qr_headers(chain_id: Option<&str>) -> Vec<(String, String)> {
    let mut headers = vec![
        ("User-Agent".into(), WEB_QR_USER_AGENT.into()),
        ("Referer".into(), "https://music.163.com/".into()),
        ("Origin".into(), "https://music.163.com".into()),
        ("x-os".into(), "web".into()),
        ("X-channelSource".into(), "undefined".into()),
        ("Nm-GCore-Status".into(), "1".into()),
    ];
    if let Some(chain_id) = chain_id {
        headers.extend([
            ("X-loginMethod".into(), "QrCode".into()),
            ("x-login-chain-id".into(), chain_id.into()),
        ]);
    }
    headers
}

fn merge_set_cookies(existing: &str, set_cookies: &[String]) -> Result<String, Error> {
    if existing.len() > 8192
        || set_cookies.len() > 32
        || set_cookies.iter().any(|cookie| cookie.len() > 8192)
    {
        return Err(Error::ResponseBound);
    }
    let mut values = BTreeMap::<String, String>::new();
    for pair in existing
        .split(';')
        .map(str::trim)
        .filter(|pair| !pair.is_empty())
    {
        let (name, value) = pair.split_once('=').ok_or(Error::ResponseShapeMismatch)?;
        values.insert(name.into(), value.into());
    }
    for set_cookie in set_cookies {
        let pair = set_cookie
            .split(';')
            .next()
            .ok_or(Error::ResponseShapeMismatch)?;
        let (name, value) = pair.split_once('=').ok_or(Error::ResponseShapeMismatch)?;
        values.insert(name.trim().into(), value.trim().into());
    }
    if values.len() > 64
        || values
            .iter()
            .any(|(name, value)| name.is_empty() || name.len() > 128 || value.len() > 4096)
    {
        return Err(Error::ResponseBound);
    }
    Ok(values
        .into_iter()
        .map(|(name, value)| format!("{name}={value}"))
        .collect::<Vec<_>>()
        .join("; "))
}

#[derive(Clone, Eq, PartialEq)]
pub struct Credential {
    version: u8,
    provider: String,
    music_u: String,
    csrf: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct StoredCredential {
    version: u8,
    provider: String,
    music_u: String,
    csrf: String,
}
impl std::fmt::Debug for Credential {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("NetEaseCredential([REDACTED])")
    }
}
impl Credential {
    fn validate(&self) -> Result<(), Error> {
        if self.version != 1
            || self.provider != "netease-cloud-music"
            || self.music_u.is_empty()
            || self.music_u.len() > 4096
            || self.csrf.len() > 256
            || !self
                .music_u
                .bytes()
                .chain(self.csrf.bytes())
                .all(|b| b.is_ascii_graphic() && !matches!(b, b';' | b',' | b'"' | b'\\'))
        {
            return Err(Error::ResponseShapeMismatch);
        }
        Ok(())
    }
    /// Opaque secure-storage bytes, never a presentation or logging value.
    /// # Errors
    /// Rejects invalid internal session invariants.
    pub fn export(&self) -> Result<Vec<u8>, Error> {
        self.validate()?;
        serde_json::to_vec(&json!({"version":self.version,"provider":self.provider,"music_u":self.music_u,"csrf":self.csrf})).map_err(|_|Error::ResponseShapeMismatch)
    }
    /// Imports only a candidate; the Provider must verify it before authentication.
    /// # Errors
    /// Rejects oversized, foreign, future-version, malformed or invalid credentials.
    pub fn import(bytes: &[u8]) -> Result<Self, Error> {
        if bytes.len() > 8192 {
            return Err(Error::ResponseBound);
        }
        let stored: StoredCredential =
            serde_json::from_slice(bytes).map_err(|_| Error::ResponseShapeMismatch)?;
        let value = Self {
            version: stored.version,
            provider: stored.provider,
            music_u: stored.music_u,
            csrf: stored.csrf,
        };
        value.validate()?;
        Ok(value)
    }
    /// Builds a pending credential from the minimal browser Cookie header
    /// returned by an official `NetEase` login surface.
    ///
    /// # Errors
    /// Rejects non-UTF-8, oversized, conflicting or malformed Cookie data.
    pub fn from_browser_cookie_header(bytes: &[u8]) -> Result<Self, Error> {
        if bytes.len() > 8192 {
            return Err(Error::ResponseBound);
        }
        let cookie = std::str::from_utf8(bytes).map_err(|_| Error::ResponseShapeMismatch)?;
        Self::from_cookie_sources(cookie, None)
    }
    pub(crate) fn cookie(&self) -> String {
        format!("MUSIC_U={}; __csrf={}", self.music_u, self.csrf)
    }
    fn from_cookie_sources(cookie: &str, body_cookie: Option<&str>) -> Result<Self, Error> {
        if cookie.len() > 8192 || body_cookie.is_some_and(|value| value.len() > 32 * 1024) {
            return Err(Error::ResponseBound);
        }
        let mut music_u: Option<String> = None;
        let mut csrf: Option<String> = None;
        let mut pairs = cookie
            .split(';')
            .chain(body_cookie.into_iter().flat_map(|value| value.split(';')));
        for pair in pairs.by_ref().take(128) {
            if let Some((name, value)) = pair.split_once('=') {
                let target = match name.trim() {
                    "MUSIC_U" => &mut music_u,
                    "__csrf" => &mut csrf,
                    _ => continue,
                };
                let value = value.trim().to_owned();
                if let Some(current) = target.as_ref() {
                    if !current.is_empty() && !value.is_empty() && current != &value {
                        return Err(Error::ResponseShapeMismatch);
                    }
                    if !current.is_empty() || value.is_empty() {
                        continue;
                    }
                }
                *target = Some(value);
            }
        }
        if pairs.next().is_some() {
            return Err(Error::ResponseBound);
        }
        let value = Self {
            version: 1,
            provider: "netease-cloud-music".into(),
            music_u: music_u.ok_or(Error::ResponseShapeMismatch)?,
            csrf: csrf.unwrap_or_default(),
        };
        value.validate()?;
        Ok(value)
    }
}
/// Raw key stays inside Rust; only its locally encoded image is presented.
pub struct QrKey {
    key: String,
    cookie: String,
    chain_id: String,
}

#[derive(Clone)]
pub struct SmsLoginChallenge {
    country_code: String,
    phone: String,
    cookie: String,
    device_id: String,
}

impl std::fmt::Debug for SmsLoginChallenge {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("NetEaseSmsLoginChallenge([REDACTED])")
    }
}
impl std::fmt::Debug for QrKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("NetEaseQrKey([REDACTED])")
    }
}
impl QrKey {
    fn login_url(&self) -> Result<url::Url, Error> {
        let mut url = url::Url::parse("https://music.163.com/st/platform/scanlogin")
            .map_err(|_| Error::ProtocolUnavailable)?;
        url.query_pairs_mut()
            .append_pair("codekey", &self.key)
            .append_pair("chainId", &self.chain_id)
            .append_pair("hdw_device", "web")
            .append_pair("hdw_appid", "web")
            .append_pair("hitExp", "1");
        Ok(url)
    }

    /// Returns the same official confirmation URL encoded into the QR image.
    ///
    /// This lets a native client hand the active challenge to the system
    /// browser or the provider app without exposing browser cookies to the
    /// client. The URL is a short-lived secret and must not be logged.
    /// # Errors
    /// Returns a coarse protocol error when the fixed URL cannot be encoded.
    pub fn external_confirmation_url(&self) -> Result<String, Error> {
        Ok(self.login_url()?.to_string())
    }

    /// # Errors
    /// Returns a coarse encoding error; the QR key never appears in diagnostics.
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
pub enum QrPoll {
    Waiting,
    Scanned,
    Expired,
    Confirmed(Credential),
}
impl std::fmt::Debug for QrPoll {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::Waiting => "Waiting",
            Self::Scanned => "Scanned",
            Self::Expired => "Expired",
            Self::Confirmed(_) => "Confirmed([REDACTED])",
        })
    }
}
pub struct Account {
    pub id: u64,
    pub name: String,
    pub avatar: Option<String>,
}
#[derive(Deserialize)]
pub struct UserPlaylist {
    #[serde(flatten)]
    pub playlist: Playlist,
    pub creator: Creator,
    #[serde(rename = "specialType", default)]
    pub special_type: u32,
}
#[derive(Deserialize)]
pub struct Creator {
    #[serde(rename = "userId")]
    pub id: u64,
}
pub struct UserPlaylistPage {
    pub items: Vec<UserPlaylist>,
    pub more: bool,
}
impl<T: Transport> NeteaseClient<T> {
    async fn mobile_login_request(
        &self,
        phase: &'static str,
        path: &str,
        mut payload: Value,
        cookie: &str,
        device_id: &str,
    ) -> Result<(Value, Vec<String>), Error> {
        if cookie.len() > 8192
            || device_id.len() != 52
            || !device_id.bytes().all(|byte| byte.is_ascii_hexdigit())
        {
            return Err(Error::InputBound);
        }
        payload["csrf_token"] = json!("");
        payload["header"] = json!({});
        payload["deviceId"] = json!(device_id);
        payload["e_r"] = json!(true);
        let text = serde_json::to_string(&payload).map_err(|_| Error::InputBound)?;
        if text.len() > 64 * 1024 {
            return Err(Error::InputBound);
        }
        let response = self
            .transport
            .send(Request {
                url: format!(
                    "{MOBILE_LOGIN_BASE}{}",
                    path.strip_prefix("/api/").ok_or(Error::InputBound)?
                ),
                form: crate::crypto::eapi(path, &text)?,
                cookie: Some(cookie.into()),
                headers: mobile_login_headers(device_id),
            })
            .await?;
        sms_debug(format_args!(
            "phase={phase} transport_status={}",
            response.status
        ));
        if response.body.len() > MAX_RESPONSE_BYTES {
            return Err(Error::ResponseBound);
        }
        match response.status {
            200 => {}
            429 => return Err(Error::RateLimited),
            _ => return Err(Error::ProtocolUnavailable),
        }
        let decoded = match serde_json::from_slice::<Value>(&response.body) {
            Ok(value) if value.is_object() => value,
            _ => serde_json::from_slice(&crate::crypto::eapi_response(&response.body)?)
                .map_err(|_| Error::ResponseShapeMismatch)?,
        };
        Ok((decoded, response.set_cookies))
    }

    /// Sends one user-requested SMS code and retains only the bounded in-memory
    /// login context required to submit it. No phone value is logged or stored.
    /// # Errors
    /// Invalid input, rate limiting, risk verification, transport and malformed
    /// responses remain distinct.
    pub async fn send_sms_code(
        &self,
        country_code: &str,
        phone: &str,
    ) -> Result<SmsLoginChallenge, Error> {
        validate_phone(country_code, phone)?;
        let (cookie, device_id) = mobile_login_context()?;
        let (value, set_cookies) = self
            .mobile_login_request(
                "send",
                "/api/sms/captcha/sent",
                json!({
                    "ctcode":country_code,
                    "cellphone":phone,
                    "os":"iOS",
                    "fromPage":"RN",
                    "rnBundleVersion":"0.0.5",
                    "rnBundleName":"new-rn-login",
                    "verifyId":1,
                }),
                &cookie,
                &device_id,
            )
            .await?;
        let code = response_code(&value)?;
        sms_debug(format_args!("phase=send code={code}"));
        match code {
            200 => Ok(SmsLoginChallenge {
                country_code: country_code.into(),
                phone: phone.into(),
                cookie: merge_set_cookies(&cookie, &set_cookies)?,
                device_id,
            }),
            400 | 502 | 503 => Err(Error::VerificationRejected),
            429 => Err(Error::RateLimited),
            8821 => Err(Error::SecurityVerificationRequired),
            8830 => Err(Error::SecondaryVerificationRequired),
            _ => Err(Error::UpstreamUnknown),
        }
    }

    /// Exchanges one user-entered SMS code for an opaque account credential.
    /// # Errors
    /// A rejected code never becomes a credential; returned account cookies
    /// are bounded and parsed only inside the client.
    pub async fn login_with_sms_code(
        &self,
        challenge: &SmsLoginChallenge,
        code: &str,
    ) -> Result<Credential, Error> {
        validate_phone(&challenge.country_code, &challenge.phone)?;
        validate_sms_code(code)?;
        let (value, set_cookies) = self
            .mobile_login_request(
                "login",
                "/api/login/cellphone",
                json!({
                    "type":"1",
                    "https":"true",
                    "phone":challenge.phone,
                    "countrycode":challenge.country_code,
                    "captcha":code,
                    "remember":"true",
                    "rememberLogin":"true",
                    "os":"iOS",
                    "fromPage":"RN",
                    "rnBundleVersion":"0.0.5",
                    "rnBundleName":"new-rn-login",
                    "verifyId":1,
                }),
                &challenge.cookie,
                &challenge.device_id,
            )
            .await?;
        let response_code = response_code(&value)?;
        sms_debug(format_args!(
            "phase=login business_code={response_code} has_verify_token={} has_verify_config_id={} has_verify_type={} has_event_id={} has_sign={}",
            value.get("verifyToken").is_some() || value.pointer("/data/verifyToken").is_some(),
            value.get("verifyConfigId").is_some()
                || value.pointer("/data/verifyConfigId").is_some(),
            value.get("verifyType").is_some() || value.pointer("/data/verifyType").is_some(),
            value.get("event_id").is_some() || value.pointer("/data/event_id").is_some(),
            value.get("sign").is_some() || value.pointer("/data/sign").is_some(),
        ));
        match response_code {
            200 => {
                let cookie = merge_set_cookies(&challenge.cookie, &set_cookies)?;
                Credential::from_cookie_sources(
                    &cookie,
                    value.get("cookie").and_then(Value::as_str),
                )
            }
            400 | 502 | 503 => Err(Error::VerificationRejected),
            429 => Err(Error::RateLimited),
            8821 => Err(Error::SecurityVerificationRequired),
            8830 => Err(Error::SecondaryVerificationRequired),
            _ => Err(Error::UpstreamUnknown),
        }
    }

    /// Creates one QR challenge only after an explicit caller action.
    /// # Errors
    /// Invalid/missing keys and all upstream failures stop.
    pub async fn qr_key(&self) -> Result<QrKey, Error> {
        let (cookie, chain_id) = web_qr_context()?;
        let (v, set_cookies) = self
            .raw_request_with_headers(
                "/api/login/qrcode/unikey",
                json!({"type":1,"noCheckToken":true}),
                false,
                Some(&cookie),
                web_qr_headers(None),
            )
            .await?;
        let code = v
            .get("code")
            .and_then(Value::as_i64)
            .ok_or(Error::ResponseShapeMismatch)?;
        qr_debug(format_args!("phase=key code={code}"));
        match code {
            200 => {}
            8821 => return Err(Error::SecurityVerificationRequired),
            8830 => return Err(Error::SecondaryVerificationRequired),
            _ => return Err(Error::UpstreamUnknown),
        }
        let key = v
            .get("unikey")
            .and_then(Value::as_str)
            .ok_or(Error::ResponseShapeMismatch)?;
        if key.is_empty()
            || key.len() > 256
            || !key
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_'))
        {
            return Err(Error::ResponseShapeMismatch);
        }
        Ok(QrKey {
            key: key.into(),
            cookie: merge_set_cookies(&cookie, &set_cookies)?,
            chain_id,
        })
    }
    /// Exactly one explicit poll; no background loop or automatic approval.
    /// # Errors
    /// Unknown states or confirmed responses without a valid cookie stop.
    pub async fn qr_poll(&self, key: &mut QrKey) -> Result<QrPoll, Error> {
        let (v, cookies) = self
            .raw_request_with_headers(
                "/api/login/qrcode/client/login",
                json!({
                    "type":1,
                    "key":key.key,
                    "noCheckToken":true,
                    "ydDeviceToken":"",
                }),
                false,
                Some(&key.cookie),
                web_qr_headers(Some(&key.chain_id)),
            )
            .await?;
        key.cookie = merge_set_cookies(&key.cookie, &cookies)?;
        let code = v
            .get("code")
            .and_then(Value::as_i64)
            .ok_or(Error::ResponseShapeMismatch)?;
        qr_debug(format_args!("phase=poll code={code}"));
        match code {
            800 => Ok(QrPoll::Expired),
            801 => Ok(QrPoll::Waiting),
            802 => Ok(QrPoll::Scanned),
            803 => Ok(QrPoll::Confirmed(Credential::from_cookie_sources(
                &key.cookie,
                v.get("cookie").and_then(Value::as_str),
            )?)),
            8821 => Err(Error::SecurityVerificationRequired),
            8830 => Err(Error::SecondaryVerificationRequired),
            _ => Err(Error::UpstreamUnknown),
        }
    }
    /// # Errors
    /// Null account/profile or explicit unauthenticated responses reject the candidate; unknown failures retain it.
    pub async fn account(&self, credential: &Credential) -> Result<Account, Error> {
        let (v, _) = self
            .request(
                "/api/w/nuser/account/get",
                json!({}),
                false,
                Some(&credential.cookie()),
            )
            .await?;
        if v.get("account") == Some(&Value::Null) || v.get("profile") == Some(&Value::Null) {
            return Err(Error::CredentialRejected);
        }
        let aid = v
            .pointer("/account/id")
            .and_then(Value::as_u64)
            .ok_or(Error::ResponseShapeMismatch)?;
        if v.pointer("/profile/userId").and_then(Value::as_u64) != Some(aid) {
            return Err(Error::ResponseShapeMismatch);
        }
        id(aid)?;
        let name = v
            .pointer("/profile/nickname")
            .and_then(Value::as_str)
            .ok_or(Error::ResponseShapeMismatch)?;
        text(name)?;
        let avatar = v
            .pointer("/profile/avatarUrl")
            .filter(|v| !v.is_null())
            .map(|v| {
                v.as_str()
                    .map(str::to_owned)
                    .ok_or(Error::ResponseShapeMismatch)
            })
            .transpose()?;
        Ok(Account {
            id: aid,
            name: name.into(),
            avatar: crate::artwork(avatar)?,
        })
    }
    /// # Errors
    /// One authenticated page; invalid identity, page bounds or response shape stop.
    pub async fn user_playlists(
        &self,
        credential: &Credential,
        user: u64,
        offset: u32,
        size: u32,
    ) -> Result<UserPlaylistPage, Error> {
        id(user)?;
        bounds(offset, size)?;
        let (v, _) = self
            .request(
                "/api/user/playlist",
                json!({"uid":user,"offset":offset,"limit":size,"includeVideo":false}),
                false,
                Some(&credential.cookie()),
            )
            .await?;
        let items: Vec<UserPlaylist> = decode(
            v.get("playlist")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        let more: bool = decode(v.get("more").cloned().ok_or(Error::ResponseShapeMismatch)?)?;
        if items.len() > size as usize || (more && items.is_empty()) {
            return Err(Error::ResponseShapeMismatch);
        }
        for p in &items {
            p.playlist.validate()?;
            id(p.creator.id)?;
        }
        Ok(UserPlaylistPage { items, more })
    }
    /// Unordered liked identities; never pretend to be recent-play order.
    /// # Errors
    /// Rejects lists above the body-budget-derived identity ceiling, duplicates and invalid IDs.
    pub async fn liked_ids(&self, credential: &Credential, user: u64) -> Result<Vec<u64>, Error> {
        id(user)?;
        let (v, _) = self
            .request(
                "/api/song/like/get",
                json!({"uid":user}),
                false,
                Some(&credential.cookie()),
            )
            .await?;
        let ids: Vec<u64> = decode(v.get("ids").cloned().ok_or(Error::ResponseShapeMismatch)?)?;
        if ids.len() > MAX_COLLECTION_IDENTITIES {
            return Err(Error::ResponseBound);
        }
        let mut unique = std::collections::HashSet::new();
        for value in &ids {
            id(*value)?;
            if !unique.insert(*value) {
                return Err(Error::ResponseShapeMismatch);
            }
        }
        Ok(ids)
    }
    /// # Errors
    /// Identical standard source rules with the explicit authenticated context.
    pub async fn authenticated_media(
        &self,
        credential: &Credential,
        id: u64,
    ) -> Result<crate::Media, Error> {
        crate::catalog::id(id)?;
        let (v, _) = self
            .request(
                "/api/song/enhance/player/url/v1",
                json!({"ids":format!("[{id}]"),"level":"standard","encodeType":"aac","e_r":false}),
                true,
                Some(&credential.cookie()),
            )
            .await?;
        crate::media::decode_media(&v, id)
    }
    /// # Errors
    /// Bounded authenticated daily songs; there is no invented playlist identity.
    pub async fn daily_tracks(&self, credential: &Credential) -> Result<Vec<Song>, Error> {
        let (v, _) = self
            .request(
                "/api/v3/discovery/recommend/songs",
                json!({}),
                false,
                Some(&credential.cookie()),
            )
            .await?;
        let songs: Vec<Song> = decode(
            v.pointer("/data/dailySongs")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        if songs.len() > 100 {
            return Err(Error::ResponseBound);
        }
        for s in &songs {
            s.validate()?;
        }
        Ok(songs)
    }
    /// # Errors
    /// One Personal FM batch only; no autoplay/feedback or hidden continuation.
    pub async fn personal_fm(&self, credential: &Credential) -> Result<Vec<Song>, Error> {
        let (v, _) = self
            .request(
                "/api/v1/radio/get",
                json!({}),
                false,
                Some(&credential.cookie()),
            )
            .await?;
        let songs: Vec<Song> = decode(v.get("data").cloned().ok_or(Error::ResponseShapeMismatch)?)?;
        if songs.len() > 10 {
            return Err(Error::ResponseBound);
        }
        for s in &songs {
            s.validate()?;
        }
        Ok(songs)
    }
}

#[cfg(test)]
#[allow(clippy::items_after_test_module)]
mod qr_request_tests {
    use super::*;
    use crate::{Request, Response};
    use std::{
        collections::VecDeque,
        sync::{Arc, Mutex},
    };

    type RequestObservation = (String, Vec<String>, Vec<String>, Vec<String>);

    struct RecordingTransport {
        responses: Mutex<VecDeque<Value>>,
        requests: Arc<Mutex<Vec<RequestObservation>>>,
    }

    struct MobileRecordingTransport {
        responses: Mutex<VecDeque<Value>>,
        observations: Arc<Mutex<Vec<RequestObservation>>>,
        encrypted_payloads: Arc<Mutex<Vec<String>>>,
    }

    impl Transport for MobileRecordingTransport {
        async fn send(&self, request: Request) -> Result<Response, Error> {
            self.observations.lock().unwrap().push((
                request.url().to_owned(),
                request
                    .form()
                    .iter()
                    .map(|(name, _)| name.clone())
                    .collect(),
                request
                    .headers()
                    .iter()
                    .map(|(name, _)| name.clone())
                    .collect(),
                request
                    .cookie()
                    .into_iter()
                    .flat_map(|cookie| cookie.split(';'))
                    .filter_map(|pair| pair.trim().split_once('=').map(|(name, _)| name.into()))
                    .collect(),
            ));
            self.encrypted_payloads.lock().unwrap().push(
                request
                    .form()
                    .first()
                    .map(|(_, value)| value.clone())
                    .ok_or(Error::ProtocolUnavailable)?,
            );
            let body = self
                .responses
                .lock()
                .unwrap()
                .pop_front()
                .ok_or(Error::ProtocolUnavailable)?;
            Ok(Response {
                status: 200,
                body: serde_json::to_vec(&body).unwrap(),
                set_cookies: vec![],
            })
        }
    }

    fn decode_mobile_request_payload(encrypted: &str) -> Value {
        let mut bytes = Vec::with_capacity(encrypted.len() / 2);
        for pair in encrypted.as_bytes().chunks_exact(2) {
            let text = std::str::from_utf8(pair).unwrap();
            bytes.push(u8::from_str_radix(text, 16).unwrap());
        }
        let decoded = String::from_utf8(crate::crypto::eapi_response(&bytes).unwrap()).unwrap();
        let (_, payload_and_digest) = decoded.split_once("-36cd479b6b5-").unwrap();
        let (payload, _) = payload_and_digest.rsplit_once("-36cd479b6b5-").unwrap();
        serde_json::from_str(payload).unwrap()
    }

    impl Transport for RecordingTransport {
        async fn send(&self, request: Request) -> Result<Response, Error> {
            self.requests.lock().unwrap().push((
                request.url().to_owned(),
                request
                    .form()
                    .iter()
                    .map(|(name, _)| name.clone())
                    .collect(),
                request
                    .headers()
                    .iter()
                    .map(|(name, _)| name.clone())
                    .collect(),
                request
                    .cookie()
                    .into_iter()
                    .flat_map(|cookie| cookie.split(';'))
                    .filter_map(|pair| pair.trim().split_once('=').map(|(name, _)| name.into()))
                    .collect(),
            ));
            let body = self
                .responses
                .lock()
                .unwrap()
                .pop_front()
                .ok_or(Error::ProtocolUnavailable)?;
            Ok(Response {
                status: 200,
                body: serde_json::to_vec(&body).unwrap(),
                set_cookies: vec![],
            })
        }
    }

    #[tokio::test]
    async fn qr_key_and_poll_share_the_web_cookie_and_chain_context() {
        let requests = Arc::new(Mutex::new(Vec::new()));
        let client = NeteaseClient::new(RecordingTransport {
            responses: Mutex::new(VecDeque::from([
                json!({"code":200,"unikey":"synthetic-safe-key"}),
                json!({"code":801}),
            ])),
            requests: Arc::clone(&requests),
        });

        let mut key = client.qr_key().await.unwrap();
        let external_confirmation_url = key.external_confirmation_url().unwrap();
        let login_url = url::Url::parse(&external_confirmation_url).unwrap();
        assert_eq!(login_url.path(), "/st/platform/scanlogin");
        let login_query = login_url.query_pairs().collect::<BTreeMap<_, _>>();
        assert_eq!(
            login_query.get("codekey").map(std::convert::AsRef::as_ref),
            Some("synthetic-safe-key")
        );
        assert_eq!(
            login_query
                .get("hdw_device")
                .map(std::convert::AsRef::as_ref),
            Some("web")
        );
        assert_eq!(
            login_query
                .get("hdw_appid")
                .map(std::convert::AsRef::as_ref),
            Some("web")
        );
        assert!(login_query.contains_key("chainId"));
        assert!(matches!(
            client.qr_poll(&mut key).await,
            Ok(QrPoll::Waiting)
        ));
        assert_eq!(
            *requests.lock().unwrap(),
            [
                (
                    "https://music.163.com/weapi/login/qrcode/unikey".into(),
                    vec!["params".into(), "encSecKey".into()],
                    vec![
                        "User-Agent".into(),
                        "Referer".into(),
                        "Origin".into(),
                        "x-os".into(),
                        "X-channelSource".into(),
                        "Nm-GCore-Status".into(),
                    ],
                    vec![
                        "JSESSIONID-WYYY".into(),
                        "_iuqxldmzr_".into(),
                        "_ntes_nnid".into(),
                        "_ntes_nuid".into(),
                        "NMTID".into(),
                        "WEVNSM".into(),
                        "WNMCID".into(),
                    ],
                ),
                (
                    "https://music.163.com/weapi/login/qrcode/client/login".into(),
                    vec!["params".into(), "encSecKey".into()],
                    vec![
                        "User-Agent".into(),
                        "Referer".into(),
                        "Origin".into(),
                        "x-os".into(),
                        "X-channelSource".into(),
                        "Nm-GCore-Status".into(),
                        "X-loginMethod".into(),
                        "x-login-chain-id".into(),
                    ],
                    vec![
                        "JSESSIONID-WYYY".into(),
                        "NMTID".into(),
                        "WEVNSM".into(),
                        "WNMCID".into(),
                        "_iuqxldmzr_".into(),
                        "_ntes_nnid".into(),
                        "_ntes_nuid".into(),
                    ],
                ),
            ]
        );
    }

    #[tokio::test]
    async fn qr_security_verification_and_body_cookie_are_not_generic_failures() {
        let client = NeteaseClient::new(RecordingTransport {
            responses: Mutex::new(VecDeque::from([
                json!({"code":200,"unikey":"synthetic-safe-key"}),
                json!({"code":8821}),
            ])),
            requests: Arc::new(Mutex::new(Vec::new())),
        });
        let mut key = client.qr_key().await.unwrap();
        assert!(matches!(
            client.qr_poll(&mut key).await,
            Err(Error::SecurityVerificationRequired)
        ));

        let client = NeteaseClient::new(RecordingTransport {
            responses: Mutex::new(VecDeque::from([
                json!({"code":200,"unikey":"synthetic-safe-key"}),
                json!({"code":8830}),
            ])),
            requests: Arc::new(Mutex::new(Vec::new())),
        });
        let mut key = client.qr_key().await.unwrap();
        assert!(matches!(
            client.qr_poll(&mut key).await,
            Err(Error::SecondaryVerificationRequired)
        ));

        let client = NeteaseClient::new(RecordingTransport {
            responses: Mutex::new(VecDeque::from([
                json!({"code":200,"unikey":"synthetic-safe-key"}),
                json!({
                    "code":803,
                    "cookie":"MUSIC_U=synthetic-session; __csrf=synthetic-csrf",
                }),
            ])),
            requests: Arc::new(Mutex::new(Vec::new())),
        });
        let mut key = client.qr_key().await.unwrap();
        assert!(matches!(
            client.qr_poll(&mut key).await,
            Ok(QrPoll::Confirmed(_))
        ));
    }

    #[tokio::test]
    async fn sms_send_and_login_use_one_redacted_mobile_eapi_context() {
        let observations = Arc::new(Mutex::new(Vec::new()));
        let encrypted_payloads = Arc::new(Mutex::new(Vec::new()));
        let client = NeteaseClient::new(MobileRecordingTransport {
            responses: Mutex::new(VecDeque::from([
                json!({"code":200}),
                json!({
                    "code":200,
                    "cookie":"MUSIC_U=synthetic-session; __csrf=synthetic-csrf",
                }),
            ])),
            observations: Arc::clone(&observations),
            encrypted_payloads: Arc::clone(&encrypted_payloads),
        });

        let challenge = client.send_sms_code("86", "00000000000").await.unwrap();
        let credential = client
            .login_with_sms_code(&challenge, "123456")
            .await
            .unwrap();
        assert!(credential.export().is_ok());

        let requests = observations.lock().unwrap();
        assert_eq!(requests.len(), 2);
        assert_eq!(
            requests[0].0,
            "https://interface3.music.163.com/eapi/sms/captcha/sent"
        );
        assert_eq!(
            requests[1].0,
            "https://interface3.music.163.com/eapi/login/cellphone"
        );
        for (_, form, headers, cookies) in requests.iter() {
            assert_eq!(form, &["params"]);
            assert!(headers.contains(&"x-aeapi".into()));
            assert!(headers.contains(&"x-deviceid".into()));
            assert!(cookies.contains(&"deviceId".into()));
            assert!(cookies.contains(&"requestId".into()));
        }
        drop(requests);

        let payloads = encrypted_payloads.lock().unwrap();
        let sent = decode_mobile_request_payload(&payloads[0]);
        assert_eq!(sent["ctcode"], "86");
        assert_eq!(sent["cellphone"], "00000000000");
        assert_eq!(sent["header"], json!({}));
        assert_eq!(sent["e_r"], true);
        let login = decode_mobile_request_payload(&payloads[1]);
        assert_eq!(login["phone"], "00000000000");
        assert_eq!(login["captcha"], "123456");
        assert_eq!(login["rememberLogin"], "true");
        assert_eq!(sent["deviceId"], login["deviceId"]);
    }

    #[tokio::test]
    async fn sms_bounds_and_security_status_fail_without_credentials() {
        let client = NeteaseClient::new(MobileRecordingTransport {
            responses: Mutex::new(VecDeque::from([json!({"code":8821})])),
            observations: Arc::new(Mutex::new(Vec::new())),
            encrypted_payloads: Arc::new(Mutex::new(Vec::new())),
        });
        assert!(matches!(
            client.send_sms_code("86", "00000000000").await,
            Err(Error::SecurityVerificationRequired)
        ));
        assert!(matches!(
            client.send_sms_code("+86", "not-a-phone").await,
            Err(Error::InputBound)
        ));

        let client = NeteaseClient::new(MobileRecordingTransport {
            responses: Mutex::new(VecDeque::from([json!({"code":8830})])),
            observations: Arc::new(Mutex::new(Vec::new())),
            encrypted_payloads: Arc::new(Mutex::new(Vec::new())),
        });
        assert!(matches!(
            client.send_sms_code("86", "00000000000").await,
            Err(Error::SecondaryVerificationRequired)
        ));
    }
}

impl<T: Transport> NeteaseClient<T> {
    /// # Errors
    /// Bounded authenticated resource recommendations, with no invented pagination.
    pub async fn personalized_playlists(
        &self,
        credential: &Credential,
    ) -> Result<Vec<Playlist>, Error> {
        let (v, _) = self
            .request(
                "/api/v1/discovery/recommend/resource",
                json!({}),
                false,
                Some(&credential.cookie()),
            )
            .await?;
        let items: Vec<Playlist> = decode(
            v.get("recommend")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        if items.len() > 100 {
            return Err(Error::ResponseBound);
        }
        for p in &items {
            p.validate()?;
        }
        Ok(items)
    }
    /// # Errors
    /// One bounded favorite-Album page; missing totals and contradictory continuation stop.
    pub async fn favorite_albums(
        &self,
        credential: &Credential,
        offset: u32,
        size: u32,
    ) -> Result<crate::Page<crate::Album>, Error> {
        bounds(offset, size)?;
        let (v, _) = self
            .request(
                "/api/album/sublist",
                json!({"offset":offset,"limit":size,"total":true}),
                false,
                Some(&credential.cookie()),
            )
            .await?;
        let items: Vec<crate::Album> =
            decode(v.get("data").cloned().ok_or(Error::ResponseShapeMismatch)?)?;
        let total: u32 = decode(
            v.get("count")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        let more: bool = decode(
            v.get("hasMore")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        crate::catalog::check_page(items.len(), offset, size, total, more)?;
        for a in &items {
            a.validate()?;
        }
        Ok(crate::Page {
            items,
            offset,
            total,
            more,
        })
    }
    /// # Errors
    /// One bounded favorite-Artist page; missing totals and contradictory continuation stop.
    pub async fn favorite_artists(
        &self,
        credential: &Credential,
        offset: u32,
        size: u32,
    ) -> Result<crate::Page<crate::Artist>, Error> {
        bounds(offset, size)?;
        let (v, _) = self
            .request(
                "/api/artist/sublist",
                json!({"offset":offset,"limit":size,"total":true}),
                false,
                Some(&credential.cookie()),
            )
            .await?;
        let items: Vec<crate::Artist> =
            decode(v.get("data").cloned().ok_or(Error::ResponseShapeMismatch)?)?;
        let total: u32 = decode(
            v.get("count")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        let more: bool = decode(
            v.get("hasMore")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        crate::catalog::check_page(items.len(), offset, size, total, more)?;
        for a in &items {
            a.validate()?;
        }
        Ok(crate::Page {
            items,
            offset,
            total,
            more,
        })
    }
}
