use std::fmt;
use std::time::Duration;

use serde::Deserialize;
use serde_json::Value;

use crate::{HttpRequest, HttpTransport, QqMusicClient, normalized_https_image_uri};

const COMMENTS_URL: &str = "https://c.y.qq.com/base/fcgi-bin/fcg_global_comment_h5.fcg";
const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_PAGE_SIZE: u32 = 50;
const MAX_HOT_COMMENTS: usize = 100;
const MAX_COMMENT_ID_BYTES: usize = 256;
const MAX_AUTHOR_BYTES: usize = 1024;
const MAX_CONTENT_BYTES: usize = 16 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CommentSection {
    Hot,
    Latest,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CommentField {
    Id,
    AuthorDisplayName,
    Content,
    PublishedAt,
    PraiseCount,
}

pub enum QqMusicTrackCommentsError<E> {
    InvalidSongId,
    InvalidPageSize {
        size: u32,
    },
    InvalidOffset {
        offset: u32,
        size: u32,
    },
    Transport(E),
    HttpStatus(u16),
    InvalidJson,
    Upstream {
        code: i64,
        subcode: Option<i64>,
    },
    MissingLatestComments,
    MissingTotal,
    InvalidPagination,
    InvalidComment {
        section: CommentSection,
        index: usize,
        field: CommentField,
    },
}

impl<E> fmt::Debug for QqMusicTrackCommentsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidSongId => formatter.write_str("InvalidSongId([REDACTED])"),
            Self::InvalidPageSize { size } => formatter
                .debug_struct("InvalidPageSize")
                .field("size", size)
                .finish(),
            Self::InvalidOffset { offset, size } => formatter
                .debug_struct("InvalidOffset")
                .field("offset", offset)
                .field("size", size)
                .finish(),
            Self::Transport(_) => formatter.write_str("Transport([REDACTED])"),
            Self::HttpStatus(status) => formatter.debug_tuple("HttpStatus").field(status).finish(),
            Self::InvalidJson => formatter.write_str("InvalidJson([REDACTED])"),
            Self::Upstream { code, subcode } => formatter
                .debug_struct("Upstream")
                .field("code", code)
                .field("subcode", subcode)
                .finish(),
            Self::MissingLatestComments => formatter.write_str("MissingLatestComments"),
            Self::MissingTotal => formatter.write_str("MissingTotal"),
            Self::InvalidPagination => formatter.write_str("InvalidPagination"),
            Self::InvalidComment {
                section,
                index,
                field,
            } => formatter
                .debug_struct("InvalidComment")
                .field("section", section)
                .field("index", index)
                .field("field", field)
                .finish(),
        }
    }
}

impl<E> fmt::Display for QqMusicTrackCommentsError<E> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidSongId => formatter.write_str("QQ Music song identity is invalid"),
            Self::InvalidPageSize { size } => {
                write!(
                    formatter,
                    "comment page size {size} is outside 1..={MAX_PAGE_SIZE}"
                )
            }
            Self::InvalidOffset { offset, size } => write!(
                formatter,
                "comment offset {offset} is not aligned to page size {size}"
            ),
            Self::Transport(_) => formatter.write_str("QQ Music comment request failed"),
            Self::HttpStatus(status) => {
                write!(formatter, "comment request returned HTTP {status}")
            }
            Self::InvalidJson => formatter.write_str("comment response was not valid JSON"),
            Self::Upstream { code, subcode } => write!(
                formatter,
                "comment request failed with code {code} and subcode {subcode:?}"
            ),
            Self::MissingLatestComments => {
                formatter.write_str("comment response has no latest-comment section")
            }
            Self::MissingTotal => formatter.write_str("comment response has no total count"),
            Self::InvalidPagination => formatter.write_str("comment pagination is invalid"),
            Self::InvalidComment {
                section,
                index,
                field,
            } => write!(
                formatter,
                "{section:?} comment {index} has an invalid {field:?}"
            ),
        }
    }
}

