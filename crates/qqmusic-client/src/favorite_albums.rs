use std::fmt;
use std::time::Duration;

use serde::Deserialize;

use crate::{Credential, HttpRequest, HttpTransport, QqMusicAlbumSummary, QqMusicClient};

const FAVORITE_ALBUMS_URL: &str = "https://c.y.qq.com/fav/fcgi-bin/fcg_get_profile_order_asset.fcg";
const MAX_RESPONSE_BYTES: usize = 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_PAGE_SIZE: u32 = 100;
const MAX_TITLE_BYTES: usize = 4 * 1024;
const CREDENTIAL_REJECTION_CODE: i64 = 4_000;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FavoriteAlbumField {
    AlbumId,
    AlbumMid,
    AlbumName,
}

#[derive(PartialEq)]
pub enum QqMusicFavoriteAlbumsError<E> {
    InvalidPageSize {
        size: u32,
    },
    InvalidRange,
    Transport(E),
    HttpStatus(u16),
    InvalidJson,
    MissingGlobalCode,
    Rejected {
        code: i64,
    },
    Upstream {
        global_code: i64,
        subcode: Option<i64>,
    },
    MissingData,
    MissingAlbums,
    MissingTotal,
    MissingHasMore,
    InvalidHasMore,
    InvalidPagination,
    InvalidAlbum {
        index: usize,
        field: FavoriteAlbumField,
    },
}

impl<E> fmt::Debug for QqMusicFavoriteAlbumsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidPageSize { size } => formatter
                .debug_struct("InvalidPageSize")
                .field("size", size)
                .finish(),
            Self::InvalidRange => formatter.write_str("InvalidRange"),
            Self::Transport(_) => formatter.write_str("Transport([REDACTED])"),
            Self::HttpStatus(status) => formatter.debug_tuple("HttpStatus").field(status).finish(),
            Self::InvalidJson => formatter.write_str("InvalidJson([REDACTED])"),
            Self::MissingGlobalCode => formatter.write_str("MissingGlobalCode"),
            Self::Rejected { code } => formatter
                .debug_struct("Rejected")
                .field("code", code)
                .finish(),
            Self::Upstream {
                global_code,
                subcode,
            } => formatter
                .debug_struct("Upstream")
                .field("global_code", global_code)
                .field("subcode", subcode)
                .finish(),
            Self::MissingData => formatter.write_str("MissingData"),
            Self::MissingAlbums => formatter.write_str("MissingAlbums"),
            Self::MissingTotal => formatter.write_str("MissingTotal"),
            Self::MissingHasMore => formatter.write_str("MissingHasMore"),
            Self::InvalidHasMore => formatter.write_str("InvalidHasMore"),
            Self::InvalidPagination => formatter.write_str("InvalidPagination"),
            Self::InvalidAlbum { index, field } => formatter
                .debug_struct("InvalidAlbum")
                .field("index", index)
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicFavoriteAlbumsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidPageSize { size } => write!(
                formatter,
                "favorite-Album page size {size} is outside 1..={MAX_PAGE_SIZE}"
            ),
            Self::InvalidRange => formatter.write_str("favorite-Album page range is invalid"),
            Self::Transport(_) => formatter.write_str("QQ Music favorite-Album request failed"),
            Self::HttpStatus(status) => {
                write!(formatter, "favorite-Album request returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("favorite-Album response was not valid JSON"),
            Self::MissingGlobalCode => {
                formatter.write_str("favorite-Album response has no global code")
            }
            Self::Rejected { code } => {
                write!(
                    formatter,
                    "QQ Music rejected the credential with code {code}"
                )
            }
            Self::Upstream {
                global_code,
                subcode,
            } => write!(
                formatter,
                "favorite-Album request failed with global code {global_code} and subcode {subcode:?}"
            ),
            Self::MissingData => formatter.write_str("favorite-Album data is missing"),
            Self::MissingAlbums => formatter.write_str("favorite-Album array is missing"),
            Self::MissingTotal => formatter.write_str("favorite-Album total is missing"),
            Self::MissingHasMore => {
                formatter.write_str("favorite-Album continuation flag is missing")
            }
            Self::InvalidHasMore => {
                formatter.write_str("favorite-Album continuation flag is invalid")
            }
            Self::InvalidPagination => formatter.write_str("favorite-Album pagination is invalid"),
            Self::InvalidAlbum { index, field } => {
                write!(formatter, "favorite Album {index} has an invalid {field:?}")
            }
        }
    }
}

