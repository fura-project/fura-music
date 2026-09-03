use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::credential::is_credential_rejection_code;
use crate::{Credential, HttpRequest, HttpTransport, QqMusicClient, normalized_https_image_uri};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_OWNED_PLAYLISTS_RESPONSE_BYTES: usize = 1024 * 1024;
const OWNED_PLAYLISTS_TIMEOUT: Duration = Duration::from_secs(30);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OwnedPlaylistField {
    PlaylistId,
    DirectoryId,
    Name,
}

pub enum QqMusicOwnedPlaylistsError<E> {
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
    MissingPlaylists,
    InvalidPlaylist {
        index: usize,
        field: OwnedPlaylistField,
    },
}

impl<E> fmt::Debug for QqMusicOwnedPlaylistsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
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
            Self::MissingPlaylists => formatter.write_str("MissingPlaylists"),
            Self::InvalidPlaylist { index, field } => formatter
                .debug_struct("InvalidPlaylist")
                .field("index", index)
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicOwnedPlaylistsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Transport(_) => formatter.write_str("QQ Music owned-playlist request failed"),
            Self::Serialize => formatter.write_str("could not serialize owned-playlist request"),
            Self::HttpStatus(status) => {
                write!(formatter, "owned-playlist request returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("owned-playlist response was not valid JSON"),
            Self::MissingGlobalCode => {
                formatter.write_str("owned-playlist response has no global code")
            }
            Self::MissingResult => formatter.write_str("owned-playlist result is missing"),
            Self::MissingResultCode => formatter.write_str("owned-playlist result has no code"),
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
                "owned-playlist request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("owned-playlist data is missing"),
            Self::MissingPlaylists => formatter.write_str("owned-playlist array is missing"),
            Self::InvalidPlaylist { index, field } => {
                write!(formatter, "owned playlist {index} has an invalid {field:?}")
            }
        }
    }
}

impl<E> std::error::Error for QqMusicOwnedPlaylistsError<E>
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
pub struct QqMusicOwnedPlaylist {
    playlist_id: u64,
    directory_id: u64,
    name: String,
    cover_url: Option<String>,
    track_count: Option<u32>,
}

impl QqMusicOwnedPlaylist {
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

    #[must_use]
    pub fn cover_url(&self) -> Option<&str> {
        self.cover_url.as_deref()
    }

    #[must_use]
    pub const fn track_count(&self) -> Option<u32> {
        self.track_count
    }
}

impl fmt::Debug for QqMusicOwnedPlaylist {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicOwnedPlaylist")
            .field("playlist_id", &"[REDACTED]")
            .field("directory_id", &"[REDACTED]")
            .field("name", &"[REDACTED]")
            .field("has_cover", &self.cover_url.is_some())
            .field("track_count", &self.track_count)
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicOwnedPlaylists {
    playlists: Vec<QqMusicOwnedPlaylist>,
}

impl QqMusicOwnedPlaylists {
    #[must_use]
    pub fn playlists(&self) -> &[QqMusicOwnedPlaylist] {
        &self.playlists
    }
}

impl fmt::Debug for QqMusicOwnedPlaylists {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicOwnedPlaylists")
            .field("playlist_count", &self.playlists.len())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Returns the playlists created by the authenticated account, including
    /// QQ Music's built-in liked-songs directory when the service lists it.
    /// Favorited playlists use a different RPC and are not included.
    ///
    /// # Errors
    ///
    /// Keeps transport, service, credential rejection, response shape, and
    /// invalid playlist entries distinct without retaining response content.
    pub async fn owned_playlists(
        &self,
        credential: &Credential,
    ) -> Result<QqMusicOwnedPlaylists, QqMusicOwnedPlaylistsError<T::Error>> {
        let body = serde_json::to_vec(&OwnedPlaylistsRequest::new(credential))
            .map_err(|_| QqMusicOwnedPlaylistsError::Serialize)?;
        let response = self
            .transport()
            .execute(
                HttpRequest::post(MUSICU_URL)
                    .header("Content-Type", "application/json")
                    .header("Origin", "https://y.qq.com")
                    .header("Referer", "https://y.qq.com/")
                    .header("Cookie", credential.musicu_cookie_header())
                    .body(body)
                    .response_body_limit(MAX_OWNED_PLAYLISTS_RESPONSE_BYTES)
                    .timeout(OWNED_PLAYLISTS_TIMEOUT),
            )
            .await
            .map_err(QqMusicOwnedPlaylistsError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicOwnedPlaylistsError::HttpStatus(response.status()));
        }

        let envelope: OwnedPlaylistsResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicOwnedPlaylistsError::InvalidJson)?;
        map_response(envelope)
    }
}

#[derive(Serialize)]
struct OwnedPlaylistsRequest<'a> {
    comm: OwnedPlaylistsComm<'a>,
    #[serde(rename = "music.musicasset.PlaylistBaseRead")]
    request: OwnedPlaylistsRpc<'a>,
}

