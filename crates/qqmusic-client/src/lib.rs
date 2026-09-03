//! Raw QQ Music protocol boundary.
//!
//! Endpoint-specific requests and response models are added only with protocol
//! evidence. The client owns native HTTPS transport without exposing it to
//! providers or Flutter.

use reqwest::Url;

const MAX_IMAGE_URI_BYTES: usize = 4 * 1024;

mod album;
mod album_details;
mod album_favorites;
mod album_search;
mod artist;
mod artist_albums;
mod artist_search;
mod comments;
mod credential;
mod credential_verification;
mod daily_recommendation;
mod favorite_albums;
mod favorite_artists;
mod favorite_playlists;
mod login_credential;
mod lyrics;
mod media_resolution;
mod music_video;
mod new_albums;
mod new_songs;
mod owned_playlists;
mod personalized_tracks;
mod playlist_containers;
mod playlist_detail;
mod playlist_search;
mod protocol_strategy;
mod qq_qr;
mod qq_quick_login;
mod qrc_cipher;
mod radar_recommendations;
mod rankings;
mod recommendations;
mod search;
mod track_likes;
mod transport;
mod wechat_exchange;
mod wechat_login;
mod wechat_qr;

pub use album::{AlbumTrackField, QqMusicAlbumTrackPage, QqMusicAlbumTracksError};
pub use album_details::{AlbumDetailField, QqMusicAlbumDetails, QqMusicAlbumDetailsError};
pub use album_favorites::{QqMusicAlbumFavoriteError, QqMusicAlbumFavoriteState};
pub use album_search::{AlbumSearchField, QqMusicAlbumSearchError, QqMusicAlbumSearchPage};
pub use artist::{ArtistTrackField, QqMusicArtistTrackPage, QqMusicArtistTracksError};
pub use artist_albums::{ArtistAlbumField, QqMusicArtistAlbumPage, QqMusicArtistAlbumsError};
pub use artist_search::{ArtistSearchField, QqMusicArtistSearchError, QqMusicArtistSearchPage};
pub use comments::{
    CommentField, CommentSection, QqMusicTrackComment, QqMusicTrackCommentsError,
    QqMusicTrackCommentsPage,
};
pub use credential::{
    Credential, CredentialExpiry, CredentialPersistenceError, CredentialRestorePlan,
    CredentialSessionSecrets, InvalidCredential, InvalidCredentialExpiry, InvalidLoginType,
    LocalCredentialValidity, LoginType,
};
pub use credential_verification::{CredentialVerificationError, QqMusicAccountSummary};
pub use daily_recommendation::{
    DailyRecommendationField, PersonalizedPlaylistField, QqMusicDailyRecommendation,
    QqMusicDailyRecommendationError, QqMusicPersonalizedPlaylist,
    QqMusicPersonalizedPlaylistsError,
};
pub use favorite_albums::{
    FavoriteAlbumField, QqMusicFavoriteAlbumsError, QqMusicFavoriteAlbumsPage,
};
pub use favorite_artists::{
    FavoriteArtistField, QqMusicFavoriteArtistsError, QqMusicFavoriteArtistsPage,
};
pub use favorite_playlists::{
    FavoritePlaylistField, QqMusicFavoritePlaylist, QqMusicFavoritePlaylistsError,
    QqMusicFavoritePlaylistsPage,
};
pub use login_credential::LoginCredentialError;
pub use lyrics::{
    QqMusicAuxiliaryLyricLine, QqMusicLyricDocumentField, QqMusicLyricTrack, QqMusicLyrics,
    QqMusicLyricsError, QqMusicTimedLyricLine, QqMusicTimedLyricSegment,
};
pub use media_resolution::{
    MediaProtocolPhase, MediaResponseField, QqMusicAudioQuality, QqMusicCdnDispatch,
    QqMusicMediaError, QqMusicMediaSource,
};
pub use music_video::{
    MusicVideoProtocolPhase, MusicVideoResponseField, QqMusicMusicVideoQuality,
    QqMusicTrackMusicVideo, QqMusicTrackMusicVideoError,
};
pub use new_albums::{
    NewAlbumField, QqMusicNewAlbumArea, QqMusicNewAlbumPage, QqMusicNewAlbumRelease,
    QqMusicNewAlbumsError,
};
pub use new_songs::{
    NewSongTrackField, QqMusicNewSongCategory, QqMusicNewSongCollection, QqMusicNewSongsError,
};
pub use owned_playlists::{
    OwnedPlaylistField, QqMusicOwnedPlaylist, QqMusicOwnedPlaylists, QqMusicOwnedPlaylistsError,
};
pub use personalized_tracks::{
    PersonalizedTrackField, QqMusicPersonalizedTracks, QqMusicPersonalizedTracksError,
    QqMusicRelatedTracks, QqMusicRelatedTracksError,
};
pub use playlist_containers::{
    QqMusicCreatePlaylistError, QqMusicCreatedPlaylist, QqMusicDeletePlaylistError,
};
pub use playlist_detail::{
    PlaylistDetailTrackField, QqMusicAlbumSummary, QqMusicArtistSummary,
    QqMusicPlaylistDetailError, QqMusicPlaylistTracksPage, QqMusicTrackSummary,
};
pub use playlist_search::{
    PlaylistSearchField, QqMusicPlaylistSearchError, QqMusicPlaylistSearchPage,
    QqMusicPlaylistSearchSummary,
};
pub use qq_qr::{QqQrAuthorization, QqQrError, QqQrPollResult, QqQrSession};
pub use qq_quick_login::{
    QqDesktopQuickLoginAccount, QqDesktopQuickLoginError, QqDesktopQuickLoginSession,
};
pub use radar_recommendations::{QqMusicRadarError, QqMusicRadarTrackPage, RadarTrackField};
pub use rankings::{
    QqMusicRankingGroup, QqMusicRankingSummary, QqMusicRankingTrackPage, QqMusicRankingsError,
    RankingField, RankingGroupField, RankingTrackField,
};
pub use recommendations::{
    QqMusicRecommendedPlaylist, QqMusicRecommendedPlaylistsError, QqMusicRecommendedPlaylistsPage,
    RecommendedPlaylistField,
};
pub use search::{QqMusicSearchError, QqMusicTrackSearchPage, SearchTrackField};
pub use track_likes::{
    QqMusicPlaylistTrackError, QqMusicPlaylistTrackState, QqMusicTrackLikeError,
    QqMusicTrackLikeState,
};
pub use transport::{
    HttpMethod, HttpRequest, HttpResponse, HttpTransport, ReqwestTransport, ReqwestTransportError,
};
pub use wechat_exchange::WechatCredentialExchangeError;
pub use wechat_login::{
    InvalidWechatQrLoginPolicy, QrLoginChannel, WechatQrLoginCancellation,
    WechatQrLoginCoordinator, WechatQrLoginError, WechatQrLoginPolicy, WechatQrLoginProgress,
    WechatQrLoginSession,
};
pub use wechat_qr::{
    QrImage, QrImageMediaType, WechatAuthorizationCode, WechatQrError, WechatQrPollResult,
    WechatQrSession,
};

