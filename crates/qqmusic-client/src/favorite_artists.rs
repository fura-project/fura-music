use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::credential::is_credential_rejection_code;
use crate::{Credential, HttpRequest, HttpTransport, QqMusicArtistSummary, QqMusicClient};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MAX_RESPONSE_BYTES: usize = 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_PAGE_SIZE: u32 = 100;
const MAX_NAME_BYTES: usize = 4 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FavoriteArtistField {
    ArtistMid,
    ArtistName,
}

#[derive(PartialEq)]
pub enum QqMusicFavoriteArtistsError<E> {
    MissingEncryptedUin,
    InvalidPageSize {
        size: u32,
    },
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
    MissingArtists,
    MissingTotal,
    MissingHasMore,
    InvalidHasMore,
    InvalidPagination,
    InvalidArtist {
        index: usize,
        field: FavoriteArtistField,
    },
}

impl<E> fmt::Debug for QqMusicFavoriteArtistsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::MissingEncryptedUin => formatter.write_str("MissingEncryptedUin"),
            Self::InvalidPageSize { size } => formatter
                .debug_struct("InvalidPageSize")
                .field("size", size)
                .finish(),
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
            Self::MissingArtists => formatter.write_str("MissingArtists"),
            Self::MissingTotal => formatter.write_str("MissingTotal"),
            Self::MissingHasMore => formatter.write_str("MissingHasMore"),
            Self::InvalidHasMore => formatter.write_str("InvalidHasMore"),
            Self::InvalidPagination => formatter.write_str("InvalidPagination"),
            Self::InvalidArtist { index, field } => formatter
                .debug_struct("InvalidArtist")
                .field("index", index)
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicFavoriteArtistsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::MissingEncryptedUin => {
                formatter.write_str("favorite-Artist request requires encrypted account identity")
            }
            Self::InvalidPageSize { size } => write!(
                formatter,
                "favorite-Artist page size {size} is outside 1..={MAX_PAGE_SIZE}"
            ),
            Self::Serialize => formatter.write_str("could not serialize favorite-Artist request"),
            Self::Transport(_) => formatter.write_str("QQ Music favorite-Artist request failed"),
            Self::HttpStatus(status) => {
                write!(formatter, "favorite-Artist request returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("favorite-Artist response was not valid JSON"),
            Self::MissingGlobalCode => {
                formatter.write_str("favorite-Artist response has no global code")
            }
            Self::MissingResult => formatter.write_str("favorite-Artist result is missing"),
            Self::MissingResultCode => formatter.write_str("favorite-Artist result has no code"),
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
                "favorite-Artist request failed with global code {global_code} and result code {result_code:?}"
            ),
            Self::MissingData => formatter.write_str("favorite-Artist data is missing"),
            Self::MissingArtists => formatter.write_str("favorite-Artist array is missing"),
            Self::MissingTotal => formatter.write_str("favorite-Artist total is missing"),
            Self::MissingHasMore => {
                formatter.write_str("favorite-Artist continuation flag is missing")
            }
            Self::InvalidHasMore => {
                formatter.write_str("favorite-Artist continuation flag is invalid")
            }
            Self::InvalidPagination => formatter.write_str("favorite-Artist pagination is invalid"),
            Self::InvalidArtist { index, field } => {
                write!(
                    formatter,
                    "favorite Artist {index} has an invalid {field:?}"
                )
            }
        }
    }
}

impl<E> std::error::Error for QqMusicFavoriteArtistsError<E>
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
pub struct QqMusicFavoriteArtistsPage {
    offset: u32,
    total: u32,
    has_more: bool,
    artists: Vec<QqMusicArtistSummary>,
}

impl QqMusicFavoriteArtistsPage {
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
    pub fn artists(&self) -> &[QqMusicArtistSummary] {
        &self.artists
    }
}