impl<E> std::error::Error for QqMusicTrackCommentsError<E>
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
pub struct QqMusicTrackComment {
    comment_id: String,
    author_display_name: String,
    author_avatar_uri: Option<String>,
    content: String,
    published_at_unix_seconds: u64,
    praise_count: u64,
}

impl QqMusicTrackComment {
    #[must_use]
    pub fn comment_id(&self) -> &str {
        &self.comment_id
    }

    #[must_use]
    pub fn author_display_name(&self) -> &str {
        &self.author_display_name
    }

    #[must_use]
    pub fn author_avatar_uri(&self) -> Option<&str> {
        self.author_avatar_uri.as_deref()
    }

    #[must_use]
    pub fn content(&self) -> &str {
        &self.content
    }

    #[must_use]
    pub const fn published_at_unix_seconds(&self) -> u64 {
        self.published_at_unix_seconds
    }

    #[must_use]
    pub const fn praise_count(&self) -> u64 {
        self.praise_count
    }
}

impl fmt::Debug for QqMusicTrackComment {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicTrackComment")
            .field("comment_id", &"[REDACTED]")
            .field("author_display_name", &"[REDACTED]")
            .field("has_author_avatar", &self.author_avatar_uri.is_some())
            .field("content", &"[REDACTED]")
            .field("published_at_unix_seconds", &self.published_at_unix_seconds)
            .field("praise_count", &self.praise_count)
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicTrackCommentsPage {
    offset: u32,
    next_offset: u32,
    total: u32,
    has_more: bool,
    omitted_hot_comment_count: u32,
    omitted_latest_comment_count: u32,
    hot_comments: Vec<QqMusicTrackComment>,
    latest_comments: Vec<QqMusicTrackComment>,
}

impl QqMusicTrackCommentsPage {
    #[must_use]
    pub const fn offset(&self) -> u32 {
        self.offset
    }

    #[must_use]
    pub const fn total(&self) -> u32 {
        self.total
    }

    #[must_use]
    pub const fn next_offset(&self) -> u32 {
        self.next_offset
    }

    #[must_use]
    pub const fn omitted_hot_comment_count(&self) -> u32 {
        self.omitted_hot_comment_count
    }

