use crate::{Error, NeteaseClient, Transport};
use serde_json::json;
use std::fmt;

pub struct LyricLine {
    pub start_ms: u32,
    pub duration_ms: u32,
    pub text: String,
    pub segments: Vec<LyricSegment>,
}
impl fmt::Debug for LyricLine {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("LyricLine")
            .field("start_ms", &self.start_ms)
            .field("duration_ms", &self.duration_ms)
            .field("text", &"[REDACTED]")
            .field("segment_count", &self.segments.len())
            .finish()
    }
}
pub struct LyricSegment {
    pub start_ms: u32,
    pub duration_ms: u32,
    pub text: String,
}
impl fmt::Debug for LyricSegment {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("LyricSegment")
            .field("start_ms", &self.start_ms)
            .field("duration_ms", &self.duration_ms)
            .field("text", &"[REDACTED]")
            .finish()
    }
}
pub struct AuxiliaryLyricLine {
    pub start_ms: u32,
    pub text: String,
}
impl fmt::Debug for AuxiliaryLyricLine {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AuxiliaryLyricLine")
            .field("start_ms", &self.start_ms)
            .field("text", &"[REDACTED]")
            .finish()
    }
}
pub struct Lyrics {
    pub lines: Vec<LyricLine>,
    pub translation: Vec<AuxiliaryLyricLine>,
    pub romanization: Vec<AuxiliaryLyricLine>,
    pub omitted_line_count: u32,
}
impl fmt::Debug for Lyrics {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("Lyrics")
            .field("line_count", &self.lines.len())
            .field("translation_line_count", &self.translation.len())
            .field("romanization_line_count", &self.romanization.len())
            .field("omitted_line_count", &self.omitted_line_count)
            .finish()
    }
}
/// # Errors
/// Omits independently malformed timed lines and rejects oversized text.
/// Metadata and untimed text are ignored.
pub fn parse_lrc(text: &str) -> Result<Vec<(u32, String)>, Error> {
    parse_lrc_with_integrity(text).map(|(rows, _)| rows)
}

/// Parses the current line-oriented YRC representation without inferring any
/// missing timings. JSON metadata rows are ignored; independently malformed
/// timed rows are counted by the response decoder and make it fall back to the
/// canonical line-timed LRC track.
///
/// # Errors
/// Rejects oversized documents, timing overflow, and resource-bound breaches.
pub fn parse_yrc(text: &str) -> Result<Vec<LyricLine>, Error> {
    parse_yrc_with_integrity(text).map(|(rows, _)| rows)
}

fn parse_yrc_with_integrity(text: &str) -> Result<(Vec<LyricLine>, u32), Error> {
    if text.len() > 512 * 1024 {
        return Err(Error::ResponseBound);
    }
    let mut rows = Vec::new();
    let mut segment_count = 0_usize;
    let mut omitted_line_count = 0_u32;
    for raw_line in text.lines() {
        let line = raw_line.trim_end_matches('\r');
        if line.trim().is_empty() || line.trim_start().starts_with('{') {
            continue;
        }
        match parse_yrc_line(line) {
            Ok(mut row) => {
                segment_count = segment_count
                    .checked_add(row.segments.len())
                    .ok_or(Error::ResponseBound)?;
                if segment_count > 100_000 {
                    return Err(Error::ResponseBound);
                }
                row.segments.shrink_to_fit();
                rows.push(row);
                if rows.len() > 10_000 {
                    return Err(Error::ResponseBound);
                }
            }
            Err(Error::ResponseShapeMismatch) => {
                omitted_line_count = omitted_line_count
                    .checked_add(1)
                    .ok_or(Error::ResponseBound)?;
            }
            Err(error) => return Err(error),
        }
    }
    rows.sort_by_key(|line| line.start_ms);
    Ok((rows, omitted_line_count))
}

