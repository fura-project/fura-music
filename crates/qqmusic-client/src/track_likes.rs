use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::credential::is_credential_rejection_code;
use crate::{Credential, HttpRequest, HttpTransport, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_RESPONSE_BYTES: usize = 256 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const LIKED_SONGS_DIRECTORY_ID: u32 = 201;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicTrackLikeState {
    Liked,
    NotLiked,
}

impl QqMusicTrackLikeState {
    const fn method(self) -> &'static str {
        match self {
            Self::Liked => "AddSonglist",
            Self::NotLiked => "DelSonglist",
        }
    }
}

#[derive(PartialEq)]
pub enum QqMusicTrackLikeError<E> {
    InvalidSongId,
    Serialize,
    Transport(E),
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
    MissingMutationCode,
    MutationRejected {
        code: i64,
    },
}

impl<E> fmt::Debug for QqMusicTrackLikeError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidSongId => formatter.write_str("InvalidSongId"),
            Self::Serialize => formatter.write_str("Serialize"),
            Self::Transport(_) => formatter.write_str("Transport([REDACTED])"),
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
            Self::MissingMutationCode => formatter.write_str("MissingMutationCode"),
            Self::MutationRejected { code } => formatter
                .debug_struct("MutationRejected")
                .field("code", code)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicTrackLikeError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidSongId => formatter.write_str("track-like song ID is invalid"),
            Self::Serialize => formatter.write_str("could not serialize track-like request"),
            Self::Transport(_) => formatter.write_str("QQ Music track-like request failed"),
            Self::HttpStatus(status) => {
                write!(formatter, "track-like request returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("track-like response was not valid JSON"),
            Self::MissingGlobalCode => {
                formatter.write_str("track-like response has no global code")
            }
            Self::MissingResult => formatter.write_str("track-like result is missing"),
            Self::MissingResultCode => formatter.write_str("track-like result has no code"),
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
                "track-like request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("track-like result data is missing"),
            Self::MissingMutationCode => {
                formatter.write_str("track-like mutation result has no code")
            }
            Self::MutationRejected { code } => {
                write!(
                    formatter,
                    "track-like mutation was rejected with code {code}"
                )
            }
        }
    }
}

impl<E> std::error::Error for QqMusicTrackLikeError<E>
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
    /// Requests one exact desired membership state in the built-in liked-song
    /// collection. A successful response confirms the request; cancellation or
    /// transport failure cannot prove that the remote write did not happen.
    ///
    /// # Errors
    ///
    /// Keeps credential rejection, service rejection, transport uncertainty,
    /// and malformed responses distinct without retaining account or Track
    /// content in diagnostics.
    pub async fn set_track_liked(
        &self,
        credential: &Credential,
        song_id: u64,
        song_type: u32,
        state: QqMusicTrackLikeState,
    ) -> Result<(), QqMusicTrackLikeError<T::Error>> {
        if song_id == 0 {
            return Err(QqMusicTrackLikeError::InvalidSongId);
        }
        let body = serde_json::to_vec(&TrackLikeRequest::new(
            credential, song_id, song_type, state,
        ))
        .map_err(|_| QqMusicTrackLikeError::Serialize)?;
        let response = self
            .transport()
            .execute(
                HttpRequest::post(MUSICU_URL)
                    .header("Content-Type", "application/json")
                    .header("Origin", "https://y.qq.com")
                    .header("Referer", "https://y.qq.com/")
                    .header("Cookie", credential.musicu_cookie_header())
                    .body(body)
                    .response_body_limit(MAX_RESPONSE_BYTES)
                    .timeout(REQUEST_TIMEOUT),
            )
            .await
            .map_err(QqMusicTrackLikeError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicTrackLikeError::HttpStatus(response.status()));
        }
        let envelope: TrackLikeResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicTrackLikeError::InvalidJson)?;
        map_response(envelope)
    }
}

#[derive(Serialize)]
struct TrackLikeRequest<'a> {
    comm: TrackLikeComm<'a>,
    #[serde(rename = "req_0")]
    request: TrackLikeRpc,
}

impl<'a> TrackLikeRequest<'a> {
    fn new(
        credential: &'a Credential,
        song_id: u64,
        song_type: u32,
        state: QqMusicTrackLikeState,
    ) -> Self {
        Self {
            comm: TrackLikeComm {
                client_version: 4_747_474,
                client_type: 24,
                format: "json",
                account_id: credential.music_id(),
                auth_key: credential.music_key(),
                login_type: credential.login_type().value(),
            },
            request: TrackLikeRpc {
                module: "music.musicasset.PlaylistDetailWrite",
                method: state.method(),
                param: TrackLikeParam {
                    directory_id: LIKED_SONGS_DIRECTORY_ID,
                    songs: [TrackLikeSong { song_id, song_type }],
                },
            },
        }
    }
}

#[derive(Serialize)]
struct TrackLikeComm<'a> {
    #[serde(rename = "cv")]
    client_version: u32,
    #[serde(rename = "ct")]
    client_type: u32,
    format: &'static str,
    #[serde(rename = "uin")]
    account_id: &'a str,
    #[serde(rename = "authst")]
    auth_key: &'a str,
    #[serde(rename = "tmeLoginType")]
    login_type: u32,
}

#[derive(Serialize)]
struct TrackLikeRpc {
    module: &'static str,
    method: &'static str,
    param: TrackLikeParam,
}

#[derive(Serialize)]
struct TrackLikeParam {
    #[serde(rename = "dirId")]
    directory_id: u32,
    #[serde(rename = "v_songInfo")]
    songs: [TrackLikeSong; 1],
}