    #[must_use]
    pub const fn omitted_latest_comment_count(&self) -> u32 {
        self.omitted_latest_comment_count
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn hot_comments(&self) -> &[QqMusicTrackComment] {
        &self.hot_comments
    }

    #[must_use]
    pub fn latest_comments(&self) -> &[QqMusicTrackComment] {
        &self.latest_comments
    }
}

impl fmt::Debug for QqMusicTrackCommentsPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("QqMusicTrackCommentsPage")
            .field("offset", &self.offset)
            .field("next_offset", &self.next_offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("omitted_hot_comment_count", &self.omitted_hot_comment_count)
            .field(
                "omitted_latest_comment_count",
                &self.omitted_latest_comment_count,
            )
            .field("hot_comment_count", &self.hot_comments.len())
            .field("latest_comment_count", &self.latest_comments.len())
            .finish()
    }
}

impl<T> QqMusicClient<T>
where
    T: HttpTransport,
{
    /// Loads one anonymous bounded page of read-only song comments.
    ///
    /// Hot comments are kept separate on the initial page. Page continuation
    /// applies only to the latest-comment collection.
    ///
    /// # Errors
    ///
    /// Keeps transport, service, pagination, and row failures distinct while
    /// keeping returned user-generated content out of diagnostics.
    pub async fn track_comments(
        &self,
        song_id: u64,
        offset: u32,
        size: u32,
    ) -> Result<QqMusicTrackCommentsPage, QqMusicTrackCommentsError<T::Error>> {
        if song_id == 0 {
            return Err(QqMusicTrackCommentsError::InvalidSongId);
        }
        if !(1..=MAX_PAGE_SIZE).contains(&size) {
            return Err(QqMusicTrackCommentsError::InvalidPageSize { size });
        }
        if !offset.is_multiple_of(size) {
            return Err(QqMusicTrackCommentsError::InvalidOffset { offset, size });
        }
        let page_number = offset / size;
        let response = self
            .transport()
            .execute(
                HttpRequest::get(COMMENTS_URL)
                    .query("g_tk", "5381")
                    .query("loginUin", "0")
                    .query("hostUin", "0")
                    .query("format", "json")
                    .query("inCharset", "utf8")
                    .query("outCharset", "utf-8")
                    .query("notice", "0")
                    .query("platform", "yqq.json")
                    .query("needNewCode", "0")
                    .query("cid", "205360772")
                    .query("reqtype", "2")
                    .query("biztype", "1")
                    .query("topid", song_id.to_string())
                    .query("cmd", "8")
                    .query("needmusiccrit", "0")
                    .query("pagenum", page_number.to_string())
                    .query("pagesize", size.to_string())
                    .header("Referer", "https://y.qq.com/")
                    .response_body_limit(MAX_RESPONSE_BYTES)
                    .timeout(REQUEST_TIMEOUT),
            )
            .await
            .map_err(QqMusicTrackCommentsError::Transport)?;
        if !(200..300).contains(&response.status()) {
            return Err(QqMusicTrackCommentsError::HttpStatus(response.status()));
        }
        let envelope: LegacyCommentResponse = serde_json::from_slice(response.body())
            .map_err(|_| QqMusicTrackCommentsError::InvalidJson)?;
        map_response(envelope, offset, size)
    }
}

#[derive(Deserialize)]
struct LegacyCommentResponse {
    code: Option<i64>,
    subcode: Option<i64>,
    hot_comment: Option<RawCommentGroup>,
    comment: Option<RawCommentGroup>,
}

#[derive(Deserialize)]
struct RawCommentGroup {
    commenttotal: Option<FlexibleUnsigned>,
    commentlist: Option<Vec<Value>>,
}

#[derive(Deserialize)]
struct RawComment {
    commentid: Option<FlexibleCommentId>,
    nick: Option<String>,
    avatarurl: Option<String>,
    rootcommentcontent: Option<String>,
    middlecommentcontent: Option<Vec<RawSubComment>>,
    praisenum: Option<FlexibleUnsigned>,
    time: Option<FlexibleUnsigned>,
}

#[derive(Deserialize)]
struct RawSubComment {
    subcommentid: Option<FlexibleCommentId>,
    subcommentcontent: Option<String>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum FlexibleUnsigned {
    Number(u64),
    Text(String),
}

#[derive(Deserialize)]
#[serde(untagged)]
enum FlexibleCommentId {
    Number(u64),
    Text(String),
}

impl FlexibleCommentId {
    fn into_string(self) -> Option<String> {
        match self {
            Self::Number(value) if value != 0 => Some(value.to_string()),
            Self::Text(value)
                if value != "0"
                    && !value.trim().is_empty()
                    && value.len() <= MAX_COMMENT_ID_BYTES
                    && !value.chars().any(char::is_control) =>
            {
                Some(value)
            }
            Self::Number(_) | Self::Text(_) => None,
        }
    }
}

impl FlexibleUnsigned {
    fn to_u64(&self) -> Option<u64> {
        match self {
            Self::Number(value) => Some(*value),
            Self::Text(value) => value.parse().ok(),
        }
    }
}

fn map_response<E>(
    envelope: LegacyCommentResponse,
    offset: u32,
    requested_size: u32,
) -> Result<QqMusicTrackCommentsPage, QqMusicTrackCommentsError<E>> {
    if envelope.code.is_some_and(|code| code != 0) || envelope.subcode.is_some_and(|code| code != 0)
    {
        return Err(QqMusicTrackCommentsError::Upstream {
            code: envelope.code.unwrap_or(0),
            subcode: envelope.subcode,
        });
    }
    let latest_group = envelope
        .comment
        .ok_or(QqMusicTrackCommentsError::MissingLatestComments)?;
    let reported_total = latest_group
        .commenttotal
        .as_ref()
        .and_then(FlexibleUnsigned::to_u64)
        .and_then(|value| u32::try_from(value).ok())
        .ok_or(QqMusicTrackCommentsError::MissingTotal)?;
    let raw_latest = latest_group.commentlist.unwrap_or_default();
    let raw_latest_count = u32::try_from(raw_latest.len())
        .map_err(|_| QqMusicTrackCommentsError::InvalidPagination)?;
    if raw_latest_count > requested_size {
        return Err(QqMusicTrackCommentsError::InvalidPagination);
    }
    let raw_hot = if offset == 0 {
        envelope
            .hot_comment
            .and_then(|group| group.commentlist)
            .unwrap_or_default()
    } else {
        Vec::new()
    };
    if raw_hot.len() > MAX_HOT_COMMENTS {
        return Err(QqMusicTrackCommentsError::InvalidPagination);
    }
    let (hot_comments, omitted_hot_comment_count) = map_comment_rows(raw_hot, CommentSection::Hot)?;
    let (latest_comments, omitted_latest_comment_count) =
        map_comment_rows(raw_latest, CommentSection::Latest)?;
    let (total, has_more) =
        normalize_pagination(reported_total, offset, requested_size, raw_latest_count)?;
    let next_offset = offset
        .checked_add(raw_latest_count)
        .ok_or(QqMusicTrackCommentsError::InvalidPagination)?;
    Ok(QqMusicTrackCommentsPage {
        offset,
        next_offset,
        total,
        has_more,
        omitted_hot_comment_count,
        omitted_latest_comment_count,
        hot_comments,
        latest_comments,
    })
}

fn map_comment_rows<E>(
    rows: Vec<Value>,
    section: CommentSection,
) -> Result<(Vec<QqMusicTrackComment>, u32), QqMusicTrackCommentsError<E>> {
    let mut comments = Vec::with_capacity(rows.len());
    let mut omitted = 0_u32;
    for (index, value) in rows.into_iter().enumerate() {
        let mapped = serde_json::from_value::<RawComment>(value)
            .map_err(|_| QqMusicTrackCommentsError::InvalidComment {
                section,
                index,
                field: CommentField::Id,
            })
            .and_then(|raw| map_comment(raw, section, index));
        match mapped {
            Ok(Some(comment)) => comments.push(comment),
            Ok(None) | Err(QqMusicTrackCommentsError::InvalidComment { .. }) => {
                omitted = omitted
                    .checked_add(1)
                    .ok_or(QqMusicTrackCommentsError::InvalidPagination)?;
            }
            Err(error) => return Err(error),
        }
    }
    Ok((comments, omitted))
}

fn normalize_pagination<E>(
    reported_total: u32,
    offset: u32,
    requested_size: u32,
    raw_count: u32,
) -> Result<(u32, bool), QqMusicTrackCommentsError<E>> {
    let returned_end = offset
        .checked_add(raw_count)
        .ok_or(QqMusicTrackCommentsError::InvalidPagination)?;
    let next_page_offset = offset
        .checked_add(requested_size)
        .ok_or(QqMusicTrackCommentsError::InvalidPagination)?;

    if returned_end <= reported_total {
        let has_more = raw_count != 0 && next_page_offset < reported_total;
        return Ok((reported_total, has_more));
    }

    // The legacy endpoint is observed returning a stale commenttotal while
    // still returning valid rows. A full page proves that another page may be
    // reachable, but a short page is the only bounded terminal signal this
    // stateless page-number contract exposes.
    if raw_count == requested_size {
        let lower_bound_total = next_page_offset
            .checked_add(1)
            .ok_or(QqMusicTrackCommentsError::InvalidPagination)?;
        Ok((lower_bound_total, true))
    } else {
        Ok((returned_end, false))
    }
}

fn map_comment<E>(
    raw: RawComment,
    section: CommentSection,
    index: usize,
) -> Result<Option<QqMusicTrackComment>, QqMusicTrackCommentsError<E>> {
    let invalid = |field| QqMusicTrackCommentsError::InvalidComment {
        section,
        index,
        field,
    };
    let comment_id = raw
        .commentid
        .and_then(FlexibleCommentId::into_string)
        .ok_or_else(|| invalid(CommentField::Id))?;
    let nested_content = raw.middlecommentcontent.and_then(|comments| {
        comments.into_iter().find_map(|comment| {
            let subcomment_id = comment.subcommentid?.into_string()?;
            (subcomment_id == comment_id).then_some(comment.subcommentcontent)
        })
    });
    let content = match nested_content {
        Some(content) => content,
        None => raw.rootcommentcontent,
    };
    let Some(content) = content.filter(|value| !value.trim().is_empty()) else {
        return Ok(None);
    };
    if content.len() > MAX_CONTENT_BYTES {
        return Err(invalid(CommentField::Content));
    }
    let Some(author_display_name) = raw.nick else {
        return Ok(None);
    };
    if author_display_name.trim().is_empty() {
        return Ok(None);
    }
    if author_display_name.len() > MAX_AUTHOR_BYTES {
        return Err(invalid(CommentField::AuthorDisplayName));
    }
    let published_at_unix_seconds = raw
        .time
        .as_ref()
        .and_then(FlexibleUnsigned::to_u64)
        .filter(|value| *value != 0)
        .ok_or_else(|| invalid(CommentField::PublishedAt))?;
    let praise_count = raw
        .praisenum
        .as_ref()
        .and_then(FlexibleUnsigned::to_u64)
        .ok_or_else(|| invalid(CommentField::PraiseCount))?;
    Ok(Some(QqMusicTrackComment {
        comment_id,
        author_display_name,
        author_avatar_uri: normalized_https_image_uri(raw.avatarurl),
        content,
        published_at_unix_seconds,
        praise_count,
    }))
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use super::{
        MAX_CONTENT_BYTES, MAX_RESPONSE_BYTES, QqMusicTrackCommentsError, REQUEST_TIMEOUT,
    };
    use crate::{HttpMethod, HttpRequest, HttpResponse, HttpTransport, QqMusicClient};

    struct CommentsTransport {
        response: HttpResponse,
        requests: Mutex<Vec<HttpRequest>>,
    }

    impl CommentsTransport {
        fn from_json(body: &Value) -> Self {
            Self {
                response: HttpResponse::new(200, serde_json::to_vec(body).expect("fixture JSON")),
                requests: Mutex::new(Vec::new()),
            }
        }

        fn with_response(status: u16, body: &[u8]) -> Self {
            Self {
                response: HttpResponse::new(status, body.to_vec()),
                requests: Mutex::new(Vec::new()),
            }
        }
    }

    impl HttpTransport for CommentsTransport {
        type Error = Infallible;

        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            self.requests.lock().expect("request lock").push(request);
            Ok(self.response.clone())
        }
    }

