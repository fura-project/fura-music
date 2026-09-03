use std::fmt;
use std::time::Duration;

use quick_xml::Reader;
use quick_xml::XmlVersion;
use quick_xml::events::{BytesStart, Event};
use serde::{Deserialize, Serialize};

use crate::credential::is_credential_rejection_code;
use crate::qrc_cipher::decrypt_cloud_qrc;
use crate::{Credential, HttpRequest, HttpTransport, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_LYRIC_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const LYRIC_REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_LYRIC_LINES: usize = 10_000;
const MAX_LYRIC_SEGMENTS: usize = 100_000;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicLyricTrack {
    Original,
    Translation,
    Romanization,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicLyricDocumentField {
    Representation,
    Ciphertext,
    Xml,
    LyricContent,
    Timing,
    SafetyLimit,
}

pub enum QqMusicLyricsError<E> {
    InvalidSongMid,
    Transport(E),
    Serialize,
    HttpStatus(u16),
    InvalidJson,
    MissingGlobalCode,
    MissingResult,
    MissingResultCode,
    Rejected {
        code: i64,
    },
    Upstream {
        global_code: i64,
        result_code: Option<i64>,
    },
    MissingData,
    MissingLyrics,
    Unavailable,
    InvalidDocument {
        track: QqMusicLyricTrack,
        field: QqMusicLyricDocumentField,
    },
}

impl<E> fmt::Debug for QqMusicLyricsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidSongMid => formatter.write_str("InvalidSongMid"),
            Self::Transport(_) => formatter.write_str("Transport([REDACTED])"),
            Self::Serialize => formatter.write_str("Serialize"),
            Self::HttpStatus(status) => formatter.debug_tuple("HttpStatus").field(status).finish(),
            Self::InvalidJson => formatter.write_str("InvalidJson([REDACTED])"),
            Self::MissingGlobalCode => formatter.write_str("MissingGlobalCode"),
            Self::MissingResult => formatter.write_str("MissingResult"),
            Self::MissingResultCode => formatter.write_str("MissingResultCode"),
            Self::Rejected { code } => formatter
                .debug_struct("Rejected")
                .field("code", code)
                .finish(),
            Self::Upstream {
                global_code,
                result_code,
            } => formatter
                .debug_struct("Upstream")
                .field("global_code", global_code)
                .field("result_code", result_code)
                .finish(),
            Self::MissingData => formatter.write_str("MissingData"),
            Self::MissingLyrics => formatter.write_str("MissingLyrics"),
            Self::Unavailable => formatter.write_str("Unavailable"),
            Self::InvalidDocument { track, field } => formatter
                .debug_struct("InvalidDocument")
                .field("track", track)
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> QqMusicLyricsError<E> {
    // Returns a stable, content-free failure stage for opt-in diagnostics.
    #[must_use]
    pub(crate) const fn diagnostic_code(&self) -> &'static str {
        match self {
            Self::InvalidSongMid => "identity.invalid_song_mid",
            Self::Transport(_) => "transport.failed",
            Self::Serialize => "request.serialize",
            Self::HttpStatus(_) => "response.http_status",
            Self::InvalidJson => "response.invalid_json",
            Self::MissingGlobalCode => "response.missing_global_code",
            Self::MissingResult => "response.missing_result",
            Self::MissingResultCode => "response.missing_result_code",
            Self::Rejected { .. } => "response.credential_rejected",
            Self::Upstream { .. } => "response.upstream_failure",
            Self::MissingData => "response.missing_data",
            Self::MissingLyrics => "response.missing_original",
            Self::Unavailable => "content.unavailable",
            Self::InvalidDocument {
                track: QqMusicLyricTrack::Original,
                field: QqMusicLyricDocumentField::Representation,
            } => "original.invalid_representation",
            Self::InvalidDocument {
                track: QqMusicLyricTrack::Original,
                field: QqMusicLyricDocumentField::Ciphertext,
            } => "original.invalid_ciphertext",
            Self::InvalidDocument {
                track: QqMusicLyricTrack::Original,
                field: QqMusicLyricDocumentField::Xml,
            } => "original.invalid_xml",
            Self::InvalidDocument {
                track: QqMusicLyricTrack::Original,
                field: QqMusicLyricDocumentField::LyricContent,
            } => "original.invalid_content",
            Self::InvalidDocument {
                track: QqMusicLyricTrack::Original,
                field: QqMusicLyricDocumentField::Timing,
            } => "original.invalid_timing",
            Self::InvalidDocument {
                track: QqMusicLyricTrack::Original,
                field: QqMusicLyricDocumentField::SafetyLimit,
            } => "original.safety_limit",
            Self::InvalidDocument {
                track: QqMusicLyricTrack::Translation,
                ..
            } => "translation.invalid",
            Self::InvalidDocument {
                track: QqMusicLyricTrack::Romanization,
                ..
            } => "romanization.invalid",
        }
    }
}

impl<E> fmt::Display for QqMusicLyricsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidSongMid => formatter.write_str("QQ Music song MID is invalid"),
            Self::Transport(_) => formatter.write_str("QQ Music lyric request failed"),
            Self::Serialize => formatter.write_str("could not serialize the lyric request"),
            Self::HttpStatus(status) => write!(formatter, "lyric request returned HTTP {status}"),
            Self::InvalidJson => formatter.write_str("lyric response was not valid JSON"),
            Self::MissingGlobalCode => formatter.write_str("lyric response has no global code"),
            Self::MissingResult => formatter.write_str("lyric result is missing"),
            Self::MissingResultCode => formatter.write_str("lyric result has no code"),
            Self::Rejected { code } => {
                write!(
                    formatter,
                    "QQ Music rejected the credential with code {code}"
                )
            }
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "lyric request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("lyric response data is missing"),
            Self::MissingLyrics => formatter.write_str("lyric response has no original field"),
            Self::Unavailable => formatter.write_str("QQ Music returned no lyrics for this track"),
            Self::InvalidDocument { track, field } => {
                write!(formatter, "{track:?} lyric has an invalid {field:?}")
            }
        }
    }
}