/// A QQ Music protocol client parameterized by its transport implementation.
#[derive(Debug)]
pub struct QqMusicClient<T> {
    transport: T,
}

impl<T> QqMusicClient<T> {
    #[must_use]
    pub const fn new(transport: T) -> Self {
        Self { transport }
    }

    #[must_use]
    pub const fn transport(&self) -> &T {
        &self.transport
    }

    #[must_use]
    pub fn into_transport(self) -> T {
        self.transport
    }
}

/// Keeps optional display artwork from turning an otherwise valid catalog row
/// into a protocol failure. QQ still returns cleartext or protocol-relative
/// artwork on its evidenced image hosts even though the same resources are
/// served over HTTPS.
fn normalized_https_image_uri(value: Option<String>) -> Option<String> {
    let value = value?.trim().to_owned();
    if value.is_empty() || value.len() > MAX_IMAGE_URI_BYTES {
        return None;
    }
    let protocol_relative = value.starts_with("//");
    let normalized = if protocol_relative {
        format!("https:{value}")
    } else {
        value
    };
    let mut url = Url::parse(&normalized).ok()?;
    url.host()?;
    if !url.username().is_empty() || url.password().is_some() {
        return None;
    }
    match url.scheme() {
        "https" if !protocol_relative || url.host_str().is_some_and(is_evidenced_qq_image_host) => {
            Some(normalized)
        }
        "http" if url.host_str().is_some_and(is_evidenced_qq_image_host) => {
            url.set_scheme("https").ok()?;
            Some(url.into())
        }
        _ => None,
    }
}

fn is_evidenced_qq_image_host(host: &str) -> bool {
    matches!(host, "qpic.y.qq.com" | "p.qpic.cn" | "y.gtimg.cn")
}

#[cfg(test)]
mod tests {
    use super::{QqMusicClient, normalized_https_image_uri};

    #[test]
    fn client_owns_but_does_not_hide_transport_lifecycle() {
        let client = QqMusicClient::new("offline-transport");
        assert_eq!(client.transport(), &"offline-transport");
        assert_eq!(client.into_transport(), "offline-transport");
    }

    #[test]
    fn optional_artwork_is_https_or_absent() {
        assert_eq!(
            normalized_https_image_uri(Some(
                " http://qpic.y.qq.com/music_cover/fixture/300?n=1 ".into()
            )),
            Some("https://qpic.y.qq.com/music_cover/fixture/300?n=1".into())
        );
        assert_eq!(
            normalized_https_image_uri(Some("http://p.qpic.cn/music_cover/fixture/300?n=1".into())),
            Some("https://p.qpic.cn/music_cover/fixture/300?n=1".into())
        );
        assert_eq!(
            normalized_https_image_uri(Some("//y.gtimg.cn/music/photo_new/fixture.jpg?n=1".into())),
            Some("https://y.gtimg.cn/music/photo_new/fixture.jpg?n=1".into())
        );
        assert_eq!(
            normalized_https_image_uri(Some("https://example.invalid/cover.jpg".into())),
            Some("https://example.invalid/cover.jpg".into())
        );
        assert_eq!(
            normalized_https_image_uri(Some("http://example.invalid/cover.jpg".into())),
            None
        );
        assert_eq!(
            normalized_https_image_uri(Some(
                "http://p.qpic.cn.example.invalid/music_cover/fixture/300".into()
            )),
            None
        );
        assert_eq!(
            normalized_https_image_uri(Some("//example.invalid/cover.jpg".into())),
            None
        );
        assert_eq!(
            normalized_https_image_uri(Some(
                "https://user:secret@example.invalid/cover.jpg".into()
            )),
            None
        );
        assert_eq!(normalized_https_image_uri(Some("   ".into())), None);
        assert_eq!(normalized_https_image_uri(None), None);
    }
}
