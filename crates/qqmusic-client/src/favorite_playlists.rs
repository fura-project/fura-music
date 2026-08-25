use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::credential::is_credential_rejection_code;
use crate::{Credential, HttpRequest, HttpTransport, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_FAVORITE_PLAYLISTS_RESPONSE_BYTES: usize = 1024 * 1024;
const FAVORITE_PLAYLISTS_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_PAGE_SIZE: u32 = 100;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FavoritePlaylistField {
    PlaylistId,
    Name,
}

pub enum QqMusicFavoritePlaylistsError<E> {
    MissingEncryptedUin,
    InvalidPageSize {
        size: u32,
    },
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
    MissingTotal,
    MissingHasMore,
    InvalidHasMore,
    InvalidPlaylist {
        index: usize,
        field: FavoritePlaylistField,
    },
}

impl<E> fmt::Debug for QqMusicFavoritePlaylistsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::MissingEncryptedUin => formatter.write_str("MissingEncryptedUin"),
            Self::InvalidPageSize { size } => formatter
                .debug_struct("InvalidPageSize")
                .field("size", size)
                .finish(),
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
            Self::MissingTotal => formatter.write_str("MissingTotal"),
            Self::MissingHasMore => formatter.write_str("MissingHasMore"),
            Self::InvalidHasMore => formatter.write_str("InvalidHasMore"),
            Self::InvalidPlaylist { index, field } => formatter
                .debug_struct("InvalidPlaylist")
                .field("index", index)
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicFavoritePlaylistsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::MissingEncryptedUin => {
                formatter.write_str("credential has no encrypted account identity")
            }
            Self::InvalidPageSize { size } => write!(
                formatter,
                "favorite-playlist page size {size} is outside 1..={MAX_PAGE_SIZE}"
            ),
            Self::Transport(_) => formatter.write_str("QQ Music favorite-playlist request failed"),
            Self::Serialize => formatter.write_str("could not serialize favorite-playlist request"),
            Self::HttpStatus(status) => {
                write!(
                    formatter,
                    "favorite-playlist request returned HTTP {status}"
                )
            }
            Self::InvalidJson => {
                formatter.write_str("favorite-playlist response was not valid JSON")
            }
            Self::MissingGlobalCode => {
                formatter.write_str("favorite-playlist response has no global code")
            }
            Self::MissingResult => formatter.write_str("favorite-playlist result is missing"),
            Self::MissingResultCode => formatter.write_str("favorite-playlist result has no code"),
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
                "favorite-playlist request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("favorite-playlist data is missing"),
            Self::MissingPlaylists => formatter.write_str("favorite-playlist array is missing"),
            Self::MissingTotal => formatter.write_str("favorite-playlist total is missing"),
            Self::MissingHasMore => {
                formatter.write_str("favorite-playlist continuation flag is missing")
            }
            Self::InvalidHasMore => {
                formatter.write_str("favorite-playlist continuation flag is invalid")
            }
            Self::InvalidPlaylist { index, field } => {
                write!(
                    formatter,
                    "favorite playlist {index} has an invalid {field:?}"
                )
            }
        }
    }
}

impl<E> std::error::Error for QqMusicFavoritePlaylistsError<E>
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
pub struct QqMusicFavoritePlaylist {
    playlist_id: u64,
    name: String,
    cover_url: Option<String>,
    track_count: Option<u32>,
}

