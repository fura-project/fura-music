use crate::api::authentication::native_qq_music_provider;
use music_domain::{AudioQuality, ResolvedMediaSource, TrackId};
use netease_client::{HttpsTransport, NeteaseClient};
use provider_api::{
    BuiltInMediaSources, BuiltInProvider, MediaResolutionError, MediaSourceCoordinator,
    MediaSourceResolver,
};
use provider_netease::NeteaseProvider;
use provider_qqmusic::QqMusicMediaSourceResolver;
use qqmusic_client::ReqwestTransport;
use std::sync::OnceLock;

pub(crate) type NativeMediaSourceCoordinator = MediaSourceCoordinator<
    BuiltInMediaSources<
        QqMusicMediaSourceResolver<'static, ReqwestTransport>,
        NativeNeteaseResolver,
    >,
>;

/// Native static composition only: initialize NetEase HTTPS on its selected route.
/// A NetEase transport initialization failure must not disable existing QQ playback.
pub(crate) struct NativeNeteaseResolver;
impl MediaSourceResolver for NativeNeteaseResolver {
    fn supports(&self, id: &TrackId) -> bool {
        id.provider() == &BuiltInProvider::NetEaseCloudMusic.id()
    }
    async fn resolve_media(
        &self,
        id: TrackId,
        quality: AudioQuality,
    ) -> Result<ResolvedMediaSource, MediaResolutionError> {
        if !self.supports(&id) {
            return Err(MediaResolutionError::Unavailable);
        }
        static NETEASE: OnceLock<Result<NeteaseProvider<HttpsTransport>, ()>> = OnceLock::new();
        let provider = match NETEASE.get_or_init(|| {
            HttpsTransport::new()
                .map(|t| NeteaseProvider::new(NeteaseClient::new(t)))
                .map_err(|_| ())
        }) {
            Ok(provider) => provider,
            Err(()) => return Err(MediaResolutionError::CoreUnavailable),
        };
        provider
            .media_source_resolver()
            .resolve_media(id, quality)
            .await
    }
}
pub(crate) fn native_media_source_coordinator() -> Result<NativeMediaSourceCoordinator, ()> {
    let qq = native_qq_music_provider()?;
    Ok(MediaSourceCoordinator::new(BuiltInMediaSources::new(
        qq.media_source_resolver(),
        NativeNeteaseResolver,
    )))
}