    fn comment(id: &Value, author: &str, content: &str, time: &Value, praise: &Value) -> Value {
        json!({
            "commentid": id,
            "nick": author,
            "avatarurl": "http://thirdqq.qlogo.cn/g?b=qq&nk=fixture",
            "rootcommentcontent": content,
            "time": time,
            "praisenum": praise
        })
    }

    #[tokio::test]
    async fn sends_evidenced_anonymous_request_and_maps_separate_sections() {
        let client = QqMusicClient::new(CommentsTransport::from_json(&json!({
            "code": 0,
            "subcode": 0,
            "hot_comment": {"commentlist": [
                comment(&json!("91001"), "Fixture hot author", "Fixture hot text", &json!(1_700_000_001), &json!(41))
            ]},
            "comment": {
                "commenttotal": "21",
                "commentlist": [
                    comment(&json!(92001), "Fixture latest author", "Fixture latest text", &json!("1700000002"), &json!("7"))
                ]
            }
        })));

        let page = client
            .track_comments(41001, 0, 20)
            .await
            .expect("comment page");
        assert_eq!(page.offset(), 0);
        assert_eq!(page.total(), 21);
        assert!(page.has_more());
        assert_eq!(page.hot_comments()[0].comment_id(), "91001");
        assert_eq!(page.hot_comments()[0].praise_count(), 41);
        assert_eq!(
            page.latest_comments()[0].author_display_name(),
            "Fixture latest author"
        );
        assert_eq!(page.latest_comments()[0].content(), "Fixture latest text");
        assert_eq!(
            page.latest_comments()[0].author_avatar_uri(),
            Some("https://thirdqq.qlogo.cn/g?b=qq&nk=fixture")
        );
        assert_eq!(
            page.latest_comments()[0].published_at_unix_seconds(),
            1_700_000_002
        );
        let debug = format!("{:?}", page.latest_comments()[0]);
        assert!(debug.contains("has_author_avatar: true"));
        assert!(!debug.contains("thirdqq.qlogo.cn"));

        let request = &client.transport().requests.lock().expect("request lock")[0];
        assert_eq!(request.method(), HttpMethod::Get);
        assert_eq!(
            request.url(),
            "https://c.y.qq.com/base/fcgi-bin/fcg_global_comment_h5.fcg"
        );
        assert_eq!(request.max_response_body_bytes(), MAX_RESPONSE_BYTES);
        assert_eq!(request.request_timeout(), Some(REQUEST_TIMEOUT));
        assert!(request.headers().iter().all(|(name, _)| name != "Cookie"));
        let query = request.query_pairs();
        for pair in [
            ("biztype", "1"),
            ("topid", "41001"),
            ("cmd", "8"),
            ("pagenum", "0"),
            ("pagesize", "20"),
        ] {
            assert!(
                query
                    .iter()
                    .any(|(name, value)| name == pair.0 && value == pair.1)
            );
        }
        let debug = format!("{page:?} {:?} {request:?}", page.hot_comments()[0]);
        for private in [
            "41001",
            "91001",
            "Fixture hot author",
            "Fixture hot text",
            "Fixture latest author",
            "Fixture latest text",
        ] {
            assert!(!debug.contains(private));
        }
    }