fn parse_yrc_line(line: &str) -> Result<LyricLine, Error> {
    let (timing, mut content) = line
        .strip_prefix('[')
        .and_then(|line| line.split_once(']'))
        .ok_or(Error::ResponseShapeMismatch)?;
    let mut timing_parts = timing.split(',');
    let start_ms = parse_yrc_u32(timing_parts.next())?;
    let duration_ms = parse_yrc_u32(timing_parts.next())?;
    if timing_parts.next().is_some() {
        return Err(Error::ResponseShapeMismatch);
    }
    let line_end = start_ms
        .checked_add(duration_ms)
        .ok_or(Error::ResponseShapeMismatch)?;
    let mut segments = Vec::new();
    let mut text = String::new();
    let mut previous_end = start_ms;
    while !content.is_empty() {
        let tagged = content
            .strip_prefix('(')
            .ok_or(Error::ResponseShapeMismatch)?;
        let (segment_timing, after_timing) =
            tagged.split_once(')').ok_or(Error::ResponseShapeMismatch)?;
        let mut segment_parts = segment_timing.split(',');
        let segment_start = parse_yrc_u32(segment_parts.next())?;
        let segment_duration = parse_yrc_u32(segment_parts.next())?;
        parse_yrc_u32(segment_parts.next())?;
        if segment_parts.next().is_some() {
            return Err(Error::ResponseShapeMismatch);
        }
        let next_tag = after_timing.find('(').unwrap_or(after_timing.len());
        let segment_text = after_timing
            .get(..next_tag)
            .ok_or(Error::ResponseShapeMismatch)?;
        if segment_text.is_empty() {
            return Err(Error::ResponseShapeMismatch);
        }
        let segment_end = segment_start
            .checked_add(segment_duration)
            .ok_or(Error::ResponseShapeMismatch)?;
        if segment_start < start_ms || segment_start < previous_end || segment_end > line_end {
            return Err(Error::ResponseShapeMismatch);
        }
        previous_end = segment_end;
        text.push_str(segment_text);
        segments.push(LyricSegment {
            start_ms: segment_start,
            duration_ms: segment_duration,
            text: segment_text.to_owned(),
        });
        if segments.len() > 4_096 {
            return Err(Error::ResponseBound);
        }
        content = after_timing
            .get(next_tag..)
            .ok_or(Error::ResponseShapeMismatch)?;
    }
    if segments.is_empty() {
        return Err(Error::ResponseShapeMismatch);
    }
    Ok(LyricLine {
        start_ms,
        duration_ms,
        text,
        segments,
    })
}

fn parse_yrc_u32(value: Option<&str>) -> Result<u32, Error> {
    let value = value.ok_or(Error::ResponseShapeMismatch)?;
    if value.is_empty() || !value.bytes().all(|byte| byte.is_ascii_digit()) {
        return Err(Error::ResponseShapeMismatch);
    }
    value
        .parse::<u32>()
        .map_err(|_| Error::ResponseShapeMismatch)
}

fn parse_lrc_with_integrity(text: &str) -> Result<(Vec<(u32, String)>, u32), Error> {
    if text.len() > 512 * 1024 {
        return Err(Error::ResponseBound);
    }
    let mut rows = Vec::new();
    let mut omitted_line_count = 0_u32;
    for line in text.lines() {
        match parse_lrc_line(line) {
            Ok((starts, remaining)) => {
                for start in starts {
                    rows.push((start, remaining.to_owned()));
                    if rows.len() > 10_000 {
                        return Err(Error::ResponseBound);
                    }
                }
            }
            Err(Error::ResponseShapeMismatch) => {
                omitted_line_count = omitted_line_count
                    .checked_add(1)
                    .ok_or(Error::ResponseBound)?;
            }
            Err(error) => return Err(error),
        }
    }
    rows.sort_by_key(|(start, _)| *start);
    Ok((rows, omitted_line_count))
}