impl<E> std::error::Error for QqMusicLyricsError<E>
where
    E: std::error::Error + 'static,
{
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Transport(error) => Some(error),
            _ => None,
        }
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicTimedLyricSegment {
    text: String,
    start_ms: u32,
    duration_ms: u32,
}

impl QqMusicTimedLyricSegment {
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
pub struct QqMusicTimedLyricLine {
    text: String,
    start_ms: u32,
    duration_ms: u32,
    segments: Vec<QqMusicTimedLyricSegment>,
}

impl QqMusicTimedLyricLine {
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
    pub fn segments(&self) -> &[QqMusicTimedLyricSegment] {
        &self.segments
    }
}

impl fmt::Debug for QqMusicTimedLyricLine {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicTimedLyricLine")
            .field("text", &"[REDACTED]")
            .field("start_ms", &self.start_ms)
            .field("duration_ms", &self.duration_ms)
            .field("segment_count", &self.segments.len())
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicAuxiliaryLyricLine {
    text: String,
    start_ms: u32,
}

impl QqMusicAuxiliaryLyricLine {
    #[must_use]
    pub fn text(&self) -> &str {
        &self.text
    }

    #[must_use]
    pub const fn start_ms(&self) -> u32 {
        self.start_ms
    }
}

impl fmt::Debug for QqMusicAuxiliaryLyricLine {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicAuxiliaryLyricLine")
            .field("text", &"[REDACTED]")
            .field("start_ms", &self.start_ms)
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicLyrics {
    original: Vec<QqMusicTimedLyricLine>,
    translation: Vec<QqMusicAuxiliaryLyricLine>,
    romanization: Vec<QqMusicAuxiliaryLyricLine>,
}

impl QqMusicLyrics {
    #[must_use]
    pub fn original(&self) -> &[QqMusicTimedLyricLine] {
        &self.original
    }

    #[must_use]
    pub fn translation(&self) -> &[QqMusicAuxiliaryLyricLine] {
        &self.translation
    }