    #[tokio::test]
    async fn keeps_bounded_non_numeric_comment_identity_opaque() {
        let client = QqMusicClient::new(CommentsTransport::from_json(&json!({
            "code": 0,
            "subcode": 0,
            "comment": {
                "commenttotal": 1,
                "commentlist": [
                    comment(
                        &json!("fixture-comment:id/value=opaque"),
                        "Fixture author",
                        "Fixture text",
                        &json!(1_700_000_002),
                        &json!(7)
                    )
                ]
            }
        })));

        let page = client
            .track_comments(41001, 0, 20)
            .await
            .expect("comment page");
        assert_eq!(
            page.latest_comments()[0].comment_id(),
            "fixture-comment:id/value=opaque"
        );
        assert!(!format!("{page:?}").contains("fixture-comment:id/value=opaque"));
    }

    #[tokio::test]
    async fn skips_evidenced_blank_deleted_rows_without_changing_pagination() {
        let client = QqMusicClient::new(CommentsTransport::from_json(&json!({
            "code": 0,
            "subcode": 0,
            "comment": {
                "commenttotal": 2,
                "commentlist": [
                    comment(
                        &json!(92001),
                        "Fixture author",
                        "Fixture text",
                        &json!(1_700_000_002),
                        &json!(7)
                    ),
                    comment(
                        &json!(92002),
                        "Deleted author",
                        "   ",
                        &json!(1_700_000_003),
                        &json!(0)
                    )
                ]
            }
        })));

        let page = client
            .track_comments(41001, 0, 2)
            .await
            .expect("comment page");
        assert_eq!(page.total(), 2);
        assert_eq!(page.latest_comments().len(), 1);
        assert!(!page.has_more());
    }

