# QQ Music cloud recent-plays protocol evidence

Updated: 2026-09-09. Scope: account cloud-history read and the separately requested Fura-to-QQ write path. Execution remains `HUMAN_GATED_REGRESSION`; no stored credential or real account was automated.

## Corrected read: official Windows protocol, Human read recovery confirmed

**2026-09-09 Human result:** after running the corrected candidate, the maintainer reports “可以了” and provides a page showing 500 loaded records. This is a successful real-account read observation. The report does not separately establish both login channels, update latency, full cross-client ordering/pagination, or Fura-to-cloud writes. No personal Track data from the screenshot is retained here.

Human previously confirmed that both **QQ and WeChat** return method code **500003** with the old request. This is a common request/protocol failure; it is not evidence of a WeChat-only limitation, an empty account, or expired credentials. The old route was based on an external wrapper without a verified successful recent-history observation. Its source is no longer the read-protocol authority.

### Direct public software evidence

The Agent downloaded QQ Music Windows **22.22** from Tencent's public CDN through the URL in [Microsoft's WinGet installer manifest](https://github.com/microsoft/winget-pkgs/blob/master/manifests/t/Tencent/QQMusic/22.22/Tencent.QQMusic.installer.yaml). The 98,311,720-byte installer SHA-256 exactly matched the manifest: `fb0ef24d347aff281722e68139727dae548804907040ac0b17b17c562f2599f1`. This verifies the selected distribution artifact, not that it is the Human's installed version or the newest QQ release. It was unpacked without installing or executing Windows code. No account, local client data, credential, or browser cookie was accessed.

`QQMusic_Protocol.dll` SHA-256: `60bf73ac621d89b5cade5bfdbfac6779a8d568de7ed79a71d2bd29911135e584`. Static request construction and decoder control flow establish these protocol facts (image base `0x10000000`):

| Evidence location | Fact |
| --- | --- |
| File offsets `0x12005c`, `0x120094`, `0x1200b8` and their initialized request descriptors | `music.musicasset.PlayRecentlyRead.GetPlayRecentlyInfo`, module `music.musicasset.PlayRecentlyRead`, method `GetPlayRecentlyInfo` |
| Request builder VA `0x1002a9f6`–`0x1002aaae` | JSON `param.type` and `param.updateTime` are integers. There is no `uin`, `begin`, or `num` in this endpoint's parameters. Session identity remains in the common authenticated envelope. |
| Decoder VA `0x1002af1b`, song branch at `0x1002afba` | Check result code and `result.data.code`; `result.data.type == 2` selects songs. |
| Decoder VA `0x1002afc3` onward | Songs are `result.data.data.songList[]`; each row contains `track`, `lastTime`, and `listenCnt`. The outer data also has `updateTime`. |
| Track decoder VA `0x1003eea2` onward | `track` uses the existing modern QQ `type`, `id`, `mid`, `name`/`title`, `subtitle`, `interval` model. |
| Decoder VA `0x1002af75`–`0x1002af9f` | Data codes 0, -300 and -301 proceed to typed payload validation. Fura admits these exact statuses only with a valid song snapshot; it does not invent meanings for them or turn absent records into empty success. |

These are interface/behavior observations. No proprietary implementation, binary, disassembly, media URL, or account response is copied into the repository. Rust request and response handling are independently implemented. Public artifacts and local analysis are in `/tmp/fura-qq-recent-protocol-audit` for this diagnostic session.

A bounded scan of the official web profile/player/common/download scripts found no corresponding recent-history wire call. That negative result and the Linux client's missing feature are not used to infer Windows behavior.

### One anonymous compatibility control

One serial, read-only request to the new method used `{ "type": 2, "updateTime": 0 }`, the established signed musicu envelope, and **no Cookie or account credential**. It returned HTTP 200, global code 0, method code 1000 (authentication required in this credential-free context). No payload was retained and no retry, alternate endpoint, device/profile rotation, or account request followed. This confirms that the corrected route reaches an authentication gate; it does **not** prove a real account's successful read or assign an official meaning to the old 500003 code.

### Implemented correction and bounds

- Replace the old `RecentPlayList.GetRecentPlayList` call with the directly evidenced `PlayRecentlyRead.GetPlayRecentlyInfo` call. Request songs (`type=2`) from the initial snapshot (`updateTime=0`); no speculative delta merge or remote pagination.
- Decode all result layers and `data.data.songList[].track/lastTime`. Unknown failures remain errors; malformed/missing lists cannot become valid empty history. Preserve the supplied row order, exact QQ identities and omitted-row accounting. `lastTime` stays an opaque source integer; no timestamp unit or cross-client ordering guarantee is fabricated.
- Enforce local ceilings of 8 MiB per response, 5,000 raw records, 30 seconds, and 1–100 rows per UI page. These are Fura resource budgets, not claims about QQ retention. Exceeding a ceiling produces an explicit error rather than silent truncation.
- Retain one immutable snapshot inside the exact authenticated credential state. First-page entry/refresh fetches once; subsequent pages reuse that snapshot. Sign-out, rejection, restore and credential replacement drop it with the state. A unique request token prevents a late success or rejection from replacing a newer refresh, including re-login with identical credential bytes. Cancellation leaves a subsequent load free to proceed. No history is persisted to disk.
- Keep provider-neutral Track pages and the existing Flutter `PagedTracksController`. No Domain, Provider API, public Bridge, generated Dart or Flutter presentation changes. No cross-service source substitution.
- Opt-in diagnostics now include `route=PlayRecentlyRead`, login channel, fixed type/updateTime and a redacted outcome, allowing the Human to distinguish this candidate from the previous diagnostic build. No credentials, signature, raw response, titles or IDs are logged.

The official binary also contains `PlayRecentlyWrite.ReportPlayRecentlyInfo` and `DeletePlayRecentlyInfo` names. They are only a new static research lead: this read regression does not implement, test live, or authorize any write/delete call. Reporting lifecycle, confirmation and same-account round-trip evidence remain unestablished. Do not claim bidirectional sync.

### Acceptance and validation boundary

The corrected candidate was built at `/tmp/fura-qq-recent-fixed-lwqdf_gi/run.sh`; the maintainer has now confirmed successful loading as recorded above. Nine Client and seven Provider regressions pass; final workspace/all-target tests report **491 passed / 0 failed / 14 ignored**. Format, strict Clippy and native build pass. The launcher syntax and copied native hash were checked; the Agent did not launch it or access an account. Further read acceptance can compare the same account's official recent list and exercise multiple pages/refresh; the initial loading check has succeeded. The new diagnostic prefix is enough to report a failure. No interception setup or credential export is requested.

Current status: **request/decoder defect corrected from direct official evidence; real-account cloud-read success remains HUMAN_EVIDENCE_REQUIRED**. A known failed old candidate is not a successful sync baseline. Final validation counts and the isolated launcher are recorded in `PROGRESS.md`.

## Superseded 2026-09-08 read candidate (historical evidence)

Two inputs guided the current ordinary-session request model; neither establishes real-account compatibility:

- The maintainer supplied `POST https://u.y.qq.com/cgi-bin/musicu.fcg`, module `music.musichallSong.RecentPlayList`, method `GetRecentPlayList`, and `begin`/`num` pagination with the current UIN/session.
- [`wangwalk/qqm` `src/api/user.ts`](https://github.com/wangwalk/qqm/blob/4a434ccf7468af29731a9792917cb6fc5a126bab/src/api/user.ts) independently calls the same module/method and decodes `req_0.data.vecPlayRecord[]`, `unPlayTime`, and `stSongInfo`. Its adjacent [API client](https://github.com/wangwalk/qqm/blob/4a434ccf7468af29731a9792917cb6fc5a126bab/src/api/client.ts) supplies the current `uin`, `qq`, `authst`, `tmeLoginType`, key-derived `g_tk` values and Cookie in the common authenticated musicu envelope, then signs the exact serialized body with its evidenced `zzc` query-signature algorithm. That source explicitly checks nonzero `req_0.code` instead of treating it as empty history.

Fura keeps the QQ module, method, signed request DTO and response DTO in `qqmusic-client`. The request-sign test uses a fixed independent known answer so a body-field or serialization-order change cannot silently leave a stale signature. `QqMusicProvider` reuses its existing sole credential/session owner and exposes only provider-neutral ordered Track pages. The typed cancellable Bridge reuses the established Track-page result; Flutter never constructs or decodes musicu JSON. Production injects `RustRecentPlaysGateway` into the existing Recent page, which continues to use the shared `PagedTracksController`.

The request size is restricted to `1..=100`. `begin` is the raw consumed-record offset, not the number of successfully mapped rows. Invalid source records therefore increment the existing omitted count while still moving the continuation. The observed response does not guarantee `total` or `has_more`; if absent, a full page yields only a one-record-ahead lower bound and a short page closes the collection. This prevents the UI from inventing the 2,500 total shown by the official Windows product screenshot.

`unPlayTime` is retained inside the raw Client result as an optional opaque integer. It is deliberately not named `played_at`, converted to a date, or sent over the Bridge because no reliable evidence establishes its unit or exact meaning.

Deterministic coverage includes request host/module/method/UIN/cookie/bounds, key-derived CSRF fields, a fixed `zzc` signature known answer, ordinary and `songmid`-only mapping, a legitimate empty response, an unknown-total full page, credential rejection, malformed JSON, missing record arrays, omitted malformed Tracks, Provider error mapping, Bridge cancellation, Dart paging forwarding and persisted-credential cleanup. Numeric song ID/type are never fabricated when absent: `songmid` still permits playback resolution, while operations whose protocol genuinely needs a numeric ID remain unavailable for that row. These tests do not establish that the maintainer's account accepts the route, that QQ and WeChat login have identical capability, that the server retains more than 100 rows, or that order remains stable during concurrent official-client playback.

## Earlier write survey (historical evidence)

[Tencent's official IoT music-service documentation](https://cloud.tencent.com/document/product/1081/67456) documents `describeRecentPlay({Type, UpdateTime})` and `reportRecentPlay({ResourceId, Type})`, where Type 2 is a song. This proves that Tencent offers a third-party-device history-reporting product in that SDK. It does **not** expose the underlying host/path, module, method, ordinary QQ Music Cookie/session parameters, acknowledgement codes, duplicate behavior, or reporting lifecycle, and it uses a different IoT/H5 authorization environment.

A bounded source survey inspected the current trees of `wangwalk/qqm`, `L-1124/QQMusicApi`, `jsososo/QQMusicApi`, `yakult-green-tea/qq-music-api`, and `Suxiaoqinx/QQMusicapi`, plus exact searches for `RecentPlayList`, `GetRecentPlayList`, `reportRecentPlay`, `RecentPlay`, `PlayRecord`, `PlayHistory`, `ReportPlay`, `AddRecent`, `unPlayTime`, and `music.musichallSong`. The read implementation above was found only in `wangwalk/qqm`; no ordinary-session write request with parameters and authentication evidence was found. General indexed searches produced no stronger candidate, while grep.app returned HTTP 429. Those are bounded negative results, not proof that no private write protocol exists.

Consequently no guessed `AddRecentPlay`/`ReportRecentPlay` method, IoT bridge, arbitrary song ID conversion, five/30-second threshold, retry policy, or playback hook enters production. `ProviderCapability::RecentHistoryWrite` exists only so read and write cannot be conflated; QQ Music does not advertise it. Playback remains independent of history sync.

## Human acceptance gates after the corrected read candidate

Read:

1. In an official QQ Music client, play several distinctive Tracks and wait for its own recent list to update.
2. Open the same account in Fura, enter Recent Plays, and refresh.
3. Compare Track identity, ordering, multiple pages, refresh behavior and the QQ-versus-WeChat login channel. Record only coarse outcomes.
4. Sign out or switch account and confirm the previous snapshot disappears immediately. Exercise an expired credential and verify the UI shows rejection rather than an empty collection.

Write remains unimplemented. Static Windows evidence now identifies read/write method names, but further Agent research must establish complete write parameters, identity, acknowledgement, duplicate behavior and actual reporting lifecycle before implementation. Any later real-account write acceptance remains Human-operated. If that capability is authorized and implemented, reverse acceptance must compare a baseline cloud read, play a baseline-absent Track in Fura, observe it in a fresh `GetPlayRecentlyInfo` snapshot, and then observe it in an official QQ Music client. Only both observations can establish Fura-to-cloud-to-official visibility.

## Status of the superseded candidate

| Item | Status |
| --- | --- |
| Superseded QQ cloud recent-play request | Offline foundation; Human read failed with 500003 in both login channels |
| Read pagination | Bounded official snapshot and 1–100-row local pages; Human loaded 500 records, ongoing ordering/refresh remains separate evidence |
| Existing Recent UI connected to production data | Complete |
| Fura cloud write | Blocked on ordinary-session protocol evidence |
| Write visible in official client | Not verified |
| Bidirectional synchronization | Not complete |


## 2026-09-09 initial diagnostic observation: WeChat Recent Plays fails

The maintainer explicitly selected `HUMAN_GATED_REGRESSION / CORE`, supplied the signed-in Recent Plays error screenshot, and confirmed **WeChat QR login**. This is a reported failed read, not a successful cloud-sync acceptance. No NetEase or visual iteration belongs to this regression.

The screenshot's generic error stage covers network, HTTP/upstream, invalid-response and Core failures. It cannot reveal the root cause or distinguish a restriction from a parser mismatch. The pinned qqm reference above explicitly warns at `getRecentTracks` that the endpoint may require QQ rather than WeChat. That warning is a compatibility suspicion, **not authoritative evidence that every WeChat account is unsupported**. No forced QQ login, credential substitution, endpoint/profile rotation or guessed error-code semantics is justified by it.

Static comparison and synthetic regressions confirm that Fura preserves WeChat `tmeLoginType=1`, its own account identity and `wxuin` cookie, and sends one bounded signed request. Upstream nonzero codes remain errors rather than empty records or silent credential rejection. There is no evidence-backed parameter/endpoint repair yet; the present request and UI are preserved.

The Client now provides opt-in diagnostic output via `FURA_QQMUSIC_RECENT_PLAYS_DIAGNOSTICS=1`. Each explicit page request emits `[qqmusic.recent_plays]`, its channel, begin/num, and either success or the existing redacted typed error. HTTP status and global/result codes are retained; no account identity, key, signature, Cookie, URL, raw body, Track/lyric content or transport error text is logged. The toggle is off by default and initiates no request itself. It does not export protocol details through the Bridge.

For the Human check, start the built application with that environment variable, enter Recent Plays and retry once. Share only the prefix-matching lines. If the result is rate/security restricted, stop retries; do not switch profiles or endpoints. Agent validation uses only FakeTransport; no stored account or real authenticated request was automated. The Human has now supplied the live error below; a successful official-request comparison is still needed before claiming a protocol repair.


### Human-observed result and current conclusion

The Human ran the isolated diagnostic bundle and initiated the read. The only retained observation is:

```text
[qqmusic.recent_plays] channel=wechat begin=0 num=100 outcome=Upstream { global_code: 0, result_code: Some(500003) }
```

The transport returned a parseable musicu result: outer success, inner method failure. `map_response` stops at the nonzero method code before record mapping; this occurrence is not a list-layout/pagination/parser failure. It is not a verified credential-expiry or empty-history result. Fura continues to classify it as an unknown upstream/service failure and preserves the active credential.

A bounded current source/search check found no authoritative definition of 500003 for this method and no evidenced replacement recent-history route. The current [yakult-green-tea implementation README](https://github.com/yakult-green-tea/qq-music-api#qq-音乐原生扫码登录) also records 500003 for a different musicasset method, so the number alone cannot prove a WeChat-only restriction, nonexistent method, or a required new parameter. A bounded scan of already-downloaded official Linux JS found no RecentPlayList/GetRecent symbol; Linux's missing UI feature supplies no Windows wire evidence.

**Initial read acceptance: FAILED for this reported WeChat context.** At this checkpoint the exact protocol cause was unresolved. Human subsequently confirmed QQ also returns 500003; the static official Windows investigation below supersedes the channel hypothesis. Protocol research is Agent work; this regression does not require Human to install interception certificates, export cookies, or reverse engineer the official client. Fura-to-cloud reporting remains separately unimplemented.


Regression validation: nine Client recent-play tests and two Provider history tests pass, including the exact 500003 error shape, WeChat construction, redaction and session preservation. Full `cargo test --workspace --all-targets`: **486 passed / 0 failed / 14 ignored**; `cargo clippy --workspace --all-targets -- -D warnings`, `cargo fmt --all -- --check` and native Bridge library build pass. No public Bridge or Flutter change was made. The Human successfully exercised the isolated native diagnostic bundle. This verifies diagnosis and failure handling, not cloud-read success. Changes remain local and uncommitted; no push.