    #[must_use]
    pub fn romanization(&self) -> &[QqMusicAuxiliaryLyricLine] {
        &self.romanization
    }
}

impl fmt::Debug for QqMusicLyrics {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicLyrics")
            .field("original_line_count", &self.original.len())
            .field("translation_line_count", &self.translation.len())
            .field("romanization_line_count", &self.romanization.len())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Loads and parses the current encrypted cloud lyric representation.
    ///
    /// # Errors
    ///
    /// Returns typed transport, response, availability, decryption, and
    /// document failures without retaining lyric content in diagnostics.
    pub async fn lyrics(
        &self,
        credential: Option<&Credential>,
        song_mid: &str,
        song_type: u32,
    ) -> Result<QqMusicLyrics, QqMusicLyricsError<T::Error>> {
        let result: Result<QqMusicLyrics, QqMusicLyricsError<T::Error>> = async {
            if !is_safe_song_mid(song_mid) {
                return Err(QqMusicLyricsError::InvalidSongMid);
            }
            let body = serde_json::to_vec(&LyricRequest::new(credential, song_mid, song_type))
                .map_err(|_| QqMusicLyricsError::Serialize)?;
            let mut request = HttpRequest::post(MUSICU_URL)
                .header("Content-Type", "application/json")
                .header("Origin", "https://y.qq.com")
                .header("Referer", "https://y.qq.com/")
                .body(body)
                .response_body_limit(MAX_LYRIC_RESPONSE_BYTES)
                .timeout(LYRIC_REQUEST_TIMEOUT);
            if let Some(credential) = credential {
                request = request.header("Cookie", credential.musicu_cookie_header());
            }
            let response = self
                .transport()
                .execute(request)
                .await
                .map_err(QqMusicLyricsError::Transport)?;
            if !(200..300).contains(&response.status()) {
                return Err(QqMusicLyricsError::HttpStatus(response.status()));
            }

            let envelope: LyricEnvelope = serde_json::from_slice(response.body())
                .map_err(|_| QqMusicLyricsError::InvalidJson)?;
            let data = extract_data(envelope)?;
            let encrypted_original = data.lyric.ok_or(QqMusicLyricsError::MissingLyrics)?;
            if encrypted_original.is_empty() {
                return Err(QqMusicLyricsError::Unavailable);
            }
            if data.crypt != Some(1) {
                return Err(invalid_document(
                    QqMusicLyricTrack::Original,
                    QqMusicLyricDocumentField::Representation,
                ));
            }

            let original_text = decrypt_track(&encrypted_original, QqMusicLyricTrack::Original)?;
            let original = match data.qrc {
                Some(1) => parse_qrc_xml(&original_text),
                Some(0) => parse_original_lrc(&original_text),
                _ => {
                    return Err(invalid_document(
                        QqMusicLyricTrack::Original,
                        QqMusicLyricDocumentField::Representation,
                    ));
                }
            }
            .map_err(|field| invalid_document(QqMusicLyricTrack::Original, field))?;
            if original.is_empty() {
                return Err(QqMusicLyricsError::Unavailable);
            }
            let translation = parse_optional_auxiliary(data.trans, QqMusicLyricTrack::Translation);
            let romanization = parse_optional_auxiliary(data.roma, QqMusicLyricTrack::Romanization);

            Ok(QqMusicLyrics {
                original,
                translation,
                romanization,
            })
        }
        .await;
        lyric_debug_result(&result);
        result
    }
}

fn extract_data<E>(envelope: LyricEnvelope) -> Result<LyricData, QqMusicLyricsError<E>> {
    let global_code = envelope.code.ok_or(QqMusicLyricsError::MissingGlobalCode)?;
    if global_code != 0 {
        if is_credential_rejection_code(global_code) {
            return Err(QqMusicLyricsError::Rejected { code: global_code });
        }
        return Err(QqMusicLyricsError::Upstream {
            global_code,
            result_code: None,
        });
    }
    let result = envelope.result.ok_or(QqMusicLyricsError::MissingResult)?;
    let result_code = result.code.ok_or(QqMusicLyricsError::MissingResultCode)?;
    if result_code != 0 {
        if is_credential_rejection_code(result_code) {
            return Err(QqMusicLyricsError::Rejected { code: result_code });
        }
        return Err(QqMusicLyricsError::Upstream {
            global_code,
            result_code: Some(result_code),
        });
    }
    result.data.ok_or(QqMusicLyricsError::MissingData)
}

fn decrypt_track<E>(
    ciphertext: &str,
    track: QqMusicLyricTrack,
) -> Result<String, QqMusicLyricsError<E>> {
    decrypt_cloud_qrc(ciphertext)
        .map_err(|_| invalid_document(track, QqMusicLyricDocumentField::Ciphertext))
}

fn parse_optional_auxiliary(
    ciphertext: Option<String>,
    track: QqMusicLyricTrack,
) -> Vec<QqMusicAuxiliaryLyricLine> {
    let Some(ciphertext) = ciphertext.filter(|value| !value.is_empty()) else {
        return Vec::new();
    };
    let parsed = decrypt_cloud_qrc(&ciphertext)
        .map_err(|_| QqMusicLyricDocumentField::Ciphertext)
        .and_then(|plaintext| parse_auxiliary_document(&plaintext));
    match parsed {
        Ok(lines) if !lines.is_empty() => lines,
        Ok(_) => {
            lyric_debug_optional(track, QqMusicLyricDocumentField::LyricContent);
            Vec::new()
        }
        Err(field) => {
            lyric_debug_optional(track, field);
            Vec::new()
        }
    }
}

fn parse_original_lrc(
    document: &str,
) -> Result<Vec<QqMusicTimedLyricLine>, QqMusicLyricDocumentField> {
    parse_lrc(document).map(|lines| {
        lines
            .into_iter()
            .map(|line| QqMusicTimedLyricLine {
                text: line.text,
                start_ms: line.start_ms,
                duration_ms: 0,
                segments: Vec::new(),
            })
            .collect()
    })
}

fn parse_auxiliary_document(
    document: &str,
) -> Result<Vec<QqMusicAuxiliaryLyricLine>, QqMusicLyricDocumentField> {
    let lrc = parse_lrc(document)?;
    if !lrc.is_empty() {
        return Ok(lrc);
    }
    let qrc = if document.trim_start().starts_with('<') {
        parse_qrc_xml(document)?
    } else {
        parse_qrc_content(document)?
    };
    Ok(qrc
        .into_iter()
        .map(|line| QqMusicAuxiliaryLyricLine {
            text: line.text,
            start_ms: line.start_ms,
        })
        .collect())
}

fn lyric_debug_result<E>(result: &Result<QqMusicLyrics, QqMusicLyricsError<E>>) {
    if std::env::var_os("FURA_QQ_LYRIC_DEBUG").is_none() {
        return;
    }
    match result {
        Ok(lyrics) => eprintln!(
            "[fura][qq-lyrics] outcome=success original_lines={} translation_lines={} romanization_lines={}",
            lyrics.original.len(),
            lyrics.translation.len(),
            lyrics.romanization.len(),
        ),
        Err(error) => eprintln!(
            "[fura][qq-lyrics] outcome=failure stage={}",
            error.diagnostic_code(),
        ),
    }
}

fn lyric_debug_optional(track: QqMusicLyricTrack, field: QqMusicLyricDocumentField) {
    if std::env::var_os("FURA_QQ_LYRIC_DEBUG").is_some() {
        eprintln!("[fura][qq-lyrics] outcome=partial optional_track={track:?} field={field:?}");
    }
}

fn invalid_document<E>(
    track: QqMusicLyricTrack,
    field: QqMusicLyricDocumentField,
) -> QqMusicLyricsError<E> {
    QqMusicLyricsError::InvalidDocument { track, field }
}

fn parse_qrc_xml(xml: &str) -> Result<Vec<QqMusicTimedLyricLine>, QqMusicLyricDocumentField> {
    let mut reader = Reader::from_str(xml);
    reader.config_mut().trim_text(false);
    loop {
        match reader.read_event() {
            Ok(Event::Start(element) | Event::Empty(element))
                if element.name().as_ref() == "Lyric_1" =>
            {
                if let Some(content) = lyric_content(&element)? {
                    return parse_qrc_content(&content);
                }
            }
            Ok(Event::Eof) => return Err(QqMusicLyricDocumentField::LyricContent),
            Ok(_) => {}
            Err(_) => return Err(QqMusicLyricDocumentField::Xml),
        }
    }
}

fn decode_qrc_xml_entities(value: &str) -> String {
    let mut decoded = String::with_capacity(value.len());
    let mut cursor = 0_usize;
    while let Some(relative_start) = value[cursor..].find('&') {
        let start = cursor + relative_start;
        decoded.push_str(&value[cursor..start]);
        let entity = value[start + 1..]
            .find(';')
            .filter(|length| *length <= 16)
            .and_then(|length| {
                let body = &value[start + 1..start + 1 + length];
                decode_qrc_xml_entity(body).map(|character| (length, character))
            });
        if let Some((length, character)) = entity {
            decoded.push(character);
            cursor = start + length + 2;
        } else {
            decoded.push('&');
            cursor = start + 1;
        }
    }
    decoded.push_str(&value[cursor..]);
    decoded
}

fn decode_qrc_xml_entity(value: &str) -> Option<char> {
    match value {
        "amp" => Some('&'),
        "lt" => Some('<'),
        "gt" => Some('>'),
        "quot" => Some('"'),
        "apos" => Some('\''),
        value if value.starts_with("#x") => {
            char::from_u32(u32::from_str_radix(&value[2..], 16).ok()?)
        }
        value if value.starts_with('#') => char::from_u32(value[1..].parse().ok()?),
        _ => None,
    }
}

fn lyric_content(element: &BytesStart<'_>) -> Result<Option<String>, QqMusicLyricDocumentField> {
    let mut lyric_type = None;
    let mut content = None;
    for attribute in element.attributes().with_checks(true) {
        let attribute = attribute.map_err(|_| QqMusicLyricDocumentField::Xml)?;
        match attribute.key.as_ref() {
            "LyricType" => {
                lyric_type = Some(
                    attribute
                        .normalized_value(XmlVersion::Implicit1_0)
                        .map_err(|_| QqMusicLyricDocumentField::Xml)?
                        .into_owned(),
                );
            }
            // QQ's XML-shaped QRC can leave reserved characters such as the
            // ampersand in `Up&Up` unescaped inside this one content field.
            // Preserve XML structure parsing, but decode only known entities
            // here and keep literal/unknown ampersands as lyric text.
            "LyricContent" => {
                let value = attribute.value.as_ref();
                content = Some(decode_qrc_xml_entities(value));
            }
            _ => {}
        }
    }
    Ok((lyric_type.as_deref() == Some("1"))
        .then_some(content)
        .flatten())
}

fn parse_qrc_content(
    content: &str,
) -> Result<Vec<QqMusicTimedLyricLine>, QqMusicLyricDocumentField> {
    let mut lines = Vec::new();
    let mut segment_count = 0_usize;
    let mut current = find_pair_tag(content, 0, b'[', b']');
    while let Some((tag_start, body_start, start_ms, duration_ms)) = current {
        let next = find_pair_tag(content, body_start, b'[', b']');
        let body_end = next.map_or(content.len(), |(start, _, _, _)| start);
        let body = content[body_start..body_end].trim_matches(['\r', '\n']);
        start_ms
            .checked_add(duration_ms)
            .ok_or(QqMusicLyricDocumentField::Timing)?;
        let (text, segments) = parse_qrc_segments(body)?;
        segment_count = segment_count
            .checked_add(segments.len())
            .ok_or(QqMusicLyricDocumentField::SafetyLimit)?;
        if lines.len() >= MAX_LYRIC_LINES || segment_count > MAX_LYRIC_SEGMENTS {
            return Err(QqMusicLyricDocumentField::SafetyLimit);
        }
        lines.push(QqMusicTimedLyricLine {
            text,
            start_ms,
            duration_ms,
            segments,
        });
        current = next;
        let _ = tag_start;
    }
    Ok(lines)
}

fn parse_qrc_segments(
    body: &str,
) -> Result<(String, Vec<QqMusicTimedLyricSegment>), QqMusicLyricDocumentField> {
    let mut segments = Vec::new();
    let mut text = String::new();
    let mut text_start = 0_usize;
    let mut search_from = 0_usize;
    while let Some((tag_start, tag_end, start_ms, duration_ms)) =
        find_pair_tag(body, search_from, b'(', b')')
    {
        start_ms
            .checked_add(duration_ms)
            .ok_or(QqMusicLyricDocumentField::Timing)?;
        let segment_text = &body[text_start..tag_start];
        text.push_str(segment_text);
        segments.push(QqMusicTimedLyricSegment {
            text: segment_text.into(),
            start_ms,
            duration_ms,
        });
        text_start = tag_end;
        search_from = tag_end;
    }
    text.push_str(&body[text_start..]);
    Ok((text, segments))
}

fn find_pair_tag(
    value: &str,
    from: usize,
    open: u8,
    close: u8,
) -> Option<(usize, usize, u32, u32)> {
    let bytes = value.as_bytes();
    let mut cursor = from;
    while cursor < bytes.len() {
        let relative = bytes[cursor..].iter().position(|byte| *byte == open)?;
        let start = cursor + relative;
        let end_relative = bytes[start + 1..].iter().position(|byte| *byte == close)?;
        let end = start + 1 + end_relative;
        if let Some((first, second)) = parse_u32_pair(&value[start + 1..end]) {
            return Some((start, end + 1, first, second));
        }
        cursor = start + 1;
    }
    None
}

fn parse_u32_pair(value: &str) -> Option<(u32, u32)> {
    let (first, second) = value.split_once(',')?;
    if first.is_empty()
        || second.is_empty()
        || !first.bytes().all(|byte| byte.is_ascii_digit())
        || !second.bytes().all(|byte| byte.is_ascii_digit())
    {
        return None;
    }
    Some((first.parse().ok()?, second.parse().ok()?))
}

fn parse_lrc(document: &str) -> Result<Vec<QqMusicAuxiliaryLyricLine>, QqMusicLyricDocumentField> {
    let mut lines = Vec::new();
    for raw_line in document.lines() {
        let mut cursor = 0_usize;
        let mut starts = Vec::new();
        while raw_line.as_bytes().get(cursor) == Some(&b'[') {
            let Some(relative_end) = raw_line.as_bytes()[cursor + 1..]
                .iter()
                .position(|byte| *byte == b']')
            else {
                return Err(QqMusicLyricDocumentField::Timing);
            };
            let end = cursor + 1 + relative_end;
            match parse_lrc_timestamp(&raw_line[cursor + 1..end])? {
                Some(start_ms) => starts.push(start_ms),
                None if starts.is_empty() => break,
                None => return Err(QqMusicLyricDocumentField::Timing),
            }
            cursor = end + 1;
        }
        if starts.is_empty() {
            continue;
        }
        let text = &raw_line[cursor..];
        for start_ms in starts {
            if lines.len() >= MAX_LYRIC_LINES {
                return Err(QqMusicLyricDocumentField::SafetyLimit);
            }
            lines.push(QqMusicAuxiliaryLyricLine {
                text: text.into(),
                start_ms,
            });
        }
    }
    Ok(lines)
}

fn parse_lrc_timestamp(value: &str) -> Result<Option<u32>, QqMusicLyricDocumentField> {
    let Some((minutes, remainder)) = value.split_once(':') else {
        return Ok(None);
    };
    if minutes.is_empty() || !minutes.bytes().all(|byte| byte.is_ascii_digit()) {
        return Ok(None);
    }
    let fraction_index = remainder
        .bytes()
        .position(|byte| byte == b'.' || byte == b':');
    let (seconds, fraction) = fraction_index.map_or((remainder, None), |index| {
        (&remainder[..index], Some(&remainder[index + 1..]))
    });
    if seconds.is_empty()
        || !seconds.bytes().all(|byte| byte.is_ascii_digit())
        || fraction.is_some_and(|value| {
            value.is_empty() || value.len() > 3 || !value.bytes().all(|byte| byte.is_ascii_digit())
        })
    {
        return Err(QqMusicLyricDocumentField::Timing);
    }
    let minutes: u32 = minutes
        .parse()
        .map_err(|_| QqMusicLyricDocumentField::Timing)?;
    let seconds: u32 = seconds
        .parse()
        .map_err(|_| QqMusicLyricDocumentField::Timing)?;
    let fraction_ms = match fraction {
        None => 0,
        Some(value) if value.len() == 1 => {
            value
                .parse::<u32>()
                .map_err(|_| QqMusicLyricDocumentField::Timing)?
                * 100
        }
        Some(value) if value.len() == 2 => {
            value
                .parse::<u32>()
                .map_err(|_| QqMusicLyricDocumentField::Timing)?
                * 10
        }
        Some(value) => value
            .parse::<u32>()
            .map_err(|_| QqMusicLyricDocumentField::Timing)?,
    };
    minutes
        .checked_mul(60_000)
        .and_then(|value| {
            seconds
                .checked_mul(1_000)
                .and_then(|seconds| value.checked_add(seconds))
        })
        .and_then(|value| value.checked_add(fraction_ms))
        .map(Some)
        .ok_or(QqMusicLyricDocumentField::Timing)
}

fn is_safe_song_mid(value: &str) -> bool {
    !value.is_empty() && value.len() <= 64 && value.bytes().all(|byte| byte.is_ascii_alphanumeric())
}

#[derive(Serialize)]
struct LyricRequest<'a> {
    comm: LyricComm<'a>,
    #[serde(rename = "req_0")]
    request: LyricRpc<'a>,
}

impl<'a> LyricRequest<'a> {
    fn new(credential: Option<&'a Credential>, song_mid: &'a str, song_type: u32) -> Self {
        Self {
            comm: LyricComm::new(credential),
            request: LyricRpc {
                module: "music.musichallSong.PlayLyricInfo",
                method: "GetPlayLyricInfo",
                param: LyricParam {
                    song_mid,
                    song_type,
                    crypt: 1,
                    lrc_timestamp: 0,
                    qrc: 1,
                    qrc_timestamp: 0,
                    romanization: 1,
                    romanization_timestamp: 0,
                    translation: 1,
                    translation_timestamp: 0,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct LyricRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: LyricParam<'a>,
}

#[derive(Serialize)]
struct LyricParam<'a> {
    #[serde(rename = "songMid")]
    song_mid: &'a str,
    #[serde(rename = "type")]
    song_type: u32,
    crypt: u8,
    #[serde(rename = "lrc_t")]
    lrc_timestamp: u8,
    qrc: u8,
    #[serde(rename = "qrc_t")]
    qrc_timestamp: u8,
    #[serde(rename = "roma")]
    romanization: u8,
    #[serde(rename = "roma_t")]
    romanization_timestamp: u8,
    #[serde(rename = "trans")]
    translation: u8,
    #[serde(rename = "trans_t")]
    translation_timestamp: u8,
}

#[derive(Serialize)]
struct LyricComm<'a> {
    cv: u32,
    #[serde(rename = "v")]
    version: u32,
    #[serde(rename = "ct")]
    client_type: &'static str,
    #[serde(rename = "tmeAppID")]
    app_id: &'static str,
    format: &'static str,
    #[serde(rename = "inCharset")]
    input_charset: &'static str,
    #[serde(rename = "outCharset")]
    output_charset: &'static str,
    #[serde(rename = "uid")]
    user_id: &'a str,
    #[serde(rename = "qq")]
    account_id: &'a str,
    #[serde(rename = "authst")]
    auth_key: &'a str,
    #[serde(rename = "tmeLoginType")]
    login_type: u32,
    #[serde(rename = "loginUin")]
    login_uin: &'a str,
}

impl<'a> LyricComm<'a> {
    fn new(credential: Option<&'a Credential>) -> Self {
        let (user_id, auth_key, login_type) = credential.map_or(("0", "", 0), |credential| {
            (
                credential.music_id(),
                credential.music_key(),
                credential.login_type().value(),
            )
        });
        Self {
            cv: 13_020_508,
            version: 13_020_508,
            client_type: "11",
            app_id: "qqmusic",
            format: "json",
            input_charset: "utf-8",
            output_charset: "utf-8",
            user_id,
            account_id: user_id,
            auth_key,
            login_type,
            login_uin: user_id,
        }
    }
}

#[derive(Deserialize)]
struct LyricEnvelope {
    code: Option<i64>,
    #[serde(rename = "req_0")]
    result: Option<LyricResult>,
}

#[derive(Deserialize)]
struct LyricResult {
    code: Option<i64>,
    data: Option<LyricData>,
}

#[derive(Deserialize)]
struct LyricData {
    crypt: Option<i64>,
    qrc: Option<i64>,
    lyric: Option<String>,
    trans: Option<String>,
    roma: Option<String>,
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::{Arc, Mutex};

    use serde_json::{Value, json};

    use super::{
        QqMusicLyricDocumentField, QqMusicLyricTrack, QqMusicLyricsError, parse_auxiliary_document,
        parse_lrc, parse_qrc_xml,
    };
    use crate::{Credential, HttpRequest, HttpResponse, HttpTransport, LoginType, QqMusicClient};

    const ORIGINAL: &str = "6447440FA5912BEC47EBDC0F7AB9DBF847898BC76ABCB709C0C54D9D6978ECB97215F4B28B51CCAE8B4EB4770A40E946F617E688A35972D20678A27250A2CC7A27B47B4F03BC55A3A2C612D6BB5D5E1F84A193DD1300931765FDCE14968B9672AC39037736BFCF7477FFB1FC1A30262A2642D946938797373D17F93807532D4521F920DE15943C1C159ECE086BD712BBD41B53DB6F9B3611440AD23536818A61FCDEA679DAB19A08";
    const TRANSLATION: &str = "32DABB4C5E9846FA45D76834744321F1D6DEBD05CD29B5D704D95053C04BB7107871D3901D3239B44E462C5D14EF95C3";
    const ROMANIZATION: &str =
        "32DABB4C5E9846FAF51AD82250F0023B114969FFF15F2E8D0463E1D98F0635733405C33283708F7F";

    #[derive(Clone)]
    struct FixtureTransport {
        response: Arc<Mutex<Option<HttpResponse>>>,
        requests: Arc<Mutex<Vec<HttpRequest>>>,
    }

    impl FixtureTransport {
        fn new(response: &Value) -> Self {
            Self {
                response: Arc::new(Mutex::new(Some(HttpResponse::new(
                    200,
                    serde_json::to_vec(response).expect("fixture JSON"),
                )))),
                requests: Arc::new(Mutex::new(Vec::new())),
            }
        }

        fn requests(&self) -> Vec<HttpRequest> {
            self.requests.lock().expect("request lock").clone()
        }
    }

    impl HttpTransport for FixtureTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("request lock").push(request);
            Ok(self
                .response
                .lock()
                .expect("response lock")
                .take()
                .expect("fixture response"))
        }
    }

