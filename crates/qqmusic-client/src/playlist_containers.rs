use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::credential::is_credential_rejection_code;
use crate::{Credential, HttpRequest, HttpTransport, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_RESPONSE_BYTES: usize = 256 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_PLAYLIST_NAME_BYTES: usize = 256;

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicCreatedPlaylist {
    playlist_id: u64,
    directory_id: u64,
    name: String,
}

impl QqMusicCreatedPlaylist {
    #[must_use]
    pub const fn playlist_id(&self) -> u64 {
        self.playlist_id
    }

    #[must_use]
    pub const fn directory_id(&self) -> u64 {
        self.directory_id
    }

    #[must_use]
    pub fn name(&self) -> &str {
        &self.name
    }
}

impl fmt::Debug for QqMusicCreatedPlaylist {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicCreatedPlaylist")
            .field("playlist_id", &"[REDACTED]")
            .field("directory_id", &"[REDACTED]")
            .field("name", &"[REDACTED]")
            .finish()
    }
}

#[derive(PartialEq)]
pub enum QqMusicCreatePlaylistError<E> {
    InvalidName,
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
    MissingCreatedResult,
    MissingPlaylistId,
    ConflictingPlaylistId,
    MissingDirectoryId,
    InvalidReturnedName,
}

#[derive(PartialEq)]
pub enum QqMusicDeletePlaylistError<E> {
    InvalidDirectoryId,
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
    MissingDeletedResult,
    MissingDirectoryId,
    MismatchedDirectoryId,
}

impl<E> fmt::Debug for QqMusicDeletePlaylistError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidDirectoryId => formatter.write_str("InvalidDirectoryId([REDACTED])"),
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
            Self::MissingDeletedResult => formatter.write_str("MissingDeletedResult"),
            Self::MissingDirectoryId => formatter.write_str("MissingDirectoryId"),
            Self::MismatchedDirectoryId => formatter.write_str("MismatchedDirectoryId([REDACTED])"),
        }
    }
}

impl<E> fmt::Display for QqMusicDeletePlaylistError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::InvalidDirectoryId => "playlist directory ID is invalid",
            Self::Serialize => "could not serialize delete-playlist request",
            Self::Transport(_) => "QQ Music delete-playlist request failed",
            Self::HttpStatus(_) => "delete-playlist request returned an HTTP error",
            Self::InvalidJson => "delete-playlist response was not valid JSON",
            Self::MissingGlobalCode => "delete-playlist response has no global code",
            Self::MissingResult => "delete-playlist result is missing",
            Self::MissingResultCode => "delete-playlist result has no code",
            Self::Rejected { .. } => "QQ Music rejected the delete-playlist credential",
            Self::Upstream { .. } => "QQ Music rejected the delete-playlist request",
            Self::MissingData => "delete-playlist data is missing",
            Self::MissingMutationCode => "delete-playlist mutation result has no code",
            Self::MutationRejected { .. } => "delete-playlist mutation was rejected",
            Self::MissingDeletedResult => "deleted-playlist result is missing",
            Self::MissingDirectoryId => "deleted-playlist result has no directory ID",
            Self::MismatchedDirectoryId => {
                "deleted-playlist result does not confirm the requested directory"
            }
        };
        formatter.write_str(message)
    }
}

impl<E> std::error::Error for QqMusicDeletePlaylistError<E>
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

impl<E> fmt::Debug for QqMusicCreatePlaylistError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidName => formatter.write_str("InvalidName([REDACTED])"),
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
            Self::MissingCreatedResult => formatter.write_str("MissingCreatedResult"),
            Self::MissingPlaylistId => formatter.write_str("MissingPlaylistId"),
            Self::ConflictingPlaylistId => formatter.write_str("ConflictingPlaylistId"),
            Self::MissingDirectoryId => formatter.write_str("MissingDirectoryId"),
            Self::InvalidReturnedName => formatter.write_str("InvalidReturnedName([REDACTED])"),
        }
    }
}

