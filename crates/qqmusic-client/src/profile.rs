//! Provider-private protocol presets. This first extraction preserves all
//! existing wire types/values; it is not an Android impersonation profile.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum QqProtocolProfile {
    Web,
    Desktop,
}

impl QqProtocolProfile {
    pub(crate) const fn user_agent(self) -> &'static str {
        // Preserve the previous transport default, not a new official UA.
        match self {
            Self::Web | Self::Desktop => concat!("flutterustmusic/", env!("CARGO_PKG_VERSION")),
        }
    }
    pub(crate) const fn referer(self) -> &'static str {
        match self {
            Self::Web | Self::Desktop => "https://y.qq.com/",
        }
    }
}

// Keep distinct capability presets. Sharing a profile does not make ct/cv
// interchangeable or justify retrying another profile after risk/rejection.
pub(crate) const WEB_MODERN_VERSION: u32 = 13_020_508;
pub(crate) const WEB_MODERN_TYPE: &str = "11";
pub(crate) const WEB_APP_ID: &str = "qqmusic";
pub(crate) const WEB_LIBRARY_VERSION: u32 = 4_747_474;
pub(crate) const WEB_PUBLIC_TYPE: u32 = 24;
pub(crate) const WEB_RECENT_TYPE: u32 = 11;
pub(crate) const WEB_LEGACY_TYPE: u32 = 20;
pub(crate) const WEB_LEGACY_VERSION: u32 = 1770;
pub(crate) const WEB_LEGACY_PLATFORM: &str = "wk_v17";
pub(crate) const WEB_JSON_PLATFORM: &str = "yqq.json";
pub(crate) const WEB_PLATFORM: &str = "yqq";
pub(crate) const DESKTOP_TYPE: u32 = 19;
pub(crate) const DESKTOP_TYPE_TEXT: &str = "19";
pub(crate) const DESKTOP_TYPE_BYTE: u8 = 19;
pub(crate) const DESKTOP_SEARCH_VERSION: &str = "1859";
pub(crate) const DESKTOP_MEDIA_PLATFORM: &str = "20";
pub(crate) const DESKTOP_COMPAT_VERSION: u32 = 0;
pub(crate) const DESKTOP_COMPAT_VERSION_BYTE: u8 = 0;
pub(crate) const WEB_PUBLIC_VERSION: u32 = 0;

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pre_extraction_wire_constants_are_unchanged() {
        assert_eq!(
            (WEB_MODERN_VERSION, WEB_MODERN_TYPE, WEB_APP_ID),
            (13_020_508, "11", "qqmusic")
        );
        assert_eq!(
            (
                DESKTOP_TYPE,
                DESKTOP_TYPE_TEXT,
                DESKTOP_SEARCH_VERSION,
                DESKTOP_MEDIA_PLATFORM
            ),
            (19, "19", "1859", "20")
        );
        assert_eq!(
            (
                WEB_LIBRARY_VERSION,
                WEB_PUBLIC_TYPE,
                WEB_LEGACY_TYPE,
                WEB_LEGACY_VERSION
            ),
            (4_747_474, 24, 20, 1770)
        );
        assert_eq!(QqProtocolProfile::Web.referer(), "https://y.qq.com/");
        assert_eq!(
            QqProtocolProfile::Desktop.user_agent(),
            concat!("flutterustmusic/", env!("CARGO_PKG_VERSION"))
        );
    }
}
