use std::collections::HashMap;
use std::fmt;
use std::time::Duration;

use reqwest::Url;
use serde::{Deserialize, Serialize};

use crate::media_resolution::request_guid;
use crate::{HttpRequest, HttpTransport, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_TEXT_BYTES: usize = 4 * 1024;
const MAX_ARTISTS: usize = 64;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MusicVideoProtocolPhase {
    TrackContext,
    Video,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MusicVideoResponseField {
    GlobalCode,
    Result,
    ResultCode,
    Data,
    TrackMid,
    VideoId,
    VideoMetadata,
    Title,
    Artists,
    ArtistName,
    Duration,
    Source,
}

pub enum QqMusicTrackMusicVideoError<E> {
    InvalidSongMid,
    RandomnessUnavailable,
    Serialize(MusicVideoProtocolPhase),
    Transport {
        phase: MusicVideoProtocolPhase,
        source: E,
    },
    HttpStatus {
        phase: MusicVideoProtocolPhase,
        status: u16,
    },
    InvalidJson(MusicVideoProtocolPhase),
    Upstream {
        phase: MusicVideoProtocolPhase,
        global_code: i64,
        result_code: Option<i64>,
    },
    InvalidResponse {
        phase: MusicVideoProtocolPhase,
        field: MusicVideoResponseField,
    },
    SourceUnavailable,
}

impl<E> fmt::Debug for QqMusicTrackMusicVideoError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidSongMid => formatter.write_str("InvalidSongMid([REDACTED])"),
            Self::RandomnessUnavailable => formatter.write_str("RandomnessUnavailable"),
            Self::Serialize(phase) => formatter.debug_tuple("Serialize").field(phase).finish(),
            Self::Transport { phase, .. } => formatter
                .debug_struct("Transport")
                .field("phase", phase)
                .field("source", &"[REDACTED]")
                .finish(),
            Self::HttpStatus { phase, status } => formatter
                .debug_struct("HttpStatus")
                .field("phase", phase)
                .field("status", status)
                .finish(),
            Self::InvalidJson(phase) => formatter
                .debug_tuple("InvalidJson")
                .field(phase)
                .field(&"[REDACTED]")
                .finish(),
            Self::Upstream {
                phase,
                global_code,
                result_code,
            } => formatter
                .debug_struct("Upstream")
                .field("phase", phase)
                .field("global_code", global_code)
                .field("result_code", result_code)
                .finish(),
            Self::InvalidResponse { phase, field } => formatter
                .debug_struct("InvalidResponse")
                .field("phase", phase)
                .field("field", field)
                .finish(),
            Self::SourceUnavailable => formatter.write_str("SourceUnavailable"),
        }
    }
}

impl<E> fmt::Display for QqMusicTrackMusicVideoError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidSongMid => formatter.write_str("QQ Music song MID is invalid"),
            Self::RandomnessUnavailable => {
                formatter.write_str("could not create a music video request identifier")
            }
            Self::Serialize(phase) => write!(formatter, "could not serialize {phase:?} request"),
            Self::Transport { phase, .. } => write!(formatter, "{phase:?} request failed"),
            Self::HttpStatus { phase, status } => {
                write!(formatter, "{phase:?} request returned HTTP {status}")
            }
            Self::InvalidJson(phase) => write!(formatter, "{phase:?} response was not valid JSON"),
            Self::Upstream {
                phase,
                global_code,
                result_code,
            } => write!(
                formatter,
                "{phase:?} failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::InvalidResponse { phase, field } => {
                write!(formatter, "{phase:?} response has an invalid {field:?}")
            }
            Self::SourceUnavailable => {
                formatter.write_str("QQ Music did not provide a supported music video source")
            }
        }
    }
}