impl<E> fmt::Display for QqMusicCreatePlaylistError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::InvalidName => "playlist name is invalid",
            Self::Serialize => "could not serialize create-playlist request",
            Self::Transport(_) => "QQ Music create-playlist request failed",
            Self::HttpStatus(_) => "create-playlist request returned an HTTP error",
            Self::InvalidJson => "create-playlist response was not valid JSON",
            Self::MissingGlobalCode => "create-playlist response has no global code",
            Self::MissingResult => "create-playlist result is missing",
            Self::MissingResultCode => "create-playlist result has no code",
            Self::Rejected { .. } => "QQ Music rejected the create-playlist credential",
            Self::Upstream { .. } => "QQ Music rejected the create-playlist request",
            Self::MissingData => "create-playlist data is missing",
            Self::MissingMutationCode => "create-playlist mutation result has no code",
            Self::MutationRejected { .. } => "create-playlist mutation was rejected",
            Self::MissingCreatedResult => "created-playlist result is missing",
            Self::MissingPlaylistId => "created playlist has no ID",
            Self::ConflictingPlaylistId => "created playlist has conflicting IDs",
            Self::MissingDirectoryId => "created playlist has no directory ID",
            Self::InvalidReturnedName => "created playlist has an invalid name",
        };
        formatter.write_str(message)
    }
}

impl<E> std::error::Error for QqMusicCreatePlaylistError<E>
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
    /// Creates one owned playlist and returns only its server-confirmed
    /// identity and name. A transport or malformed-response failure cannot
    /// prove that the remote write did not happen.
    ///
    /// # Errors
    ///
    /// Rejects an invalid name before transport and keeps credential rejection,
    /// service rejection, transport uncertainty, and malformed responses
    /// distinct without retaining account or playlist content in diagnostics.
    pub async fn create_playlist(
        &self,
        credential: &Credential,
        name: &str,
    ) -> Result<QqMusicCreatedPlaylist, QqMusicCreatePlaylistError<T::Error>> {
        if !is_valid_playlist_name(name) {
            return Err(QqMusicCreatePlaylistError::InvalidName);
        }
        let body = serde_json::to_vec(&CreatePlaylistRequest::new(credential, name))
            .map_err(|_| QqMusicCreatePlaylistError::Serialize)?;
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
            .map_err(QqMusicCreatePlaylistError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicCreatePlaylistError::HttpStatus(response.status()));
        }
        let envelope: CreatePlaylistResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicCreatePlaylistError::InvalidJson)?;
        map_response(envelope)
    }

    /// Deletes exactly one owned playlist directory and returns only after the
    /// response confirms the same nonzero directory ID. Transport or malformed
    /// response failures cannot prove that the remote write did not happen.
    ///
    /// # Errors
    ///
    /// Rejects a zero directory ID before transport and keeps credential
    /// rejection, service rejection, transport uncertainty, and malformed or
    /// mismatched confirmation distinct without retaining playlist identity.
    pub async fn delete_playlist(
        &self,
        credential: &Credential,
        directory_id: u64,
    ) -> Result<(), QqMusicDeletePlaylistError<T::Error>> {
        if directory_id == 0 {
            return Err(QqMusicDeletePlaylistError::InvalidDirectoryId);
        }
        let body = serde_json::to_vec(&DeletePlaylistRequest::new(credential, directory_id))
            .map_err(|_| QqMusicDeletePlaylistError::Serialize)?;
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
            .map_err(QqMusicDeletePlaylistError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicDeletePlaylistError::HttpStatus(response.status()));
        }
        let envelope: CreatePlaylistResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicDeletePlaylistError::InvalidJson)?;
        map_delete_response(envelope, directory_id)
    }
}

fn is_valid_playlist_name(name: &str) -> bool {
    !name.trim().is_empty()
        && name.len() <= MAX_PLAYLIST_NAME_BYTES
        && !name.chars().any(char::is_control)
}

#[derive(Serialize)]
struct CreatePlaylistRequest<'a> {
    comm: PlaylistWriteComm<'a>,
    #[serde(rename = "req_0")]
    request: CreatePlaylistRpc<'a>,
}

impl<'a> CreatePlaylistRequest<'a> {
    fn new(credential: &'a Credential, name: &'a str) -> Self {
        Self {
            comm: PlaylistWriteComm {
                client_version: 4_747_474,
                client_type: 24,
                format: "json",
                account_id: credential.music_id(),
                auth_key: credential.music_key(),
                login_type: credential.login_type().value(),
            },
            request: CreatePlaylistRpc {
                module: "music.musicasset.PlaylistBaseWrite",
                method: "AddPlaylist",
                param: CreatePlaylistParam { name },
            },
        }
    }
}

