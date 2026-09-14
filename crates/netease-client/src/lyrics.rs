use crate::{Error, NeteaseClient, Transport};
use serde_json::json;

pub struct LyricLine {
    pub start_ms: u32,
    pub text: String,
    pub translation: Option<String>,
}
pub struct Lyrics {
    pub lines: Vec<LyricLine>,
}
/// # Errors
/// Rejects malformed timestamps and oversized text. Metadata and untimed text are ignored.
pub fn parse_lrc(text: &str) -> Result<Vec<(u32, String)>, Error> {
    if text.len() > 512 * 1024 {
        return Err(Error::ResponseBound);
    }
    let mut rows = Vec::new();
    for line in text.lines() {
        let mut remaining = line;
        let mut starts = Vec::new();
        while let Some(tail) = remaining.strip_prefix('[') {
            let Some((tag, rest)) = tail.split_once(']') else {
                return Err(Error::ResponseShapeMismatch);
            };
            remaining = rest;
            if !tag.as_bytes().first().is_some_and(u8::is_ascii_digit) {
                continue;
            }
            let (minutes, seconds) = tag.split_once(':').ok_or(Error::ResponseShapeMismatch)?;
            let minutes = minutes
                .parse::<u32>()
                .map_err(|_| Error::ResponseShapeMismatch)?;
            let (seconds, fraction) = seconds.split_once('.').unwrap_or((seconds, ""));
            // NetEase can append an internal negative line marker to an
            // otherwise standard LRC timestamp, for example `00:00.00-1`.
            // It does not alter playback time and must not invalidate the
            // entire document.
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
            if seconds >= 60 || fraction.len() > 3 || !fraction.bytes().all(|b| b.is_ascii_digit())
            {
                return Err(Error::ResponseShapeMismatch);
            }
            let millis = if fraction.is_empty() {
                0
            } else {
                fraction
                    .parse::<u32>()
                    .map_err(|_| Error::ResponseShapeMismatch)?
                    * 10_u32
                        .pow(3 - u32::try_from(fraction.len()).map_err(|_| Error::ResponseBound)?)
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
        for start in starts {
            rows.push((start, remaining.to_owned()));
            if rows.len() > 10_000 {
                return Err(Error::ResponseBound);
            }
        }
    }
    rows.sort_by_key(|(start, _)| *start);
    Ok(rows)
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
        let original = parse_lrc(original)?;
        if original.is_empty() {
            return Err(Error::TrackUnavailable);
        }
        let translations = v
            .pointer("/tlyric/lyric")
            .and_then(serde_json::Value::as_str)
            .map(parse_lrc)
            .transpose()?
            .unwrap_or_default();
        let lines = original
            .into_iter()
            .map(|(start_ms, text)| {
                let matching: Vec<_> = translations
                    .iter()
                    .filter(|(time, _)| *time == start_ms)
                    .collect();
                LyricLine {
                    start_ms,
                    text,
                    translation: if matching.len() == 1 {
                        Some(matching[0].1.clone())
                    } else {
                        None
                    },
                }
            })
            .collect();
        Ok(Lyrics { lines })
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
    fn lrc_rejects_bad_timing_and_enforces_bounds() {
        for text in [
            "[00:61.1]x",
            "[00:01.1234]x",
            "[00:01.-1]x",
            "[00:01.12-x]x",
            "[999999999:00]x",
            "[00:aa]x",
        ] {
            assert!(parse_lrc(text).is_err());
        }
        assert!(parse_lrc(&"[00:01]x\n".repeat(10001)).is_err());
        assert!(parse_lrc("untimed text").unwrap().is_empty());
    }
}
