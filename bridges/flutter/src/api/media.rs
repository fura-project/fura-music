use std::fmt;
use std::future::Future;
use std::sync::atomic::{AtomicBool, Ordering};

use music_domain::{AudioFormat, AudioQuality, ResolvedMediaSource as DomainResolvedMediaSource};
use provider_api::MediaResolutionError;
use tokio::sync::Notify;

use super::domain_track_id;
use crate::media_source::native_media_source_coordinator;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MediaFormat {
    Mp3,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MediaQuality {
    Standard,
    High,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MediaQualityPreference {
    Standard,
    High,
}

/// Short-lived playback input. The URI can contain authorization material and
/// is available to the playback edge, but never to Rust diagnostics.
#[derive(Clone, Eq, PartialEq)]
pub struct ResolvedMediaSource {
    pub uri: String,
    pub format: MediaFormat,
    pub quality: MediaQuality,
    pub valid_for_seconds: u32,
}

impl fmt::Debug for ResolvedMediaSource {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ResolvedMediaSource")
            .field("uri", &"[REDACTED]")
            .field("format", &self.format)
            .field("quality", &self.quality)
            .field("valid_for_seconds", &self.valid_for_seconds)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MediaResolutionFailure {
    CoreUnavailable,
    AuthenticationRequired,
    CredentialRejected,
    Unavailable,
    Network,
    ServiceUnavailable,
    InvalidResponse,
    Replaced,
    Cancelled,
    AlreadyRunning,
}

#[derive(Clone, Eq, PartialEq)]
pub struct MediaResolution {
    pub source: Option<ResolvedMediaSource>,
    pub failure: Option<MediaResolutionFailure>,
}

impl fmt::Debug for MediaResolution {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("MediaResolution")
            .field("has_source", &self.source.is_some())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use media resolution. The provider-owned track
/// identity is retained for routing and redacted from diagnostics. The
/// preference is non-secret and the returned source reports actual quality.
#[flutter_rust_bridge::frb(opaque)]
pub struct MediaResolutionHandle {
    provider_id: String,
    opaque_track_id: String,
    preferred_quality: MediaQualityPreference,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for MediaResolutionHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("MediaResolutionHandle")
            .field("provider_id", &self.provider_id)
            .field("opaque_track_id", &"[REDACTED]")
            .field("preferred_quality", &self.preferred_quality)
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl MediaResolutionHandle {
    pub async fn run(&self) -> MediaResolution {
        if !self.active.load(Ordering::SeqCst) {
            return failed_resolution(MediaResolutionFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_resolution(MediaResolutionFailure::AlreadyRunning);
        }

        let outcome = match domain_track_id(&self.provider_id, &self.opaque_track_id) {
            Ok(track_id) => match native_media_source_coordinator() {
                Ok(coordinator) => {
                    let preferred_quality = match self.preferred_quality {
                        MediaQualityPreference::Standard => AudioQuality::Standard,
                        MediaQualityPreference::High => AudioQuality::High,
                    };
                    self.await_resolution(coordinator.resolve_media(track_id, preferred_quality))
                        .await
                }
                Err(()) => failed_resolution(MediaResolutionFailure::CoreUnavailable),
            },
            Err(()) => failed_resolution(MediaResolutionFailure::InvalidResponse),
        };
        self.running.store(false, Ordering::SeqCst);
        self.active.store(false, Ordering::SeqCst);
        outcome
    }

    async fn await_resolution<F>(&self, resolution: F) -> MediaResolution
    where
        F: Future<Output = Result<DomainResolvedMediaSource, MediaResolutionError>> + Send,
    {
        tokio::select! {
            () = self.cancelled.notified() => {
                failed_resolution(MediaResolutionFailure::Cancelled)
            }
            result = resolution => {
                if self.active.load(Ordering::SeqCst) {
                    map_resolution(result)
                } else {
                    failed_resolution(MediaResolutionFailure::Cancelled)
                }
            }
        }
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
pub fn begin_media_resolution(
    provider_id: String,
    opaque_track_id: String,
    preferred_quality: MediaQualityPreference,
) -> MediaResolutionHandle {
    MediaResolutionHandle {
        provider_id,
        opaque_track_id,
        preferred_quality,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_resolution(
    result: Result<DomainResolvedMediaSource, MediaResolutionError>,
) -> MediaResolution {
    match result {
        Ok(source) => MediaResolution {
            source: Some(ResolvedMediaSource {
                uri: source.uri().to_owned(),
                format: match source.format() {
                    AudioFormat::Mp3 => MediaFormat::Mp3,
                },
                quality: match source.quality() {
                    AudioQuality::Standard => MediaQuality::Standard,
                    AudioQuality::High => MediaQuality::High,
                },
                valid_for_seconds: source.valid_for_seconds(),
            }),
            failure: None,
        },
        Err(error) => failed_resolution(map_error(error)),
    }
}

const fn failed_resolution(failure: MediaResolutionFailure) -> MediaResolution {
    MediaResolution {
        source: None,
        failure: Some(failure),
    }
}

const fn map_error(error: MediaResolutionError) -> MediaResolutionFailure {
    match error {
        MediaResolutionError::AuthenticationRequired => {
            MediaResolutionFailure::AuthenticationRequired
        }
        MediaResolutionError::CredentialRejected => MediaResolutionFailure::CredentialRejected,
        MediaResolutionError::Unavailable => MediaResolutionFailure::Unavailable,
        MediaResolutionError::Network => MediaResolutionFailure::Network,
        MediaResolutionError::ServiceUnavailable => MediaResolutionFailure::ServiceUnavailable,
        MediaResolutionError::InvalidResponse => MediaResolutionFailure::InvalidResponse,
        MediaResolutionError::CoreUnavailable => MediaResolutionFailure::CoreUnavailable,
        MediaResolutionError::Replaced => MediaResolutionFailure::Replaced,
    }
}

#[cfg(test)]
mod tests {
    use std::future::pending;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicBool, Ordering};

    use music_domain::{AudioFormat, AudioQuality, ProviderId, ResolvedMediaSource, TrackId};
    use provider_api::MediaResolutionError;
    use tokio::sync::Notify;

    use super::{
        MediaFormat, MediaQuality, MediaQualityPreference, MediaResolutionFailure,
        begin_media_resolution, map_error, map_resolution,
    };

    #[test]
    fn maps_source_without_exposing_uri_or_identity_in_diagnostics() {
        let track_id = TrackId::new(
            ProviderId::new("qq-music").expect("provider"),
            "track:41001:0:1:private-mid",
        )
        .expect("track ID");
        let mapped = map_resolution(Ok(ResolvedMediaSource::new(
            track_id,
            "http://audio.example.test/source.mp3?vkey=private",
            AudioFormat::Mp3,
            AudioQuality::Standard,
            7_200,
        )
        .expect("source")));

        let source = mapped.source.as_ref().expect("mapped source");
        assert_eq!(source.format, MediaFormat::Mp3);
        assert_eq!(source.quality, MediaQuality::Standard);
        assert_eq!(source.valid_for_seconds, 7_200);
        assert!(source.uri.contains("vkey=private"));
        let debug = format!("{mapped:?} {source:?}");
        assert!(!debug.contains("audio.example"));
        assert!(!debug.contains("vkey"));
        assert!(!debug.contains("41001"));

        let high = map_resolution(Ok(ResolvedMediaSource::new(
            TrackId::new(
                ProviderId::new("qq-music").expect("provider"),
                "track:41001:0:1:private-mid",
            )
            .expect("track ID"),
            "http://audio.example.test/high.mp3?vkey=private",
            AudioFormat::Mp3,
            AudioQuality::High,
            7_200,
        )
        .expect("high source")));
        assert_eq!(
            high.source.expect("mapped high source").quality,
            MediaQuality::High
        );
    }

    #[test]
    fn maps_every_provider_failure_precisely() {
        let cases = [
            (
                MediaResolutionError::AuthenticationRequired,
                MediaResolutionFailure::AuthenticationRequired,
            ),
            (
                MediaResolutionError::CredentialRejected,
                MediaResolutionFailure::CredentialRejected,
            ),
            (
                MediaResolutionError::Unavailable,
                MediaResolutionFailure::Unavailable,
            ),
            (
                MediaResolutionError::Network,
                MediaResolutionFailure::Network,
            ),
            (
                MediaResolutionError::ServiceUnavailable,
                MediaResolutionFailure::ServiceUnavailable,
            ),
            (
                MediaResolutionError::InvalidResponse,
                MediaResolutionFailure::InvalidResponse,
            ),
            (
                MediaResolutionError::CoreUnavailable,
                MediaResolutionFailure::CoreUnavailable,
            ),
            (
                MediaResolutionError::Replaced,
                MediaResolutionFailure::Replaced,
            ),
        ];
        for (input, expected) in cases {
            assert_eq!(map_error(input), expected);
        }
    }

    #[tokio::test]
    async fn cancellation_is_exact_terminal_and_drops_in_flight_resolution() {
        struct DropMarker(Arc<AtomicBool>);

        impl Drop for DropMarker {
            fn drop(&mut self) {
                self.0.store(true, Ordering::SeqCst);
            }
        }

        let handle = begin_media_resolution(
            "qq-music".into(),
            "track:41001:0:1:private-mid".into(),
            MediaQualityPreference::High,
        );
        let started = Arc::new(Notify::new());
        let dropped = Arc::new(AtomicBool::new(false));
        let resolution_started = Arc::clone(&started);
        let marker = DropMarker(Arc::clone(&dropped));
        let pending_resolution = async move {
            let _marker = marker;
            resolution_started.notify_one();
            pending::<Result<ResolvedMediaSource, MediaResolutionError>>().await
        };
        let cancel = async {
            started.notified().await;
            assert!(handle.cancel());
            assert!(!handle.cancel());
        };

        let (outcome, ()) = tokio::join!(handle.await_resolution(pending_resolution), cancel);

        assert_eq!(outcome.failure, Some(MediaResolutionFailure::Cancelled));
        assert!(!handle.is_active());
        assert!(dropped.load(Ordering::SeqCst));
        assert!(!format!("{handle:?}").contains("41001"));
    }

    #[tokio::test]
    async fn concurrent_and_terminal_use_remain_explicit() {
        let handle = begin_media_resolution(
            "qq-music".into(),
            "track:41001:0:1:private-mid".into(),
            MediaQualityPreference::Standard,
        );

        handle.running.store(true, Ordering::SeqCst);
        assert_eq!(
            handle.run().await.failure,
            Some(MediaResolutionFailure::AlreadyRunning)
        );
        assert!(handle.is_active());

        handle.running.store(false, Ordering::SeqCst);
        assert!(handle.cancel());
        assert_eq!(
            handle.run().await.failure,
            Some(MediaResolutionFailure::Cancelled)
        );
        assert!(!handle.is_active());
    }
}