#[derive(Serialize)]
struct PlaylistWriteComm<'a> {
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
struct CreatePlaylistRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: CreatePlaylistParam<'a>,
}

#[derive(Serialize)]
struct CreatePlaylistParam<'a> {
    #[serde(rename = "dirName")]
    name: &'a str,
}

#[derive(Serialize)]
struct DeletePlaylistRequest<'a> {
    comm: PlaylistWriteComm<'a>,
    #[serde(rename = "req_0")]
    request: DeletePlaylistRpc,
}

impl<'a> DeletePlaylistRequest<'a> {
    fn new(credential: &'a Credential, directory_id: u64) -> Self {
        Self {
            comm: PlaylistWriteComm {
                client_version: 4_747_474,
                client_type: 24,
                format: "json",
                account_id: credential.music_id(),
                auth_key: credential.music_key(),
                login_type: credential.login_type().value(),
            },
            request: DeletePlaylistRpc {
                module: "music.musicasset.PlaylistBaseWrite",
                method: "DelPlaylist",
                param: DeletePlaylistParam { directory_id },
            },
        }
    }
}

#[derive(Serialize)]
struct DeletePlaylistRpc {
    module: &'static str,
    method: &'static str,
    param: DeletePlaylistParam,
}

#[derive(Serialize)]
struct DeletePlaylistParam {
    #[serde(rename = "dirId")]
    directory_id: u64,
}

#[derive(Deserialize)]
struct CreatePlaylistResponse {
    code: Option<i64>,
    #[serde(rename = "req_0")]
    result: Option<CreatePlaylistResultEnvelope>,
}

#[derive(Deserialize)]
struct CreatePlaylistResultEnvelope {
    code: Option<i64>,
    data: Option<CreatePlaylistData>,
}

#[derive(Deserialize)]
struct CreatePlaylistData {
    #[serde(rename = "retCode")]
    mutation_code: Option<i64>,
    result: Option<CreatePlaylistResult>,
}

#[derive(Deserialize)]
struct CreatePlaylistResult {
    tid: Option<u64>,
    id: Option<u64>,
    #[serde(rename = "dirId")]
    directory_id: Option<u64>,
    #[serde(rename = "dirName")]
    name: Option<String>,
}

fn map_response<E>(
    envelope: CreatePlaylistResponse,
) -> Result<QqMusicCreatedPlaylist, QqMusicCreatePlaylistError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicCreatePlaylistError::MissingGlobalCode)?;
    let result_code = envelope.result.as_ref().and_then(|result| result.code);
    if let Some(code) = [Some(global_code), result_code]
        .into_iter()
        .flatten()
        .find(|code| is_credential_rejection_code(*code))
    {
        return Err(QqMusicCreatePlaylistError::Rejected { code });
    }
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicCreatePlaylistError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .result
        .ok_or(QqMusicCreatePlaylistError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicCreatePlaylistError::MissingResultCode)?;
    let data = result.data.ok_or(QqMusicCreatePlaylistError::MissingData)?;
    let mutation_code = data
        .mutation_code
        .ok_or(QqMusicCreatePlaylistError::MissingMutationCode)?;
    if mutation_code != 0 {
        return Err(QqMusicCreatePlaylistError::MutationRejected {
            code: mutation_code,
        });
    }
    let created = data
        .result
        .ok_or(QqMusicCreatePlaylistError::MissingCreatedResult)?;
    let playlist_id = match (
        created.tid.filter(|id| *id != 0),
        created.id.filter(|id| *id != 0),
    ) {
        (Some(tid), Some(id)) if tid == id => tid,
        (Some(_), Some(_)) => return Err(QqMusicCreatePlaylistError::ConflictingPlaylistId),
        (Some(id), None) | (None, Some(id)) => id,
        (None, None) => return Err(QqMusicCreatePlaylistError::MissingPlaylistId),
    };
    let directory_id = created
        .directory_id
        .filter(|id| *id != 0)
        .ok_or(QqMusicCreatePlaylistError::MissingDirectoryId)?;
    let name = created
        .name
        .filter(|name| is_valid_playlist_name(name))
        .ok_or(QqMusicCreatePlaylistError::InvalidReturnedName)?;
    Ok(QqMusicCreatedPlaylist {
        playlist_id,
        directory_id,
        name,
    })
}