impl fmt::Debug for QqMusicFavoriteArtistsPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicFavoriteArtistsPage")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("artist_count", &self.artists.len())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Loads one authenticated offset page of the current account's favorite
    /// Artists without exposing account or collection values in diagnostics.
    ///
    /// # Errors
    ///
    /// Keeps missing encrypted identity, credential rejection, transport,
    /// service, response-shape, pagination, and Artist mapping distinct.
    pub async fn favorite_artists(
        &self,
        credential: &Credential,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicFavoriteArtistsPage, QqMusicFavoriteArtistsError<T::Error>> {
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicFavoriteArtistsError::InvalidPageSize { size });
        }
        let encrypted_uin = credential
            .session_secrets()
            .encrypted_uin()
            .filter(|value| !value.trim().is_empty())
            .ok_or(QqMusicFavoriteArtistsError::MissingEncryptedUin)?;
        let body = serde_json::to_vec(&FavoriteArtistsRequest::new(
            credential,
            encrypted_uin,
            offset,
            size,
        ))
        .map_err(|_| QqMusicFavoriteArtistsError::Serialize)?;
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
            .map_err(QqMusicFavoriteArtistsError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicFavoriteArtistsError::HttpStatus(response.status()));
        }
        let envelope: FavoriteArtistsResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicFavoriteArtistsError::InvalidJson)?;
        map_response(envelope, offset, size)
    }
}

#[derive(Serialize)]
struct FavoriteArtistsRequest<'a> {
    comm: FavoriteArtistsComm<'a>,
    #[serde(rename = "req_0")]
    request: FavoriteArtistsRpc<'a>,
}

impl<'a> FavoriteArtistsRequest<'a> {
    fn new(credential: &'a Credential, encrypted_uin: &'a str, offset: u32, size: u32) -> Self {
        Self {
            comm: FavoriteArtistsComm {
                client_version: 4_747_474,
                client_type: 24,
                format: "json",
                account_id: credential.music_id(),
                auth_key: credential.music_key(),
                login_type: credential.login_type().value(),
            },
            request: FavoriteArtistsRpc {
                module: "music.concern.RelationList",
                method: "GetFollowSingerList",
                param: FavoriteArtistsParam {
                    encrypted_uin,
                    offset,
                    size,
                },
            },
        }
    }
}

#[derive(Serialize)]
struct FavoriteArtistsComm<'a> {
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
struct FavoriteArtistsRpc<'a> {
    module: &'static str,
    method: &'static str,
    param: FavoriteArtistsParam<'a>,
}

#[derive(Serialize)]
struct FavoriteArtistsParam<'a> {
    #[serde(rename = "HostUin")]
    encrypted_uin: &'a str,
    #[serde(rename = "From")]
    offset: u32,
    #[serde(rename = "Size")]
    size: u32,
}

#[derive(Deserialize)]
struct FavoriteArtistsResponse {
    code: Option<i64>,
    #[serde(rename = "req_0")]
    result: Option<FavoriteArtistsResult>,
}

#[derive(Deserialize)]
struct FavoriteArtistsResult {
    code: Option<i64>,
    data: Option<FavoriteArtistsData>,
}

