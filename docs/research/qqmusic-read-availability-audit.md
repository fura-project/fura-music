# QQ Music read-availability audit — 2026-09-01

## Purpose and safety boundary

This audit distinguishes a legitimate empty result from an authorization or
service restriction and from a client incompatibility. It used only bounded,
anonymous, read-only live gates over already published public identities. No
stored credential, account endpoint, returned title, author, comment, lyric,
media URI, vkey, or response body was printed, retained, or committed.

## Outcome matrix

| Capability | Legitimate absence | Restriction/service result | Incompatible data | Current evidence |
| --- | --- | --- | --- | --- |
| Search | A successful page may contain zero rows. | QQ result code `2001` is rate limiting, not an empty page. | Missing codes/page shape or invalid Track identity remains `InvalidResponse`. | The same bounded request first succeeded, then repeated requests returned `2001`. Two current independent clients classify `2001` as rate limiting. No automatic retry was added. |
| Lyrics/QRC | Empty original lyric or a successful response without QRC is `Unavailable`; translation and romanization may independently be absent. | Explicit anonymous rejection is `AuthenticationRequired`; authenticated rejection remains `CredentialRejected`. Other nonzero upstream codes are service failures. | Missing required original field, invalid ciphertext/XML/timing, or mismatched identity remains `InvalidResponse`. | Anonymous no-Cookie request, decrypt, and QRC parse passed. The Provider no longer blocks signed-out lyrics before this request. |
| Comments | A valid page/list may be empty; blank deleted rows are tolerated only in the already evidenced newest-list shape. | HTTP/nonzero service failures remain retryable service outcomes. | Invalid pagination or malformed nonblank rows remain invalid responses. | One anonymous public page mapped successfully. The live redaction assertion was corrected so short returned values cannot create substring false positives. |
| Track-associated MV | A Track with no associated VID is successful `None`. | An associated MV without an accepted HTTPS MP4 source is `SourceUnavailable`; service codes remain service failures. | Track/VID mismatch or malformed metadata remains invalid. | One anonymous public Track-associated MV and HTTPS source mapped successfully. |
| Public Playlist Detail | A valid terminal page may be empty. | Code `2001` is rate limiting and STOP; other unknown nonzero codes remain service failures rather than being guessed into authentication. | Missing identity, page fields, required Track context, or an empty continuing page remains invalid. | The production `catalog:*` route and a two-request ignored live gate pass anonymously without Cookie/account fields; account-owned/favorite/liked contexts remain authenticated. |
| Playlist/ranking artwork | Artwork is optional display metadata; blank, invalid, or unsafe cleartext artwork becomes absent without invalidating the catalog item. | None is inferred from artwork alone. | Required playlist identity/title failures still invalidate the row. | Shared normalization preserves HTTPS, upgrades only the independently observed `http://qpic.y.qq.com` host, and drops other cleartext/invalid values. |
| Guest media source | Individual Tracks may truthfully be unavailable to an anonymous request. | Rejection/unavailable is not relabeled as VIP, region, or copyright restriction without evidence. | Mismatched source identity, absolute provider path, or malformed response remains invalid. | A bounded current new-song sample produced at least one anonymous playable source. Search is no longer a prerequisite of this gate because its independent rate limit caused false failures. |
| Related Tracks | A successful empty set is legitimate. | Signed-request service/rejection failures remain distinct. | Duplicate or malformed Track rows remain invalid. | The bounded anonymous public-seed live gate returned a nonempty compatible set. |
| Other public catalog reads | Empty new-song/new-album/recommendation/search pages are valid only where their endpoint supplies a valid empty collection and terminal pagination. | HTTP or nonzero global/named-request codes remain network/service outcomes. | Missing collections, non-advancing pagination, mismatched requested identity, duplicate identity, and malformed required fields remain invalid. | Existing fixture suites cover Album, Artist, Playlist, rankings, recommendations, and new-release boundaries; this pass additionally exercised the public new-song operation through the media gate. |
| Account/library reads | A verified account may legitimately own zero Playlists/favorites or receive an empty personalized shelf. | Signed out is `AuthenticationRequired`; explicit credential rejection remains distinct and clears only the still-current credential. | Missing result collections, invalid account-scoped identity, duplicate/non-advancing pages, and malformed rows remain invalid. | Offline lifecycle/mapping coverage passes. This pass deliberately did not automate a stored account, so live account-wide availability remains maintainer evidence. |

## Current implementation corrections

1. `QQMusicClient::lyrics` accepts an optional credential. Signed-out requests
   carry no Cookie and use only the anonymous zero/empty musicu account fields.
   `QQMusicProvider` still rechecks authenticated account replacement and clears
   an authenticated credential only on explicit rejection.
2. Optional playlist and ranking artwork now uses one bounded URL policy.
   Invalid optional artwork can no longer turn valid playlist data into a
   protocol failure, and the verified QQ image host is upgraded to HTTPS for
   Android-safe loading.
3. The media live gate obtains candidate Tracks from the public new-song
   catalog rather than Search, so a Search-only rate limit cannot falsely report
   that guest media resolution is broken.
4. Live comment diagnostics assert fixed redaction markers rather than checking
   whether arbitrary returned user strings happen to occur inside a debug
   representation.
5. Public `catalog:*` Playlist Detail now uses the independently evidenced
   anonymous `CgiGetDiss` context. Account-owned, favorite, and liked-song
   identity remains authenticated; an anonymous failure never clears the
   current account credential.

## External cross-check

- [L-1124/QQMusicApi at `108617f`](https://github.com/L-1124/QQMusicApi/tree/108617ffe80abefec6358717b9f4d3677550db10)
  maps response code `2001` to a dedicated `RatelimitedError` and treats lyric
  translation/romanization as optional strings.
- [Suxiaoqinx/QQMusicapi at `b6d748b`](https://github.com/Suxiaoqinx/QQMusicapi/tree/b6d748bb63fc65b6a98a383d8974fe3f3fd75d5b)
  independently maps code `2001` to a rate-limit error.

These implementations are evidence only. Their source was not copied.

## Limits that remain truthful

- The successful public samples do not prove that every song has lyrics,
  comments, an MV, artwork, related Tracks, or an anonymously playable source.
- QQ does not guarantee translation or romanization for every lyric, and this
  project still uses exact-start alignment rather than guessing a fuzzy match.
- A service result cannot currently be labeled as VIP, regional, copyright, or
  device restriction unless the specific outcome is independently evidenced.
- Search code `2001` is an upstream anti-abuse/rate-limit outcome. The safe
  response is to preserve a retryable service failure and reduce request
  frequency, not to loop, fabricate an empty result, or silently switch
  protocols.
- Authenticated personalized feeds, account-specific media entitlement, and the
  full M1 playback/Queue/lyric observation still require maintainer-operated
  evidence.
