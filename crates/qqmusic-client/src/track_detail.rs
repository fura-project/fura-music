use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::value::RawValue;

use crate::playlist_detail::{PlaylistDetailTrackField, RawTrack, map_track};
use crate::protocol_strategy::is_musicu_rate_limited_code;
use crate::{HttpRequest, HttpTransport, QqMusicClient, QqMusicTrackSummary};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_TRACK_DETAIL_RESPONSE_BYTES: usize = 512 * 1024;
const TRACK_DETAIL_TIMEOUT: Duration = Duration::from_secs(15);

pub enum QqMusicTrackDetailError<E> {
    InvalidTrackId,
    Transport(E),
    Serialize,
    HttpStatus(u16),
    InvalidJson,
    MissingGlobalCode,
    MissingResult,
    MissingResultCode,
    RateLimited {
        code: i64,
    },
    Upstream {
        global_code: i64,
        result_code: Option<i64>,
    },
    MissingData,
    InvalidTrack {
        field: PlaylistDetailTrackField,
    },
    IdentityMismatch,
}

impl<E> fmt::Debug for QqMusicTrackDetailError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidTrackId => formatter.write_str("InvalidTrackId"),
            Self::Transport(_) => formatter.write_str("Transport([REDACTED])"),
            Self::Serialize => formatter.write_str("Serialize"),
            Self::HttpStatus(status) => formatter.debug_tuple("HttpStatus").field(status).finish(),
            Self::InvalidJson => formatter.write_str("InvalidJson([REDACTED])"),
            Self::MissingGlobalCode => formatter.write_str("MissingGlobalCode"),
            Self::MissingResult => formatter.write_str("MissingResult"),
            Self::MissingResultCode => formatter.write_str("MissingResultCode"),
            Self::RateLimited { code } => formatter
                .debug_struct("RateLimited")
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
            Self::InvalidTrack { field } => formatter
                .debug_struct("InvalidTrack")
                .field("field", field)
                .finish(),
            Self::IdentityMismatch => formatter.write_str("IdentityMismatch"),
        }
    }
}

impl<E> fmt::Display for QqMusicTrackDetailError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidTrackId => formatter.write_str("QQ Music track ID must be nonzero"),
            Self::Transport(_) => formatter.write_str("QQ Music track detail request failed"),
            Self::Serialize => formatter.write_str("could not serialize track detail request"),
            Self::HttpStatus(status) => {
                write!(formatter, "track detail request returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("track detail response was not valid JSON"),
            Self::MissingGlobalCode => {
                formatter.write_str("track detail response has no global code")
            }
            Self::MissingResult => formatter.write_str("track detail result is missing"),
            Self::MissingResultCode => formatter.write_str("track detail result has no code"),
            Self::RateLimited { code } => write!(
                formatter,
                "QQ Music rate limited track detail with code {code}"
            ),
            Self::Upstream {
                global_code,
                result_code,
            } => write!(
                formatter,
                "track detail failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("track detail data is missing"),
            Self::InvalidTrack { field } => {
                write!(formatter, "track detail had invalid field {field:?}")
            }
            Self::IdentityMismatch => {
                formatter.write_str("track detail returned a different track identity")
            }
        }
    }
}

impl<E> std::error::Error for QqMusicTrackDetailError<E>
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

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Fetches exact QQ Music track detail by numeric song ID via
    /// `music.pf_song_detail_svr/get_song_detail_yqq` on the public Web
    /// profile.
    ///
    /// Returns `Ok(None)` when the endpoint returns no usable `track_info`
    /// record (for example a removed or zero-ID historical entry), and
    /// `Err(IdentityMismatch)` if the returned record belongs to a different
    /// numeric song ID.
    ///
    /// # Errors
    ///
    /// Rejects zero IDs before transport, keeps rate-limit/upstream/malformed
    /// failures distinct, and never leaks content or credentials.
    pub async fn track_detail_by_id(
        &self,
        song_id: u64,
    ) -> Result<Option<QqMusicTrackSummary>, QqMusicTrackDetailError<T::Error>> {
        if song_id == 0 {
            return Err(QqMusicTrackDetailError::InvalidTrackId);
        }
        let body = serde_json::to_vec(&TrackDetailByIdRequest::new(song_id))
            .map_err(|_| QqMusicTrackDetailError::Serialize)?;
        let response = self
            .transport()
            .execute(
                HttpRequest::post(MUSICU_URL)
                    .header("Content-Type", "application/json")
                    .header("Origin", "https://y.qq.com")
                    .header("Referer", crate::profile::QqProtocolProfile::Web.referer())
                    .body(body)
                    .response_body_limit(MAX_TRACK_DETAIL_RESPONSE_BYTES)
                    .timeout(TRACK_DETAIL_TIMEOUT),
            )
            .await
            .map_err(QqMusicTrackDetailError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicTrackDetailError::HttpStatus(response.status()));
        }
        let envelope: TrackDetailResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicTrackDetailError::InvalidJson)?;
        map_track_detail_response(envelope, song_id)
    }

    /// Attempts exact identity recovery for an omitted playlist row that has a
    /// validated numeric `(track_id, song_type)` but failed `SongMid` checks.
    ///
    /// Recovery succeeds ONLY when `get_song_detail_yqq` returns the exact
    /// same numeric `track_id`, the exact same `song_type`, and a validated
    /// `safe_media_mid` plus valid presentation fields. Any identity mismatch
    /// is strictly rejected.
    ///
    /// # Errors
    ///
    /// Propagates transport, protocol, rate-limit, and identity-mismatch errors.
    pub async fn recover_omitted_track_by_identity(
        &self,
        expected_track_id: u64,
        expected_song_type: u32,
    ) -> Result<Option<QqMusicTrackSummary>, QqMusicTrackDetailError<T::Error>> {
        let Some(track) = self.track_detail_by_id(expected_track_id).await? else {
            return Ok(None);
        };
        if track.track_id() != expected_track_id || track.song_type() != expected_song_type {
            return Err(QqMusicTrackDetailError::IdentityMismatch);
        }
        Ok(Some(track))
    }
}