fn map_delete_response<E>(
    envelope: CreatePlaylistResponse,
    requested_directory_id: u64,
) -> Result<(), QqMusicDeletePlaylistError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicDeletePlaylistError::MissingGlobalCode)?;
    let result_code = envelope.result.as_ref().and_then(|result| result.code);
    if let Some(code) = [Some(global_code), result_code]
        .into_iter()
        .flatten()
        .find(|code| is_credential_rejection_code(*code))
    {
        return Err(QqMusicDeletePlaylistError::Rejected { code });
    }
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicDeletePlaylistError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .result
        .ok_or(QqMusicDeletePlaylistError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicDeletePlaylistError::MissingResultCode)?;
    let data = result.data.ok_or(QqMusicDeletePlaylistError::MissingData)?;
    let mutation_code = data
        .mutation_code
        .ok_or(QqMusicDeletePlaylistError::MissingMutationCode)?;
    if mutation_code != 0 {
        return Err(QqMusicDeletePlaylistError::MutationRejected {
            code: mutation_code,
        });
    }
    let deleted = data
        .result
        .ok_or(QqMusicDeletePlaylistError::MissingDeletedResult)?;
    let returned_directory_id = deleted
        .directory_id
        .ok_or(QqMusicDeletePlaylistError::MissingDirectoryId)?;
    if returned_directory_id != requested_directory_id {
        return Err(QqMusicDeletePlaylistError::MismatchedDirectoryId);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use super::{QqMusicCreatePlaylistError, QqMusicCreatedPlaylist, QqMusicDeletePlaylistError};
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

    fn success(result: &Value) -> Value {
        json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {"retCode": 0, "result": result}
            }
        })
    }

    #[tokio::test]
    async fn sends_exact_create_request_and_maps_tid_result() {
        let client = QqMusicClient::new(FakeTransport::new(&success(&json!({
            "tid": 7002,
            "dirId": 902,
            "dirName": "Fixture playlist"
        }))));

        let created = client
            .create_playlist(&credential(), "Fixture playlist")
            .await
            .expect("confirmed created playlist");

        assert_eq!(created.playlist_id(), 7002);
        assert_eq!(created.directory_id(), 902);
        assert_eq!(created.name(), "Fixture playlist");
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
        assert!(!debug.contains("Fixture playlist"));
        let body: Value = serde_json::from_slice(
            requests[0]
                .body_bytes()
                .expect("create-playlist request body"),
        )
        .expect("request JSON");
        assert_eq!(
            body["req_0"]["module"],
            "music.musicasset.PlaylistBaseWrite"
        );
        assert_eq!(body["req_0"]["method"], "AddPlaylist");
        assert_eq!(
            body["req_0"]["param"],
            json!({"dirName": "Fixture playlist"})
        );
    }

    #[tokio::test]
    async fn accepts_independently_observed_id_compatibility() {
        for result in [
            json!({"id": 7002, "dirId": 902, "dirName": "Server name"}),
            json!({"tid": 7002, "id": 7002, "dirId": 902, "dirName": "Server name"}),
        ] {
            let client = QqMusicClient::new(FakeTransport::new(&success(&result)));
            assert_eq!(
                client
                    .create_playlist(&credential(), "Requested name")
                    .await
                    .expect("compatible result")
                    .name(),
                "Server name"
            );
        }
    }

    #[tokio::test]
    async fn rejects_invalid_name_before_transport() {
        for name in [
            String::new(),
            "   ".into(),
            "line\nbreak".into(),
            "x".repeat(super::MAX_PLAYLIST_NAME_BYTES + 1),
        ] {
            let client = QqMusicClient::new(FakeTransport::new(&success(&json!({
                "tid": 7002,
                "dirId": 902,
                "dirName": "Server name"
            }))));
            assert_eq!(
                client.create_playlist(&credential(), &name).await,
                Err(QqMusicCreatePlaylistError::InvalidName)
            );
            assert!(client.transport().requests().is_empty());
        }
    }

    #[test]
    fn created_playlist_debug_is_redacted() {
        let created = QqMusicCreatedPlaylist {
            playlist_id: 7002,
            directory_id: 902,
            name: "Private playlist".into(),
        };
        let debug = format!("{created:?}");
        assert!(!debug.contains("7002"));
        assert!(!debug.contains("902"));
        assert!(!debug.contains("Private playlist"));
    }

    #[tokio::test]
    async fn rejects_conflicting_and_incomplete_success_results() {
        let cases = [
            (
                success(&json!({
                    "tid": 7002,
                    "id": 7003,
                    "dirId": 902,
                    "dirName": "Server name"
                })),
                QqMusicCreatePlaylistError::ConflictingPlaylistId,
            ),
            (
                success(&json!({"dirId": 902, "dirName": "Server name"})),
                QqMusicCreatePlaylistError::MissingPlaylistId,
            ),
            (
                success(&json!({"tid": 7002, "dirName": "Server name"})),
                QqMusicCreatePlaylistError::MissingDirectoryId,
            ),
            (
                success(&json!({"tid": 7002, "dirId": 902, "dirName": ""})),
                QqMusicCreatePlaylistError::InvalidReturnedName,
            ),
            (
                json!({"code": 0, "req_0": {"code": 0, "data": {"retCode": 80092}}}),
                QqMusicCreatePlaylistError::MutationRejected { code: 80_092 },
            ),
        ];
        for (fixture, expected) in cases {
            let client = QqMusicClient::new(FakeTransport::new(&fixture));
            assert_eq!(
                client
                    .create_playlist(&credential(), "Requested name")
                    .await,
                Err(expected)
            );
        }
    }

    #[tokio::test]
    async fn sends_exact_delete_request_and_requires_matching_directory() {
        let client = QqMusicClient::new(FakeTransport::new(&success(&json!({
            "tid": 7002,
            "dirId": 902,
            "dirName": "Deleted playlist"
        }))));

        client
            .delete_playlist(&credential(), 902)
            .await
            .expect("confirmed playlist deletion");

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
        assert!(!debug.contains("902"));
        let body: Value = serde_json::from_slice(
            requests[0]
                .body_bytes()
                .expect("delete-playlist request body"),
        )
        .expect("request JSON");
        assert_eq!(
            body["req_0"]["module"],
            "music.musicasset.PlaylistBaseWrite"
        );
        assert_eq!(body["req_0"]["method"], "DelPlaylist");
        assert_eq!(body["req_0"]["param"], json!({"dirId": 902}));
    }

    #[tokio::test]
    async fn delete_rejects_invalid_directory_before_transport() {
        let client = QqMusicClient::new(FakeTransport::new(&success(&json!({
            "dirId": 902
        }))));

        assert_eq!(
            client.delete_playlist(&credential(), 0).await,
            Err(QqMusicDeletePlaylistError::InvalidDirectoryId)
        );
        assert!(client.transport().requests().is_empty());
    }

    #[tokio::test]
    async fn delete_preserves_rejection_and_unknown_confirmation_semantics() {
        let cases = [
            (
                json!({"code": 0, "req_0": {"code": 104_401}}),
                QqMusicDeletePlaylistError::Rejected { code: 104_401 },
            ),
            (
                json!({"code": 0, "req_0": {"code": 8}}),
                QqMusicDeletePlaylistError::Upstream {
                    global_code: 0,
                    result_code: Some(8),
                },
            ),
            (
                json!({"code": 0, "req_0": {"code": 0, "data": {"retCode": 9}}}),
                QqMusicDeletePlaylistError::MutationRejected { code: 9 },
            ),
            (
                success(&json!({})),
                QqMusicDeletePlaylistError::MissingDirectoryId,
            ),
            (
                success(&json!({"dirId": 0})),
                QqMusicDeletePlaylistError::MismatchedDirectoryId,
            ),
            (
                success(&json!({"dirId": 903})),
                QqMusicDeletePlaylistError::MismatchedDirectoryId,
            ),
        ];
        for (fixture, expected) in cases {
            let client = QqMusicClient::new(FakeTransport::new(&fixture));
            assert_eq!(
                client.delete_playlist(&credential(), 902).await,
                Err(expected)
            );
        }
    }

    #[test]
    fn delete_error_debug_redacts_identity() {
        let debug = format!(
            "{:?}",
            QqMusicDeletePlaylistError::<Infallible>::MismatchedDirectoryId
        );
        assert!(!debug.contains("902"));
    }
}