#[derive(Deserialize)]
struct FavoriteArtistsData {
    #[serde(rename = "Total")]
    total: Option<u32>,
    #[serde(rename = "List")]
    artists: Option<Vec<RawFavoriteArtist>>,
    #[serde(rename = "HasMore")]
    has_more: Option<RawHasMore>,
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
struct RawFavoriteArtist {
    #[serde(rename = "MID")]
    mid: Option<String>,
    #[serde(rename = "Name")]
    name: Option<String>,
}

fn map_response<E>(
    envelope: FavoriteArtistsResponse,
    offset: u32,
    size: u32,
) -> Result<QqMusicFavoriteArtistsPage, QqMusicFavoriteArtistsError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicFavoriteArtistsError::MissingGlobalCode)?;
    let result_code = envelope.result.as_ref().and_then(|result| result.code);
    if let Some(code) = [Some(global_code), result_code]
        .into_iter()
        .flatten()
        .find(|code| is_credential_rejection_code(*code))
    {
        return Err(QqMusicFavoriteArtistsError::Rejected { code });
    }
    if global_code != 0 || result_code.is_some_and(|code| code != 0) {
        return Err(QqMusicFavoriteArtistsError::Upstream {
            global_code,
            result_code,
        });
    }
    let result = envelope
        .result
        .ok_or(QqMusicFavoriteArtistsError::MissingResult)?;
    result
        .code
        .ok_or(QqMusicFavoriteArtistsError::MissingResultCode)?;
    let data = result
        .data
        .ok_or(QqMusicFavoriteArtistsError::MissingData)?;
    let raw_artists = data
        .artists
        .ok_or(QqMusicFavoriteArtistsError::MissingArtists)?;
    let total = data
        .total
        .ok_or(QqMusicFavoriteArtistsError::MissingTotal)?;
    let has_more = data
        .has_more
        .ok_or(QqMusicFavoriteArtistsError::MissingHasMore)?
        .value()
        .ok_or(QqMusicFavoriteArtistsError::InvalidHasMore)?;
    let raw_count = u32::try_from(raw_artists.len())
        .map_err(|_| QqMusicFavoriteArtistsError::InvalidPagination)?;
    let page_end = offset
        .checked_add(raw_count)
        .ok_or(QqMusicFavoriteArtistsError::InvalidPagination)?;
    if raw_count > size
        || page_end > total
        || (has_more && (raw_count == 0 || page_end >= total))
        || (!has_more && page_end != total)
    {
        return Err(QqMusicFavoriteArtistsError::InvalidPagination);
    }
    let artists = raw_artists
        .into_iter()
        .enumerate()
        .map(|(index, raw)| map_artist(raw, index))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(QqMusicFavoriteArtistsPage {
        offset,
        total,
        has_more,
        artists,
    })
}

fn map_artist<E>(
    raw: RawFavoriteArtist,
    index: usize,
) -> Result<QqMusicArtistSummary, QqMusicFavoriteArtistsError<E>> {
    let mid = safe_mid(raw.mid).ok_or(QqMusicFavoriteArtistsError::InvalidArtist {
        index,
        field: FavoriteArtistField::ArtistMid,
    })?;
    let name = raw
        .name
        .filter(|value| !value.trim().is_empty() && value.len() <= MAX_NAME_BYTES)
        .ok_or(QqMusicFavoriteArtistsError::InvalidArtist {
            index,
            field: FavoriteArtistField::ArtistName,
        })?;
    Ok(QqMusicArtistSummary::new(None, Some(mid), name))
}

