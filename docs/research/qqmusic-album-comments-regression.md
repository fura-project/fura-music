# QQ Music Album Order and Comment Compatibility Regression

Date: 2026-09-10
Scope: public Album Track reads and anonymous read-only song comments
Status: implemented and machine-verified; maintainer runtime acceptance remains Human review

## Executive result

Two independent QQ response-contract regressions were responsible for the reported behavior:

1. Album Track requests omitted QQ Music's explicit canonical-order selector. The service's current default returns a different order from the official client, so relying on that default made the result unstable across service changes and visibly wrong across pages.
2. The legacy comment endpoint does not consistently satisfy its own flat schema. In current public responses, `commenttotal` can be stale, reply text can live only in `middlecommentcontent`, and unavailable/deleted rows can lack displayable content or an author. Treating any one of those rows or counters as fatal discarded an otherwise usable page and surfaced `InvalidResponse`.

The fix stays inside the existing architecture. QQ request and response details remain in `qqmusic-client`; provider-neutral Domain and typed Bridge models are unchanged; Flutter only stops requiring the mapped row count to equal the raw terminal cursor position.

No account credential, Cookie, private library identity, comment text, author name, or raw response body was retained during this investigation.

## 1. Album Track order

### Reproduction

The existing request used:

```text
POST https://u.y.qq.com/cgi-bin/musicu.fcg
module = music.musichallAlbum.AlbumSongList
method = GetAlbumSongList
param = { albumMid, begin, num }
```

A bounded anonymous comparison against one stable public Album produced these results:

| Request variant | Returned `index_album` sequence |
| --- | --- |
| Existing payload, with no explicit order | 13, 12, ... 1 |
| Same payload plus `albumID: 0, order: 2` | 1, 2, ... 13 |

The explicit request also matched the official Album order when mapped through the production Rust client. The checked-in opt-in live regression records only stable public catalog identifiers and asserts the 13-item order; it does not print or retain Album/Track names or response bodies.

The `albumID: 0, order: 2` shape is independently present in Lyricify's QQ Music Album implementation and in the historical jsososo implementation. These are corroborating client implementations, not official QQ protocol documentation:

- [Lyricify QQ Music `GetAlbumSongList`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/master/Lyricify.Lyrics.Helper/Providers/Web/QQMusic/Api.cs)
- [jsososo QQMusicApi Album route at the inspected revision](https://github.com/jsososo/QQMusicApi/blob/13b08afd3180cc74d76fff208956b77a560abd22/routes/album.js)

### Root cause and chosen fix

The Flutter Album controller preserves page order and appends pages; it does not sort or reverse Tracks. The Rust response mapper also preserves upstream order. Therefore this was not a Flutter list-layout or merge-sort defect.

The QQ request now explicitly sends:

```json
{
  "albumMid": "<public album MID>",
  "albumID": 0,
  "begin": 0,
  "num": 30,
  "order": 2
}
```

This fixes the source order before pagination. Sorting client-side was rejected because numeric Track IDs are not a contractual Album sequence, and client-side reversal would be incorrect for multi-disc Albums and would scramble page boundaries.

Reachable Git history contains only the original Album browsing implementation for this file; it contains no earlier `order: 2` fix that was later reverted. The previously correct behavior was therefore most likely dependent on an earlier upstream default or a different request path, not a lost local commit.

## 2. Comment response compatibility

### Current legacy endpoint observations

The production client currently uses the stateless page-number endpoint:

```text
GET https://c.y.qq.com/base/fcgi-bin/fcg_global_comment_h5.fcg
biztype = 1
cmd = 8
topid = <public song id>
pagenum = offset / page_size
pagesize = page_size
```

Bounded anonymous probes on public songs observed the following content-free shapes:

| Public response case | Reported total | Raw rows | Relevant shape |
| --- | ---: | ---: | --- |
| Terminal first page | 1 | 16 | 9 rows contained nested reply data; next page was empty |
| Full first and second pages | 1 | 20 + 20 | reply text was nested; some root text fields were absent |
| Full page followed by terminal page | 0 | 20 + 8 | the second page was reachable despite the zero total |

Only counters, field presence, and key names were inspected. User-generated text, author identity, and comment identity were not logged or retained.

For reply-shaped rows, the top-level `commentid` matched a nested `subcommentid`; the displayable reply body was in that matching row's `subcommentcontent`. Using `rootcommentcontent` alone either rejected the row or risked showing the parent text as the reply.

### Compatibility policy

The Rust mapper now applies these bounded rules:

1. Parse and validate the opaque top-level comment identity.
2. If `middlecommentcontent` contains a `subcommentid` matching that identity, use its `subcommentcontent`; otherwise use `rootcommentcontent`.
3. Omit a row whose selected content or display author is absent/blank. This models an unavailable/deleted display row; it does not fabricate content or an author.
4. Continue rejecting malformed identities, timestamps, praise counts, oversized content, and oversized author values.
5. Advance pagination using the raw row count, not the number of displayable mapped rows.
6. If the reported total still encloses the returned raw range, retain it. If it is stale-low and a full page was returned, expose `next_page_offset + 1` as a conservative lower bound and keep continuation reachable. If it is stale-low and a short page was returned, use the observed raw end as the terminal bound.

The Provider and Flutter controller also preserve continuation when every raw row in a full page is unavailable. The visible list can be empty while the raw cursor advances by the fixed page size, so one damaged page cannot hide later valid comments or create a zero-progress retry loop.

Flutter's typed adapter still rejects negative ranges, mapped rows beyond the raw bound, hot comments on later pages, and impossible `hasMore` envelopes. It no longer requires a terminal page's displayable-row count to land exactly on the raw total because intentionally omitted upstream rows occupy raw cursor positions.

### Why this patch does not migrate endpoints

A newer musicu contract exists using:

```text
module = music.globalComment.CommentRead
method = GetNewCommentList / GetHotCommentList
cursor = LastCommentSeqNo
```

The current maintained QQMusicApi implementation advances `LastCommentSeqNo` from the final returned comment's `SeqNo`, and its model exposes `CommentList.Comments`, `HasMore`, and `Total`:

- [Current QQMusicApi comment request and cursor strategy](https://github.com/L-1124/QQMusicApi/blob/374017047c39dc987418450b6d513bc216499a69/qqmusic_api/modules/comment.py)
- [Current QQMusicApi comment response model](https://github.com/L-1124/QQMusicApi/blob/374017047c39dc987418450b6d513bc216499a69/qqmusic_api/models/comment.py)
- [Independent captured `GetNewCommentList` request shape](https://github.com/ProxymanApp/Proxyman/issues/615)

An anonymous probe confirmed that the modern endpoint responds, but changing only `PageNum` repeats the same page; the continuation cursor is required. Fura Music's current provider-neutral comment contract is stateless `(track, offset, size)`. A correct migration would therefore require an explicit cursor-bearing snapshot/continuation contract and separate hot/latest requests. That is a larger protocol and Bridge change than this reproduced regression warrants, so this patch repairs the currently shipped endpoint without inventing cursor state in Flutter. The modern route remains a future protocol migration candidate, not a hidden fallback.

## 3. Regression coverage

The implementation includes deterministic coverage for:

- exact Album request serialization including `albumID: 0` and `order: 2`;
- public live Album order through the production mapper;
- coherent and stale-low comment totals;
- full-page continuation and short-page termination;
- nested reply content selected by matching opaque ID;
- unavailable latest and hot rows omitted without discarding the page;
- a fully omitted raw page still advancing to the next fixed offset;
- malformed/oversized comment data still rejected;
- raw cursor bounds accepted by the Flutter gateway/controller when display rows were omitted;
- redacted Rust diagnostics that do not expose catalog or comment content.

The opt-in live tests are deliberately ignored in normal offline runs and require `QQMUSIC_LIVE_TESTS=1`.

## 4. Acceptance boundary

Machine evidence proves the corrected request and the observed public response shapes on 2026-09-10. It does not prove every QQ Music Album or comment corpus shape, nor does it replace maintainer verification of the exact Albums and songs that originally reproduced the issue. Runtime acceptance should check:

1. the originally reported Album against the official QQ Music client, including a multi-page or multi-disc Album if available;
2. at least one song that previously displayed “返回的是不合法的数据”;
3. initial comments, one continuation page, and retry behavior;
4. that no private/account-only content appears in logs.