    fn credential() -> Credential {
        Credential::new(
            "123456",
            "synthetic-key",
            LoginType::new(1).expect("login type"),
        )
        .expect("credential")
    }

    fn success_response() -> Value {
        json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {
                    "crypt": 1,
                    "qrc": 1,
                    "lyric": ORIGINAL,
                    "trans": TRANSLATION,
                    "roma": ROMANIZATION
                }
            }
        })
    }

    #[tokio::test]
    async fn serializes_verified_request_and_parses_synthetic_tracks() {
        let transport = FixtureTransport::new(&success_response());
        let client = QqMusicClient::new(transport.clone());
        let lyrics = client
            .lyrics(Some(&credential()), "fixtureMID01", 0)
            .await
            .expect("lyrics");

        assert_eq!(lyrics.original().len(), 2);
        assert_eq!(lyrics.original()[0].text(), "Synthetic");
        assert_eq!(lyrics.original()[0].start_ms(), 1_000);
        assert_eq!(lyrics.original()[0].duration_ms(), 800);
        assert_eq!(lyrics.original()[0].segments().len(), 2);
        assert_eq!(lyrics.original()[0].segments()[0].text(), "Syn");
        assert_eq!(lyrics.original()[0].segments()[1].start_ms(), 1_400);
        assert_eq!(lyrics.translation()[0].start_ms(), 1_000);
        assert_eq!(lyrics.translation()[0].text(), "Translated fixture");
        assert_eq!(lyrics.romanization()[0].text(), "Romanized fixture");

        let requests = transport.requests();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].url(), "https://u.y.qq.com/cgi-bin/musicu.fcg");
        assert_eq!(requests[0].max_response_body_bytes(), 2 * 1024 * 1024);
        let body: Value =
            serde_json::from_slice(requests[0].body_bytes().expect("lyric request body"))
                .expect("request JSON");
        assert_eq!(body["req_0"]["module"], "music.musichallSong.PlayLyricInfo");
        assert_eq!(body["req_0"]["method"], "GetPlayLyricInfo");
        assert_eq!(body["req_0"]["param"]["songMid"], "fixtureMID01");
        assert_eq!(body["req_0"]["param"]["type"], 0);
        for field in ["crypt", "qrc", "trans", "roma"] {
            assert_eq!(body["req_0"]["param"][field], 1);
        }
        assert!(format!("{lyrics:?}").contains("original_line_count: 2"));
        assert!(!format!("{lyrics:?}").contains("Synthetic"));
    }

    #[tokio::test]
    async fn anonymous_lyrics_send_no_cookie_or_fabricated_account_material() {
        let transport = FixtureTransport::new(&success_response());
        QqMusicClient::new(transport.clone())
            .lyrics(None, "fixtureMID01", 0)
            .await
            .expect("anonymous lyrics");

        let requests = transport.requests();
        assert_eq!(requests.len(), 1);
        assert!(
            requests[0]
                .headers()
                .iter()
                .all(|(name, _)| name != "Cookie")
        );
        let body: Value =
            serde_json::from_slice(requests[0].body_bytes().expect("lyric request body"))
                .expect("request JSON");
        assert_eq!(body["comm"]["uid"], "0");
        assert_eq!(body["comm"]["qq"], "0");
        assert_eq!(body["comm"]["loginUin"], "0");
        assert_eq!(body["comm"]["authst"], "");
        assert_eq!(body["comm"]["tmeLoginType"], 0);
    }

    #[tokio::test]
    async fn accepts_encrypted_line_timed_original_without_inventing_word_timing() {
        let transport = FixtureTransport::new(&json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {
                    "crypt": 1,
                    "qrc": 0,
                    "lyric": TRANSLATION,
                    "trans": "",
                    "roma": ""
                }
            }
        }));
        let lyrics = QqMusicClient::new(transport)
            .lyrics(None, "fixtureMID01", 0)
            .await
            .expect("line-timed lyrics");

        assert_eq!(lyrics.original().len(), 2);
        assert_eq!(lyrics.original()[0].text(), "Translated fixture");
        assert_eq!(lyrics.original()[0].start_ms(), 1_000);
        assert_eq!(lyrics.original()[0].duration_ms(), 0);
        assert!(lyrics.original()[0].segments().is_empty());
    }

    #[tokio::test]
    async fn malformed_optional_track_does_not_discard_valid_original() {
        let mut response = success_response();
        response["req_0"]["data"]["trans"] = json!("0000000000000000");
        let lyrics = QqMusicClient::new(FixtureTransport::new(&response))
            .lyrics(None, "fixtureMID01", 0)
            .await
            .expect("valid original survives malformed optional track");

        assert_eq!(lyrics.original().len(), 2);
        assert!(lyrics.translation().is_empty());
        assert_eq!(lyrics.romanization().len(), 1);
    }

    #[test]
    fn qrc_parser_decodes_xml_entities_and_preserves_source_timing() {
        let xml = r#"<QrcInfos><LyricInfo><Lyric_1 LyricType="1" LyricContent="[0,10]A&amp;B(0,10)&#10;[20,0](19,2)"/></LyricInfo></QrcInfos>"#;
        let lines = parse_qrc_xml(xml).expect("QRC XML");

        assert_eq!(lines.len(), 2);
        assert_eq!(lines[0].text(), "A&B");
        assert_eq!(lines[0].segments()[0].text(), "A&B");
        assert_eq!(lines[1].text(), "");
        assert_eq!(lines[1].segments()[0].start_ms(), 19);
    }

    #[test]
    fn qrc_parser_accepts_unescaped_ampersand_in_qq_pseudo_xml_metadata() {
        let xml = r#"<QrcInfos><LyricInfo><Lyric_1 LyricType="1" LyricContent="[ti:Up&Up]&#10;[1000,500]Up(1000,200)&(1200,100)Up(1300,200)"/></LyricInfo></QrcInfos>"#;
        let lines = parse_qrc_xml(xml).expect("QQ pseudo XML");

        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].text(), "Up&Up");
        assert_eq!(lines[0].start_ms(), 1_000);
        assert_eq!(lines[0].segments().len(), 3);
        assert_eq!(lines[0].segments()[1].text(), "&");
    }

    #[test]
    fn qrc_parser_keeps_unknown_entities_as_lyric_text() {
        let xml = r#"<QrcInfos><LyricInfo><Lyric_1 LyricType="1" LyricContent="[1000,500]A&unknown;B(1000,500)"/></LyricInfo></QrcInfos>"#;
        let lines = parse_qrc_xml(xml).expect("unknown lyric entity");

        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].text(), "A&unknown;B");
    }

    #[test]
    fn lrc_parser_supports_multiple_tags_and_fraction_widths() {
        let lines = parse_lrc("[ar:Fixture]\n[00:01.2][00:02:034]Auxiliary\n[00:03]").expect("LRC");
        assert_eq!(
            lines
                .iter()
                .map(super::QqMusicAuxiliaryLyricLine::start_ms)
                .collect::<Vec<_>>(),
            [1_200, 2_034, 3_000]
        );
        assert_eq!(lines[0].text(), "Auxiliary");
        assert_eq!(lines[2].text(), "");
    }

    #[test]
    fn auxiliary_parser_accepts_qrc_documents_as_line_timed_text() {
        let xml = r#"<QrcInfos><LyricInfo><Lyric_1 LyricType="1" LyricContent="[1000,800]Optional(1000,800)"/></LyricInfo></QrcInfos>"#;
        let lines = parse_auxiliary_document(xml).expect("auxiliary QRC");

        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].text(), "Optional");
        assert_eq!(lines[0].start_ms(), 1_000);
    }

    #[tokio::test]
    async fn keeps_unavailable_rejection_and_invalid_documents_distinct() {
        let unavailable = FixtureTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 0, "data": {"crypt": 1, "qrc": 1, "lyric": ""}}
        }));
        assert!(matches!(
            QqMusicClient::new(unavailable)
                .lyrics(Some(&credential()), "fixtureMID01", 0)
                .await,
            Err(QqMusicLyricsError::Unavailable)
        ));

        let unavailable_without_qrc = FixtureTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 0, "data": {"crypt": 0, "qrc": 0, "lyric": ""}}
        }));
        assert!(matches!(
            QqMusicClient::new(unavailable_without_qrc)
                .lyrics(Some(&credential()), "fixtureMID01", 0)
                .await,
            Err(QqMusicLyricsError::Unavailable)
        ));

        let rejected = FixtureTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 104_401}
        }));
        assert!(matches!(
            QqMusicClient::new(rejected)
                .lyrics(Some(&credential()), "fixtureMID01", 0)
                .await,
            Err(QqMusicLyricsError::Rejected { code: 104_401 })
        ));

        let invalid = FixtureTransport::new(&json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {"crypt": 1, "qrc": 1, "lyric": "0000000000000000"}
            }
        }));
        assert!(matches!(
            QqMusicClient::new(invalid)
                .lyrics(Some(&credential()), "fixtureMID01", 0)
                .await,
            Err(QqMusicLyricsError::InvalidDocument {
                track: QqMusicLyricTrack::Original,
                field: QqMusicLyricDocumentField::Ciphertext,
            })
        ));
    }

    #[tokio::test]
    async fn rejects_invalid_identity_before_transport_and_redacts_errors() {
        let transport = FixtureTransport::new(&success_response());
        let result = QqMusicClient::new(transport.clone())
            .lyrics(Some(&credential()), "bad mid", 0)
            .await;
        assert!(matches!(result, Err(QqMusicLyricsError::InvalidSongMid)));
        assert!(transport.requests().is_empty());

        let error: QqMusicLyricsError<Infallible> = QqMusicLyricsError::InvalidDocument {
            track: QqMusicLyricTrack::Translation,
            field: QqMusicLyricDocumentField::Timing,
        };
        assert_eq!(error.diagnostic_code(), "translation.invalid");
        assert!(!format!("{error:?}").contains("fixture"));
    }
}