fn parse_lrc_line(line: &str) -> Result<(Vec<u32>, &str), Error> {
    let mut remaining = line;
    let mut starts = Vec::new();
    while let Some(tail) = remaining.strip_prefix('[') {
        let (tag, rest) = tail.split_once(']').ok_or(Error::ResponseShapeMismatch)?;
        remaining = rest;
        if !tag.as_bytes().first().is_some_and(u8::is_ascii_digit) {
            continue;
        }
        let (minutes, seconds) = tag.split_once(':').ok_or(Error::ResponseShapeMismatch)?;
        let minutes = minutes
            .parse::<u32>()
            .map_err(|_| Error::ResponseShapeMismatch)?;
        let (seconds, fraction) = seconds.split_once('.').unwrap_or((seconds, ""));
        // NetEase can append an internal negative line marker to an otherwise
        // standard LRC timestamp, for example `00:00.00-1`.
        let fraction = if let Some((fraction, marker)) = fraction.split_once('-') {
            if fraction.is_empty()
                || marker.is_empty()
                || !marker.bytes().all(|b| b.is_ascii_digit())
            {
                return Err(Error::ResponseShapeMismatch);
            }
            fraction
        } else {
            fraction
        };
        let seconds = seconds
            .parse::<u32>()
            .map_err(|_| Error::ResponseShapeMismatch)?;
        if seconds >= 60 || fraction.len() > 3 || !fraction.bytes().all(|b| b.is_ascii_digit()) {
            return Err(Error::ResponseShapeMismatch);
        }
        let millis = if fraction.is_empty() {
            0
        } else {
            fraction
                .parse::<u32>()
                .map_err(|_| Error::ResponseShapeMismatch)?
                * 10_u32.pow(3 - u32::try_from(fraction.len()).map_err(|_| Error::ResponseBound)?)
        };
        let start = minutes
            .checked_mul(60_000)
            .and_then(|m| m.checked_add(seconds * 1000 + millis))
            .ok_or(Error::ResponseShapeMismatch)?;
        starts.push(start);
        if starts.len() > 32 {
            return Err(Error::ResponseBound);
        }
    }
    Ok((starts, remaining))
}
impl<T: Transport> NeteaseClient<T> {
    /// # Errors
    /// Returns unavailable for untimed/missing lyrics; malformed timing and upstream errors STOP.
    pub async fn lyrics(&self, id: u64) -> Result<Lyrics, Error> {
        crate::catalog::id(id)?;
        let (v, _) = self
            .request(
                "/api/song/lyric/v1",
                json!({
                    "id": id,
                    "cp": false,
                    "tv": 0,
                    "lv": 0,
                    "rv": 0,
                    "kv": 0,
                    "yv": 0,
                    "ytv": 0,
                    "yrv": 0
                }),
                true,
                None,
            )
            .await?;
        let (word_lines, omitted_word) = parse_optional_word_track(&v, "/yrc/lyric")?;
        let (line_rows, omitted_original) = parse_optional_canonical_track(&v, "/lrc/lyric")?;
        // A partially malformed word-timing document is presentation data, not
        // permission to discard valid canonical lyrics. Fall back atomically.
        let lines = if omitted_word == 0 && !word_lines.is_empty() {
            word_lines
        } else {
            line_rows
                .into_iter()
                .map(|(start_ms, text)| LyricLine {
                    start_ms,
                    duration_ms: 0,
                    text,
                    segments: Vec::new(),
                })
                .collect()
        };
        if lines.is_empty() {
            return Err(Error::TrackUnavailable);
        }
        let (translations, omitted_translation) =
            parse_optional_track_candidates(&v, &["/ytlrc/lyric", "/tlyric/lyric"]);
        let (romanizations, omitted_romanization) =
            parse_optional_track_candidates(&v, &["/yromalrc/lyric", "/romalrc/lyric"]);
        Ok(Lyrics {
            lines,
            translation: translations
                .into_iter()
                .map(|(start_ms, text)| AuxiliaryLyricLine { start_ms, text })
                .collect(),
            romanization: romanizations
                .into_iter()
                .map(|(start_ms, text)| AuxiliaryLyricLine { start_ms, text })
                .collect(),
            omitted_line_count: omitted_original
                .checked_add(omitted_word)
                .and_then(|count| count.checked_add(omitted_translation))
                .and_then(|count| count.checked_add(omitted_romanization))
                .ok_or(Error::ResponseBound)?,
        })
    }
}

fn parse_optional_canonical_track(
    response: &serde_json::Value,
    pointer: &str,
) -> Result<(Vec<(u32, String)>, u32), Error> {
    let Some(value) = response.pointer(pointer) else {
        return Ok((Vec::new(), 0));
    };
    let document = value.as_str().ok_or(Error::ResponseShapeMismatch)?;
    parse_lrc_with_integrity(document)
}

fn parse_optional_word_track(
    response: &serde_json::Value,
    pointer: &str,
) -> Result<(Vec<LyricLine>, u32), Error> {
    let Some(value) = response.pointer(pointer) else {
        return Ok((Vec::new(), 0));
    };
    let Some(document) = value.as_str() else {
        return Ok((Vec::new(), 1));
    };
    // Malformed individual word rows are counted so canonical LRC can replace
    // the whole presentation track. Resource bounds remain hard failures;
    // falling back must not turn an oversized YRC document into an accepted
    // response.
    parse_yrc_with_integrity(document)
}

fn parse_optional_track_candidates(
    response: &serde_json::Value,
    pointers: &[&str],
) -> (Vec<(u32, String)>, u32) {
    for pointer in pointers {
        if response.pointer(pointer).is_some() {
            return parse_optional_track(response, pointer);
        }
    }
    (Vec::new(), 0)
}

