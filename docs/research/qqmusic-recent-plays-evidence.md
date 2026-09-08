# QQ Music cloud recent-plays protocol evidence

Date: 2026-09-08. Scope: account cloud-history read and the separately requested Fura-to-QQ write path. Execution remains `HUMAN_GATED_REGRESSION`; no stored credential or real account was automated.

## Read protocol: implemented, live acceptance pending

Two independent inputs now close the minimum ordinary-session read request:

- The maintainer supplied `POST https://u.y.qq.com/cgi-bin/musicu.fcg`, module `music.musichallSong.RecentPlayList`, method `GetRecentPlayList`, and `begin`/`num` pagination with the current UIN/session.
- [`wangwalk/qqm` `src/api/user.ts`](https://github.com/wangwalk/qqm/blob/4a434ccf7468af29731a9792917cb6fc5a126bab/src/api/user.ts) independently calls the same module/method and decodes `req_0.data.vecPlayRecord[]`, `unPlayTime`, and `stSongInfo`. Its adjacent [API client](https://github.com/wangwalk/qqm/blob/4a434ccf7468af29731a9792917cb6fc5a126bab/src/api/client.ts) supplies the current `uin`, `qq`, `authst`, `tmeLoginType`, key-derived `g_tk` values and Cookie in the common authenticated musicu envelope, then signs the exact serialized body with its evidenced `zzc` query-signature algorithm. That source explicitly checks nonzero `req_0.code` instead of treating it as empty history.

Fura keeps the QQ module, method, signed request DTO and response DTO in `qqmusic-client`. The request-sign test uses a fixed independent known answer so a body-field or serialization-order change cannot silently leave a stale signature. `QqMusicProvider` reuses its existing sole credential/session owner and exposes only provider-neutral ordered Track pages. The typed cancellable Bridge reuses the established Track-page result; Flutter never constructs or decodes musicu JSON. Production injects `RustRecentPlaysGateway` into the existing Recent page, which continues to use the shared `PagedTracksController`.

The request size is restricted to `1..=100`. `begin` is the raw consumed-record offset, not the number of successfully mapped rows. Invalid source records therefore increment the existing omitted count while still moving the continuation. The observed response does not guarantee `total` or `has_more`; if absent, a full page yields only a one-record-ahead lower bound and a short page closes the collection. This prevents the UI from inventing the 2,500 total shown by the official Windows product screenshot.

`unPlayTime` is retained inside the raw Client result as an optional opaque integer. It is deliberately not named `played_at`, converted to a date, or sent over the Bridge because no reliable evidence establishes its unit or exact meaning.

Deterministic coverage includes request host/module/method/UIN/cookie/bounds, key-derived CSRF fields, a fixed `zzc` signature known answer, ordinary and `songmid`-only mapping, a legitimate empty response, an unknown-total full page, credential rejection, malformed JSON, missing record arrays, omitted malformed Tracks, Provider error mapping, Bridge cancellation, Dart paging forwarding and persisted-credential cleanup. Numeric song ID/type are never fabricated when absent: `songmid` still permits playback resolution, while operations whose protocol genuinely needs a numeric ID remain unavailable for that row. These tests do not establish that the maintainer's account accepts the route, that QQ and WeChat login have identical capability, that the server retains more than 100 rows, or that order remains stable during concurrent official-client playback.

## Write protocol: blocked

[Tencent's official IoT music-service documentation](https://cloud.tencent.com/document/product/1081/67456) documents `describeRecentPlay({Type, UpdateTime})` and `reportRecentPlay({ResourceId, Type})`, where Type 2 is a song. This proves that Tencent offers a third-party-device history-reporting product in that SDK. It does **not** expose the underlying host/path, module, method, ordinary QQ Music Cookie/session parameters, acknowledgement codes, duplicate behavior, or reporting lifecycle, and it uses a different IoT/H5 authorization environment.

A bounded source survey inspected the current trees of `wangwalk/qqm`, `L-1124/QQMusicApi`, `jsososo/QQMusicApi`, `yakult-green-tea/qq-music-api`, and `Suxiaoqinx/QQMusicapi`, plus exact searches for `RecentPlayList`, `GetRecentPlayList`, `reportRecentPlay`, `RecentPlay`, `PlayRecord`, `PlayHistory`, `ReportPlay`, `AddRecent`, `unPlayTime`, and `music.musichallSong`. The read implementation above was found only in `wangwalk/qqm`; no ordinary-session write request with parameters and authentication evidence was found. General indexed searches produced no stronger candidate, while grep.app returned HTTP 429. Those are bounded negative results, not proof that no private write protocol exists.

Consequently no guessed `AddRecentPlay`/`ReportRecentPlay` method, IoT bridge, arbitrary song ID conversion, five/30-second threshold, retry policy, or playback hook enters production. `ProviderCapability::RecentHistoryWrite` exists only so read and write cannot be conflated; QQ Music does not advertise it. Playback remains independent of history sync.

## Human acceptance gates

Read:

1. In an official QQ Music client, play several distinctive Tracks and wait for its own recent list to update.
2. Open the same account in Fura, enter Recent Plays, and refresh.
3. Compare Track identity, ordering, multiple pages, refresh behavior and the QQ-versus-WeChat login channel. Record only coarse outcomes.
4. Sign out or switch account and confirm the previous snapshot disappears immediately. Exercise an expired credential and verify the UI shows rejection rather than an empty collection.

Write remains blocked until a maintainer-operated capture or trustworthy implementation supplies the ordinary-session host/path, module/method, complete parameters, song identity, UIN/cookie requirements, success result, duplicate behavior and actual official-client reporting point. If that evidence is obtained, the reverse acceptance must first compare a baseline cloud read, play a baseline-absent Track in Fura, observe it in a fresh `GetRecentPlayList`, and then observe it in an official QQ Music client. Only both observations can establish Fura-to-cloud-to-official visibility.

## Current status

| Item | Status |
| --- | --- |
| QQ cloud recent-play read implementation | Complete offline; Human real-account acceptance pending |
| Read pagination | Complete against the evidenced `begin`/`num` contract; real multi-page behavior pending |
| Existing Recent UI connected to production data | Complete |
| Fura cloud write | Blocked on ordinary-session protocol evidence |
| Write visible in official client | Not verified |
| Bidirectional synchronization | Not complete |
