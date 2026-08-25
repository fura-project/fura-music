use std::fmt;
use std::future::Future;
use std::sync::atomic::{AtomicBool, Ordering};

use music_domain::SynchronizedLyrics;
use provider_api::{LyricsError, LyricsProvider};
use tokio::sync::Notify;

use super::{authentication::native_qq_music_provider, domain_track_id};

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicTimedLyricSegment {
    pub text: String,
    pub start_ms: u32,
    pub duration_ms: u32,
}

impl fmt::Debug for QqMusicTimedLyricSegment {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicTimedLyricSegment")
            .field("text", &"[REDACTED]")
            .field("start_ms", &self.start_ms)
            .field("duration_ms", &self.duration_ms)
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicSynchronizedLyricLine {
    pub text: String,
    pub start_ms: u32,
    pub duration_ms: u32,
    pub segments: Vec<QqMusicTimedLyricSegment>,
    pub translation: Option<String>,
    pub romanization: Option<String>,
}

impl fmt::Debug for QqMusicSynchronizedLyricLine {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicSynchronizedLyricLine")
            .field("text", &"[REDACTED]")
            .field("start_ms", &self.start_ms)
            .field("duration_ms", &self.duration_ms)
            .field("segment_count", &self.segments.len())
            .field("has_translation", &self.translation.is_some())
            .field("has_romanization", &self.romanization.is_some())
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicSynchronizedLyrics {
    pub lines: Vec<QqMusicSynchronizedLyricLine>,
}

impl fmt::Debug for QqMusicSynchronizedLyrics {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicSynchronizedLyrics")
            .field("line_count", &self.lines.len())
            .field(
                "has_word_timing",
                &self.lines.iter().any(|line| !line.segments.is_empty()),
            )
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicLyricLoadFailure {
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
pub struct QqMusicLyricLoad {
    pub lyrics: Option<QqMusicSynchronizedLyrics>,
    pub failure: Option<QqMusicLyricLoadFailure>,
}

impl fmt::Debug for QqMusicLyricLoad {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicLyricLoad")
            .field("has_lyrics", &self.lyrics.is_some())
            .field("failure", &self.failure)
            .finish()
    }
}

/// One cancellable, single-use synchronized-lyric load. Provider-owned track
/// identity is retained only for routing and redacted from diagnostics.
#[flutter_rust_bridge::frb(opaque)]
pub struct QqMusicLyricLoadHandle {
    provider_id: String,
    opaque_track_id: String,
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl fmt::Debug for QqMusicLyricLoadHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicLyricLoadHandle")
            .field("provider_id", &self.provider_id)
            .field("opaque_track_id", &"[REDACTED]")
            .field("active", &self.is_active())
            .field("running", &self.running.load(Ordering::SeqCst))
            .finish()
    }
}

impl QqMusicLyricLoadHandle {
    pub async fn run(&self) -> QqMusicLyricLoad {
        if !self.active.load(Ordering::SeqCst) {
            return failed_load(QqMusicLyricLoadFailure::Cancelled);
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return failed_load(QqMusicLyricLoadFailure::AlreadyRunning);
        }

        let outcome = match domain_track_id(&self.provider_id, &self.opaque_track_id) {
            Ok(track_id) => match native_qq_music_provider() {
                Ok(provider) => self.await_load(provider.lyrics(track_id)).await,
                Err(()) => failed_load(QqMusicLyricLoadFailure::CoreUnavailable),
            },
            Err(()) => failed_load(QqMusicLyricLoadFailure::InvalidResponse),
        };
        self.running.store(false, Ordering::SeqCst);
        self.active.store(false, Ordering::SeqCst);
        outcome
    }