fn safe_mid(value: Option<String>) -> Option<String> {
    value.filter(|value| {
        !value.trim().is_empty()
            && value.len() <= 64
            && value.bytes().all(|byte| byte.is_ascii_alphanumeric())
    })
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use super::{FavoriteArtistField, MUSICU_URL, QqMusicFavoriteArtistsError};
    use crate::{
        Credential, CredentialSessionSecrets, HttpMethod, HttpRequest, HttpResponse, HttpTransport,
        LoginType, QqMusicClient,
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
        Credential::new("123456", "W_X_fixture-key", LoginType::WECHAT)
            .expect("fixture credential")
            .with_session_secrets(CredentialSessionSecrets::new(
                None,
                None,
                None,
                None,
                None,
                Some("encryptedFixtureUin".into()),
            ))
    }

    fn response(artists: &Value, total: u32, has_more: &Value) -> Value {
        json!({
            "code": 0,
            "req_0": {
                "code": 0,
                "data": {
                    "Total": total,
                    "List": artists,
                    "HasMore": has_more
                }
            }
        })
    }

    #[tokio::test]
    async fn sends_authenticated_offset_request_and_maps_mid_only_artists() {
        let client = QqMusicClient::new(FakeTransport::new(&response(
            &json!([
                {"MID": "fixtureArtistMid1", "Name": "First Artist"},
                {"MID": "fixtureArtistMid2", "Name": "Second Artist"}
            ]),
            22,
            &json!(false),
        )));

        let page = client
            .favorite_artists(&credential(), 20, 2)
            .await
            .expect("favorite Artists");

        assert_eq!(page.offset(), 20);
        assert_eq!(page.total(), 22);
        assert!(!page.has_more());
        assert_eq!(page.artists().len(), 2);
        assert_eq!(page.artists()[0].artist_id(), None);
        assert_eq!(page.artists()[1].media_mid(), Some("fixtureArtistMid2"));
        assert_eq!(page.artists()[1].name(), "Second Artist");

        let requests = client.transport().requests();
        assert_eq!(requests.len(), 1);
        let request = &requests[0];
        assert_eq!(request.method(), HttpMethod::Post);
        assert_eq!(request.url(), MUSICU_URL);
        let body: Value = serde_json::from_slice(request.body_bytes().expect("request body"))
            .expect("request JSON");
        assert_eq!(body["req_0"]["module"], "music.concern.RelationList");
        assert_eq!(body["req_0"]["method"], "GetFollowSingerList");
        assert_eq!(body["req_0"]["param"]["HostUin"], "encryptedFixtureUin");
        assert_eq!(body["req_0"]["param"]["From"], 20);
        assert_eq!(body["req_0"]["param"]["Size"], 2);
        assert!(request.headers().iter().any(|(name, value)| {
            name == "Cookie" && value.contains("qm_keyst=W_X_fixture-key")
        }));
        let debug = format!("{request:?} {page:?}");
        assert!(!debug.contains("123456"));
        assert!(!debug.contains("W_X_fixture-key"));
        assert!(!debug.contains("encryptedFixtureUin"));
        assert!(!debug.contains("Second Artist"));
        assert!(!debug.contains("fixtureArtistMid2"));
    }

    #[tokio::test]
    async fn rejects_missing_identity_and_invalid_pagination_before_guessing() {
        let client = QqMusicClient::new(FakeTransport::new(&response(&json!([]), 0, &json!(0))));
        let missing_identity =
            Credential::new("123456", "fixture-key", LoginType::WECHAT).expect("credential");
        assert_eq!(
            client.favorite_artists(&missing_identity, 0, 20).await,
            Err(QqMusicFavoriteArtistsError::MissingEncryptedUin)
        );
        assert!(client.transport().requests().is_empty());
        assert_eq!(
            client.favorite_artists(&credential(), 0, 0).await,
            Err(QqMusicFavoriteArtistsError::InvalidPageSize { size: 0 })
        );

        let non_advancing =
            QqMusicClient::new(FakeTransport::new(&response(&json!([]), 1, &json!(true))));
        assert_eq!(
            non_advancing.favorite_artists(&credential(), 0, 20).await,
            Err(QqMusicFavoriteArtistsError::InvalidPagination)
        );
    }

    #[tokio::test]
    async fn distinguishes_rejection_upstream_and_invalid_rows() {
        let rejected = QqMusicClient::new(FakeTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 1000}
        })));
        assert_eq!(
            rejected.favorite_artists(&credential(), 0, 20).await,
            Err(QqMusicFavoriteArtistsError::Rejected { code: 1_000 })
        );

        let upstream = QqMusicClient::new(FakeTransport::new(&json!({
            "code": 0,
            "req_0": {"code": 50006}
        })));
        assert_eq!(
            upstream.favorite_artists(&credential(), 0, 20).await,
            Err(QqMusicFavoriteArtistsError::Upstream {
                global_code: 0,
                result_code: Some(50_006)
            })
        );

        let invalid = QqMusicClient::new(FakeTransport::new(&response(
            &json!([{"MID": "unsafe/mid", "Name": "Artist"}]),
            1,
            &json!(0),
        )));
        assert_eq!(
            invalid.favorite_artists(&credential(), 0, 20).await,
            Err(QqMusicFavoriteArtistsError::InvalidArtist {
                index: 0,
                field: FavoriteArtistField::ArtistMid
            })
        );
    }
}
