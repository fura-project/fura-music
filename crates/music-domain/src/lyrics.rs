use std::fmt;

use crate::TrackId;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LyricTimingField {
    LineEnd,
    SegmentEnd,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidLyricTiming {
    field: LyricTimingField,
}

impl InvalidLyricTiming {
    #[must_use]
    pub const fn field(self) -> LyricTimingField {
        self.field
    }
}

impl fmt::Display for InvalidLyricTiming {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "lyric timing has an overflowing {:?}",
            self.field
        )
    }
}

impl std::error::Error for InvalidLyricTiming {}

/// One provider-neutral timed text segment. A segment can be a character,
/// whitespace, punctuation, or a multi-character chunk; it does not claim to
/// be a linguistic word.
#[derive(Clone, Eq, PartialEq)]
pub struct TimedLyricSegment {
    text: String,
    start_ms: u32,
    duration_ms: u32,
}

impl TimedLyricSegment {
    /// # Errors
    ///
    /// Rejects a start plus duration that cannot be represented in the
    /// millisecond domain. Empty or whitespace text is preserved because QRC
    /// timing can intentionally attach to spacing or an empty marker.
    pub fn new(
        text: impl Into<String>,
        start_ms: u32,
        duration_ms: u32,
    ) -> Result<Self, InvalidLyricTiming> {
        start_ms
            .checked_add(duration_ms)
            .ok_or(InvalidLyricTiming {
                field: LyricTimingField::SegmentEnd,
            })?;
        Ok(Self {
            text: text.into(),
            start_ms,
            duration_ms,
        })
    }

    #[must_use]
    pub fn text(&self) -> &str {
        &self.text
    }

    #[must_use]
    pub const fn start_ms(&self) -> u32 {
        self.start_ms
    }

    #[must_use]
    pub const fn duration_ms(&self) -> u32 {
        self.duration_ms
    }

    #[must_use]
    pub const fn end_ms(&self) -> u32 {
        self.start_ms + self.duration_ms
    }
}

impl fmt::Debug for TimedLyricSegment {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("TimedLyricSegment")
            .field("text", &"[REDACTED]")
            .field("start_ms", &self.start_ms)
            .field("duration_ms", &self.duration_ms)
            .finish()
    }
}

/// One synchronized original lyric line plus optional exact-start auxiliary
/// text. Timed segments stay in provider order; the Domain does not sort or
/// infer alignment.
#[derive(Clone, Eq, PartialEq)]
pub struct SynchronizedLyricLine {
    text: String,
    start_ms: u32,
    duration_ms: u32,
    segments: Vec<TimedLyricSegment>,
    translation: Option<String>,
    romanization: Option<String>,
}

impl SynchronizedLyricLine {
    /// # Errors
    ///
    /// Rejects a start plus duration that cannot be represented. Empty lines,
    /// zero durations, gaps, overlaps, and segments outside the line interval
    /// remain representable because current QQ Music evidence does not justify
    /// normalizing or rejecting them.
    pub fn new(
        text: impl Into<String>,
        start_ms: u32,
        duration_ms: u32,
        segments: Vec<TimedLyricSegment>,
    ) -> Result<Self, InvalidLyricTiming> {
        start_ms
            .checked_add(duration_ms)
            .ok_or(InvalidLyricTiming {
                field: LyricTimingField::LineEnd,
            })?;
        Ok(Self {
            text: text.into(),
            start_ms,
            duration_ms,
            segments,
            translation: None,
            romanization: None,
        })
    }

    #[must_use]
    pub fn with_translation(mut self, translation: Option<String>) -> Self {
        self.translation = translation.filter(|value| !value.is_empty());
        self
    }

    #[must_use]
    pub fn with_romanization(mut self, romanization: Option<String>) -> Self {
        self.romanization = romanization.filter(|value| !value.is_empty());
        self
    }

    #[must_use]
    pub fn text(&self) -> &str {
        &self.text
    }

    #[must_use]
    pub const fn start_ms(&self) -> u32 {
        self.start_ms
    }

    #[must_use]
    pub const fn duration_ms(&self) -> u32 {
        self.duration_ms
    }

    #[must_use]
    pub const fn end_ms(&self) -> u32 {
        self.start_ms + self.duration_ms
    }

    #[must_use]
    pub fn segments(&self) -> &[TimedLyricSegment] {
        &self.segments
    }

    #[must_use]
    pub fn translation(&self) -> Option<&str> {
        self.translation.as_deref()
    }

    #[must_use]
    pub fn romanization(&self) -> Option<&str> {
        self.romanization.as_deref()
    }
}

impl fmt::Debug for SynchronizedLyricLine {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("SynchronizedLyricLine")
            .field("text", &"[REDACTED]")
            .field("start_ms", &self.start_ms)
            .field("duration_ms", &self.duration_ms)
            .field("segment_count", &self.segments.len())
            .field("has_translation", &self.translation.is_some())
            .field("has_romanization", &self.romanization.is_some())
            .finish()
    }
}

/// Provider-neutral synchronized lyrics for one opaque track identity.
#[derive(Clone, Eq, PartialEq)]
pub struct SynchronizedLyrics {
    track_id: TrackId,
    lines: Vec<SynchronizedLyricLine>,
}