#[derive(Serialize)]
struct TrackLikeSong {
    #[serde(rename = "songId")]
    song_id: u64,
    #[serde(rename = "songType")]
    song_type: u32,
}

#[derive(Deserialize)]
struct TrackLikeResponse {
    code: Option<i64>,
    #[serde(rename = "req_0")]
    result: Option<TrackLikeResult>,
}

#[derive(Deserialize)]
struct TrackLikeResult {
    code: Option<i64>,
    data: Option<TrackLikeData>,
}

#[derive(Deserialize)]
struct TrackLikeData {
    #[serde(rename = "retCode")]
    mutation_code: Option<i64>,
}

fn map_response<E>(envelope: TrackLikeResponse) -> Result<(), QqMusicTrackLikeError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicTrackLikeError::MissingGlobalCode)?;
    let result_code = envelope.result.as_ref().and_then(|result| result.code);
    if let Some(code) = [Some(global_code), result_code]
        .into_iter()
        .flatten()
        .find(|code| is_credential_rejection_code(*code))
    {
        return Err(QqMusicTrackLikeError::Rejected { code });
    }
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicTrackLikeError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .result
        .ok_or(QqMusicTrackLikeError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicTrackLikeError::MissingResultCode)?;
    let data = result.data.ok_or(QqMusicTrackLikeError::MissingData)?;
    let mutation_code = data
        .mutation_code
        .ok_or(QqMusicTrackLikeError::MissingMutationCode)?;
    if mutation_code != 0 {
        return Err(QqMusicTrackLikeError::MutationRejected {
            code: mutation_code,
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use super::{QqMusicTrackLikeError, QqMusicTrackLikeState};
    use crate::{
        Credential, HttpMethod, HttpRequest, HttpResponse, HttpTransport, LoginType, QqMusicClient,
    };

    struct FakeTransport {
        response: HttpResponse,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl FakeTransport {
        fn new(response: &Value) -> Self {
            Self {
                response: HttpResponse::new(
                    200,
                    serde_json::to_vec(response).expect("fixture JSON"),
                ),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn requests(&self) -> Vec<HttpRequest> {
            self.requests.lock().expect("request lock").clone()
        }
    }

    impl HttpTransport for FakeTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("request lock").push(request);
            Ok(self.response.clone())
        }
    }

    fn credential() -> Credential {
        Credential::new("123456", "W_X_fixture-key", LoginType::WECHAT).expect("fixture credential")
    }

    fn success() -> Value {
        json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {"retCode": 0}
            }
        })
    }

    #[tokio::test]
    async fn sends_exact_single_track_like_and_unlike_requests() {
        for (state, method) in [
            (QqMusicTrackLikeState::Liked, "AddSonglist"),
            (QqMusicTrackLikeState::NotLiked, "DelSonglist"),
        ] {
            let client = QqMusicClient::new(FakeTransport::new(&success()));

            client
                .set_track_liked(&credential(), 41_001, 7, state)
                .await
                .expect("confirmed mutation");

            let requests = client.transport().requests();
            assert_eq!(requests.len(), 1);
            let request = &requests[0];
            assert_eq!(request.method(), HttpMethod::Post);
            assert!(request.url().contains("musicu.fcg"));
            assert_eq!(request.max_response_body_bytes(), 256 * 1024);
            assert_eq!(
                request.request_timeout(),
                Some(std::time::Duration::from_secs(30))
            );
            let debug = format!("{request:?}");
            assert!(!debug.contains("W_X_fixture-key"));
            assert!(!debug.contains("41001"));
            let body: Value = serde_json::from_slice(request.body_bytes().expect("request body"))
                .expect("request JSON");
            assert_eq!(
                body["req_0"]["module"],
                "music.musicasset.PlaylistDetailWrite"
            );
            assert_eq!(body["req_0"]["method"], method);
            assert_eq!(body["req_0"]["param"]["dirId"], 201);
            assert_eq!(
                body["req_0"]["param"]["v_songInfo"],
                json!([{"songId": 41_001, "songType": 7}])
            );
        }
    }

    #[tokio::test]
    async fn rejects_invalid_identity_before_transport() {
        let client = QqMusicClient::new(FakeTransport::new(&success()));

        assert_eq!(
            client
                .set_track_liked(&credential(), 0, 0, QqMusicTrackLikeState::Liked)
                .await,
            Err(QqMusicTrackLikeError::InvalidSongId)
        );
        assert!(client.transport().requests().is_empty());
    }

    #[tokio::test]
    async fn preserves_credential_service_and_response_failures() {
        let cases = [
            (
                json!({"code": 104_401, "req_0": {"code": 0, "data": {"retCode": 0}}}),
                QqMusicTrackLikeError::Rejected { code: 104_401 },
            ),
            (
                json!({"code": 0, "req_0": {"code": 50_006}}),
                QqMusicTrackLikeError::Upstream {
                    global_code: 0,
                    result_code: Some(50_006),
                },
            ),
            (
                json!({"code": 0, "req_0": {"code": 0, "data": {"retCode": 80_092}}}),
                QqMusicTrackLikeError::MutationRejected { code: 80_092 },
            ),
            (
                json!({"code": 0, "req_0": {"code": 0, "data": {}}}),
                QqMusicTrackLikeError::MissingMutationCode,
            ),
        ];
        for (fixture, expected) in cases {
            let client = QqMusicClient::new(FakeTransport::new(&fixture));
            assert_eq!(
                client
                    .set_track_liked(&credential(), 41_001, 0, QqMusicTrackLikeState::Liked)
                    .await,
                Err(expected)
            );
        }
    }
}