    async fn await_load<F>(&self, load: F) -> QqMusicLyricLoad
    where
        F: Future<Output = Result<SynchronizedLyrics, LyricsError>> + Send,
    {
        tokio::select! {
            () = self.cancelled.notified() => {
                failed_load(QqMusicLyricLoadFailure::Cancelled)
            }
            result = load => {
                if self.active.load(Ordering::SeqCst) {
                    map_load(result)
                } else {
                    failed_load(QqMusicLyricLoadFailure::Cancelled)
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
pub fn begin_qq_music_lyric_load(
    provider_id: String,
    opaque_track_id: String,
) -> QqMusicLyricLoadHandle {
    QqMusicLyricLoadHandle {
        provider_id,
        opaque_track_id,
        active: AtomicBool::new(true),
        running: AtomicBool::new(false),
        cancelled: Notify::new(),
    }
}

fn map_load(result: Result<SynchronizedLyrics, LyricsError>) -> QqMusicLyricLoad {
    match result {
        Ok(lyrics) => QqMusicLyricLoad {
            lyrics: Some(QqMusicSynchronizedLyrics {
                lines: lyrics
                    .lines()
                    .iter()
                    .map(|line| QqMusicSynchronizedLyricLine {
                        text: line.text().to_owned(),
                        start_ms: line.start_ms(),
                        duration_ms: line.duration_ms(),
                        segments: line
                            .segments()
                            .iter()
                            .map(|segment| QqMusicTimedLyricSegment {
                                text: segment.text().to_owned(),
                                start_ms: segment.start_ms(),
                                duration_ms: segment.duration_ms(),
                            })
                            .collect(),
                        translation: line.translation().map(str::to_owned),
                        romanization: line.romanization().map(str::to_owned),
                    })
                    .collect(),
            }),
            failure: None,
        },
        Err(error) => failed_load(map_error(error)),
    }
}

const fn failed_load(failure: QqMusicLyricLoadFailure) -> QqMusicLyricLoad {
    QqMusicLyricLoad {
        lyrics: None,
        failure: Some(failure),
    }
}

const fn map_error(error: LyricsError) -> QqMusicLyricLoadFailure {
    match error {
        LyricsError::AuthenticationRequired => QqMusicLyricLoadFailure::AuthenticationRequired,
        LyricsError::CredentialRejected => QqMusicLyricLoadFailure::CredentialRejected,
        LyricsError::Unavailable => QqMusicLyricLoadFailure::Unavailable,
        LyricsError::Network => QqMusicLyricLoadFailure::Network,
        LyricsError::ServiceUnavailable => QqMusicLyricLoadFailure::ServiceUnavailable,
        LyricsError::InvalidResponse => QqMusicLyricLoadFailure::InvalidResponse,
        LyricsError::Replaced => QqMusicLyricLoadFailure::Replaced,
    }
}

#[cfg(test)]
mod tests {
    use std::future::pending;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicBool, Ordering};

    use music_domain::{
        ProviderId, SynchronizedLyricLine, SynchronizedLyrics, TimedLyricSegment, TrackId,
    };
    use provider_api::LyricsError;
    use tokio::sync::Notify;

    use super::{QqMusicLyricLoadFailure, begin_qq_music_lyric_load, map_error, map_load};

    fn lyrics_fixture() -> SynchronizedLyrics {
        let segment = TimedLyricSegment::new("private segment", 1_000, 400).expect("segment");
        let line = SynchronizedLyricLine::new("private original", 1_000, 800, vec![segment])
            .expect("line")
            .with_translation(Some("private translation".into()))
            .with_romanization(Some("private romanization".into()));
        let track_id = TrackId::new(
            ProviderId::new("qq-music").expect("provider"),
            "track:41001:0:1:private-mid",
        )
        .expect("track ID");
        SynchronizedLyrics::new(track_id, vec![line]).expect("lyrics")
    }

    #[test]
    fn maps_synchronized_lyrics_without_exposing_text_or_identity_in_diagnostics() {
        let mapped = map_load(Ok(lyrics_fixture()));
        let lyrics = mapped.lyrics.as_ref().expect("mapped lyrics");
        assert_eq!(lyrics.lines.len(), 1);
        let line = &lyrics.lines[0];
        assert_eq!(line.text, "private original");
        assert_eq!(line.start_ms, 1_000);
        assert_eq!(line.duration_ms, 800);
        assert_eq!(line.translation.as_deref(), Some("private translation"));
        assert_eq!(line.romanization.as_deref(), Some("private romanization"));
        assert_eq!(line.segments.len(), 1);
        assert_eq!(line.segments[0].text, "private segment");
        assert_eq!(line.segments[0].start_ms, 1_000);
        assert_eq!(line.segments[0].duration_ms, 400);

        let debug = format!("{mapped:?} {lyrics:?} {line:?} {:?}", line.segments[0]);
        for secret in [
            "private original",
            "private translation",
            "private romanization",
            "private segment",
            "private-mid",
        ] {
            assert!(!debug.contains(secret));
        }
    }

    #[test]
    fn maps_every_provider_failure_precisely() {
        let cases = [
            (
                LyricsError::AuthenticationRequired,
                QqMusicLyricLoadFailure::AuthenticationRequired,
            ),
            (
                LyricsError::CredentialRejected,
                QqMusicLyricLoadFailure::CredentialRejected,
            ),
            (
                LyricsError::Unavailable,
                QqMusicLyricLoadFailure::Unavailable,
            ),
            (LyricsError::Network, QqMusicLyricLoadFailure::Network),
            (
                LyricsError::ServiceUnavailable,
                QqMusicLyricLoadFailure::ServiceUnavailable,
            ),
            (
                LyricsError::InvalidResponse,
                QqMusicLyricLoadFailure::InvalidResponse,
            ),
            (LyricsError::Replaced, QqMusicLyricLoadFailure::Replaced),
        ];
        for (input, expected) in cases {
            assert_eq!(map_error(input), expected);
        }
    }

    #[tokio::test]
    async fn cancellation_is_exact_terminal_and_drops_in_flight_load() {
        struct DropMarker(Arc<AtomicBool>);

        impl Drop for DropMarker {
            fn drop(&mut self) {
                self.0.store(true, Ordering::SeqCst);
            }
        }

        let handle =
            begin_qq_music_lyric_load("qq-music".into(), "track:41001:0:1:private-mid".into());
        let started = Arc::new(Notify::new());
        let dropped = Arc::new(AtomicBool::new(false));
        let load_started = Arc::clone(&started);
        let marker = DropMarker(Arc::clone(&dropped));
        let pending_load = async move {
            let _marker = marker;
            load_started.notify_one();
            pending::<Result<SynchronizedLyrics, LyricsError>>().await
        };
        let cancel = async {
            started.notified().await;
            assert!(handle.cancel());
            assert!(!handle.cancel());
        };

        let (outcome, ()) = tokio::join!(handle.await_load(pending_load), cancel);

        assert_eq!(outcome.failure, Some(QqMusicLyricLoadFailure::Cancelled));
        assert!(!handle.is_active());
        assert!(dropped.load(Ordering::SeqCst));
        assert!(!format!("{handle:?}").contains("private-mid"));
    }
}
