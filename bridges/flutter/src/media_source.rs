use provider_api::MediaSourceCoordinator;
use provider_qqmusic::QqMusicMediaSourceResolver;
use qqmusic_client::ReqwestTransport;

use crate::api::authentication::native_qq_music_provider;

pub(crate) type NativeMediaSourceCoordinator =
    MediaSourceCoordinator<QqMusicMediaSourceResolver<'static, ReqwestTransport>>;

pub(crate) fn native_media_source_coordinator() -> Result<NativeMediaSourceCoordinator, ()> {
    let provider = native_qq_music_provider()?;
    Ok(MediaSourceCoordinator::new(
        provider.media_source_resolver(),
    ))
}
