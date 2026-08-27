use std::fmt;
use std::time::Duration;

use serde::Deserialize;

use crate::{HttpRequest, HttpTransport, QqMusicClient};

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
            .field("content", &"[REDACTED]")
            .field("published_at_unix_seconds", &self.published_at_unix_seconds)
            .field("praise_count", &self.praise_count)
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct QqMusicTrackCommentsPage {
    offset: u32,
    total: u32,
    has_more: bool,
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
            .field("total", &self.total)
            .field("has_more", &self.has_more)
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
    commentlist: Option<Vec<RawComment>>,
}

#[derive(Deserialize)]
struct RawComment {
    commentid: Option<FlexibleUnsigned>,
    nick: Option<String>,
    rootcommentcontent: Option<String>,
    praisenum: Option<FlexibleUnsigned>,
    time: Option<FlexibleUnsigned>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum FlexibleUnsigned {
    Number(u64),
    Text(String),
}

impl FlexibleUnsigned {
    fn to_u64(&self) -> Option<u64> {
        match self {
            Self::Number(value) => Some(*value),
            Self::Text(value) => value.parse().ok(),
        }
    }

    fn into_string(self) -> Option<String> {
        match self {
            Self::Number(value) => Some(value.to_string()),
            Self::Text(value) if value.bytes().all(|byte| byte.is_ascii_digit()) => Some(value),
            Self::Text(_) => None,
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
    let total = latest_group
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
    let hot_comments = raw_hot
        .into_iter()
        .enumerate()
        .map(|(index, raw)| map_comment(raw, CommentSection::Hot, index))
        .collect::<Result<Vec<_>, _>>()?;
    let latest_comments = raw_latest
        .into_iter()
        .enumerate()
        .map(|(index, raw)| map_comment(raw, CommentSection::Latest, index))
        .collect::<Result<Vec<_>, _>>()?;
    let returned_end = offset
        .checked_add(raw_latest_count)
        .ok_or(QqMusicTrackCommentsError::InvalidPagination)?;
    if returned_end > total {
        return Err(QqMusicTrackCommentsError::InvalidPagination);
    }
    let next_page_offset = offset
        .checked_add(requested_size)
        .ok_or(QqMusicTrackCommentsError::InvalidPagination)?;
    let has_more = raw_latest_count != 0 && next_page_offset < total;
    if raw_latest_count != 0 && !has_more && returned_end != total {
        return Err(QqMusicTrackCommentsError::InvalidPagination);
    }
    Ok(QqMusicTrackCommentsPage {
        offset,
        total,
        has_more,
        hot_comments,
        latest_comments,
    })
}

fn map_comment<E>(
    raw: RawComment,
    section: CommentSection,
    index: usize,
) -> Result<QqMusicTrackComment, QqMusicTrackCommentsError<E>> {
    let invalid = |field| QqMusicTrackCommentsError::InvalidComment {
        section,
        index,
        field,
    };
    let comment_id = raw
        .commentid
        .and_then(FlexibleUnsigned::into_string)
        .filter(|value| value != "0" && value.len() <= MAX_COMMENT_ID_BYTES)
        .ok_or_else(|| invalid(CommentField::Id))?;
    let author_display_name = bounded_text(raw.nick, MAX_AUTHOR_BYTES)
        .ok_or_else(|| invalid(CommentField::AuthorDisplayName))?;
    let content = bounded_text(raw.rootcommentcontent, MAX_CONTENT_BYTES)
        .ok_or_else(|| invalid(CommentField::Content))?;
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
    Ok(QqMusicTrackComment {
        comment_id,
        author_display_name,
        content,
        published_at_unix_seconds,
        praise_count,
    })
}

fn bounded_text(value: Option<String>, max_bytes: usize) -> Option<String> {
    value.filter(|value| !value.trim().is_empty() && value.len() <= max_bytes)
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::Mutex;

    use serde_json::{Value, json};

    use super::{
        CommentField, CommentSection, MAX_RESPONSE_BYTES, QqMusicTrackCommentsError,
        REQUEST_TIMEOUT,
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
            page.latest_comments()[0].published_at_unix_seconds(),
            1_700_000_002
        );

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

        let invalid = QqMusicClient::new(CommentsTransport::from_json(&json!({
            "comment": {
                "commenttotal": 1,
                "commentlist": [comment(
                    &json!(92001),
                    "must-not-leak-author",
                    " ",
                    &json!(1_700_000_002),
                    &json!(2)
                )]
            }
        })));
        let error = invalid
            .track_comments(41001, 0, 20)
            .await
            .expect_err("blank content");
        assert!(matches!(
            error,
            QqMusicTrackCommentsError::InvalidComment {
                section: CommentSection::Latest,
                index: 0,
                field: CommentField::Content
            }
        ));
        let debug = format!("{error:?} {error}");
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