fn parse_optional_track(response: &serde_json::Value, pointer: &str) -> (Vec<(u32, String)>, u32) {
    let Some(document) = response
        .pointer(pointer)
        .and_then(serde_json::Value::as_str)
    else {
        return (Vec::new(), 0);
    };
    match parse_lrc_with_integrity(document) {
        Ok(parsed) => parsed,
        // Auxiliary text is optional presentation data. A malformed or
        // oversized local document is omitted without discarding valid
        // canonical lyrics.
        Err(_) => (Vec::new(), 1),
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn lrc_supports_repeated_and_fractional_timestamps_without_words() {
        assert_eq!(
            parse_lrc("[ar:fixture]\n[01:02.3][01:03.45]Example\n[01:04.567]End").unwrap(),
            vec![
                (62300, "Example".into()),
                (63450, "Example".into()),
                (64567, "End".into())
            ]
        );
        assert_eq!(
            parse_lrc("[00:00.00-1] 作词 : Fixture\n[00:01.25]Line").unwrap(),
            vec![(0, " 作词 : Fixture".into()), (1250, "Line".into())]
        );
    }
    #[test]
    fn lrc_omits_bad_timing_lines_and_enforces_bounds() {
        for text in [
            "[00:61.1]x",
            "[00:01.1234]x",
            "[00:01.-1]x",
            "[00:01.12-x]x",
            "[999999999:00]x",
            "[00:aa]x",
        ] {
            assert!(parse_lrc(text).unwrap().is_empty());
        }
        assert_eq!(
            parse_lrc("[00:01]A\n[00:61.1]bad\n[00:02]B").unwrap(),
            vec![(1000, "A".into()), (2000, "B".into())]
        );
        assert!(parse_lrc(&"[00:01]x\n".repeat(10001)).is_err());
        assert!(parse_lrc("untimed text").unwrap().is_empty());
    }

    #[test]
    fn yrc_maps_absolute_word_timing_without_inference() {
        let lines = parse_yrc(
            "{\"t\":0,\"c\":[{\"tx\":\"metadata\"}]}\n\
             [1000,900](1000,400,0)One (1400,500,0)line",
        )
        .expect("YRC");
        assert_eq!(lines.len(), 1);
        assert_eq!((lines[0].start_ms, lines[0].duration_ms), (1_000, 900));
        assert_eq!(lines[0].text, "One line");
        assert_eq!(lines[0].segments.len(), 2);
        assert_eq!(
            (
                lines[0].segments[0].start_ms,
                lines[0].segments[0].duration_ms,
                lines[0].segments[0].text.as_str()
            ),
            (1_000, 400, "One ")
        );
        assert_eq!(
            (
                lines[0].segments[1].start_ms,
                lines[0].segments[1].duration_ms,
                lines[0].segments[1].text.as_str()
            ),
            (1_400, 500, "line")
        );
    }

    #[test]
    fn yrc_rejects_inferred_overlapping_and_out_of_line_timing() {
        for document in [
            "[1000,900](0,400,0)relative",
            "[1000,900](1000,600,0)first(1500,200,0)overlap",
            "[1000,900](1800,200,0)outside",
            "[1000,900](1000,400,0)",
            "[1000,900]plain text",
        ] {
            assert!(
                parse_yrc(document)
                    .expect("bounded malformed YRC")
                    .is_empty()
            );
        }
        assert!(parse_yrc(&"[0,1](0,1,0)x\n".repeat(10_001)).is_err());
    }

    #[test]
    fn debug_output_redacts_all_lyric_text() {
        let lyrics = Lyrics {
            lines: vec![LyricLine {
                start_ms: 1_000,
                duration_ms: 1_000,
                text: "private original".into(),
                segments: vec![LyricSegment {
                    start_ms: 1_000,
                    duration_ms: 1_000,
                    text: "private segment".into(),
                }],
            }],
            translation: vec![AuxiliaryLyricLine {
                start_ms: 1_000,
                text: "private translation".into(),
            }],
            romanization: vec![AuxiliaryLyricLine {
                start_ms: 1_000,
                text: "private romanization".into(),
            }],
            omitted_line_count: 0,
        };
        let debug = format!(
            "{lyrics:?} {:?} {:?} {:?} {:?}",
            lyrics.lines[0],
            lyrics.lines[0].segments[0],
            lyrics.translation[0],
            lyrics.romanization[0]
        );
        for secret in [
            "private original",
            "private translation",
            "private romanization",
            "private segment",
        ] {
            assert!(!debug.contains(secret));
        }
    }
}