impl QqMusicFavoritePlaylist {
    #[must_use]
    pub const fn playlist_id(&self) -> u64 {
        self.playlist_id
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

impl fmt::Debug for QqMusicFavoritePlaylist {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicFavoritePlaylist")
            .field("playlist_id", &"[REDACTED]")
            .field("name", &"[REDACTED]")
            .field("has_cover", &self.cover_url.is_some())
            .field("track_count", &self.track_count)
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicFavoritePlaylistsPage {
    offset: u32,
    total: u32,
    has_more: bool,
    playlists: Vec<QqMusicFavoritePlaylist>,
}

impl QqMusicFavoritePlaylistsPage {
    #[must_use]
    pub const fn offset(&self) -> u32 {
        self.offset
    }

    #[must_use]
    pub const fn total(&self) -> u32 {
        self.total
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn playlists(&self) -> &[QqMusicFavoritePlaylist] {
        &self.playlists
    }
}

impl fmt::Debug for QqMusicFavoritePlaylistsPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicFavoritePlaylistsPage")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("playlist_count", &self.playlists.len())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Returns one page of playlists favorited by the authenticated account.
    /// This is separate from account-owned playlists and requires the
    /// credential's encrypted UIN.
    ///
    /// # Errors
    ///
    /// Rejects missing encrypted identity and page sizes outside `1..=100`
    /// before transport. Network, service, credential rejection, response
    /// shape, pagination, and invalid rows remain distinct.
    pub async fn favorite_playlists_page(
        &self,
        credential: &Credential,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicFavoritePlaylistsPage, QqMusicFavoritePlaylistsError<T::Error>> {
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicFavoritePlaylistsError::InvalidPageSize { size });
        }
        let encrypted_uin = credential
            .session_secrets()
            .encrypted_uin()
            .filter(|value| !value.trim().is_empty())
            .ok_or(QqMusicFavoritePlaylistsError::MissingEncryptedUin)?;
        let body = serde_json::to_vec(&FavoritePlaylistsRequest::new(
            credential,
            encrypted_uin,
            offset,
            size,
        ))
        .map_err(|_| QqMusicFavoritePlaylistsError::Serialize)?;
        let response = self
            .transport()
            .execute(
                HttpRequest::post(MUSICU_URL)
                    .header("Content-Type", "application/json")
                    .header("Origin", "https://y.qq.com")
                    .header("Referer", "https://y.qq.com/")
                    .header("Cookie", credential.musicu_cookie_header())
                    .body(body)
                    .response_body_limit(MAX_FAVORITE_PLAYLISTS_RESPONSE_BYTES)
                    .timeout(FAVORITE_PLAYLISTS_TIMEOUT),
            )
            .await
            .map_err(QqMusicFavoritePlaylistsError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicFavoritePlaylistsError::HttpStatus(response.status()));
        }

        let envelope: FavoritePlaylistsResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicFavoritePlaylistsError::InvalidJson)?;
        map_response(envelope, offset)
    }
}

#[derive(Serialize)]
struct FavoritePlaylistsRequest<'a> {
    comm: FavoritePlaylistsComm<'a>,
    #[serde(rename = "music.musicasset.PlaylistFavRead")]
    request: FavoritePlaylistsRpc<'a>,
}

