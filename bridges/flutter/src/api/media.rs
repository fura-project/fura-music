use std::fmt;
use std::future::Future;
use std::sync::atomic::{AtomicBool, Ordering};

use music_domain::{AudioFormat, AudioQuality, ResolvedMediaSource};
use provider_api::{MediaResolutionError, MediaResolutionProvider};
use tokio::sync::Notify;

use super::{authentication::native_qq_music_provider, domain_track_id};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicMediaFormat {
    Mp3,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicMediaQuality {
    Standard,
}

/// Short-lived playback input. The URI can contain authorization material and
/// is available to the playback edge, but never to Rust diagnostics.
#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicResolvedMediaSource {
    pub uri: String,
    pub format: QqMusicMediaFormat,
    pub quality: QqMusicMediaQuality,
    pub valid_for_seconds: u32,
}

impl fmt::Debug for QqMusicResolvedMediaSource {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicResolvedMediaSource")
            .field("uri", &"[REDACTED]")
            .field("format", &self.format)
            .field("quality", &self.quality)
            .field("valid_for_seconds", &self.valid_for_seconds)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicMediaResolutionFailure {
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
pub struct QqMusicMediaResolution {
    pub source: Option<QqMusicResolvedMediaSource>,
    pub failure: Option<QqMusicMediaResolutionFailure>,
}

impl fmt::Debug for QqMusicMediaResolution {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicMediaResolution")
            .field("has_source", &self.source.is_some())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use standard-media resolution. The provider-owned
/// track identity is retained for routing and redacted from diagnostics.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicMediaResolutionHandle {
    provider_id: String,
    opaque_track_id: String,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicMediaResolutionHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicMediaResolutionHandle")
            .field("provider_id", &self.provider_id)
            .field("opaque_track_id", &"[REDACTED]")
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicMediaResolutionHandle {
    pub async fn run(&self) -> QqMusicMediaResolution {
        if !self.active.load(Ordering::SeqCst) {
            return failed_resolution(QqMusicMediaResolutionFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_resolution(QqMusicMediaResolutionFailure::AlreadyRunning);
        }

        let outcome = match domain_track_id(&self.provider_id, &self.opaque_track_id) {
            Ok(track_id) => match native_qq_music_provider() {
                Ok(provider) => {
                    self.await_resolution(provider.resolve_standard_media(track_id))
                        .await
                }
                Err(()) => failed_resolution(QqMusicMediaResolutionFailure::CoreUnavailable),
            },
            Err(()) => failed_resolution(QqMusicMediaResolutionFailure::InvalidResponse),
        };
        self.running.store(false, Ordering::SeqCst);
        self.active.store(false, Ordering::SeqCst);
        outcome
    }

    async fn await_resolution<F>(&self, resolution: F) -> QqMusicMediaResolution
    where
        F: Future<Output = Result<ResolvedMediaSource, MediaResolutionError>> + Send,
    {
        tokio::select! {
            () = self.cancelled.notified() => {
                failed_resolution(QqMusicMediaResolutionFailure::Cancelled)
            }
            result = resolution => {
                if self.active.load(Ordering::SeqCst) {
                    map_resolution(result)
                } else {
                    failed_resolution(QqMusicMediaResolutionFailure::Cancelled)
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
pub fn begin_qq_music_media_resolution(
    provider_id: String,
    opaque_track_id: String,
) -> QqMusicMediaResolutionHandle {
    QqMusicMediaResolutionHandle {
        provider_id,
        opaque_track_id,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_resolution(
    result: Result<ResolvedMediaSource, MediaResolutionError>,
) -> QqMusicMediaResolution {
    match result {
        Ok(source) => QqMusicMediaResolution {
            source: Some(QqMusicResolvedMediaSource {
                uri: source.uri().to_owned(),
                format: match source.format() {
                    AudioFormat::Mp3 => QqMusicMediaFormat::Mp3,
                },
                quality: match source.quality() {
                    AudioQuality::Standard => QqMusicMediaQuality::Standard,
                },
                valid_for_seconds: source.valid_for_seconds(),
            }),
            failure: None,
        },
        Err(error) => failed_resolution(map_error(error)),
    }
}

const fn failed_resolution(failure: QqMusicMediaResolutionFailure) -> QqMusicMediaResolution {
    QqMusicMediaResolution {
        source: None,
        failure: Some(failure),
    }
}

const fn map_error(error: MediaResolutionError) -> QqMusicMediaResolutionFailure {
    match error {
        MediaResolutionError::AuthenticationRequired => {
            QqMusicMediaResolutionFailure::AuthenticationRequired
        }
        MediaResolutionError::CredentialRejected => {
            QqMusicMediaResolutionFailure::CredentialRejected
        }
        MediaResolutionError::Unavailable => QqMusicMediaResolutionFailure::Unavailable,
        MediaResolutionError::Network => QqMusicMediaResolutionFailure::Network,
        MediaResolutionError::ServiceUnavailable => {
            QqMusicMediaResolutionFailure::ServiceUnavailable
        }
        MediaResolutionError::InvalidResponse => QqMusicMediaResolutionFailure::InvalidResponse,
        MediaResolutionError::CoreUnavailable => QqMusicMediaResolutionFailure::CoreUnavailable,
        MediaResolutionError::Replaced => QqMusicMediaResolutionFailure::Replaced,
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
        QqMusicMediaFormat, QqMusicMediaQuality, QqMusicMediaResolutionFailure,
        begin_qq_music_media_resolution, map_error, map_resolution,
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
        assert_eq!(source.format, QqMusicMediaFormat::Mp3);
        assert_eq!(source.quality, QqMusicMediaQuality::Standard);
        assert_eq!(source.valid_for_seconds, 7_200);
        assert!(source.uri.contains("vkey=private"));
        let debug = format!("{mapped:?} {source:?}");
        assert!(!debug.contains("audio.example"));
        assert!(!debug.contains("vkey"));
        assert!(!debug.contains("41001"));
    }

    #[test]
    fn maps_every_provider_failure_precisely() {
        let cases = [
            (
                MediaResolutionError::AuthenticationRequired,
                QqMusicMediaResolutionFailure::AuthenticationRequired,
            ),
            (
                MediaResolutionError::CredentialRejected,
                QqMusicMediaResolutionFailure::CredentialRejected,
            ),
            (
                MediaResolutionError::Unavailable,
                QqMusicMediaResolutionFailure::Unavailable,
            ),
            (
                MediaResolutionError::Network,
                QqMusicMediaResolutionFailure::Network,
            ),
            (
                MediaResolutionError::ServiceUnavailable,
                QqMusicMediaResolutionFailure::ServiceUnavailable,
            ),
            (
                MediaResolutionError::InvalidResponse,
                QqMusicMediaResolutionFailure::InvalidResponse,
            ),
            (
                MediaResolutionError::CoreUnavailable,
                QqMusicMediaResolutionFailure::CoreUnavailable,
            ),
            (
                MediaResolutionError::Replaced,
                QqMusicMediaResolutionFailure::Replaced,
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

        let handle = begin_qq_music_media_resolution(
            "qq-music".into(),
            "track:41001:0:1:private-mid".into(),
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

        assert_eq!(
            outcome.failure,
            Some(QqMusicMediaResolutionFailure::Cancelled)
        );
        assert!(!handle.is_active());
        assert!(dropped.load(Ordering::SeqCst));
        assert!(!format!("{handle:?}").contains("41001"));
    }
}