impl<E> std::error::Error for QqMusicTrackMusicVideoError<E>
where
    E: std::error::Error + 'static,
{
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Transport { source, .. } => Some(source),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicMusicVideoQuality {
    FullHd,
    Hd,
    Sd,
    Low,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicTrackMusicVideo {
    vid: String,
    title: String,
    artist_names: Vec<String>,
    artwork_uri: Option<String>,
    duration_seconds: u32,
    source_uri: String,
    quality: QqMusicMusicVideoQuality,
}

impl QqMusicTrackMusicVideo {
    #[must_use]
    pub fn vid(&self) -> &str {
        &self.vid
    }

    #[must_use]
    pub fn title(&self) -> &str {
        &self.title
    }

    #[must_use]
    pub fn artist_names(&self) -> &[String] {
        &self.artist_names
    }

    #[must_use]
    pub fn artwork_uri(&self) -> Option<&str> {
        self.artwork_uri.as_deref()
    }

    #[must_use]
    pub const fn duration_seconds(&self) -> u32 {
        self.duration_seconds
    }

    #[must_use]
    pub fn source_uri(&self) -> &str {
        &self.source_uri
    }

    #[must_use]
    pub const fn quality(&self) -> QqMusicMusicVideoQuality {
        self.quality
    }
}

impl fmt::Debug for QqMusicTrackMusicVideo {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicTrackMusicVideo")
            .field("vid", &"[REDACTED]")
            .field("title", &"[REDACTED]")
            .field("artist_count", &self.artist_names.len())
            .field("has_artwork", &self.artwork_uri.is_some())
            .field("duration_seconds", &self.duration_seconds)
            .field("source_uri", &"[REDACTED]")
            .field("quality", &self.quality)
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Resolves the exact MV attached to one public QQ Music Track.
    ///
    /// The first bounded anonymous request verifies the Track/MV association;
    /// only then are metadata and a supported HTTPS MP4 source requested.
    ///
    /// # Errors
    ///
    /// Keeps phase-specific transport, service, identity, metadata, and source
    /// failures distinct without exposing MIDs, VIDs, or source URLs.
    pub async fn track_music_video(
        &self,
        song_mid: &str,
    ) -> Result<Option<QqMusicTrackMusicVideo>, QqMusicTrackMusicVideoError<T::Error>> {
        if !safe_opaque_id(song_mid) {
            return Err(QqMusicTrackMusicVideoError::InvalidSongMid);
        }

        let track_body = serde_json::to_vec(&TrackContextRequest::new(song_mid)).map_err(|_| {
            QqMusicTrackMusicVideoError::Serialize(MusicVideoProtocolPhase::TrackContext)
        })?;
        let track_response = self
            .transport()
            .execute(request(track_body))
            .await
            .map_err(|source| QqMusicTrackMusicVideoError::Transport {
                phase: MusicVideoProtocolPhase::TrackContext,
                source,
            })?;
        ensure_http_success(&track_response, MusicVideoProtocolPhase::TrackContext)?;
        let track_envelope: TrackContextResponse = serde_json::from_slice(track_response.body())
            .map_err(|_| {
                QqMusicTrackMusicVideoError::InvalidJson(MusicVideoProtocolPhase::TrackContext)
            })?;
        let Some(vid) = map_track_context(track_envelope, song_mid)? else {
            return Ok(None);
        };

        let guid =
            request_guid().map_err(|()| QqMusicTrackMusicVideoError::RandomnessUnavailable)?;
        let video_body = serde_json::to_vec(&VideoRequest::new(&vid, &guid))
            .map_err(|_| QqMusicTrackMusicVideoError::Serialize(MusicVideoProtocolPhase::Video))?;
        let video_response = self
            .transport()
            .execute(request(video_body))
            .await
            .map_err(|source| QqMusicTrackMusicVideoError::Transport {
                phase: MusicVideoProtocolPhase::Video,
                source,
            })?;
        ensure_http_success(&video_response, MusicVideoProtocolPhase::Video)?;
        let video_envelope: VideoResponse =
            serde_json::from_slice(video_response.body()).map_err(|_| {
                QqMusicTrackMusicVideoError::InvalidJson(MusicVideoProtocolPhase::Video)
            })?;
        map_video_response(video_envelope, vid).map(Some)
    }
}

fn request(body: Vec<u8>) -> HttpRequest {
    HttpRequest::post(MUSICU_URL)
        .header("Content-Type", "application/json")
        .header("Origin", "https://y.qq.com")
        .header("Referer", "https://y.qq.com/")
        .body(body)
        .response_body_limit(MAX_RESPONSE_BYTES)
        .timeout(REQUEST_TIMEOUT)
}

fn ensure_http_success<E>(
    response: &crate::HttpResponse,
    phase: MusicVideoProtocolPhase,
) -> Result<(), QqMusicTrackMusicVideoError<E>> {
    if (200..300).contains(&response.status()) {
        Ok(())
    } else {
        Err(QqMusicTrackMusicVideoError::HttpStatus {
            phase,
            status: response.status(),
        })
    }
}

#[derive(Serialize)]
struct CommonRequest {
    #[serde(rename = "ct")]
    client_type: u32,
    #[serde(rename = "cv")]
    client_version: u32,
    format: &'static str,
}

impl CommonRequest {
    const fn web() -> Self {
        Self {
            client_type: 24,
            client_version: 0,
            format: "json",
        }
    }
}

#[derive(Serialize)]
struct TrackContextRequest<'a> {
    comm: CommonRequest,
    songinfo: TrackContextRpc<'a>,
}

impl<'a> TrackContextRequest<'a> {
    const fn new(song_mid: &'a str) -> Self {
        Self {
            comm: CommonRequest::web(),
            songinfo: TrackContextRpc {
                module: "music.pf_song_detail_svr",
                method: "get_song_detail_yqq",
                param: TrackContextParam { song_mid },
            },
        }
    }
}

#[derive(Serialize)]
struct TrackContextRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: TrackContextParam<'a>,
}