impl<'a> OwnedPlaylistsRequest<'a> {
    fn new(credential: &'a Credential) -> Self {
        Self {
            comm: OwnedPlaylistsComm {
                cv: 13_020_508,
                version: 13_020_508,
                client_type: "11",
                app_id: "qqmusic",
                format: "json",
                input_charset: "utf-8",
                output_charset: "utf-8",
                user_id: credential.music_id(),
                account_id: credential.music_id(),
                auth_key: credential.music_key(),
                login_type: credential.login_type().value(),
                login_uin: credential.music_id(),
            },
            request: OwnedPlaylistsRpc {
                module: "music.musicasset.PlaylistBaseRead",
                method: "GetPlaylistByUin",
                param: OwnedPlaylistsParam {
                    account_id: credential.music_id(),
                },
            },
        }
    }
}

#[derive(Serialize)]
struct OwnedPlaylistsComm<'a> {
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
struct OwnedPlaylistsRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: OwnedPlaylistsParam<'a>,
}

#[derive(Serialize)]
struct OwnedPlaylistsParam<'a> {
    #[serde(rename = "uin")]
    account_id: &'a str,
}

#[derive(Deserialize)]
struct OwnedPlaylistsResponse {
    code: Option<i64>,
    #[serde(rename = "music.musicasset.PlaylistBaseRead")]
    result: Option<OwnedPlaylistsResult>,
}

#[derive(Deserialize)]
struct OwnedPlaylistsResult {
    code: Option<i64>,
    data: Option<OwnedPlaylistsData>,
}

#[derive(Deserialize)]
struct OwnedPlaylistsData {
    #[serde(rename = "v_playlist")]
    playlists: Option<Vec<RawOwnedPlaylist>>,
}

#[derive(Deserialize)]
struct RawOwnedPlaylist {
    tid: Option<u64>,
    #[serde(rename = "dirId")]
    directory_id: Option<u64>,
    #[serde(rename = "dirName")]
    name: Option<String>,
    #[serde(rename = "picUrl")]
    cover_url: Option<String>,
    #[serde(rename = "songNum")]
    track_count: Option<u32>,
}