    #[tokio::test]
    async fn omits_unavailable_hot_rows_without_discarding_latest_comments() {
        let client = QqMusicClient::new(CommentsTransport::from_json(&json!({
            "code": 0,
            "subcode": 0,
            "hot_comment": {
                "commentlist": [comment(
                    &json!(92002),
                    "Fixture author",
                    "   ",
                    &json!(1_700_000_003),
                    &json!(0)
                )]
            },
            "comment": {
                "commenttotal": 1,
                "commentlist": [comment(
                    &json!(92003),
                    "Latest author",
                    "Latest content",
                    &json!(1_700_000_004),
                    &json!(1)
                )]
            }
        })));

        let page = client
            .track_comments(41001, 0, 20)
            .await
            .expect("unavailable hot row is optional");
        assert!(page.hot_comments().is_empty());
        assert_eq!(page.latest_comments().len(), 1);
    }

    #[tokio::test]
    async fn maps_matching_nested_reply_content_instead_of_parent_content() {
        let client = QqMusicClient::new(CommentsTransport::from_json(&json!({
            "code": 0,
            "subcode": 0,
            "comment": {
                "commenttotal": 1,
                "commentlist": [{
                    "commentid": "reply:92001",
                    "nick": "Reply author",
                    "rootcommentcontent": "Parent content must not be selected",
                    "middlecommentcontent": [{
                        "subcommentid": "reply:92001",
                        "subcommentcontent": "Actual reply content"
                    }, {
                        "subcommentid": "different:92002",
                        "subcommentcontent": "Different reply content"
                    }],
                    "time": 1_700_000_002,
                    "praisenum": 7
                }]
            }
        })));

        let page = client
            .track_comments(41001, 0, 20)
            .await
            .expect("nested reply page");
        assert_eq!(page.latest_comments().len(), 1);
        assert_eq!(page.latest_comments()[0].content(), "Actual reply content");
    }