#[derive(Serialize)]
struct TrackContextParam<'a> {
    song_mid: &'a str,
}

#[derive(Serialize)]
struct VideoRequest<'a> {
    comm: CommonRequest,
    mvinfo: VideoInfoRpc<'a>,
    mvurl: VideoUrlRpc<'a>,
}

impl<'a> VideoRequest<'a> {
    const fn new(vid: &'a str, guid: &'a str) -> Self {
        Self {
            comm: CommonRequest::web(),
            mvinfo: VideoInfoRpc {
                module: "video.VideoDataServer",
                method: "get_video_info_batch",
                param: VideoInfoParam {
                    vidlist: [vid],
                    required: ["vid", "cover_pic", "duration", "singers", "name"],
                },
            },
            mvurl: VideoUrlRpc {
                module: "music.stream.MvUrlProxy",
                method: "GetMvUrls",
                param: VideoUrlParam {
                    vids: [vid],
                    request_type: 10_003,
                    guid,
                    videoformat: 1,
                    format: 265,
                    dolby: 1,
                    use_new_domain: 1,
                    use_ipv6: 1,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct VideoInfoRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: VideoInfoParam<'a>,
}

#[derive(Serialize)]
struct VideoInfoParam<'a> {
    vidlist: [&'a str; 1],
    required: [&'static str; 5],
}

#[derive(Serialize)]
struct VideoUrlRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: VideoUrlParam<'a>,
}

#[derive(Serialize)]
struct VideoUrlParam<'a> {
    vids: [&'a str; 1],
    request_type: u32,
    guid: &'a str,
    videoformat: u32,
    format: u32,
    dolby: u32,
    use_new_domain: u32,
    use_ipv6: u32,
}

#[derive(Deserialize)]
struct TrackContextResponse {
    code: Option<i64>,
    songinfo: Option<RpcResult<TrackContextData>>,
}

#[derive(Deserialize)]
struct TrackContextData {
    track_info: Option<RawTrackContext>,
}

#[derive(Deserialize)]
struct RawTrackContext {
    mid: Option<String>,
    mv: Option<RawTrackMusicVideo>,
}

#[derive(Deserialize)]
struct RawTrackMusicVideo {
    vid: Option<String>,
}

#[derive(Deserialize)]
struct VideoResponse {
    code: Option<i64>,
    mvinfo: Option<RpcResult<HashMap<String, RawVideoMetadata>>>,
    mvurl: Option<RpcResult<HashMap<String, RawVideoSources>>>,
}

#[derive(Deserialize)]
struct RpcResult<D> {
    code: Option<i64>,
    data: Option<D>,
}

#[derive(Deserialize)]
struct RawVideoMetadata {
    vid: Option<String>,
    name: Option<String>,
    cover_pic: Option<String>,
    duration: Option<u64>,
    singers: Option<Vec<RawVideoArtist>>,
}

#[derive(Deserialize)]
struct RawVideoArtist {
    #[serde(alias = "singer_name")]
    name: Option<String>,
}

#[derive(Deserialize)]
struct RawVideoSources {
    mp4: Option<Vec<RawVideoSource>>,
}

#[derive(Deserialize)]
struct RawVideoSource {
    code: Option<i64>,
    filetype: Option<u32>,
    freeflow_url: Option<Vec<String>>,
    url: Option<Vec<String>>,
    comm_url: Option<Vec<String>>,
}

fn map_track_context<E>(
    envelope: TrackContextResponse,
    requested_mid: &str,
) -> Result<Option<String>, QqMusicTrackMusicVideoError<E>> {
    let data = checked_result(
        envelope.code,
        envelope.songinfo,
        MusicVideoProtocolPhase::TrackContext,
    )?;
    let track = data
        .track_info
        .ok_or(QqMusicTrackMusicVideoError::InvalidResponse {
            phase: MusicVideoProtocolPhase::TrackContext,
            field: MusicVideoResponseField::Data,
        })?;
    let response_mid = track.mid.filter(|value| safe_opaque_id(value)).ok_or(
        QqMusicTrackMusicVideoError::InvalidResponse {
            phase: MusicVideoProtocolPhase::TrackContext,
            field: MusicVideoResponseField::TrackMid,
        },
    )?;
    if response_mid != requested_mid {
        return Err(QqMusicTrackMusicVideoError::InvalidResponse {
            phase: MusicVideoProtocolPhase::TrackContext,
            field: MusicVideoResponseField::TrackMid,
        });
    }
    match track.mv.and_then(|value| value.vid) {
        None => Ok(None),
        Some(value) if value.trim().is_empty() => Ok(None),
        Some(value) if safe_opaque_id(&value) => Ok(Some(value)),
        Some(_) => Err(QqMusicTrackMusicVideoError::InvalidResponse {
            phase: MusicVideoProtocolPhase::TrackContext,
            field: MusicVideoResponseField::VideoId,
        }),
    }
}

fn map_video_response<E>(
    envelope: VideoResponse,
    requested_vid: String,
) -> Result<QqMusicTrackMusicVideo, QqMusicTrackMusicVideoError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicTrackMusicVideoError::InvalidResponse {
            phase: MusicVideoProtocolPhase::Video,
            field: MusicVideoResponseField::GlobalCode,
        })?;
    if global_code != 0 {
        return Err(QqMusicTrackMusicVideoError::Upstream {
            phase: MusicVideoProtocolPhase::Video,
            global_code,
            result_code: None,
        });
    }
    let metadata = checked_subresult(envelope.mvinfo, MusicVideoProtocolPhase::Video)?;
    let sources = checked_subresult(envelope.mvurl, MusicVideoProtocolPhase::Video)?;
    let raw_metadata =
        metadata
            .get(&requested_vid)
            .ok_or(QqMusicTrackMusicVideoError::InvalidResponse {
                phase: MusicVideoProtocolPhase::Video,
                field: MusicVideoResponseField::VideoMetadata,
            })?;
    if raw_metadata.vid.as_deref() != Some(requested_vid.as_str()) {
        return Err(QqMusicTrackMusicVideoError::InvalidResponse {
            phase: MusicVideoProtocolPhase::Video,
            field: MusicVideoResponseField::VideoId,
        });
    }
    let title = bounded_text(raw_metadata.name.as_ref()).ok_or(
        QqMusicTrackMusicVideoError::InvalidResponse {
            phase: MusicVideoProtocolPhase::Video,
            field: MusicVideoResponseField::Title,
        },
    )?;
    let raw_artists =
        raw_metadata
            .singers
            .as_ref()
            .ok_or(QqMusicTrackMusicVideoError::InvalidResponse {
                phase: MusicVideoProtocolPhase::Video,
                field: MusicVideoResponseField::Artists,
            })?;
    if raw_artists.is_empty() || raw_artists.len() > MAX_ARTISTS {
        return Err(QqMusicTrackMusicVideoError::InvalidResponse {
            phase: MusicVideoProtocolPhase::Video,
            field: MusicVideoResponseField::Artists,
        });
    }
    let artist_names = raw_artists
        .iter()
        .map(|artist| {
            bounded_text(artist.name.as_ref()).ok_or(QqMusicTrackMusicVideoError::InvalidResponse {
                phase: MusicVideoProtocolPhase::Video,
                field: MusicVideoResponseField::ArtistName,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;
    let duration_seconds = raw_metadata
        .duration
        .and_then(|value| u32::try_from(value).ok())
        .filter(|value| *value != 0)
        .ok_or(QqMusicTrackMusicVideoError::InvalidResponse {
            phase: MusicVideoProtocolPhase::Video,
            field: MusicVideoResponseField::Duration,
        })?;
    let artwork_uri = raw_metadata
        .cover_pic
        .as_ref()
        .and_then(|value| https_uri(value).then(|| value.clone()));
    let raw_sources =
        sources
            .get(&requested_vid)
            .ok_or(QqMusicTrackMusicVideoError::InvalidResponse {
                phase: MusicVideoProtocolPhase::Video,
                field: MusicVideoResponseField::Source,
            })?;
    let (source_uri, quality) = select_source(raw_sources)?;

    Ok(QqMusicTrackMusicVideo {
        vid: requested_vid,
        title,
        artist_names,
        artwork_uri,
        duration_seconds,
        source_uri,
        quality,
    })
}

fn checked_result<E, D>(
    global_code: Option<i64>,
    result: Option<RpcResult<D>>,
    phase: MusicVideoProtocolPhase,
) -> Result<D, QqMusicTrackMusicVideoError<E>> {
    let global_code = global_code.ok_or(QqMusicTrackMusicVideoError::InvalidResponse {
        phase,
        field: MusicVideoResponseField::GlobalCode,
    })?;
    let result_code = result.as_ref().and_then(|value| value.code);
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicTrackMusicVideoError::Upstream {
            phase,
            global_code,
            result_code,
        });
    }
    let result = result.ok_or(QqMusicTrackMusicVideoError::InvalidResponse {
        phase,
        field: MusicVideoResponseField::Result,
    })?;
    result
        .code
        .ok_or(QqMusicTrackMusicVideoError::InvalidResponse {
            phase,
            field: MusicVideoResponseField::ResultCode,
        })?;
    result
        .data
        .ok_or(QqMusicTrackMusicVideoError::InvalidResponse {
            phase,
            field: MusicVideoResponseField::Data,
        })
}

fn checked_subresult<E, D>(
    result: Option<RpcResult<D>>,
    phase: MusicVideoProtocolPhase,
) -> Result<D, QqMusicTrackMusicVideoError<E>> {
    let result_code = result.as_ref().and_then(|value| value.code);
    if result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicTrackMusicVideoError::Upstream {
            phase,
            global_code: 0,
            result_code,
        });
    }
    let result = result.ok_or(QqMusicTrackMusicVideoError::InvalidResponse {
        phase,
        field: MusicVideoResponseField::Result,
    })?;
    result
        .code
        .ok_or(QqMusicTrackMusicVideoError::InvalidResponse {
            phase,
            field: MusicVideoResponseField::ResultCode,
        })?;
    result
        .data
        .ok_or(QqMusicTrackMusicVideoError::InvalidResponse {
            phase,
            field: MusicVideoResponseField::Data,
        })
}

fn select_source<E>(
    sources: &RawVideoSources,
) -> Result<(String, QqMusicMusicVideoQuality), QqMusicTrackMusicVideoError<E>> {
    let mp4 = sources
        .mp4
        .as_ref()
        .ok_or(QqMusicTrackMusicVideoError::SourceUnavailable)?;
    for (filetype, quality) in [
        (40, QqMusicMusicVideoQuality::FullHd),
        (30, QqMusicMusicVideoQuality::Hd),
        (20, QqMusicMusicVideoQuality::Sd),
        (10, QqMusicMusicVideoQuality::Low),
    ] {
        for source in mp4
            .iter()
            .filter(|source| source.code == Some(0) && source.filetype == Some(filetype))
        {
            for candidate in source
                .freeflow_url
                .iter()
                .flatten()
                .chain(source.url.iter().flatten())
                .chain(source.comm_url.iter().flatten())
            {
                if https_uri(candidate) {
                    return Ok((candidate.clone(), quality));
                }
            }
        }
    }
    Err(QqMusicTrackMusicVideoError::SourceUnavailable)
}

fn safe_opaque_id(value: &str) -> bool {
    !value.is_empty() && value.len() <= 64 && value.bytes().all(|byte| byte.is_ascii_alphanumeric())
}

fn bounded_text(value: Option<&String>) -> Option<String> {
    value
        .filter(|value| !value.trim().is_empty() && value.len() <= MAX_TEXT_BYTES)
        .cloned()
}

fn https_uri(value: &str) -> bool {
    Url::parse(value).is_ok_and(|url| url.scheme() == "https" && url.host().is_some())
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use super::{
        MAX_RESPONSE_BYTES, MusicVideoProtocolPhase, MusicVideoResponseField,
        QqMusicMusicVideoQuality, QqMusicTrackMusicVideoError, REQUEST_TIMEOUT,
    };
    use crate::{HttpMethod, HttpRequest, HttpResponse, HttpTransport, QqMusicClient};

    struct MusicVideoTransport {
        responses: Mutex<VecDeque<HttpResponse>>,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl MusicVideoTransport {
        fn from_json(responses: &[Value]) -> Self {
            Self {
                responses: Mutex::new(
                    responses
                        .iter()
                        .map(|body| {
                            HttpResponse::new(200, serde_json::to_vec(body).expect("fixture JSON"))
                        })
                        .collect(),
                ),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn with_responses(responses: Vec<HttpResponse>) -> Self {
            Self {
                responses: Mutex::new(responses.into()),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn requests(&self) -> Vec<HttpRequest> {
            self.requests.lock().expect("requests").clone()
        }
    }

    impl HttpTransport for MusicVideoTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("requests").push(request);
            Ok(self
                .responses
                .lock()
                .expect("responses")
                .pop_front()
                .expect("scripted response"))
        }
    }

    fn track_response(mid: &str, vid: Option<&str>) -> Value {
        json!({
            "code": 0,
            "songinfo": {
                "code": 0,
                "data": {
                    "track_info": {"mid": mid, "mv": {"vid": vid.unwrap_or("")}}
                }
            }
        })
    }

    fn video_response(mp4: &Value) -> Value {
        json!({
            "code": 0,
            "mvinfo": {
                "code": 0,
                "data": {
                    "fixtureMvVid": {
                        "vid": "fixtureMvVid",
                        "name": "Private MV title",
                        "cover_pic": "https://example.invalid/private-cover.jpg",
                        "duration": 180,
                        "singers": [{"name": "Private Artist"}]
                    }
                }
            },
            "mvurl": {
                "code": 0,
                "data": {"fixtureMvVid": {"mp4": mp4, "hls": []}}
            }
        })
    }

    fn source(filetype: u32, uri: &str) -> Value {
        json!({
            "code": 0,
            "filetype": filetype,
            "freeflow_url": [uri],
            "url": [],
            "comm_url": []
        })
    }

    #[tokio::test]
    async fn verifies_track_association_then_maps_preferred_https_mp4() {
        let client = QqMusicClient::new(MusicVideoTransport::from_json(&[
            track_response("fixtureTrackMid", Some("fixtureMvVid")),
            video_response(&json!([
                source(20, "https://example.invalid/private-sd.mp4"),
                source(40, "https://example.invalid/private-fhd.mp4")
            ])),
        ]));

        let video = client
            .track_music_video("fixtureTrackMid")
            .await
            .expect("MV result")
            .expect("associated MV");
        assert_eq!(video.vid(), "fixtureMvVid");
        assert_eq!(video.title(), "Private MV title");
        assert_eq!(video.artist_names(), &["Private Artist"]);
        assert_eq!(video.duration_seconds(), 180);
        assert_eq!(
            video.artwork_uri(),
            Some("https://example.invalid/private-cover.jpg")
        );
        assert_eq!(
            video.source_uri(),
            "https://example.invalid/private-fhd.mp4"
        );
        assert_eq!(video.quality(), QqMusicMusicVideoQuality::FullHd);

        let requests = client.transport().requests();
        assert_eq!(requests.len(), 2);
        for request in &requests {
            assert_eq!(request.method(), HttpMethod::Post);
            assert_eq!(request.url(), "https://u.y.qq.com/cgi-bin/musicu.fcg");
            assert_eq!(request.max_response_body_bytes(), MAX_RESPONSE_BYTES);
            assert_eq!(request.request_timeout(), Some(REQUEST_TIMEOUT));
            assert!(request.headers().iter().all(|(name, _)| name != "Cookie"));
        }
        let track_body: Value =
            serde_json::from_slice(requests[0].body_bytes().expect("track body"))
                .expect("track request JSON");
        assert_eq!(track_body["songinfo"]["module"], "music.pf_song_detail_svr");
        assert_eq!(track_body["songinfo"]["method"], "get_song_detail_yqq");
        assert_eq!(
            track_body["songinfo"]["param"]["song_mid"],
            "fixtureTrackMid"
        );
        let video_body: Value =
            serde_json::from_slice(requests[1].body_bytes().expect("video body"))
                .expect("video request JSON");
        assert_eq!(video_body["mvinfo"]["module"], "video.VideoDataServer");
        assert_eq!(video_body["mvurl"]["module"], "music.stream.MvUrlProxy");
        assert_eq!(video_body["mvurl"]["param"]["request_type"], 10_003);
        assert_eq!(video_body["mvurl"]["param"]["format"], 265);
        let guid = video_body["mvurl"]["param"]["guid"].as_str().expect("guid");
        assert_eq!(guid.len(), 32);
        assert!(guid.bytes().all(|byte| byte.is_ascii_hexdigit()));

        let debug = format!("{video:?} {:?} {:?}", requests[0], requests[1]);
        for private in [
            "fixtureTrackMid",
            "fixtureMvVid",
            "Private MV title",
            "Private Artist",
            "private-fhd",
            "private-cover",
        ] {
            assert!(!debug.contains(private));
        }
    }

    #[tokio::test]
    async fn no_associated_mv_is_a_successful_one_request_result() {
        let client = QqMusicClient::new(MusicVideoTransport::from_json(&[track_response(
            "fixtureTrackMid",
            None,
        )]));

        assert!(
            client
                .track_music_video("fixtureTrackMid")
                .await
                .expect("truthful no-MV result")
                .is_none()
        );
        assert_eq!(client.transport().requests().len(), 1);
    }

    #[tokio::test]
    async fn rejects_mismatched_track_and_video_identity() {
        let client = QqMusicClient::new(MusicVideoTransport::from_json(&[track_response(
            "differentTrackMid",
            Some("fixtureMvVid"),
        )]));
        assert!(matches!(
            client.track_music_video("fixtureTrackMid").await,
            Err(QqMusicTrackMusicVideoError::InvalidResponse {
                phase: MusicVideoProtocolPhase::TrackContext,
                field: MusicVideoResponseField::TrackMid,
            })
        ));

        let mut mismatched =
            video_response(&json!([source(40, "https://example.invalid/private.mp4")]));
        mismatched["mvinfo"]["data"]["fixtureMvVid"]["vid"] = json!("differentMvVid");
        let client = QqMusicClient::new(MusicVideoTransport::from_json(&[
            track_response("fixtureTrackMid", Some("fixtureMvVid")),
            mismatched,
        ]));
        assert!(matches!(
            client.track_music_video("fixtureTrackMid").await,
            Err(QqMusicTrackMusicVideoError::InvalidResponse {
                phase: MusicVideoProtocolPhase::Video,
                field: MusicVideoResponseField::VideoId,
            })
        ));
    }

    #[tokio::test]
    async fn source_selection_ignores_cleartext_unknown_and_failed_rows() {
        let client = QqMusicClient::new(MusicVideoTransport::from_json(&[
            track_response("fixtureTrackMid", Some("fixtureMvVid")),
            video_response(&json!([
                source(50, "https://example.invalid/unknown.mp4"),
                source(40, "http://example.invalid/cleartext.mp4"),
                {"code": 7, "filetype": 30, "freeflow_url": ["https://example.invalid/failed.mp4"]},
                source(20, "https://example.invalid/selected.mp4")
            ])),
        ]));
        let video = client
            .track_music_video("fixtureTrackMid")
            .await
            .expect("source")
            .expect("MV");
        assert_eq!(video.quality(), QqMusicMusicVideoQuality::Sd);
        assert_eq!(video.source_uri(), "https://example.invalid/selected.mp4");

        let client = QqMusicClient::new(MusicVideoTransport::from_json(&[
            track_response("fixtureTrackMid", Some("fixtureMvVid")),
            video_response(&json!([source(40, "http://example.invalid/cleartext.mp4")])),
        ]));
        assert!(matches!(
            client.track_music_video("fixtureTrackMid").await,
            Err(QqMusicTrackMusicVideoError::SourceUnavailable)
        ));
    }

    #[tokio::test]
    async fn keeps_http_json_and_upstream_failures_phase_specific() {
        let client = QqMusicClient::new(MusicVideoTransport::with_responses(vec![
            HttpResponse::new(503, Vec::new()),
        ]));
        assert!(matches!(
            client.track_music_video("fixtureTrackMid").await,
            Err(QqMusicTrackMusicVideoError::HttpStatus {
                phase: MusicVideoProtocolPhase::TrackContext,
                status: 503,
            })
        ));

        let client = QqMusicClient::new(MusicVideoTransport::with_responses(vec![
            HttpResponse::new(200, b"private invalid JSON".to_vec()),
        ]));
        let error = client
            .track_music_video("fixtureTrackMid")
            .await
            .expect_err("invalid JSON");
        assert!(matches!(
            error,
            QqMusicTrackMusicVideoError::InvalidJson(MusicVideoProtocolPhase::TrackContext)
        ));
        assert!(!format!("{error:?}").contains("private"));

        let client = QqMusicClient::new(MusicVideoTransport::from_json(&[json!({
            "code": 0,
            "songinfo": {"code": 24001}
        })]));
        assert!(matches!(
            client.track_music_video("fixtureTrackMid").await,
            Err(QqMusicTrackMusicVideoError::Upstream {
                phase: MusicVideoProtocolPhase::TrackContext,
                global_code: 0,
                result_code: Some(24001),
            })
        ));
    }
}
