//! NetEase-only wire profiles. Preserve existing values, including legacy
//! `undefined` fields; no unclassified device identity is synthesized here.
use serde_json::Value;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum NeteaseProtocolProfile {
    WebWeapi,
    DesktopEapi,
}
impl NeteaseProtocolProfile {
    pub(crate) const fn base(self) -> &'static str {
        match self {
            Self::WebWeapi => "https://music.163.com/weapi/",
            Self::DesktopEapi => "https://interface.music.163.com/eapi/",
        }
    }
    pub(crate) fn headers(self, overrides: Vec<(String, String)>) -> Vec<(String, String)> {
        let mut headers = match self {
            Self::WebWeapi | Self::DesktopEapi => vec![
                ("Referer".into(), "https://music.163.com/".into()),
                ("User-Agent".into(), "Mozilla/5.0".into()),
            ],
        };
        for (name, value) in overrides {
            headers
                .retain(|(existing, _): &(String, String)| !existing.eq_ignore_ascii_case(&name));
            headers.push((name, value));
        }
        headers
    }
}

pub(crate) const INTERFACE3_EAPI_BASE: &str = "https://interface3.music.163.com/eapi/";
pub(crate) const WEB_QR_USER_AGENT: &str =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:152.0) Gecko/20100101 Firefox/152.0";
// Existing explicitly authorized SMS compatibility route, not a generated
// installation/device fingerprint and not a replacement desktop profile.
pub(crate) const MOBILE_LOGIN_USER_AGENT: &str =
    "neteasemusic/9.5.37 (iPhone; iOS 18.7.2; Scale/3.00)";
pub(crate) const MOBILE_LOGIN_OS: &str = "iPhone OS";
pub(crate) const MOBILE_LOGIN_OS_VERSION: &str = "18.7.2";
pub(crate) const MOBILE_LOGIN_APP_VERSION: &str = "9.5.37";
pub(crate) const MOBILE_LOGIN_BUILD_VERSION: &str = "7010";

pub(crate) fn desktop_media_context(
    music_u: &str,
    csrf: &str,
    request_id: String,
) -> (String, Value) {
    let fields = [
        ("osver", "undefined".to_owned()),
        ("deviceId", "undefined".to_owned()),
        ("appver", "8.0.0".to_owned()),
        ("versioncode", "140".to_owned()),
        ("mobilename", "undefined".to_owned()),
        ("buildver", "1623435496".to_owned()),
        ("resolution", "1920x1080".to_owned()),
        ("__csrf", csrf.to_owned()),
        ("os", "pc".to_owned()),
        ("channel", "undefined".to_owned()),
        ("requestId", request_id),
        ("MUSIC_U", music_u.to_owned()),
    ];
    let cookie = fields
        .iter()
        .map(|(name, value)| format!("{name}={value}"))
        .collect::<Vec<_>>()
        .join("; ");
    let header = fields
        .into_iter()
        .map(|(name, value)| (name.into(), Value::String(value)))
        .collect();
    (cookie, Value::Object(header))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn golden_pre_extraction_desktop_media_context_and_effective_headers() {
        let (cookie, header) = desktop_media_context(
            "synthetic-session",
            "synthetic-csrf",
            "1700000000000_1234".into(),
        );
        assert_eq!(
            header,
            json!({"osver":"undefined","deviceId":"undefined","appver":"8.0.0","versioncode":"140","mobilename":"undefined","buildver":"1623435496","resolution":"1920x1080","__csrf":"synthetic-csrf","os":"pc","channel":"undefined","requestId":"1700000000000_1234","MUSIC_U":"synthetic-session"})
        );
        assert_eq!(
            cookie,
            "osver=undefined; deviceId=undefined; appver=8.0.0; versioncode=140; mobilename=undefined; buildver=1623435496; resolution=1920x1080; __csrf=synthetic-csrf; os=pc; channel=undefined; requestId=1700000000000_1234; MUSIC_U=synthetic-session"
        );
        assert_eq!(
            NeteaseProtocolProfile::DesktopEapi.headers(vec![]),
            vec![
                ("Referer".into(), "https://music.163.com/".into()),
                ("User-Agent".into(), "Mozilla/5.0".into())
            ]
        );
        assert_eq!(
            NeteaseProtocolProfile::WebWeapi.base(),
            "https://music.163.com/weapi/"
        );
    }
}
