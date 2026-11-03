//! Opaque server-issued identity chain. No signing, decoding of encoded IDs,
//! endpoint generation, browser ownership or automatic fallback lives here.

use super::{
    CaptureSource, CapturedWebRequest, MAX_WEB_BYTES, OfficialWebCapture, ProfileCookie,
    StandardWebSource, WebPlaybackError, WebPlaybackResponse, WebTrackContext,
    checked_web_response, decode_standard_source, identity_equals, positive_id,
    validate_capture_time, validate_response_identity_aliases, wipe_string,
};
use serde::Deserialize;
use std::{collections::BTreeMap, fmt};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum CaptureProfile {
    Direct,
    Stage1,
    Stage2,
}

pub(super) struct CaptureIdentity {
    pub hash: String,
    pub album: String,
    pub recording: Option<String>,
    pub encoded: Option<String>,
}

fn normalized(name: &str) -> String {
    name.bytes()
        .filter(|b| !matches!(b, b'_' | b'-'))
        .map(|b| char::from(b.to_ascii_lowercase()))
        .collect()
}

pub(super) fn capture_identity(
    params: &BTreeMap<String, String>,
    profile: CaptureProfile,
) -> Result<CaptureIdentity, WebPlaybackError> {
    let error = match profile {
        CaptureProfile::Direct => WebPlaybackError::OfficialWebTrackIdentityUnproven,
        CaptureProfile::Stage1 => WebPlaybackError::OfficialWebStage1IdentityUnproven,
        CaptureProfile::Stage2 => WebPlaybackError::OfficialWebEncodedIdentityMismatch,
    };
    let mut identity = CaptureIdentity {
        hash: params.get("hash").cloned().unwrap_or_default(),
        album: params.get("album_id").cloned().unwrap_or_default(),
        recording: None,
        encoded: params.get("encode_album_audio_id").cloned(),
    };
    if (profile != CaptureProfile::Stage2 && identity.hash.is_empty())
        || (profile == CaptureProfile::Direct && identity.album.is_empty())
        || (profile == CaptureProfile::Stage2
            && identity
                .encoded
                .as_deref()
                .is_none_or(|id| !opaque_valid(id)))
        || (profile != CaptureProfile::Stage2 && identity.encoded.is_some())
    {
        return Err(error);
    }
    for (key, value) in params {
        let valid = match normalized(key).as_str() {
            "hash" => {
                if identity.hash.is_empty() {
                    identity.hash.clone_from(value);
                }
                value.len() == 32
                    && value.bytes().all(|b| b.is_ascii_hexdigit())
                    && value.eq_ignore_ascii_case(&identity.hash)
            }
            "albumid" => {
                if identity.album.is_empty() {
                    identity.album.clone_from(value);
                }
                positive_id(value).is_ok() && value == &identity.album
            }
            "mixsongid" | "albumaudioid" => {
                let valid = positive_id(value).is_ok()
                    && identity.recording.as_ref().is_none_or(|id| id == value);
                identity.recording = Some(value.clone());
                valid
            }
            "encodealbumaudioid" => {
                profile == CaptureProfile::Stage2 && identity.encoded.as_ref() == Some(value)
            }
            "audioid" | "songid" => false,
            _ => true,
        };
        if !valid {
            return Err(error);
        }
    }
    identity.hash.make_ascii_uppercase();
    Ok(identity)
}