impl<E> std::error::Error for QqMusicFavoriteAlbumsError<E>
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
pub struct QqMusicFavoriteAlbumsPage {
    offset: u32,
    total: u32,
    has_more: bool,
    albums: Vec<QqMusicAlbumSummary>,
}

impl QqMusicFavoriteAlbumsPage {
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
    pub fn albums(&self) -> &[QqMusicAlbumSummary] {
        &self.albums
    }
}

impl fmt::Debug for QqMusicFavoriteAlbumsPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicFavoriteAlbumsPage")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("album_count", &self.albums.len())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Loads one authenticated page of the current account's favorite Albums.
    ///
    /// # Errors
    ///
    /// Keeps credential rejection, other upstream codes, transport, response
    /// shape, pagination, and Album mapping distinct without retaining account
    /// or collection content in diagnostics.
    pub async fn favorite_albums(
        &self,
        credential: &Credential,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicFavoriteAlbumsPage, QqMusicFavoriteAlbumsError<T::Error>> {
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicFavoriteAlbumsError::InvalidPageSize { size });
        }
        let inclusive_end = offset
            .checked_add(size)
            .and_then(|value| value.checked_sub(1))
            .ok_or(QqMusicFavoriteAlbumsError::InvalidRange)?;
        let response = self
            .transport()
            .execute(
                HttpRequest::get(FAVORITE_ALBUMS_URL)
                    .query("ct", "20")
                    .query("cid", "205360956")
                    .query("userid", credential.music_id())
                    .query("reqtype", "2")
                    .query("sin", offset.to_string())
                    .query("ein", inclusive_end.to_string())
                    .query("format", "json")
                    .header("Referer", "https://y.qq.com/")
                    .header("Cookie", credential.musicu_cookie_header())
                    .response_body_limit(MAX_RESPONSE_BYTES)
                    .timeout(REQUEST_TIMEOUT),
            )
            .await
            .map_err(QqMusicFavoriteAlbumsError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicFavoriteAlbumsError::HttpStatus(response.status()));
        }
        let envelope: FavoriteAlbumsResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicFavoriteAlbumsError::InvalidJson)?;
        map_response(envelope, offset, size)
    }
}

#[derive(Deserialize)]
struct FavoriteAlbumsResponse {
    code: Option<i64>,
    subcode: Option<i64>,
    data: Option<FavoriteAlbumsData>,
}