#[derive(Serialize)]
struct TrackDetailByIdRequest {
    comm: TrackDetailComm,
    songinfo: TrackDetailRpc,
}

impl TrackDetailByIdRequest {
    const fn new(song_id: u64) -> Self {
        Self {
            comm: TrackDetailComm {
                client_type: crate::profile::WEB_PUBLIC_TYPE,
                client_version: crate::profile::WEB_PUBLIC_VERSION,
                format: "json",
            },
            songinfo: TrackDetailRpc {
                module: "music.pf_song_detail_svr",
                method: "get_song_detail_yqq",
                param: TrackDetailByIdParam { song_id },
            },
        }
    }
}

#[derive(Serialize)]
struct TrackDetailComm {
    #[serde(rename = "ct")]
    client_type: u32,
    #[serde(rename = "cv")]
    client_version: u32,
    format: &'static str,
}

#[derive(Serialize)]
struct TrackDetailRpc {
    module: &'static str,
    method: &'static str,
    param: TrackDetailByIdParam,
}

#[derive(Serialize)]
struct TrackDetailByIdParam {
    song_id: u64,
}

#[derive(Deserialize)]
struct TrackDetailResponse {
    code: Option<i64>,
    songinfo: Option<TrackDetailRpcResult>,
}

#[derive(Deserialize)]
struct TrackDetailRpcResult {
    code: Option<i64>,
    data: Option<TrackDetailData>,
}

#[derive(Deserialize)]
struct TrackDetailData {
    track_info: Option<Box<RawValue>>,
}

