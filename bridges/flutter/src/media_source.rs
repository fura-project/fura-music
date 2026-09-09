use crate::api::authentication::native_qq_music_provider;
use crate::native_netease::native_netease_provider;
use music_domain::{AudioQuality, ResolvedMediaSource, TrackId};
use provider_api::{
    BuiltInMediaSources, BuiltInProvider, MediaResolutionError, MediaSourceCoordinator,
    MediaSourceResolver,
};
use provider_qqmusic::QqMusicMediaSourceResolver;
use qqmusic_client::ReqwestTransport;

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
        let provider =
            native_netease_provider().map_err(|()| MediaResolutionError::CoreUnavailable)?;
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
