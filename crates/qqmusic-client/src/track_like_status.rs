use std::collections::{HashMap, HashSet};
use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::credential::is_credential_rejection_code;
use crate::{Credential, HttpRequest, HttpTransport, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_RESPONSE_BYTES: usize = 256 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

/// A deliberately small Fura research bound, not a claimed QQ protocol limit.
/// Current community code accepts larger batches, but the live gate for this
/// candidate is authorized to exercise only one MID and one small batch.
pub const MAX_TRACK_LIKE_STATUS_BATCH_SIZE: usize = 20;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicTrackLikeStatus {
    Liked,
    NotLiked,
    /// The requested key was absent or its value was not a boolean. This must
    /// never be interpreted as `NotLiked`.
    Unknown,
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicTrackLikeStatusBatch {
    statuses: Vec<QqMusicTrackLikeStatus>,
    response_key_count: usize,
}

impl QqMusicTrackLikeStatusBatch {
    #[must_use]
    pub fn statuses(&self) -> &[QqMusicTrackLikeStatus] {
        &self.statuses
    }

    #[must_use]
    pub const fn response_key_count(&self) -> usize {
        self.response_key_count
    }
}

impl fmt::Debug for QqMusicTrackLikeStatusBatch {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let liked_count = self
            .statuses
            .iter()
            .filter(|status| **status == QqMusicTrackLikeStatus::Liked)
            .count();
        let not_liked_count = self
            .statuses
            .iter()
            .filter(|status| **status == QqMusicTrackLikeStatus::NotLiked)
            .count();
        let unknown_count = self.statuses.len() - liked_count - not_liked_count;
        formatter
            .debug_struct("QqMusicTrackLikeStatusBatch")
            .field("requested_count", &self.statuses.len())
            .field("response_key_count", &self.response_key_count)
            .field("liked_count", &liked_count)
            .field("not_liked_count", &not_liked_count)
            .field("unknown_count", &unknown_count)
            .finish()
    }
}

#[derive(PartialEq)]
pub enum QqMusicTrackLikeStatusError<E> {
    InvalidBatchSize {
        size: usize,
    },
    InvalidSongMid {
        index: usize,
    },
    DuplicateSongMid {
        index: usize,
    },
    Serialize,
    Transport(E),
    HttpStatus(u16),
    RateLimited,
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
    MissingStatusMap,
}

impl<E> fmt::Debug for QqMusicTrackLikeStatusError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidBatchSize { size } => formatter
                .debug_struct("InvalidBatchSize")
                .field("size", size)
                .finish(),
            Self::InvalidSongMid { index } => formatter
                .debug_struct("InvalidSongMid")
                .field("index", index)
                .finish(),
            Self::DuplicateSongMid { index } => formatter
                .debug_struct("DuplicateSongMid")
                .field("index", index)
                .finish(),
            Self::Serialize => formatter.write_str("Serialize"),
            Self::Transport(_) => formatter.write_str("Transport([REDACTED])"),
            Self::HttpStatus(status) => formatter.debug_tuple("HttpStatus").field(status).finish(),
            Self::RateLimited => formatter.write_str("RateLimited"),
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
            Self::MissingStatusMap => formatter.write_str("MissingStatusMap"),
        }
    }
}

impl<E> fmt::Display for QqMusicTrackLikeStatusError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidBatchSize { size } => write!(
                formatter,
                "Track-like status batch size {size} is outside 1..={MAX_TRACK_LIKE_STATUS_BATCH_SIZE}"
            ),
            Self::InvalidSongMid { index } => {
                write!(formatter, "Track-like status MID {index} is invalid")
            }
            Self::DuplicateSongMid { index } => {
                write!(formatter, "Track-like status MID {index} is duplicated")
            }
            Self::Serialize => formatter.write_str("could not serialize Track-like status request"),
            Self::Transport(_) => formatter.write_str("QQ Music Track-like status request failed"),
            Self::HttpStatus(status) => {
                write!(
                    formatter,
                    "Track-like status request returned HTTP {status}"
                )
            }
            Self::RateLimited => formatter.write_str("QQ Music rate-limited Track-like status"),
            Self::InvalidJson => {
                formatter.write_str("Track-like status response was not valid JSON")
            }
            Self::MissingGlobalCode => {
                formatter.write_str("Track-like status response has no global code")
            }
            Self::MissingResult => formatter.write_str("Track-like status result is missing"),
            Self::MissingResultCode => formatter.write_str("Track-like status result has no code"),
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
                "Track-like status failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("Track-like status data is missing"),
            Self::MissingStatusMap => {
                formatter.write_str("Track-like status boolean map is missing")
            }
        }
    }
}