fn map_response<E>(
    envelope: OwnedPlaylistsResponse,
) -> Result<QqMusicOwnedPlaylists, QqMusicOwnedPlaylistsError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicOwnedPlaylistsError::MissingGlobalCode)?;
    let result_code = envelope.result.as_ref().and_then(|result| result.code);
    if let Some(code) = [Some(global_code), result_code]
        .into_iter()
        .flatten()
        .find(|code| is_credential_rejection_code(*code))
    {
        return Err(QqMusicOwnedPlaylistsError::Rejected { code });
    }
    if global_code != 0 {
        return Err(QqMusicOwnedPlaylistsError::Upstream {
            global_code,
            result_code,
        });
    }

    let result = envelope
        .result
        .ok_or(QqMusicOwnedPlaylistsError::MissingResult)?;
    let result_code = result
        .code
        .ok_or(QqMusicOwnedPlaylistsError::MissingResultCode)?;
    if result_code != 0 {
        return Err(QqMusicOwnedPlaylistsError::Upstream {
            global_code,
            result_code: Some(result_code),
        });
    }
    let data = result.data.ok_or(QqMusicOwnedPlaylistsError::MissingData)?;
    let raw_playlists = data
        .playlists
        .ok_or(QqMusicOwnedPlaylistsError::MissingPlaylists)?;
    let mut playlists = Vec::with_capacity(raw_playlists.len());
    for (index, raw) in raw_playlists.into_iter().enumerate() {
        let playlist_id = raw.tid.filter(|value| *value != 0).ok_or(
            QqMusicOwnedPlaylistsError::InvalidPlaylist {
                index,
                field: OwnedPlaylistField::PlaylistId,
            },
        )?;
        let directory_id = raw.directory_id.filter(|value| *value != 0).ok_or(
            QqMusicOwnedPlaylistsError::InvalidPlaylist {
                index,
                field: OwnedPlaylistField::DirectoryId,
            },
        )?;
        let name = raw.name.filter(|value| !value.trim().is_empty()).ok_or(
            QqMusicOwnedPlaylistsError::InvalidPlaylist {
                index,
                field: OwnedPlaylistField::Name,
            },
        )?;
        playlists.push(QqMusicOwnedPlaylist {
            playlist_id,
            directory_id,
            name,
            cover_url: normalized_https_image_uri(raw.cover_url),
            track_count: raw.track_count,
        });
    }
    Ok(QqMusicOwnedPlaylists { playlists })
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::convert::Infallible;
    use std::sync::Mutex;
    use std::time::Duration;

    use serde_json::{Value, json};

    use super::{OwnedPlaylistField, QqMusicOwnedPlaylistsError};
    use crate::{
        Credential, HttpMethod, HttpRequest, HttpResponse, HttpTransport, LoginType, QqMusicClient,
    };

    struct FakeTransport {
        responses: Mutex<VecDeque<HttpResponse>>,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl FakeTransport {
        fn new(response: &Value) -> Self {
            Self {
                responses: Mutex::new(
                    [HttpResponse::new(
                        200,
                        serde_json::to_vec(response).expect("fixture JSON"),
                    )]
                    .into(),
                ),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn request(&self) -> HttpRequest {
            self.requests.lock().expect("request lock")[0].clone()
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

    fn credential() -> Credential {
        Credential::new("123456", "W_X_private-key", LoginType::WECHAT).expect("fixture credential")
    }

    #[tokio::test]
    async fn serializes_evidenced_request_and_maps_owned_playlist_summaries() {
        let client = QqMusicClient::new(FakeTransport::new(&json!({
            "code": 0,
            "music.musicasset.PlaylistBaseRead": {
                "code": 0,
                "data": {
                    "v_playlist": [
                        {
                            "tid": 7001,
                            "dirId": 201,
                            "dirName": "Fixture liked songs",
                            "picUrl": "http://p.qpic.cn/music_cover/fixture/300?n=1",
                            "songNum": 42
                        },
                        {
                            "tid": 7002,
                            "dirId": 202,
                            "dirName": "Fixture road trip"
                        }
                    ],
                    "total": 2,
                    "bFinish": true
                }
            }
        })));

        let result = client
            .owned_playlists(&credential())
            .await
            .expect("fixture owned playlists");
        assert_eq!(result.playlists().len(), 2);
        assert_eq!(result.playlists()[0].playlist_id(), 7001);
        assert_eq!(result.playlists()[0].directory_id(), 201);
        assert_eq!(result.playlists()[0].name(), "Fixture liked songs");
        assert_eq!(
            result.playlists()[0].cover_url(),
            Some("https://p.qpic.cn/music_cover/fixture/300?n=1")
        );
        assert_eq!(result.playlists()[0].track_count(), Some(42));
        assert_eq!(result.playlists()[1].cover_url(), None);
        assert_eq!(result.playlists()[1].track_count(), None);

        let request = client.transport().request();
        assert_eq!(request.method(), HttpMethod::Post);
        assert_eq!(request.url(), "https://u.y.qq.com/cgi-bin/musicu.fcg");
        assert_eq!(request.max_response_body_bytes(), 1024 * 1024);
        assert_eq!(request.request_timeout(), Some(Duration::from_secs(30)));
        let body: Value =
            serde_json::from_slice(request.body_bytes().expect("owned-playlist request body"))
                .expect("request JSON");
        let rpc = &body["music.musicasset.PlaylistBaseRead"];
        assert_eq!(rpc["module"], "music.musicasset.PlaylistBaseRead");
        assert_eq!(rpc["method"], "GetPlaylistByUin");
        assert_eq!(rpc["param"]["uin"], "123456");
        assert_eq!(body["comm"]["authst"], "W_X_private-key");
        assert_eq!(body["comm"]["tmeLoginType"], 1);
        let cookie = request
            .headers()
            .iter()
            .find(|(name, _)| name == "Cookie")
            .map(|(_, value)| value)
            .expect("credential cookie");
        assert!(cookie.contains("qm_keyst=W_X_private-key"));
        assert!(!format!("{request:?}").contains("private-key"));
        assert!(!format!("{result:?}").contains("Fixture liked songs"));
    }

    #[tokio::test]
    async fn rejects_missing_identity_fields_without_leaking_playlist_content() {
        let client = QqMusicClient::new(FakeTransport::new(&json!({
            "code": 0,
            "music.musicasset.PlaylistBaseRead": {
                "code": 0,
                "data": {
                    "v_playlist": [{
                        "dirId": 202,
                        "dirName": "must-not-leak"
                    }]
                }
            }
        })));

        let error = client
            .owned_playlists(&credential())
            .await
            .expect_err("missing playlist ID must fail");
        assert!(matches!(
            error,
            QqMusicOwnedPlaylistsError::InvalidPlaylist {
                index: 0,
                field: OwnedPlaylistField::PlaylistId,
            }
        ));
        assert!(!format!("{error:?}").contains("must-not-leak"));
    }

    #[tokio::test]
    async fn keeps_rejection_upstream_and_missing_arrays_distinct() {
        let rejected = QqMusicClient::new(FakeTransport::new(&json!({
            "code": 0,
            "music.musicasset.PlaylistBaseRead": {"code": 104_401, "data": {}}
        })));
        assert!(matches!(
            rejected.owned_playlists(&credential()).await,
            Err(QqMusicOwnedPlaylistsError::Rejected { code: 104_401 })
        ));

        let upstream = QqMusicClient::new(FakeTransport::new(&json!({
            "code": 0,
            "music.musicasset.PlaylistBaseRead": {"code": 50006, "data": {}}
        })));
        assert!(matches!(
            upstream.owned_playlists(&credential()).await,
            Err(QqMusicOwnedPlaylistsError::Upstream {
                global_code: 0,
                result_code: Some(50_006),
            })
        ));

        let missing = QqMusicClient::new(FakeTransport::new(&json!({
            "code": 0,
            "music.musicasset.PlaylistBaseRead": {"code": 0, "data": {}}
        })));
        assert!(matches!(
            missing.owned_playlists(&credential()).await,
            Err(QqMusicOwnedPlaylistsError::MissingPlaylists)
        ));
    }
}