fn opaque_valid(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 4096
        && !value.chars().any(char::is_control)
        && !value.contains('\u{fffd}')
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[allow(clippy::struct_excessive_bools)] // Independent presence observations, never identity proof.
pub struct IdentityPresence {
    pub hash: bool,
    pub album_id: bool,
    pub album_audio_id: bool,
    pub encoded_id: bool,
}

#[derive(Clone, Copy, Debug)]
pub enum IdentityStage {
    Stage1Request,
    Stage1Response,
    Stage2Request,
}

impl IdentityPresence {
    /// Fixed stage/presence diagnostics. No string value can enter this formatter.
    #[must_use]
    pub fn diagnostic(self, stage: IdentityStage) -> String {
        let stage = match stage {
            IdentityStage::Stage1Request => "SONGINFO_STAGE1",
            IdentityStage::Stage1Response => "SONGINFO_STAGE1_RESPONSE",
            IdentityStage::Stage2Request => "SONGINFO_STAGE2",
        };
        format!(
            "KUGOU_IDENTITY_STAGE={stage}\nHAS_HASH={}\nHAS_ALBUM_ID={}\nHAS_ALBUM_AUDIO_ID={}\nHAS_ENCODE_ALBUM_AUDIO_ID={}",
            u8::from(self.hash),
            u8::from(self.album_id),
            u8::from(self.album_audio_id),
            u8::from(self.encoded_id)
        )
    }
    /// Bounded presence only, including rejected captures. No field value escapes.
    #[must_use]
    pub fn request(url: &str) -> Self {
        let mut presence = Self::empty();
        if url.len() <= 16_384
            && let Ok(url) = url::Url::parse(url)
        {
            for (key, _) in url.query_pairs() {
                presence.observe(&key);
            }
        }
        presence
    }
    fn empty() -> Self {
        Self {
            hash: false,
            album_id: false,
            album_audio_id: false,
            encoded_id: false,
        }
    }
    fn observe(&mut self, name: &str) {
        match normalized(name).as_str() {
            "hash" => self.hash = true,
            "albumid" => self.album_id = true,
            "albumaudioid" | "mixsongid" => self.album_audio_id = true,
            "encodealbumaudioid" => self.encoded_id = true,
            _ => (),
        }
    }
}

impl OfficialWebCapture {
    /// Capture a paused first-stage request. It must still be bound by the Provider.
    /// # Errors
    /// Requires the official route/header/profile contract and an exact hash shape.
    pub fn from_stage1_cdp(
        url: &str,
        method: &str,
        headers: &[(String, String)],
        cookies: &[ProfileCookie],
        now: u64,
    ) -> Result<Self, WebPlaybackError> {
        Self::from_profile(
            CaptureSource::OfficialWebGenerated,
            url,
            method,
            headers,
            cookies,
            now,
            CaptureProfile::Stage1,
        )
    }
    /// Capture the website-generated second request, never construct one from an ID.
    /// # Errors
    /// Requires an opaque encoded identity; the owning chain must verify its value.
    pub fn from_stage2_cdp(
        url: &str,
        method: &str,
        headers: &[(String, String)],
        cookies: &[ProfileCookie],
        now: u64,
    ) -> Result<Self, WebPlaybackError> {
        Self::from_profile(
            CaptureSource::OfficialWebGenerated,
            url,
            method,
            headers,
            cookies,
            now,
            CaptureProfile::Stage2,
        )
    }
    /// # Errors
    /// Every supplied comparable field must agree; Album need not be in the request.
    pub fn bind_stage1(
        self,
        track: WebTrackContext,
        now: u64,
    ) -> Result<CapturedWebRequest, WebPlaybackError> {
        validate_capture_time(self.captured_seconds, now)?;
        if self.profile != CaptureProfile::Stage1 || !comparable_fields_match(&self, &track) {
            return Err(WebPlaybackError::OfficialWebStage1IdentityUnproven);
        }
        Ok(CapturedWebRequest {
            capture: self,
            track,
        })
    }
}

fn comparable_fields_match(capture: &OfficialWebCapture, track: &WebTrackContext) -> bool {
    (capture.hash.is_empty() || capture.hash == track.hash)
        && (capture.album_id.is_empty() || capture.album_id == track.album_id)
        && capture
            .mix_song_id
            .as_ref()
            .is_none_or(|id| id == &track.mix_song_id)
}

struct HeaderBuffer(Vec<(String, String)>);
impl Drop for HeaderBuffer {
    fn drop(&mut self) {
        for (name, value) in &mut self.0 {
            wipe_string(name);
            wipe_string(value);
        }
    }
}

/// Complete representation response, not an invented success body or CORS policy.
pub struct Stage1WireResponse {
    pub(super) response: WebPlaybackResponse,
    headers: HeaderBuffer,
}
impl Stage1WireResponse {
    #[must_use]
    pub fn new(response: WebPlaybackResponse, headers: Vec<(String, String)>) -> Self {
        Self {
            response,
            headers: HeaderBuffer(headers),
        }
    }
    /// Presence observations only; malformed/duplicate security fields still fail decoding.
    #[must_use]
    pub fn identity_presence(&self) -> IdentityPresence {
        let mut presence = IdentityPresence::empty();
        if self.response.response.body.len() <= MAX_WEB_BYTES
            && let Ok(value) =
                serde_json::from_slice::<serde_json::Value>(&self.response.response.body)
            && let Some(data) = value.get("data").and_then(serde_json::Value::as_object)
        {
            for key in data.keys() {
                presence.observe(key);
            }
        }
        presence
    }
}

pub(super) fn bounded_response_headers(
    headers: &reqwest::header::HeaderMap,
) -> Result<Vec<(String, String)>, WebPlaybackError> {
    if headers.len() > 128 {
        return Err(WebPlaybackError::ResponseBound);
    }
    let mut result = Vec::new();
    let mut size = 0;
    for (name, value) in headers {
        size += name.as_str().len() + value.len();
        if size > 32 * 1024 {
            return Err(WebPlaybackError::ResponseBound);
        }
        result.push((
            name.as_str().to_owned(),
            value
                .to_str()
                .map_err(|_| WebPlaybackError::Stage1ResponseReplayUnsupported)?
                .to_owned(),
        ));
    }
    Ok(result)
}

/// Original bounded body and end-to-end headers for the paused first request.
pub struct Stage1Fulfillment {
    wire: Stage1WireResponse,
    headers: HeaderBuffer,
}
impl Stage1Fulfillment {
    #[must_use]
    pub fn headers(&self) -> &[(String, String)] {
        &self.headers.0
    }
    #[must_use]
    pub fn body(&self) -> &[u8] {
        &self.wire.response.response.body
    }
}

/// Non-clone proof, issued only by decoding the response to the exact bound hash.
pub struct ServerIssuedIdentity {
    encoded: String,
    track: WebTrackContext,
    cookie: String,
    first_capture: u64,
}
impl Drop for ServerIssuedIdentity {
    fn drop(&mut self) {
        wipe_string(&mut self.encoded);
        wipe_string(&mut self.cookie);
    }
}
impl ServerIssuedIdentity {
    /// # Errors
    /// Requires exact server-issued bytes, session, all supplied identities and freshness.
    pub fn bind_second(
        mut self,
        mut capture: OfficialWebCapture,
        now: u64,
    ) -> Result<CapturedWebRequest, WebPlaybackError> {
        validate_capture_time(self.first_capture, now)?;
        validate_capture_time(capture.captured_seconds, now)?;
        if capture.profile != CaptureProfile::Stage2
            || capture.encoded_id.as_deref() != Some(&self.encoded)
            || !comparable_fields_match(&capture, &self.track)
        {
            return Err(WebPlaybackError::OfficialWebEncodedIdentityMismatch);
        }
        if capture.cookie != self.cookie {
            return Err(WebPlaybackError::SessionContextRejected);
        }
        capture.captured_seconds = capture.captured_seconds.min(self.first_capture);
        // Move context without cloning a proof or retaining a second encoded authority.
        let track = WebTrackContext::new(
            &self.track.mix_song_id,
            &self.track.hash,
            &self.track.album_id,
            self.track.duration_seconds,
        )?;
        wipe_string(&mut self.encoded);
        Ok(CapturedWebRequest { capture, track })
    }
}

pub enum Stage1Decoded {
    Direct(StandardWebSource),
    Continue(ServerIssuedIdentity, Stage1Fulfillment),
}

#[derive(Deserialize)]
struct Stage1Envelope {
    data: Stage1Data,
}
#[derive(Deserialize)]
struct Stage1Data {
    hash: Option<String>,
    encode_album_audio_id: Option<String>,
    album_audio_id: Option<serde_json::Value>,
    album_id: Option<serde_json::Value>,
    #[serde(alias = "MixSongID")]
    mix_song_id: Option<serde_json::Value>,
    play_url: Option<String>,
    play_backup_url: Option<String>,
}
impl Drop for Stage1Data {
    fn drop(&mut self) {
        for value in [
            &mut self.hash,
            &mut self.encode_album_audio_id,
            &mut self.play_url,
            &mut self.play_backup_url,
        ]
        .into_iter()
        .flatten()
        {
            wipe_string(value);
        }
    }
}

/// # Errors
/// Security status precedes shape/identity. A full direct response is an independent
/// one-request branch; failure never tries the encoded branch or another endpoint.
pub fn decode_stage1(
    request: CapturedWebRequest,
    wire: Stage1WireResponse,
) -> Result<Stage1Decoded, WebPlaybackError> {
    let response = checked_web_response(&wire.response)?;
    if request.capture.profile != CaptureProfile::Stage1 {
        return Err(WebPlaybackError::OfficialWebStage1IdentityUnproven);
    }
    let mut data = serde_json::from_slice::<Stage1Envelope>(&response.body)
        .map_err(|_| WebPlaybackError::InvalidResponse)?
        .data;
    if data
        .hash
        .as_deref()
        .is_none_or(|hash| !hash.eq_ignore_ascii_case(&request.track.hash))
        || data
            .album_audio_id
            .as_ref()
            .is_some_and(|id| !identity_equals(id, &request.track.mix_song_id))
        || data
            .mix_song_id
            .as_ref()
            .is_some_and(|id| !identity_equals(id, &request.track.mix_song_id))
        || data
            .album_id
            .as_ref()
            .is_some_and(|id| !identity_equals(id, &request.track.album_id))
    {
        return Err(WebPlaybackError::Stage1ResponseIdentityMismatch);
    }
    validate_response_identity_aliases(
        &response.body,
        &request.track,
        data.encode_album_audio_id.as_deref(),
        WebPlaybackError::Stage1ResponseIdentityMismatch,
    )?;
    if data.play_url.as_ref().is_some_and(|url| !url.is_empty()) {
        return decode_standard_source(&request, wire.response).map(Stage1Decoded::Direct);
    }
    // Never fulfill a backup-only media payload into the page or silently turn
    // it into the primary source. This is not an evidenced identity-only step.
    if data
        .play_backup_url
        .as_ref()
        .is_some_and(|url| !url.is_empty())
    {
        return Err(WebPlaybackError::Stage1ResponseReplayUnsupported);
    }
    let encoded = data
        .encode_album_audio_id
        .take()
        .filter(|id| opaque_valid(id))
        .ok_or(WebPlaybackError::Stage1EncodedIdMissing)?;
    let headers = fulfillment_headers(&wire)?;
    let identity = ServerIssuedIdentity {
        encoded,
        cookie: request.capture.cookie.clone(),
        first_capture: request.capture.captured_seconds,
        track: request.track,
    };
    Ok(Stage1Decoded::Continue(
        identity,
        Stage1Fulfillment {
            wire,
            headers: HeaderBuffer(headers),
        },
    ))
}

fn fulfillment_headers(
    wire: &Stage1WireResponse,
) -> Result<Vec<(String, String)>, WebPlaybackError> {
    let error = WebPlaybackError::Stage1ResponseReplayUnsupported;
    if wire.headers.0.len() > 128
        || wire
            .headers
            .0
            .iter()
            .map(|(k, v)| k.len() + v.len())
            .sum::<usize>()
            > 32 * 1024
    {
        return Err(error);
    }
    let mut headers = Vec::new();
    let mut length = false;
    let mut chunked = false;
    let mut content_type = false;
    for (key, value) in &wire.headers.0 {
        if !key.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
            || !value
                .bytes()
                .all(|b| b == b'\t' || (0x20..=0x7e).contains(&b))
        {
            return Err(error);
        }
        match key.to_ascii_lowercase().as_str() {
            "set-cookie" | "set-cookie2" => {
                return Err(WebPlaybackError::Stage1ResponseCookieMutationUnsupported);
            }
            "content-encoding" if value != "identity" => {
                return Err(WebPlaybackError::Stage1ResponseEncodingUnsupported);
            }
            "content-length" => {
                if length || value.parse::<usize>().ok() != Some(wire.response.response.body.len())
                {
                    return Err(error);
                }
                length = true;
            }
            "content-type" => {
                if content_type
                    || Some(value.as_str()) != wire.response.response.content_type.as_deref()
                {
                    return Err(error);
                }
                content_type = true;
            }
            "connection"
                if !matches!(value.to_ascii_lowercase().as_str(), "close" | "keep-alive") =>
            {
                return Err(error);
            }
            "transfer-encoding" => {
                if chunked || value != "chunked" {
                    return Err(error);
                }
                chunked = true;
            }
            "trailer" | "upgrade" | "location" | "refresh" | "www-authenticate" | "te"
            | "proxy-connection" | "proxy-authenticate" => return Err(error),
            _ => (),
        }
        // reqwest supplies the dechunked representation; CDP body is base64 of
        // those representation bytes. Hop-by-hop framing is not replayed as data.
        if !matches!(
            key.to_ascii_lowercase().as_str(),
            "connection" | "keep-alive" | "transfer-encoding" | "proxy-connection"
        ) {
            headers.push((key.clone(), value.clone()));
        }
    }
    if !content_type || (length && chunked) {
        return Err(error);
    }
    Ok(headers)
}

macro_rules! opaque_debug {
    ($($name:ty),+ $(,)?)=>{$(impl fmt::Debug for $name {fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result {f.write_str(concat!(stringify!($name),"([REDACTED])"))}})+};
}
opaque_debug!(
    Stage1WireResponse,
    Stage1Fulfillment,
    ServerIssuedIdentity,
    Stage1Decoded
);