    #[tokio::test]
    async fn omits_rows_without_displayable_content_or_author() {
        let client = QqMusicClient::new(CommentsTransport::from_json(&json!({
            "code": 0,
            "subcode": 0,
            "comment": {
                "commenttotal": 3,
                "commentlist": [{
                    "commentid": 92001,
                    "nick": "Reply author",
                    "middlecommentcontent": [{
                        "subcommentid": 92001
                    }],
                    "time": 1_700_000_002,
                    "praisenum": 7
                }, comment(
                    &json!(92002),
                    "   ",
                    "Unavailable author",
                    &json!(1_700_000_003),
                    &json!(0)
                ), comment(
                    &json!(92003),
                    "Visible author",
                    "Visible content",
                    &json!(1_700_000_004),
                    &json!(1)
                )]
            }
        })));

        let page = client
            .track_comments(41001, 0, 20)
            .await
            .expect("unavailable rows do not invalidate the page");
        assert_eq!(page.total(), 3);
        assert_eq!(page.latest_comments().len(), 1);
        assert_eq!(page.latest_comments()[0].comment_id(), "92003");
    }

    #[tokio::test]
    async fn normalizes_stale_legacy_totals_without_losing_page_reachability() {
        let full_page = (0..20)
            .map(|index| {
                comment(
                    &json!(92_000 + index),
                    "Visible author",
                    "Visible content",
                    &json!(1_700_000_000 + index),
                    &json!(0),
                )
            })
            .collect::<Vec<_>>();
        let client = QqMusicClient::new(CommentsTransport::from_json(&json!({
            "comment": {
                "commenttotal": 1,
                "commentlist": full_page
            }
        })));

        let page = client
            .track_comments(41001, 0, 20)
            .await
            .expect("full page with stale total");
        assert_eq!(page.total(), 21);
        assert!(page.has_more());

        let unavailable_full_page = (0..20)
            .map(|index| {
                comment(
                    &json!(93_000 + index),
                    "Unavailable author",
                    "   ",
                    &json!(1_700_000_100 + index),
                    &json!(0),
                )
            })
            .collect::<Vec<_>>();
        let client = QqMusicClient::new(CommentsTransport::from_json(&json!({
            "comment": {
                "commenttotal": 1,
                "commentlist": unavailable_full_page
            }
        })));
        let page = client
            .track_comments(41001, 0, 20)
            .await
            .expect("fully unavailable raw page");
        assert!(page.latest_comments().is_empty());
        assert_eq!(page.total(), 21);
        assert!(page.has_more());

        let terminal = QqMusicClient::new(CommentsTransport::from_json(&json!({
            "comment": {
                "commenttotal": 1,
                "commentlist": [comment(
                    &json!(93001),
                    "Visible author",
                    "Visible content",
                    &json!(1_700_000_100),
                    &json!(0)
                )]
            }
        })));
        let page = terminal
            .track_comments(41001, 20, 20)
            .await
            .expect("short page with stale total");
        assert_eq!(page.total(), 21);
        assert!(!page.has_more());
    }

