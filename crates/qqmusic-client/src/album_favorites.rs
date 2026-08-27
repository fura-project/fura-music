use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::credential::is_credential_rejection_code;
use crate::{Credential, HttpRequest, HttpTransport, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_RESPONSE_BYTES: usize = 256 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QqMusicAlbumFavoriteState {
    Favorite,
    NotFavorite,
}

impl QqMusicAlbumFavoriteState {
    const fn method(self) -> &'static str {
        match self {
            Self::Favorite => "FavAlbum",
            Self::NotFavorite => "CancelFavAlbum",
        }
    }
}

#[derive(PartialEq)]
pub enum QqMusicAlbumFavoriteError<E> {
    InvalidAlbumId,
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
    MissingFailedAlbumIds,
    FailedAlbumIds,
    InvalidFailedAlbumIds,
}

impl<E> fmt::Debug for QqMusicAlbumFavoriteError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidAlbumId => formatter.write_str("InvalidAlbumId"),
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
            Self::MissingFailedAlbumIds => formatter.write_str("MissingFailedAlbumIds"),
            Self::FailedAlbumIds => formatter.write_str("FailedAlbumIds([REDACTED])"),
            Self::InvalidFailedAlbumIds => formatter.write_str("InvalidFailedAlbumIds([REDACTED])"),
        }
    }
}

impl<E> fmt::Display for QqMusicAlbumFavoriteError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::InvalidAlbumId => "Album ID is invalid",
            Self::Serialize => "could not serialize Album favorite request",
            Self::Transport(_) => "QQ Music Album favorite request failed",
            Self::HttpStatus(_) => "Album favorite request returned an HTTP error",
            Self::InvalidJson => "Album favorite response was not valid JSON",
            Self::MissingGlobalCode => "Album favorite response has no global code",
            Self::MissingResult => "Album favorite result is missing",
            Self::MissingResultCode => "Album favorite result has no code",
            Self::Rejected { .. } => "QQ Music rejected the Album favorite credential",
            Self::Upstream { .. } => "QQ Music rejected the Album favorite request",
            Self::MissingData => "Album favorite data is missing",
            Self::MissingMutationCode => "Album favorite mutation result has no code",
            Self::MutationRejected { .. } => "Album favorite mutation was rejected",
            Self::MissingFailedAlbumIds => "Album favorite response has no failed-ID list",
            Self::FailedAlbumIds => "Album favorite response reports failed items",
            Self::InvalidFailedAlbumIds => {
                "Album favorite response reports an unexpected failed-ID list"
            }
        };
        formatter.write_str(message)
    }
}

impl<E> std::error::Error for QqMusicAlbumFavoriteError<E>
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
    /// Requests one exact desired favorite state for one numeric Album ID.
    /// Transport or malformed-response failure cannot prove that the remote
    /// write did not happen.
    ///
    /// # Errors
    ///
    /// Rejects a zero ID before transport and preserves credential rejection,
    /// service rejection, transport uncertainty, and malformed responses.
    pub async fn set_album_favorite(
        &self,
        credential: &Credential,
        album_id: u64,
        state: QqMusicAlbumFavoriteState,
    ) -> Result<(), QqMusicAlbumFavoriteError<T::Error>> {
        if album_id == 0 {
            return Err(QqMusicAlbumFavoriteError::InvalidAlbumId);
        }
        let body = serde_json::to_vec(&AlbumFavoriteRequest::new(credential, album_id, state))
            .map_err(|_| QqMusicAlbumFavoriteError::Serialize)?;
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
            .map_err(QqMusicAlbumFavoriteError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicAlbumFavoriteError::HttpStatus(response.status()));
        }
        let envelope: AlbumFavoriteResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicAlbumFavoriteError::InvalidJson)?;
        map_response(envelope, album_id)
    }
}

#[derive(Serialize)]
struct AlbumFavoriteRequest<'a> {
    comm: AlbumFavoriteComm<'a>,
    #[serde(rename = "req_0")]
    request: AlbumFavoriteRpc,
}

impl<'a> AlbumFavoriteRequest<'a> {
    fn new(credential: &'a Credential, album_id: u64, state: QqMusicAlbumFavoriteState) -> Self {
        Self {
            comm: AlbumFavoriteComm {
                client_version: 4_747_474,
                client_type: 24,
                format: "json",
                account_id: credential.music_id(),
                auth_key: credential.music_key(),
                login_type: credential.login_type().value(),
            },
            request: AlbumFavoriteRpc {
                module: "music.musicasset.AlbumFavWrite",
                method: state.method(),
                param: AlbumFavoriteParam {
                    album_ids: [album_id],
                },
            },
        }
    }
}

#[derive(Serialize)]
struct AlbumFavoriteComm<'a> {
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
struct AlbumFavoriteRpc {
    module: &'static str,
    method: &'static str,
    param: AlbumFavoriteParam,
}

#[derive(Serialize)]
struct AlbumFavoriteParam {
    #[serde(rename = "v_albumId")]
    album_ids: [u64; 1],
}

#[derive(Deserialize)]
struct AlbumFavoriteResponse {
    code: Option<i64>,
    #[serde(rename = "req_0")]
    result: Option<AlbumFavoriteResultEnvelope>,
}

#[derive(Deserialize)]
struct AlbumFavoriteResultEnvelope {
    code: Option<i64>,
    data: Option<AlbumFavoriteData>,
}

