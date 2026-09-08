use crate::api::authentication::native_qq_music_provider;
use netease_client::{HttpsTransport, NeteaseClient};
use provider_api::{BuiltInMediaSources, MediaSourceCoordinator};
use provider_netease::{NeteaseMediaSourceResolver, NeteaseProvider};
use provider_qqmusic::QqMusicMediaSourceResolver;
use qqmusic_client::ReqwestTransport;
use std::sync::OnceLock;

pub(crate) type NativeMediaSourceCoordinator = MediaSourceCoordinator<
    BuiltInMediaSources<
        QqMusicMediaSourceResolver<'static, ReqwestTransport>,
        NeteaseMediaSourceResolver<'static, HttpsTransport>,
    >,
>;

pub(crate) fn native_media_source_coordinator() -> Result<NativeMediaSourceCoordinator, ()> {
    // App-lifetime static composition, matching the existing QQ lifetime. No account is loaded.
    static NETEASE: OnceLock<Result<NeteaseProvider<HttpsTransport>, ()>> = OnceLock::new();
    let netease = NETEASE
        .get_or_init(|| {
            HttpsTransport::new()
                .map(|transport| NeteaseProvider::new(NeteaseClient::new(transport)))
                .map_err(|_| ())
        })
        .as_ref()
        .map_err(|()| ())?;
    let qq = native_qq_music_provider()?;
    Ok(MediaSourceCoordinator::new(BuiltInMediaSources::new(
        qq.media_source_resolver(),
        netease.media_source_resolver(),
    )))
}