#[derive(Deserialize)]
struct FavoriteAlbumsData {
    albumlist: Option<Vec<RawFavoriteAlbum>>,
    totalalbum: Option<u32>,
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
struct RawFavoriteAlbum {
    #[serde(alias = "albumID")]
    albumid: Option<u64>,
    #[serde(alias = "albumMID")]
    albummid: Option<String>,
    #[serde(alias = "albumName")]
    albumname: Option<String>,
}

fn map_response<E>(
    envelope: FavoriteAlbumsResponse,
    offset: u32,
    size: u32,
) -> Result<QqMusicFavoriteAlbumsPage, QqMusicFavoriteAlbumsError<E>> {
    let global_code = envelope
        .code
        .ok_or(QqMusicFavoriteAlbumsError::MissingGlobalCode)?;
    if global_code == CREDENTIAL_REJECTION_CODE {
        return Err(QqMusicFavoriteAlbumsError::Rejected { code: global_code });
    }
    if global_code != 0 || envelope.subcode.is_some_and(|code| code != 0) {
        return Err(QqMusicFavoriteAlbumsError::Upstream {
            global_code,
            subcode: envelope.subcode,
        });
    }
    let data = envelope
        .data
        .ok_or(QqMusicFavoriteAlbumsError::MissingData)?;
    let raw_albums = data
        .albumlist
        .ok_or(QqMusicFavoriteAlbumsError::MissingAlbums)?;
    let total = data
        .totalalbum
        .ok_or(QqMusicFavoriteAlbumsError::MissingTotal)?;
    let has_more = data
        .has_more
        .ok_or(QqMusicFavoriteAlbumsError::MissingHasMore)?
        .value()
        .ok_or(QqMusicFavoriteAlbumsError::InvalidHasMore)?;
    let raw_count = u32::try_from(raw_albums.len())
        .map_err(|_| QqMusicFavoriteAlbumsError::InvalidPagination)?;
    let page_end = offset
        .checked_add(raw_count)
        .ok_or(QqMusicFavoriteAlbumsError::InvalidPagination)?;
    if raw_count > size
        || page_end > total
        || (has_more && (raw_count == 0 || page_end >= total))
        || (!has_more && page_end != total)
    {
        return Err(QqMusicFavoriteAlbumsError::InvalidPagination);
    }
    let albums = raw_albums
        .into_iter()
        .enumerate()
        .map(|(index, raw)| map_album(raw, index))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(QqMusicFavoriteAlbumsPage {
        offset,
        total,
        has_more,
        albums,
    })
}

fn map_album<E>(
    raw: RawFavoriteAlbum,
    index: usize,
) -> Result<QqMusicAlbumSummary, QqMusicFavoriteAlbumsError<E>> {
    let catalog_id = raw.albumid.filter(|value| *value != 0).ok_or(
        QqMusicFavoriteAlbumsError::InvalidAlbum {
            index,
            field: FavoriteAlbumField::AlbumId,
        },
    )?;
    let media_mid = safe_mid(raw.albummid).ok_or(QqMusicFavoriteAlbumsError::InvalidAlbum {
        index,
        field: FavoriteAlbumField::AlbumMid,
    })?;
    let album_name = raw
        .albumname
        .filter(|value| !value.trim().is_empty() && value.len() <= MAX_TITLE_BYTES)
        .ok_or(QqMusicFavoriteAlbumsError::InvalidAlbum {
            index,
            field: FavoriteAlbumField::AlbumName,
        })?;
    Ok(QqMusicAlbumSummary::new(
        Some(catalog_id),
        Some(media_mid),
        Some(album_name),
    ))
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

    use super::{FAVORITE_ALBUMS_URL, FavoriteAlbumField, QqMusicFavoriteAlbumsError};
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
                    serde_json::to_vec(&response).expect("fixture JSON"),
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

    fn response(albums: &Value, total: u32, has_more: &Value) -> Value {
        json!({
            "code": 0,
            "subcode": 0,
            "data": {
                "albumlist": albums,
                "totalalbum": total,
                "has_more": has_more
            }
        })
    }

    #[tokio::test]
    async fn sends_inclusive_authenticated_range_and_maps_both_field_casings() {
        let client = QqMusicClient::new(FakeTransport::new(&response(
            &json!([
                {"albumid": 43001, "albummid": "fixtureAlbumMid1", "albumname": "First Album"},
                {"albumID": 43002, "albumMID": "fixtureAlbumMid2", "albumName": "Second Album"}
            ]),
            22,
            &json!(false),
        )));

        let page = client
            .favorite_albums(&credential(), 20, 2)
            .await
            .expect("favorite Albums");

        assert_eq!(page.offset(), 20);
        assert_eq!(page.total(), 22);
        assert!(!page.has_more());
        assert_eq!(page.albums().len(), 2);
        assert_eq!(page.albums()[0].album_id(), Some(43_001));
        assert_eq!(page.albums()[1].media_mid(), Some("fixtureAlbumMid2"));
        assert_eq!(page.albums()[1].name(), Some("Second Album"));

        let requests = client.transport().requests();
        assert_eq!(requests.len(), 1);
        let request = &requests[0];
        assert_eq!(request.method(), HttpMethod::Get);
        assert_eq!(request.url(), FAVORITE_ALBUMS_URL);
        assert_eq!(
            request.query_pairs(),
            &[
                ("ct".into(), "20".into()),
                ("cid".into(), "205360956".into()),
                ("userid".into(), "123456".into()),
                ("reqtype".into(), "2".into()),
                ("sin".into(), "20".into()),
                ("ein".into(), "21".into()),
                ("format".into(), "json".into()),
            ]
        );
        assert!(request.headers().iter().any(|(name, value)| {
            name == "Cookie" && value.contains("qm_keyst=W_X_fixture-key")
        }));
        let debug = format!("{request:?} {page:?}");
        assert!(!debug.contains("123456"));
        assert!(!debug.contains("W_X_fixture-key"));
        assert!(!debug.contains("Second Album"));
        assert!(!debug.contains("fixtureAlbumMid2"));
    }

    #[tokio::test]
    async fn validates_bounds_and_continuation_without_transport_guessing() {
        let client = QqMusicClient::new(FakeTransport::new(&response(&json!([]), 0, &json!(0))));
        assert_eq!(
            client.favorite_albums(&credential(), 0, 0).await,
            Err(QqMusicFavoriteAlbumsError::InvalidPageSize { size: 0 })
        );
        assert_eq!(
            client.favorite_albums(&credential(), u32::MAX, 2).await,
            Err(QqMusicFavoriteAlbumsError::InvalidRange)
        );

        let non_advancing =
            QqMusicClient::new(FakeTransport::new(&response(&json!([]), 1, &json!(true))));
        assert_eq!(
            non_advancing.favorite_albums(&credential(), 0, 20).await,
            Err(QqMusicFavoriteAlbumsError::InvalidPagination)
        );

        let inconsistent_terminal = QqMusicClient::new(FakeTransport::new(&response(
            &json!([{"albumid": 1, "albummid": "mid", "albumname": "Album"}]),
            2,
            &json!(false),
        )));
        assert_eq!(
            inconsistent_terminal
                .favorite_albums(&credential(), 0, 20)
                .await,
            Err(QqMusicFavoriteAlbumsError::InvalidPagination)
        );
    }

    #[tokio::test]
    async fn distinguishes_evidenced_rejection_upstream_and_invalid_rows() {
        let rejected = QqMusicClient::new(FakeTransport::new(&json!({
            "code": 4000,
            "subcode": 4000,
            "data": {}
        })));
        assert_eq!(
            rejected.favorite_albums(&credential(), 0, 20).await,
            Err(QqMusicFavoriteAlbumsError::Rejected { code: 4_000 })
        );

        let anonymous_shape = QqMusicClient::new(FakeTransport::new(&json!({
            "code": -1,
            "subcode": -2,
            "data": {}
        })));
        assert_eq!(
            anonymous_shape.favorite_albums(&credential(), 0, 20).await,
            Err(QqMusicFavoriteAlbumsError::Upstream {
                global_code: -1,
                subcode: Some(-2)
            })
        );

        let unevidenced_subcode = QqMusicClient::new(FakeTransport::new(&json!({
            "code": 0,
            "subcode": 4000,
            "data": {}
        })));
        assert_eq!(
            unevidenced_subcode
                .favorite_albums(&credential(), 0, 20)
                .await,
            Err(QqMusicFavoriteAlbumsError::Upstream {
                global_code: 0,
                subcode: Some(4_000)
            })
        );

        let invalid = QqMusicClient::new(FakeTransport::new(&response(
            &json!([{"albumid": 43001, "albummid": "unsafe/mid", "albumname": "Album"}]),
            1,
            &json!(0),
        )));
        assert_eq!(
            invalid.favorite_albums(&credential(), 0, 20).await,
            Err(QqMusicFavoriteAlbumsError::InvalidAlbum {
                index: 0,
                field: FavoriteAlbumField::AlbumMid
            })
        );
    }
}