#[derive(Deserialize)]
struct AlbumFavoriteData {
    result: Option<i64>,
    #[serde(rename = "v_failedAlbumId")]
    failed_album_ids: Option<Vec<u64>>,
}

fn map_response<E>(
    envelope: AlbumFavoriteResponse,
    album_id: u64,
) -> Result<(), QqMusicAlbumFavoriteError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicAlbumFavoriteError::MissingGlobalCode)?;
    let result_code = envelope.result.as_ref().and_then(|result| result.code);
    if let Some(code) = [Some(global_code), result_code]
        .into_iter()
        .flatten()
        .find(|code| is_credential_rejection_code(*code))
    {
        return Err(QqMusicAlbumFavoriteError::Rejected { code });
    }
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicAlbumFavoriteError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .result
        .ok_or(QqMusicAlbumFavoriteError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicAlbumFavoriteError::MissingResultCode)?;
    let data = result.data.ok_or(QqMusicAlbumFavoriteError::MissingData)?;
    let mutation_code = data
        .result
        .ok_or(QqMusicAlbumFavoriteError::MissingMutationCode)?;
    if mutation_code != 0 {
        return Err(QqMusicAlbumFavoriteError::MutationRejected {
            code: mutation_code,
        });
    }
    let failed_album_ids = data
        .failed_album_ids
        .ok_or(QqMusicAlbumFavoriteError::MissingFailedAlbumIds)?;
    match failed_album_ids.as_slice() {
        [] => Ok(()),
        [failed_album_id] if *failed_album_id == album_id => {
            Err(QqMusicAlbumFavoriteError::FailedAlbumIds)
        }
        _ => Err(QqMusicAlbumFavoriteError::InvalidFailedAlbumIds),
    }
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use super::{QqMusicAlbumFavoriteError, QqMusicAlbumFavoriteState};
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
        Credential::new("123456", "W_X_fixture-key", LoginType::WECHAT).expect("credential")
    }

    fn success() -> Value {
        json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {"result": 0, "v_failedAlbumId": []}
            }
        })
    }

    #[tokio::test]
    async fn sends_exact_favorite_and_cancel_requests() {
        for (state, method) in [
            (QqMusicAlbumFavoriteState::Favorite, "FavAlbum"),
            (QqMusicAlbumFavoriteState::NotFavorite, "CancelFavAlbum"),
        ] {
            let client = QqMusicClient::new(FakeTransport::new(&success()));
            client
                .set_album_favorite(&credential(), 43_001, state)
                .await
                .expect("confirmed mutation");

            let requests = client.transport().requests();
            assert_eq!(requests.len(), 1);
            assert_eq!(requests[0].method(), HttpMethod::Post);
            assert_eq!(requests[0].max_response_body_bytes(), 256 * 1024);
            assert_eq!(
                requests[0].request_timeout(),
                Some(std::time::Duration::from_secs(30))
            );
            let debug = format!("{:?}", requests[0]);
            assert!(!debug.contains("W_X_fixture-key"));
            assert!(!debug.contains("43001"));
            let body: Value =
                serde_json::from_slice(requests[0].body_bytes().expect("favorite request body"))
                    .expect("request JSON");
            assert_eq!(body["req_0"]["module"], "music.musicasset.AlbumFavWrite");
            assert_eq!(body["req_0"]["method"], method);
            assert_eq!(body["req_0"]["param"], json!({"v_albumId": [43_001]}));
        }
    }

    #[tokio::test]
    async fn rejects_zero_id_before_transport() {
        let client = QqMusicClient::new(FakeTransport::new(&success()));
        assert_eq!(
            client
                .set_album_favorite(&credential(), 0, QqMusicAlbumFavoriteState::Favorite)
                .await,
            Err(QqMusicAlbumFavoriteError::InvalidAlbumId)
        );
        assert!(client.transport().requests().is_empty());
    }

    #[tokio::test]
    async fn keeps_rejection_and_uncertain_responses_distinct() {
        let cases = [
            (
                json!({"code": 0, "req_0": {"code": 104_401}}),
                QqMusicAlbumFavoriteError::Rejected { code: 104_401 },
            ),
            (
                json!({"code": 0, "req_0": {"code": 0, "data": {"result": 80092, "v_failedAlbumId": []}}}),
                QqMusicAlbumFavoriteError::MutationRejected { code: 80_092 },
            ),
            (
                json!({"code": 0, "req_0": {"code": 0, "data": {"result": 0}}}),
                QqMusicAlbumFavoriteError::MissingFailedAlbumIds,
            ),
            (
                json!({"code": 0, "req_0": {"code": 0, "data": {"result": 0, "v_failedAlbumId": [43_001]}}}),
                QqMusicAlbumFavoriteError::FailedAlbumIds,
            ),
            (
                json!({"code": 0, "req_0": {"code": 0, "data": {"result": 0, "v_failedAlbumId": [99_999]}}}),
                QqMusicAlbumFavoriteError::InvalidFailedAlbumIds,
            ),
        ];
        for (fixture, expected) in cases {
            let client = QqMusicClient::new(FakeTransport::new(&fixture));
            assert_eq!(
                client
                    .set_album_favorite(&credential(), 43_001, QqMusicAlbumFavoriteState::Favorite,)
                    .await,
                Err(expected)
            );
        }
    }
}