impl<E> std::error::Error for QqMusicTrackLikeStatusError<E>
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
    /// Research candidate for QQ's per-MID liked-state read. This method is
    /// intentionally not wired into the Provider or Flutter production path.
    /// Individual missing/non-boolean entries map to `Unknown`, never false.
    ///
    /// # Errors
    ///
    /// Rejects invalid or duplicate MIDs before transport and keeps HTTP,
    /// credential, upstream, transport, and envelope failures distinct.
    pub async fn track_like_statuses(
        &self,
        credential: &Credential,
        song_mids: &[&str],
    ) -> Result<QqMusicTrackLikeStatusBatch, QqMusicTrackLikeStatusError<T::Error>> {
        validate_song_mids::<T::Error>(song_mids)?;
        let body = serde_json::to_vec(&TrackLikeStatusRequest::new(credential, song_mids))
            .map_err(|_| QqMusicTrackLikeStatusError::Serialize)?;
        let response = self
            .transport()
            .execute(
                HttpRequest::post(MUSICU_URL)
                    .header("Content-Type", "application/json")
                    .header("Origin", "https://y.qq.com")
                    .header("Referer", crate::profile::QqProtocolProfile::Web.referer())
                    .header("Cookie", credential.musicu_cookie_header())
                    .body(body)
                    .response_body_limit(MAX_RESPONSE_BYTES)
                    .timeout(REQUEST_TIMEOUT),
            )
            .await
            .map_err(QqMusicTrackLikeStatusError::Transport)?;
        if response.status() == 429 {
            return Err(QqMusicTrackLikeStatusError::RateLimited);
        }
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicTrackLikeStatusError::HttpStatus(response.status()));
        }
        let envelope: TrackLikeStatusResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicTrackLikeStatusError::InvalidJson)?;
        map_response(envelope, song_mids)
    }
}

fn validate_song_mids<E>(song_mids: &[&str]) -> Result<(), QqMusicTrackLikeStatusError<E>> {
    if !(1..=MAX_TRACK_LIKE_STATUS_BATCH_SIZE).contains(&song_mids.len()) {
        return Err(QqMusicTrackLikeStatusError::InvalidBatchSize {
            size: song_mids.len(),
        });
    }
    let mut seen = HashSet::with_capacity(song_mids.len());
    for (index, song_mid) in song_mids.iter().enumerate() {
        if song_mid.is_empty()
            || song_mid.len() > 64
            || !song_mid.bytes().all(|byte| byte.is_ascii_alphanumeric())
        {
            return Err(QqMusicTrackLikeStatusError::InvalidSongMid { index });
        }
        if !seen.insert(*song_mid) {
            return Err(QqMusicTrackLikeStatusError::DuplicateSongMid { index });
        }
    }
    Ok(())
}

#[derive(Serialize)]
struct TrackLikeStatusRequest<'a> {
    comm: TrackLikeStatusComm<'a>,
    #[serde(rename = "music.musicasset.SongFavRead")]
    request: TrackLikeStatusRpc<'a>,
}

impl<'a> TrackLikeStatusRequest<'a> {
    fn new(credential: &'a Credential, song_mids: &'a [&'a str]) -> Self {
        Self {
            comm: TrackLikeStatusComm {
                cv: crate::profile::WEB_MODERN_VERSION,
                version: crate::profile::WEB_MODERN_VERSION,
                client_type: crate::profile::WEB_MODERN_TYPE,
                app_id: crate::profile::WEB_APP_ID,
                format: "json",
                input_charset: "utf-8",
                output_charset: "utf-8",
                user_id: credential.music_id(),
                account_id: credential.music_id(),
                auth_key: credential.music_key(),
                login_type: credential.login_type().value(),
                login_uin: credential.music_id(),
            },
            request: TrackLikeStatusRpc {
                module: "music.musicasset.SongFavRead",
                method: "IsSongFanByMid",
                param: TrackLikeStatusParam { song_mids },
            },
        }
    }
}

#[derive(Serialize)]
struct TrackLikeStatusComm<'a> {
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

#[derive(Serialize)]
struct TrackLikeStatusRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: TrackLikeStatusParam<'a>,
}