    #[tokio::test]
    async fn later_and_zero_row_pages_have_safe_terminal_semantics() {
        let later = QqMusicClient::new(CommentsTransport::from_json(&json!({
            "hot_comment": {"commentlist": [
                comment(&json!(91001), "Ignored hot", "Ignored hot text", &json!(1_700_000_001), &json!(1))
            ]},
            "comment": {
                "commenttotal": 21,
                "commentlist": [
                    comment(&json!(92001), "Latest", "Latest text", &json!(1_700_000_002), &json!(2))
                ]
            }
        })));
        let page = later
            .track_comments(41001, 20, 20)
            .await
            .expect("later page");
        assert!(page.hot_comments().is_empty());
        assert!(!page.has_more());

        let zero = QqMusicClient::new(CommentsTransport::from_json(&json!({
            "comment": {"commenttotal": 40, "commentlist": []}
        })));
        let page = zero
            .track_comments(41001, 20, 20)
            .await
            .expect("empty page");
        assert!(page.latest_comments().is_empty());
        assert!(!page.has_more());
    }

    #[tokio::test]
    async fn rejects_invalid_inputs_pagination_and_user_content_without_leaking_it() {
        let transport = CommentsTransport::from_json(&json!({}));
        let client = QqMusicClient::new(transport);
        assert!(matches!(
            client.track_comments(0, 0, 20).await,
            Err(QqMusicTrackCommentsError::InvalidSongId)
        ));
        assert!(matches!(
            client.track_comments(41001, 0, 0).await,
            Err(QqMusicTrackCommentsError::InvalidPageSize { size: 0 })
        ));
        assert!(matches!(
            client.track_comments(41001, 3, 20).await,
            Err(QqMusicTrackCommentsError::InvalidOffset { .. })
        ));
        assert!(
            client
                .transport()
                .requests
                .lock()
                .expect("request lock")
                .is_empty()
        );

        let oversized_content = format!("must-not-leak{}", "x".repeat(MAX_CONTENT_BYTES));
        let invalid = QqMusicClient::new(CommentsTransport::from_json(&json!({
            "comment": {
                "commenttotal": 1,
                "commentlist": [comment(
                    &json!(92001),
                    "must-not-leak-author",
                    &oversized_content,
                    &json!(1_700_000_002),
                    &json!(2)
                )]
            }
        })));
        let partial = invalid
            .track_comments(41001, 0, 20)
            .await
            .expect("oversized row is isolated");
        assert!(partial.latest_comments().is_empty());
        assert_eq!(partial.omitted_latest_comment_count(), 1);
        assert_eq!(partial.next_offset(), 1);
        let debug = format!("{partial:?}");
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("41001"));
    }

    #[tokio::test]
    async fn keeps_http_service_and_json_failures_distinct() {
        let http = QqMusicClient::new(CommentsTransport::with_response(503, b"private body"));
        assert!(matches!(
            http.track_comments(41001, 0, 20).await,
            Err(QqMusicTrackCommentsError::HttpStatus(503))
        ));

        let upstream = QqMusicClient::new(CommentsTransport::from_json(&json!({
            "code": 100,
            "subcode": 7,
            "comment": {"commenttotal": 0, "commentlist": []}
        })));
        assert!(matches!(
            upstream.track_comments(41001, 0, 20).await,
            Err(QqMusicTrackCommentsError::Upstream {
                code: 100,
                subcode: Some(7)
            })
        ));

        let invalid = QqMusicClient::new(CommentsTransport::with_response(200, b"not json"));
        assert!(matches!(
            invalid.track_comments(41001, 0, 20).await,
            Err(QqMusicTrackCommentsError::InvalidJson)
        ));
    }
}
