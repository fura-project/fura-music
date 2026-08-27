//! Raw QQ Music protocol boundary.
//!
//! Endpoint-specific requests and response models are added only with protocol
//! evidence. The client owns native HTTPS transport without exposing it to
//! providers or Flutter.

mod album;
mod album_details;
mod album_search;
mod artist;
mod artist_albums;
mod artist_search;
mod comments;
mod credential;
mod credential_verification;
mod favorite_albums;
mod favorite_artists;
mod favorite_playlists;
mod lyrics;
mod media_resolution;
mod music_video;
mod new_albums;
mod new_songs;
mod owned_playlists;
mod playlist_containers;
mod playlist_detail;
mod playlist_search;
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
pub use playlist_containers::{QqMusicCreatePlaylistError, QqMusicCreatedPlaylist};
pub use playlist_detail::{
    PlaylistDetailTrackField, QqMusicAlbumSummary, QqMusicArtistSummary,
    QqMusicPlaylistDetailError, QqMusicPlaylistTracksPage, QqMusicTrackSummary,
};
pub use playlist_search::{
    PlaylistSearchField, QqMusicPlaylistSearchError, QqMusicPlaylistSearchPage,
    QqMusicPlaylistSearchSummary,
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
    InvalidWechatQrLoginPolicy, WechatQrLoginCancellation, WechatQrLoginCoordinator,
    WechatQrLoginError, WechatQrLoginPolicy, WechatQrLoginProgress, WechatQrLoginSession,
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

#[cfg(test)]
mod tests {
    use super::QqMusicClient;

    #[test]
    fn client_owns_but_does_not_hide_transport_lifecycle() {
        let client = QqMusicClient::new("offline-transport");
        assert_eq!(client.transport(), &"offline-transport");
        assert_eq!(client.into_transport(), "offline-transport");
    }
}
