use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

use music_domain::{MusicVideo, MusicVideoQuality};
use provider_api::{MusicVideoError, TrackMusicVideoProvider};
use tokio::sync::Notify;

use super::authentication::native_qq_music_provider;
use super::domain_track_id;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TrackMusicVideoLoadFailure {
    CoreUnavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    SourceUnavailable,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TrackMusicVideoQuality {
    FullHd,
    Hd,
    Sd,
    Low,
}

#[derive(Clone, Eq, PartialEq)]
pub struct TrackMusicVideoSummary {
    pub provider_id: String,
    pub opaque_id: String,
    pub title: String,
    pub artist_names: Vec<String>,
    pub artwork_uri: Option<String>,
    pub duration_seconds: Option<u32>,
    pub source_uri: String,
    pub quality: TrackMusicVideoQuality,
}

impl fmt::Debug for TrackMusicVideoSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("TrackMusicVideoSummary")
            .field("provider_id", &self.provider_id)
            .field("opaque_id", &"[REDACTED]")
            .field("title", &"[REDACTED]")
            .field("artist_count", &self.artist_names.len())
            .field("has_artwork", &self.artwork_uri.is_some())
            .field("duration_seconds", &self.duration_seconds)
            .field("source_uri", &"[REDACTED]")
            .field("quality", &self.quality)
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct TrackMusicVideoLoad {
    pub music_video: Option<TrackMusicVideoSummary>,
    pub failure: Option<TrackMusicVideoLoadFailure>,
}

impl fmt::Debug for TrackMusicVideoLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("TrackMusicVideoLoad")
            .field("has_music_video", &self.music_video.is_some())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use lookup of the exact MV associated with a
/// provider-neutral Track identity.
#[flutter_rust_bridge::frb(opaque)]
pub struct TrackMusicVideoLoadHandle {
    provider_id: String,
    opaque_track_id: String,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for TrackMusicVideoLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("TrackMusicVideoLoadHandle")
            .field("provider_id", &self.provider_id)
            .field("opaque_track_id", &"[REDACTED]")
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl TrackMusicVideoLoadHandle {
    pub async fn run(&self) -> TrackMusicVideoLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_load(TrackMusicVideoLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_load(TrackMusicVideoLoadFailure::AlreadyRunning);
        }
        let outcome = match (
            native_qq_music_provider(),
            domain_track_id(&self.provider_id, &self.opaque_track_id),
        ) {
            (Ok(provider), Ok(track_id)) => {
                tokio::select! {
                    () = self.cancelled.notified() => {
                        failed_load(TrackMusicVideoLoadFailure::Cancelled)
                    }
                    result = provider.track_music_video(track_id) => {
                        if self.active.load(Ordering::SeqCst) {
                            map_load(result)
                        } else {
                            failed_load(TrackMusicVideoLoadFailure::Cancelled)
                        }
                    }
                }
            }
            (Err(()), _) => failed_load(TrackMusicVideoLoadFailure::CoreUnavailable),
            (_, Err(())) => failed_load(TrackMusicVideoLoadFailure::InvalidResponse),
        };
        self.running.store(false, Ordering::SeqCst);
        self.active.store(false, Ordering::SeqCst);
        outcome
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) -> bool {
        let was_active = self.active.swap(false, Ordering::SeqCst);
        if was_active {
            self.cancelled.notify_one();
        }
        was_active
    }

    #[flutter_rust_bridge::frb(sync, getter)]
    pub fn is_active(&self) -> bool {
        self.active.load(Ordering::SeqCst)
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn begin_track_music_video_load(
    provider_id: String,
    opaque_track_id: String,
) -> TrackMusicVideoLoadHandle {
    TrackMusicVideoLoadHandle {
        provider_id,
        opaque_track_id,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_load(result: Result<Option<MusicVideo>, MusicVideoError>) -> TrackMusicVideoLoad {
    let video = match result {
        Ok(video) => video,
        Err(error) => return failed_load(map_error(error)),
    };
    TrackMusicVideoLoad {
        music_video: video.as_ref().map(bridge_video),
        failure: None,
    }
}

fn bridge_video(video: &MusicVideo) -> TrackMusicVideoSummary {
    TrackMusicVideoSummary {
        provider_id: video.id().provider().as_str().to_owned(),
        opaque_id: video.id().opaque().to_owned(),
        title: video.title().to_owned(),
        artist_names: video.artist_names().to_vec(),
        artwork_uri: video.artwork_uri().map(str::to_owned),
        duration_seconds: video.duration_seconds(),
        source_uri: video.source().uri().to_owned(),
        quality: match video.source().quality() {
            MusicVideoQuality::FullHd => TrackMusicVideoQuality::FullHd,
            MusicVideoQuality::Hd => TrackMusicVideoQuality::Hd,
            MusicVideoQuality::Sd => TrackMusicVideoQuality::Sd,
            MusicVideoQuality::Low => TrackMusicVideoQuality::Low,
        },
    }
}

const fn failed_load(failure: TrackMusicVideoLoadFailure) -> TrackMusicVideoLoad {
    TrackMusicVideoLoad {
        music_video: None,
        failure: Some(failure),
    }
}

const fn map_error(error: MusicVideoError) -> TrackMusicVideoLoadFailure {
    match error {
        MusicVideoError::Network => TrackMusicVideoLoadFailure::Network,
        MusicVideoError::ServiceUnavailable => TrackMusicVideoLoadFailure::ServiceUnavailable,
        MusicVideoError::InvalidResponse => TrackMusicVideoLoadFailure::InvalidResponse,
        MusicVideoError::SourceUnavailable => TrackMusicVideoLoadFailure::SourceUnavailable,
    }
}

#[cfg(test)]
mod tests {
    use music_domain::{MusicVideo, MusicVideoId, MusicVideoQuality, MusicVideoSource, ProviderId};
    use provider_api::MusicVideoError;

    use super::{
        TrackMusicVideoLoadFailure, TrackMusicVideoQuality, begin_track_music_video_load,
        map_error, map_load,
    };

    fn video() -> MusicVideo {
        MusicVideo::new(
            MusicVideoId::new(
                ProviderId::new("qq-music").expect("provider"),
                "mv:private-id",
            )
            .expect("MV ID"),
            "must-not-leak-title",
            vec!["must-not-leak-artist".into()],
            MusicVideoSource::new(
                "https://example.invalid/private-source.mp4",
                MusicVideoQuality::Hd,
            )
            .expect("source"),
        )
        .expect("MV")
        .with_artwork_uri(Some("https://example.invalid/private-cover.jpg".into()))
        .with_duration_seconds(Some(181))
    }

    #[test]
    fn maps_music_video_without_exposing_identity_or_source() {
        let mapped = map_load(Ok(Some(video())));
        let video = mapped.music_video.as_ref().expect("MV");
        assert_eq!(video.provider_id, "qq-music");
        assert_eq!(video.opaque_id, "mv:private-id");
        assert_eq!(video.quality, TrackMusicVideoQuality::Hd);
        assert_eq!(video.duration_seconds, Some(181));
        assert_eq!(
            video.source_uri,
            "https://example.invalid/private-source.mp4"
        );
        let debug = format!("{mapped:?} {video:?}");
        for private in [
            "private-id",
            "must-not-leak",
            "private-source",
            "private-cover",
        ] {
            assert!(!debug.contains(private));
        }
    }

    #[test]
    fn preserves_truthful_no_mv_and_maps_failures() {
        let no_mv = map_load(Ok(None));
        assert!(no_mv.music_video.is_none());
        assert!(no_mv.failure.is_none());
        assert_eq!(
            map_error(MusicVideoError::SourceUnavailable),
            TrackMusicVideoLoadFailure::SourceUnavailable
        );
        assert_eq!(
            map_error(MusicVideoError::Network),
            TrackMusicVideoLoadFailure::Network
        );
    }

    #[tokio::test]
    async fn cancellation_is_exact_and_terminal() {
        let handle = begin_track_music_video_load(
            "qq-music".into(),
            "track:41001:0:fixtureTrackMid:fixtureFileMid".into(),
        );

        assert!(handle.is_active());
        assert!(handle.cancel());
        assert!(!handle.cancel());
        let result = handle.run().await;
        assert_eq!(result.failure, Some(TrackMusicVideoLoadFailure::Cancelled));
    }
}