impl SynchronizedLyrics {
    /// # Errors
    ///
    /// Rejects an empty lyric document. A provider should report unavailable
    /// lyrics rather than constructing a successful empty result.
    pub fn new(
        track_id: TrackId,
        lines: Vec<SynchronizedLyricLine>,
    ) -> Result<Self, InvalidSynchronizedLyrics> {
        if lines.is_empty() {
            return Err(InvalidSynchronizedLyrics);
        }
        Ok(Self { track_id, lines })
    }

    #[must_use]
    pub const fn track_id(&self) -> &TrackId {
        &self.track_id
    }

    #[must_use]
    pub fn lines(&self) -> &[SynchronizedLyricLine] {
        &self.lines
    }

    #[must_use]
    pub fn has_word_timing(&self) -> bool {
        self.lines.iter().any(|line| !line.segments.is_empty())
    }
}

impl fmt::Debug for SynchronizedLyrics {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("SynchronizedLyrics")
            .field("track_id", &self.track_id)
            .field("line_count", &self.lines.len())
            .field("has_word_timing", &self.has_word_timing())
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidSynchronizedLyrics;

impl fmt::Display for InvalidSynchronizedLyrics {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("synchronized lyrics must contain at least one line")
    }
}

impl std::error::Error for InvalidSynchronizedLyrics {}

#[cfg(test)]
mod tests {
    use super::{LyricTimingField, SynchronizedLyricLine, SynchronizedLyrics, TimedLyricSegment};
    use crate::{ProviderId, TrackId};

    fn track_id() -> TrackId {
        TrackId::new(
            ProviderId::new("qq-music").expect("provider"),
            "track:41001:0:1:fixture-mid",
        )
        .expect("track ID")
    }

    #[test]
    fn models_synchronized_lines_segments_and_exact_auxiliary_text() {
        let line = SynchronizedLyricLine::new(
            "Synthetic line",
            1_000,
            800,
            vec![
                TimedLyricSegment::new("Synthetic ", 1_000, 400).expect("segment"),
                TimedLyricSegment::new("line", 1_400, 400).expect("segment"),
            ],
        )
        .expect("line")
        .with_translation(Some("Translated fixture".into()))
        .with_romanization(Some("Romanized fixture".into()));
        let lyrics = SynchronizedLyrics::new(track_id(), vec![line]).expect("lyrics");

        assert_eq!(lyrics.track_id().provider().as_str(), "qq-music");
        assert!(lyrics.has_word_timing());
        let line = &lyrics.lines()[0];
        assert_eq!(line.text(), "Synthetic line");
        assert_eq!(line.start_ms(), 1_000);
        assert_eq!(line.duration_ms(), 800);
        assert_eq!(line.end_ms(), 1_800);
        assert_eq!(line.translation(), Some("Translated fixture"));
        assert_eq!(line.romanization(), Some("Romanized fixture"));
        assert_eq!(line.segments()[1].text(), "line");
        assert_eq!(line.segments()[1].start_ms(), 1_400);
        assert_eq!(line.segments()[1].duration_ms(), 400);
        assert_eq!(line.segments()[1].end_ms(), 1_800);
    }

    #[test]
    fn preserves_evidence_allowed_empty_spacing_and_outside_segments() {
        let line = SynchronizedLyricLine::new(
            "",
            100,
            0,
            vec![TimedLyricSegment::new(" ", 90, 20).expect("spacing segment")],
        )
        .expect("empty timed line")
        .with_translation(Some(String::new()))
        .with_romanization(Some(" ".into()));

        assert_eq!(line.text(), "");
        assert_eq!(line.segments()[0].text(), " ");
        assert_eq!(line.translation(), None);
        assert_eq!(line.romanization(), Some(" "));
    }

    #[test]
    fn rejects_only_overflowing_timing_and_empty_documents() {
        let segment =
            TimedLyricSegment::new("fixture", u32::MAX, 1).expect_err("overflowing segment end");
        assert_eq!(segment.field(), LyricTimingField::SegmentEnd);

        let line = SynchronizedLyricLine::new("fixture", u32::MAX, 1, Vec::new())
            .expect_err("overflowing line end");
        assert_eq!(line.field(), LyricTimingField::LineEnd);

        assert!(SynchronizedLyrics::new(track_id(), Vec::new()).is_err());
    }

    #[test]
    fn debug_output_redacts_identity_and_all_lyric_text() {
        let lyrics = SynchronizedLyrics::new(
            track_id(),
            vec![
                SynchronizedLyricLine::new(
                    "private original",
                    0,
                    1_000,
                    vec![TimedLyricSegment::new("private segment", 0, 1_000).expect("segment")],
                )
                .expect("line")
                .with_translation(Some("private translation".into()))
                .with_romanization(Some("private romanization".into())),
            ],
        )
        .expect("lyrics");

        let debug = format!(
            "{lyrics:?} {:?} {:?}",
            lyrics.lines()[0],
            lyrics.lines()[0].segments()[0]
        );
        for secret in [
            "41001",
            "private original",
            "private segment",
            "private translation",
            "private romanization",
        ] {
            assert!(!debug.contains(secret), "debug leaked {secret:?}");
        }
    }
}
