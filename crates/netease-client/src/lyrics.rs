use crate::{Error, NeteaseClient, Transport};
use serde_json::json;
use std::fmt;

pub struct LyricLine {
    pub start_ms: u32,
    pub text: String,
}
impl fmt::Debug for LyricLine {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("LyricLine")
            .field("start_ms", &self.start_ms)
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
                "/api/song/lyric",
                json!({"id":id,"tv":-1,"lv":-1,"rv":-1,"kv":-1,"_nmclfl":1}),
                false,
                None,
            )
            .await?;
        let original = v
            .pointer("/lrc/lyric")
            .and_then(serde_json::Value::as_str)
            .ok_or(Error::TrackUnavailable)?;
        let (original, omitted_original) = parse_lrc_with_integrity(original)?;
        if original.is_empty() {
            return Err(Error::TrackUnavailable);
        }
        let (translations, omitted_translation) = parse_optional_track(&v, "/tlyric/lyric");
        let (romanizations, omitted_romanization) = parse_optional_track(&v, "/romalrc/lyric");
        let lines = original
            .into_iter()
            .map(|(start_ms, text)| LyricLine { start_ms, text })
            .collect();
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
                .checked_add(omitted_translation)
                .and_then(|count| count.checked_add(omitted_romanization))
                .ok_or(Error::ResponseBound)?,
        })
    }
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
    fn debug_output_redacts_all_lyric_text() {
        let lyrics = Lyrics {
            lines: vec![LyricLine {
                start_ms: 1_000,
                text: "private original".into(),
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
            "{lyrics:?} {:?} {:?} {:?}",
            lyrics.lines[0], lyrics.translation[0], lyrics.romanization[0]
        );
        for secret in [
            "private original",
            "private translation",
            "private romanization",
        ] {
            assert!(!debug.contains(secret));
        }
    }
}