#[derive(Serialize)]
struct TrackLikeStatusParam<'a> {
    #[serde(rename = "v_songMid")]
    song_mids: &'a [&'a str],
}

#[derive(Deserialize)]
struct TrackLikeStatusResponse {
    code: Option<i64>,
    #[serde(rename = "music.musicasset.SongFavRead")]
    result: Option<TrackLikeStatusResult>,
}

#[derive(Deserialize)]
struct TrackLikeStatusResult {
    code: Option<i64>,
    data: Option<TrackLikeStatusData>,
}

#[derive(Deserialize)]
struct TrackLikeStatusData {
    #[serde(rename = "m_fan")]
    statuses: Option<HashMap<String, Value>>,
}

fn map_response<E>(
    envelope: TrackLikeStatusResponse,
    song_mids: &[&str],
) -> Result<QqMusicTrackLikeStatusBatch, QqMusicTrackLikeStatusError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicTrackLikeStatusError::MissingGlobalCode)?;
    let result_code = envelope.result.as_ref().and_then(|result| result.code);
    if let Some(code) = [Some(global_code), result_code]
        .into_iter()
        .flatten()
        .find(|code| *code == 301 || is_credential_rejection_code(*code))
    {
        return Err(QqMusicTrackLikeStatusError::Rejected { code });
    }
    if global_code != 0 {
        return Err(QqMusicTrackLikeStatusError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .result
        .ok_or(QqMusicTrackLikeStatusError::MissingResult)?;
    let result_code = result
        .code
        .ok_or(QqMusicTrackLikeStatusError::MissingResultCode)?;
    if result_code != 0 {
        return Err(QqMusicTrackLikeStatusError::Upstream {
            global_code,
            result_code: Some(result_code),
        });
    }
    let data = result
        .data
        .ok_or(QqMusicTrackLikeStatusError::MissingData)?;
    let statuses = data
        .statuses
        .ok_or(QqMusicTrackLikeStatusError::MissingStatusMap)?;
    let response_key_count = statuses.len();
    let statuses = song_mids
        .iter()
        .map(|song_mid| match statuses.get(*song_mid) {
            Some(Value::Bool(true)) => QqMusicTrackLikeStatus::Liked,
            Some(Value::Bool(false)) => QqMusicTrackLikeStatus::NotLiked,
            Some(_) | None => QqMusicTrackLikeStatus::Unknown,
        })
        .collect();
    Ok(QqMusicTrackLikeStatusBatch {
        statuses,
        response_key_count,
    })
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use super::{
        MAX_TRACK_LIKE_STATUS_BATCH_SIZE, QqMusicTrackLikeStatus, QqMusicTrackLikeStatusError,
    };
    use crate::{
        Credential, HttpMethod, HttpRequest, HttpResponse, HttpTransport, LoginType, QqMusicClient,
    };

    struct FakeTransport {
        responses: Mutex<VecDeque<HttpResponse>>,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl FakeTransport {
        fn new(status: u16, response: &Value) -> Self {
            Self {
                responses: Mutex::new(
                    [HttpResponse::new(
                        status,
                        serde_json::to_vec(response).expect("fixture JSON"),
                    )]
                    .into(),
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
            Ok(self
                .responses
                .lock()
                .expect("response lock")
                .pop_front()
                .expect("fixture response"))
        }
    }

    fn credential(login_type: LoginType) -> Credential {
        Credential::new("123456", "W_X_fixture-key", login_type).expect("fixture credential")
    }

    fn response(statuses: &Value) -> Value {
        json!({
            "code": 0,
            "music.musicasset.SongFavRead": {
                "code": 0,
                "data": {"m_fan": statuses, "private": "must-not-leak"}
            }
        })
    }

    #[tokio::test]
    async fn sends_evidenced_web_request_for_single_and_small_batch() {
        for login_type in [LoginType::WECHAT, LoginType::QQ] {
            let client = QqMusicClient::new(FakeTransport::new(
                200,
                &response(&json!({"FixtureMidA1": true, "FixtureMidB2": false})),
            ));
            let result = client
                .track_like_statuses(&credential(login_type), &["FixtureMidA1", "FixtureMidB2"])
                .await
                .expect("fixture status response");
            assert_eq!(
                result.statuses(),
                [
                    QqMusicTrackLikeStatus::Liked,
                    QqMusicTrackLikeStatus::NotLiked,
                ]
            );
            assert_eq!(result.response_key_count(), 2);

            let requests = client.transport().requests();
            assert_eq!(requests.len(), 1);
            let request = &requests[0];
            assert_eq!(request.method(), HttpMethod::Post);
            assert_eq!(request.url(), "https://u.y.qq.com/cgi-bin/musicu.fcg");
            assert_eq!(request.max_response_body_bytes(), 256 * 1024);
            assert_eq!(
                request.request_timeout(),
                Some(std::time::Duration::from_secs(30))
            );
            let body: Value = serde_json::from_slice(
                request
                    .body_bytes()
                    .expect("Track-like status request body"),
            )
            .expect("request JSON");
            assert_eq!(body["comm"]["ct"], "11");
            assert_eq!(body["comm"]["cv"], 13_020_508);
            assert_eq!(body["comm"]["tmeLoginType"], login_type.value());
            assert_eq!(
                body["music.musicasset.SongFavRead"]["module"],
                "music.musicasset.SongFavRead"
            );
            assert_eq!(
                body["music.musicasset.SongFavRead"]["method"],
                "IsSongFanByMid"
            );
            assert_eq!(
                body["music.musicasset.SongFavRead"]["param"]["v_songMid"],
                json!(["FixtureMidA1", "FixtureMidB2"])
            );
            let debug = format!("{request:?} {result:?}");
            for private in [
                "fixture-key",
                "FixtureMidA1",
                "FixtureMidB2",
                "must-not-leak",
            ] {
                assert!(!debug.contains(private));
            }
        }
    }

    #[tokio::test]
    async fn missing_or_non_boolean_entries_are_unknown_not_not_liked() {
        let client = QqMusicClient::new(FakeTransport::new(
            200,
            &response(&json!({"FixtureMidA1": "false"})),
        ));
        let result = client
            .track_like_statuses(
                &credential(LoginType::QQ),
                &["FixtureMidA1", "FixtureMidB2"],
            )
            .await
            .expect("partial status response");
        assert_eq!(
            result.statuses(),
            [
                QqMusicTrackLikeStatus::Unknown,
                QqMusicTrackLikeStatus::Unknown
            ]
        );
        assert_eq!(result.response_key_count(), 1);
    }

    #[tokio::test]
    async fn invalid_or_duplicate_mids_do_not_reach_transport() {
        for mids in [
            Vec::<&str>::new(),
            vec![""],
            vec!["bad mid"],
            vec!["FixtureMidA1", "FixtureMidA1"],
            vec!["A"; MAX_TRACK_LIKE_STATUS_BATCH_SIZE + 1],
        ] {
            let client = QqMusicClient::new(FakeTransport::new(200, &response(&json!({}))));
            assert!(
                client
                    .track_like_statuses(&credential(LoginType::WECHAT), &mids)
                    .await
                    .is_err()
            );
            assert!(client.transport().requests().is_empty());
        }
    }

    #[tokio::test]
    async fn keeps_rate_limit_rejection_upstream_and_shape_failures_distinct() {
        let cases = [
            (
                429,
                response(&json!({})),
                QqMusicTrackLikeStatusError::RateLimited,
            ),
            (
                200,
                json!({
                    "code": 0,
                    "music.musicasset.SongFavRead": {"code": 301, "data": {"m_fan": {}}}
                }),
                QqMusicTrackLikeStatusError::Rejected { code: 301 },
            ),
            (
                200,
                json!({
                    "code": 0,
                    "music.musicasset.SongFavRead": {"code": 50_006, "data": {"m_fan": {}}}
                }),
                QqMusicTrackLikeStatusError::Upstream {
                    global_code: 0,
                    result_code: Some(50_006),
                },
            ),
            (
                200,
                json!({
                    "code": 0,
                    "music.musicasset.SongFavRead": {"code": 0, "data": {}}
                }),
                QqMusicTrackLikeStatusError::MissingStatusMap,
            ),
        ];
        for (status, fixture, expected) in cases {
            let client = QqMusicClient::new(FakeTransport::new(status, &fixture));
            assert_eq!(
                client
                    .track_like_statuses(&credential(LoginType::QQ), &["FixtureMidA1"])
                    .await,
                Err(expected)
            );
            assert_eq!(client.transport().requests().len(), 1);
        }
    }
}