fn map_track_detail_response<E>(
    envelope: TrackDetailResponse,
    expected_song_id: u64,
) -> Result<Option<QqMusicTrackSummary>, QqMusicTrackDetailError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicTrackDetailError::MissingGlobalCode)?;
    let result_code = envelope.songinfo.as_ref().and_then(|result| result.code);
    if let Some(code) = [Some(global_code), result_code]
        .into_iter()
        .flatten()
        .find(|code| is_musicu_rate_limited_code(*code))
    {
        return Err(QqMusicTrackDetailError::RateLimited { code });
    }
    if global_code != 0 {
        return Err(QqMusicTrackDetailError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .songinfo
        .ok_or(QqMusicTrackDetailError::MissingResult)?;
    let result_code = result
        .code
        .ok_or(QqMusicTrackDetailError::MissingResultCode)?;
    if result_code != 0 {
        return Err(QqMusicTrackDetailError::Upstream {
            global_code,
            result_code: Some(result_code),
        });
    }
    let data = result.data.ok_or(QqMusicTrackDetailError::MissingData)?;
    let Some(raw_track_info) = data.track_info else {
        return Ok(None);
    };
    let json = raw_track_info.get();
    if json == "null" || json == "{}" {
        return Ok(None);
    }
    if !json.starts_with('{') {
        return Err(QqMusicTrackDetailError::InvalidJson);
    }
    let raw: RawTrack =
        serde_json::from_str(json).map_err(|_| QqMusicTrackDetailError::InvalidJson)?;
    if matches!(raw.id, None | Some(0)) {
        return Ok(None);
    }
    let track = map_track::<E>(raw, 0).map_err(|error| match error {
        crate::QqMusicPlaylistDetailError::InvalidTrack { field, .. }
        | crate::QqMusicPlaylistDetailError::InvalidArtist { field, .. } => {
            QqMusicTrackDetailError::InvalidTrack { field }
        }
        _ => QqMusicTrackDetailError::InvalidJson,
    })?;
    if track.track_id() != expected_song_id {
        return Err(QqMusicTrackDetailError::IdentityMismatch);
    }
    Ok(Some(track))
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use super::QqMusicTrackDetailError;
    use crate::playlist_detail::PlaylistDetailTrackField;
    use crate::{HttpRequest, HttpResponse, HttpTransport, QqMusicClient};

    struct DetailTransport {
        responses: Mutex<VecDeque<HttpResponse>>,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl DetailTransport {
        fn from_json(responses: impl IntoIterator<Item = Value>) -> Self {
            Self {
                responses: Mutex::new(
                    responses
                        .into_iter()
                        .map(|value| {
                            HttpResponse::new(
                                200,
                                serde_json::to_vec(&value).expect("fixture JSON"),
                            )
                        })
                        .collect(),
                ),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn requests(&self) -> Vec<HttpRequest> {
            self.requests.lock().expect("request lock").clone()
        }
    }

    impl HttpTransport for DetailTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("request lock").push(request);
            Ok(self
                .responses
                .lock()
                .expect("response lock")
                .pop_front()
                .expect("fixture response"))
        }
    }

    fn detail_envelope(track_info: &Value) -> Value {
        json!({
            "code": 0,
            "songinfo": {
                "code": 0,
                "data": {
                    "track_info": track_info
                }
            }
        })
    }

    #[tokio::test]
    async fn recovers_exact_track_by_numeric_id_and_song_type() {
        let client = QqMusicClient::new(DetailTransport::from_json([detail_envelope(&json!({
            "id": 900_123,
            "mid": "003ExactMid900123",
            "type": 0,
            "title": "Exact Historical Track",
            "interval": 215,
            "singer": [{"id": 77, "mid": "001ArtistMid", "name": "Fixture Artist"}],
            "album": {"id": 88, "mid": "002AlbumMid", "title": "Fixture Album"},
            "file": {"media_mid": "003ExactMediaMid"}
        }))]));

        let recovered = client
            .recover_omitted_track_by_identity(900_123, 0)
            .await
            .expect("exact recovery")
            .expect("recovered track");

        assert_eq!(recovered.track_id(), 900_123);
        assert_eq!(recovered.song_type(), 0);
        assert_eq!(recovered.song_mid(), "003ExactMid900123");
        assert_eq!(recovered.file_media_mid(), Some("003ExactMediaMid"));
        assert_eq!(recovered.title(), "Exact Historical Track");

        let requests = client.transport().requests();
        assert_eq!(requests.len(), 1);
        let body: Value =
            serde_json::from_slice(requests[0].body_bytes().expect("body")).expect("request JSON");
        assert_eq!(body["comm"]["ct"], 24);
        assert_eq!(body["comm"]["cv"], 0);
        assert_eq!(body["songinfo"]["module"], "music.pf_song_detail_svr");
        assert_eq!(body["songinfo"]["method"], "get_song_detail_yqq");
        assert_eq!(body["songinfo"]["param"]["song_id"], 900_123);
    }

    #[tokio::test]
    async fn rejects_mismatched_song_id_or_song_type_and_zero_id() {
        let client = QqMusicClient::new(DetailTransport::from_json([
            detail_envelope(&json!({
                "id": 999_999,
                "mid": "003OtherMid",
                "type": 0,
                "title": "Wrong Song",
                "singer": [{"name": "Artist"}]
            })),
            detail_envelope(&json!({
                "id": 900_123,
                "mid": "003WrongTypeMid",
                "type": 13,
                "title": "Different Version",
                "singer": [{"name": "Artist"}]
            })),
        ]));

        assert!(matches!(
            client.track_detail_by_id(0).await,
            Err(QqMusicTrackDetailError::InvalidTrackId)
        ));
        assert!(client.transport().requests().is_empty());

        assert!(matches!(
            client.recover_omitted_track_by_identity(900_123, 0).await,
            Err(QqMusicTrackDetailError::IdentityMismatch)
        ));
        assert!(matches!(
            client.recover_omitted_track_by_identity(900_123, 0).await,
            Err(QqMusicTrackDetailError::IdentityMismatch)
        ));
    }

    #[tokio::test]
    async fn unrecoverable_or_unsafe_mid_detail_never_forges_track() {
        let client = QqMusicClient::new(DetailTransport::from_json([
            detail_envelope(&json!({})),
            detail_envelope(&json!({"id": 0, "mid": ""})),
            detail_envelope(&json!({
                "id": 900_123,
                "mid": "bad/mid",
                "type": 0,
                "title": "Unsafe Mid",
                "singer": [{"name": "Artist"}]
            })),
            json!({"code": 0, "songinfo": {"code": 2001}}),
        ]));

        assert!(
            client
                .recover_omitted_track_by_identity(900_123, 0)
                .await
                .expect("empty detail")
                .is_none()
        );
        assert!(
            client
                .recover_omitted_track_by_identity(900_123, 0)
                .await
                .expect("zero id detail")
                .is_none()
        );
        assert!(matches!(
            client.recover_omitted_track_by_identity(900_123, 0).await,
            Err(QqMusicTrackDetailError::InvalidTrack {
                field: PlaylistDetailTrackField::SongMid,
            })
        ));
        assert!(matches!(
            client.recover_omitted_track_by_identity(900_123, 0).await,
            Err(QqMusicTrackDetailError::RateLimited { code: 2001 })
        ));
    }
}