impl<'a> FavoritePlaylistsRequest<'a> {
    fn new(credential: &'a Credential, encrypted_uin: &'a str, offset: u32, size: u32) -> Self {
        Self {
            comm: FavoritePlaylistsComm {
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
            request: FavoritePlaylistsRpc {
                module: "music.musicasset.PlaylistFavRead",
                method: "CgiGetPlaylistFavInfo",
                param: FavoritePlaylistsParam {
                    encrypted_uin,
                    offset,
                    size,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct FavoritePlaylistsComm<'a> {
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
struct FavoritePlaylistsRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: FavoritePlaylistsParam<'a>,
}

#[derive(Serialize)]
struct FavoritePlaylistsParam<'a> {
    #[serde(rename = "uin")]
    encrypted_uin: &'a str,
    offset: u32,
    size: u32,
}

#[derive(Deserialize)]
struct FavoritePlaylistsResponse {
    code: Option<i64>,
    #[serde(rename = "music.musicasset.PlaylistFavRead")]
    result: Option<FavoritePlaylistsResult>,
}

#[derive(Deserialize)]
struct FavoritePlaylistsResult {
    code: Option<i64>,
    data: Option<FavoritePlaylistsData>,
}

#[derive(Deserialize)]
struct FavoritePlaylistsData {
    #[serde(rename = "v_list")]
    playlists: Option<Vec<RawFavoritePlaylist>>,
    total: Option<u32>,
    hasmore: Option<RawHasMore>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum RawHasMore {
    Boolean(bool),
    Number(i64),
}

impl RawHasMore {
    const fn value(self) -> Option<bool> {
        match self {
            Self::Boolean(value) => Some(value),
            Self::Number(0) => Some(false),
            Self::Number(1) => Some(true),
            Self::Number(_) => None,
        }
    }
}

#[derive(Deserialize)]
struct RawFavoritePlaylist {
    #[serde(alias = "tid", alias = "dissid")]
    id: Option<u64>,
    #[serde(alias = "dissname", alias = "name")]
    title: Option<String>,
    #[serde(rename = "picurl", alias = "cover", alias = "logo", alias = "picUrl")]
    cover_url: Option<String>,
    #[serde(rename = "songnum", alias = "songNum", alias = "song_cnt")]
    track_count: Option<u32>,
}

fn map_response<E>(
    envelope: FavoritePlaylistsResponse,
    offset: u32,
) -> Result<QqMusicFavoritePlaylistsPage, QqMusicFavoritePlaylistsError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicFavoritePlaylistsError::MissingGlobalCode)?;
    let result_code = envelope.result.as_ref().and_then(|result| result.code);
    if let Some(code) = [Some(global_code), result_code]
        .into_iter()
        .flatten()
        .find(|code| is_credential_rejection_code(*code))
    {
        return Err(QqMusicFavoritePlaylistsError::Rejected { code });
    }
    if global_code != 0 {
        return Err(QqMusicFavoritePlaylistsError::Upstream {
            global_code,
            result_code,
        });
    }

    let result = envelope
        .result
        .ok_or(QqMusicFavoritePlaylistsError::MissingResult)?;
    let result_code = result
        .code
        .ok_or(QqMusicFavoritePlaylistsError::MissingResultCode)?;
    if result_code != 0 {
        return Err(QqMusicFavoritePlaylistsError::Upstream {
            global_code,
            result_code: Some(result_code),
        });
    }
    let data = result
        .data
        .ok_or(QqMusicFavoritePlaylistsError::MissingData)?;
    let raw_playlists = data
        .playlists
        .ok_or(QqMusicFavoritePlaylistsError::MissingPlaylists)?;
    let total = data
        .total
        .ok_or(QqMusicFavoritePlaylistsError::MissingTotal)?;
    let has_more = data
        .hasmore
        .ok_or(QqMusicFavoritePlaylistsError::MissingHasMore)?
        .value()
        .ok_or(QqMusicFavoritePlaylistsError::InvalidHasMore)?;
    let mut playlists = Vec::with_capacity(raw_playlists.len());
    for (index, raw) in raw_playlists.into_iter().enumerate() {
        let playlist_id = raw.id.filter(|value| *value != 0).ok_or(
            QqMusicFavoritePlaylistsError::InvalidPlaylist {
                index,
                field: FavoritePlaylistField::PlaylistId,
            },
        )?;
        let name = raw.title.filter(|value| !value.trim().is_empty()).ok_or(
            QqMusicFavoritePlaylistsError::InvalidPlaylist {
                index,
                field: FavoritePlaylistField::Name,
            },
        )?;
        playlists.push(QqMusicFavoritePlaylist {
            playlist_id,
            name,
            cover_url: raw.cover_url.filter(|value| !value.trim().is_empty()),
            track_count: raw.track_count,
        });
    }

    Ok(QqMusicFavoritePlaylistsPage {
        offset,
        total,
        has_more,
        playlists,
    })
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::convert::Infallible;
    use std::sync::Mutex;
    use std::time::Duration;

    use serde_json::{Value, json};

    use super::{FavoritePlaylistField, QqMusicFavoritePlaylistsError};
    use crate::{
        Credential, CredentialSessionSecrets, HttpMethod, HttpRequest, HttpResponse, HttpTransport,
        LoginType, QqMusicClient,
    };

    struct FakeTransport {
        responses: Mutex<VecDeque<HttpResponse>>,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl FakeTransport {
        fn new(responses: impl IntoIterator<Item = Value>) -> Self {
            Self {
                responses: Mutex::new(
                    responses
                        .into_iter()
                        .map(|response| {
                            HttpResponse::new(
                                200,
                                serde_json::to_vec(&response).expect("fixture JSON"),
                            )
                        })
                        .collect(),
                ),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn request(&self) -> HttpRequest {
            self.requests.lock().expect("request lock")[0].clone()
        }

        fn request_count(&self) -> usize {
            self.requests.lock().expect("request lock").len()
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
        Credential::new("123456", "W_X_private-key", LoginType::WECHAT)
            .expect("fixture credential")
            .with_session_secrets(CredentialSessionSecrets::new(
                None,
                None,
                None,
                None,
                None,
                Some("secret-encrypted-uin".into()),
            ))
    }

    #[tokio::test]
    async fn serializes_evidenced_page_and_maps_favorite_summaries() {
        let client = QqMusicClient::new(FakeTransport::new([json!({
            "code": 0,
            "music.musicasset.PlaylistFavRead": {
                "code": 0,
                "data": {
                    "v_list": [
                        {
                            "id": 8001,
                            "title": "Fixture evening",
                            "picurl": "https://example.invalid/evening.jpg",
                            "songnum": 31
                        },
                        {
                            "dissid": 8002,
                            "dissname": "Fixture commute"
                        }
                    ],
                    "total": 102,
                    "hasmore": 1
                }
            }
        })]));

        let result = client
            .favorite_playlists_page(&credential(), 100, 2)
            .await
            .expect("fixture favorite playlists");
        assert_eq!(result.offset(), 100);
        assert_eq!(result.total(), 102);
        assert!(result.has_more());
        assert_eq!(result.playlists().len(), 2);
        assert_eq!(result.playlists()[0].playlist_id(), 8001);
        assert_eq!(result.playlists()[0].name(), "Fixture evening");
        assert_eq!(
            result.playlists()[0].cover_url(),
            Some("https://example.invalid/evening.jpg")
        );
        assert_eq!(result.playlists()[0].track_count(), Some(31));
        assert_eq!(result.playlists()[1].playlist_id(), 8002);
        assert_eq!(result.playlists()[1].cover_url(), None);

        let request = client.transport().request();
        assert_eq!(request.method(), HttpMethod::Post);
        assert_eq!(request.url(), "https://u.y.qq.com/cgi-bin/musicu.fcg");
        assert_eq!(request.max_response_body_bytes(), 1024 * 1024);
        assert_eq!(request.request_timeout(), Some(Duration::from_secs(30)));
        let body: Value = serde_json::from_slice(
            request
                .body_bytes()
                .expect("favorite-playlist request body"),
        )
        .expect("request JSON");
        let rpc = &body["music.musicasset.PlaylistFavRead"];
        assert_eq!(rpc["module"], "music.musicasset.PlaylistFavRead");
        assert_eq!(rpc["method"], "CgiGetPlaylistFavInfo");
        assert_eq!(rpc["param"]["uin"], "secret-encrypted-uin");
        assert_eq!(rpc["param"]["offset"], 100);
        assert_eq!(rpc["param"]["size"], 2);
        assert_eq!(body["comm"]["authst"], "W_X_private-key");
        assert!(!format!("{request:?}").contains("secret-encrypted-uin"));
        assert!(!format!("{result:?}").contains("Fixture evening"));
    }

    #[tokio::test]
    async fn rejects_missing_identity_and_invalid_page_size_before_transport() {
        let transport = FakeTransport::new([]);
        let client = QqMusicClient::new(transport);
        let no_encrypted_uin =
            Credential::new("123456", "key", LoginType::WECHAT).expect("fixture credential");

        assert!(matches!(
            client.favorite_playlists_page(&credential(), 0, 0).await,
            Err(QqMusicFavoritePlaylistsError::InvalidPageSize { size: 0 })
        ));
        assert!(matches!(
            client.favorite_playlists_page(&credential(), 0, 101).await,
            Err(QqMusicFavoritePlaylistsError::InvalidPageSize { size: 101 })
        ));
        assert!(matches!(
            client
                .favorite_playlists_page(&no_encrypted_uin, 0, 100)
                .await,
            Err(QqMusicFavoritePlaylistsError::MissingEncryptedUin)
        ));
        assert_eq!(client.transport().request_count(), 0);
    }

    #[tokio::test]
    async fn keeps_rejection_upstream_and_invalid_pagination_distinct() {
        let client = QqMusicClient::new(FakeTransport::new([
            json!({
                "code": 0,
                "music.musicasset.PlaylistFavRead": {"code": 104_400, "data": {}}
            }),
            json!({
                "code": 0,
                "music.musicasset.PlaylistFavRead": {"code": 50006, "data": {}}
            }),
            json!({
                "code": 0,
                "music.musicasset.PlaylistFavRead": {
                    "code": 0,
                    "data": {"v_list": [], "total": 0, "hasmore": 2}
                }
            }),
        ]));

        assert!(matches!(
            client.favorite_playlists_page(&credential(), 0, 100).await,
            Err(QqMusicFavoritePlaylistsError::Rejected { code: 104_400 })
        ));
        assert!(matches!(
            client.favorite_playlists_page(&credential(), 0, 100).await,
            Err(QqMusicFavoritePlaylistsError::Upstream {
                global_code: 0,
                result_code: Some(50_006),
            })
        ));
        assert!(matches!(
            client.favorite_playlists_page(&credential(), 0, 100).await,
            Err(QqMusicFavoritePlaylistsError::InvalidHasMore)
        ));
    }

    #[tokio::test]
    async fn rejects_invalid_rows_without_leaking_playlist_content() {
        let client = QqMusicClient::new(FakeTransport::new([json!({
            "code": 0,
            "music.musicasset.PlaylistFavRead": {
                "code": 0,
                "data": {
                    "v_list": [{"id": 0, "title": "must-not-leak"}],
                    "total": 1,
                    "hasmore": false
                }
            }
        })]));

        let error = client
            .favorite_playlists_page(&credential(), 0, 100)
            .await
            .expect_err("zero playlist identity must fail");
        assert!(matches!(
            error,
            QqMusicFavoritePlaylistsError::InvalidPlaylist {
                index: 0,
                field: FavoritePlaylistField::PlaylistId,
            }
        ));
        assert!(!format!("{error:?}").contains("must-not-leak"));
    }
}
