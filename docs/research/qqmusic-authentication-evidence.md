# QQ Music authentication evidence

- **Status:** Active research for M1 authentication
- **Last checked:** 2026-08-31
- **Scope:** Credential lifecycle, restore semantics, bounded signed-in account identity, and QQ/WeChat QR authorization.

> **Current product status (2026-09-02):** The phone/one-time-code investigation below is retained only as historical protocol research. The production Client, Provider, Bridge, Dart controller, and UI no longer expose that unverified path; QQ and WeChat QR are the supported authorization choices.

This note records behavioral evidence, not source code. Reference implementations have different licenses, so implementation in this repository must be independent.

## Sources inspected

1. [L-1124/QQMusicApi at `108617f`](https://github.com/L-1124/QQMusicApi/tree/108617ffe80abefec6358717b9f4d3677550db10) (2026-08-05, GPL-3.0-or-later), especially `qqmusic_api/models/request.py`, `modules/login.py`, `modules/login_utils.py`, and authentication tests.
2. [yakult-green-tea/qq-music-api at `2c27d6b`](https://github.com/yakult-green-tea/qq-music-api/tree/2c27d6b90dd56bcf0796883e27216f69189d8f68) (2026-08-25, MIT), especially `src/services/auth/qrLogin.ts` and its QR/session tests. Its repository records a real QQ Music App QR acceptance run on 2026-08-04.
3. [feeluown/feeluown-qqmusic at `241a967`](https://github.com/feeluown/feeluown-qqmusic/tree/241a9678bcd26e88d19e08e5da8048018f06e330) (2026-03-26; no license file found in the inspected checkout), especially `fuo_qqmusic/login.py`, `provider.py`, and `provider_ui.py`. It is supporting evidence for cookie restore behavior, not a source to copy.
4. [ylw1997/qqmusic-api at `5f87b07`](https://github.com/ylw1997/qqmusic-api/tree/5f87b07b85923f8862d7b57f9d558ce0314ba1a7) (2026-04-27), especially its executable `wx_login_qr` flow and QR documentation. This independently matches the L-1124 WeChat bootstrap parameters.
5. [Suxiaoqinx/QQMusicapi at `b6d748b`](https://github.com/Suxiaoqinx/QQMusicapi/tree/b6d748bb63fc65b6a98a383d8974fe3f3fd75d5b) (rechecked 2026-09-02), especially `src/modules/login.js`, as an independent QQ Connect request-shape cross-check.

No real account, cookie, or authorization code was used. Live QR response bytes were processed transiently by the opt-in test but were not printed or persisted.

## Cross-validated behavior

### A stored credential is untrusted input

L-1124 exposes a local timestamp check but separately validates credentials with `music.UserInfo.userInfoServer/GetLoginUserInfo`. The yakult implementation validates restored session shape and performs the same authenticated user request. FeelUOwn restores cookies and then fetches the user; it treats a failed fetch as a failed auto-login.

Therefore “credential bytes exist” must not become “authenticated.” Restore begins in a pending-verification state. A transient transport failure must also remain distinguishable from an explicit credential rejection.

### Minimum credential core

The two current protocol implementations agree that authenticated musicu calls require:

- a non-empty account identity (`musicid`, sometimes normalized from `str_musicid`);
- a non-empty `musickey`;
- a non-zero numeric login type carried as `loginType` / `tmeLoginType`.

Observed login types include WeChat `1`, QQ `2`, and QQ Music App `6`. The protocol model preserves other non-zero values instead of treating this observed set as permanently exhaustive.

### Local expiry is not server validity

Both current implementations consume `musickeyCreateTime + keyExpiresIn` when present. This can identify a locally expired key, but an unexpired timestamp cannot prove that QQ Music still accepts the credential. Missing lifetime metadata must remain “unknown,” not “valid.”

Both current implementations recognize upstream codes `1000`, `104400`, and `104401` as credential/authentication rejection signals around validation or refresh. The network error mapper uses only these observed rejection codes; the local lifecycle model does not synthesize them.

### Server verification of a restored credential

L-1124, yakult, and ylw1997 independently use the named `music.UserInfo.userInfoServer` request with module `music.UserInfo.userInfoServer`, method `GetLoginUserInfo`, and an empty parameter object. FeelUOwn provides a separate behavioral cross-check: it restores cookie material and considers auto-login successful only after fetching the authenticated user. The current lightweight request form carries the account ID, music key, and login type in `ct=11` musicu comm fields and in the QQ Music Cookie.

The implementation requires both the global response code and the named result code to be zero. Codes `1000`, `104400`, and `104401` are the only currently cross-validated credential-rejection values. A non-rejection value such as `50006`, HTTP failure, transport error, or missing/malformed result is not logout evidence and retains the startup candidate for retry.

Verification has an exact process-local attempt ID. The Provider compares both that ID and the retained candidate before and after the await; cancellation, retry, or beginning a new QR login makes a late result `Replaced`. Only explicit rejection clears Rust credential state and triggers platform-vault deletion at the Dart edge. This lifecycle is fixture-tested but has not accepted a real account credential in this checkout.

### Bounded signed-in account identity

Two current independent implementations agree on the only public identity
fields selected for the first-release account summary:

- [yakult `qrLogin.ts` at `2c27d6b`](https://github.com/yakult-green-tea/qq-music-api/blob/2c27d6b90dd56bcf0796883e27216f69189d8f68/src/services/auth/qrLogin.ts) records a measured real-session `GetLoginUserInfo` shape with account fields nested under `data.info`; its sanitized regression uses `info.nick` and `info.logo` and records that the response does not carry a reliable account ID;
- [ylw1997's current `get-user-info` contract at `5f87b07`](https://github.com/ylw1997/qqmusic-api/blob/5f87b07b85923f8862d7b57f9d558ce0314ba1a7/docs/apis/get-user-info.md) independently documents the same named operation and the same nested `nick` / `logo` fields.

L-1124's current implementation deliberately consumes only the response code
for credential validity and does not model profile data. The project therefore
keeps credential verification successful when `info` is absent or unusable,
while the separate account-summary capability requires a bounded nonblank
display name and treats the avatar as optional. It exposes neither the account
ID nor any credential field, rechecks the exact credential after the await,
and cancels or rejects results that cross sign-out/account replacement.

No stored credential or real account was accessed during this discovery. The
offline fixture is synthetic and retains no personal response content, so it
does not by itself prove current behavior for the maintainer's account.

## Important differences

- L-1124 exposes QQ web QR, WeChat web QR, and QQ Music App QR channels. The App channel uses MQTT over WSS.
- The yakult project deliberately exposes two canonical channels: QQ Music App QR and WeChat web QR. It normalizes public waiting/scanned/success states separately from upstream events.
- FeelUOwn uses an embedded web/cookie workflow and persists cookies as plain JSON. That demonstrates restore behavior but does not meet this project's release security boundary.
- The implementations use fallback session durations when upstream expiry fields are missing. Those durations are implementation policy, not verified protocol truth, and are not adopted here.

## Current project decision

The first credential model contains only the cross-validated core fields plus optional expiry metadata. It provides these restore plans:

- `SignedOut` when storage yields no credential;
- `VerifyWithServer` when a structurally valid credential is present and is not locally expired;
- `LocallyExpired` when advertised lifetime has ended, retaining the credential for a future refresh/reauthentication decision.

Credential debug output redacts account identity and `musickey`. Persistence and server verification are implemented; credential refresh remains outside the current slice.

### QQ Web QR authorization

L-1124's current QQ Web flow uses `ptqrshow` with QQ Connect application
`100497308`, retains only the short-lived `qrsig`, and polls `ptqrlogin`. The
poll token uses QQ's additive Hash33 with seed `0`; the later OAuth `g_tk`
uses the same additive algorithm with seed `5381`. These are distinct inputs,
not interchangeable variants of a generic hash. An initial implementation
using the wrong seed/operator produced a repeatable HTTP 403 on polling; a
known-answer regression now locks both values.

After a confirmed QR, both current L-1124 and Suxiaoqinx flows call `check_sig`
without carrying the transient `qrsig` cookie, then carry only response cookies
into QQ Connect authorization. Suxiaoqinx also supplies the QQ QR-page Referer
on the authorization POST. A maintainer report in which the approving device
succeeded while the client failed exposed that this repository did the opposite
at both boundaries. The corrected request regression now rejects a Cookie on
`check_sig`, requires that Referer on authorization, and retains the existing
no-redirect behavior. The returned code is exchanged through
`QQConnectLogin.LoginServer.QQLogin` with QQ login type `2`. Authorization
cookies, redirect codes, account identity, and credentials stay inside redacted
Rust session types and never cross the typed Bridge.

On 2026-08-31 the ignored, environment-gated `live_qq_qr` test fetched a new
QQ Web QR and received the unconfirmed waiting state from one poll. It did not
display or scan the QR, approve authorization, access an account, or retain
the image or session values. This proves current anonymous bootstrap and poll
compatibility only.

On 2026-09-02 a maintainer-operated, secret-safe interactive run completed the
confirmed path. Opt-in diagnostics retained only phase status, value-presence
booleans, JSON value kinds, and redacted error categories. They showed a
successful `check_sig` redirect with `p_skey`, a successful authorization
redirect with a code, and an HTTP-successful, syntactically valid musicu login
envelope with the expected named login result. The client still returned
`InvalidJson` because its deserializer flattened every non-`code` top-level
value into `LoginResponse`; real musicu transport metadata such as `ts`,
`start_ts`, and `traceid` are scalars and therefore made that flatten operation
fail before the named result could be read. The decoder now selects only the
global code and exact named login result. A synthetic regression includes
unrelated scalar metadata, and the maintainer confirmed that QR approval then
signed the client in. No QR session value, cookie, authorization code, account
identity, credential, response body, or account content was printed or saved.

### Historical: phone plus one-time-code authorization

This is not a documented Tencent public login API. The only current direct
implementation found for this exact phone flow is the independently inspected
L-1124 reverse-engineered QQ Music client implementation. Its Android-profile flow uses
`music.login.LoginServer.SendPhoneAuthCode` followed by
`music.login.LoginServer.Login`, with `tmeLoginMethod: 3`, an area code and
plain phone number for the send operation, and `loginMode: 1` plus the
one-time code for authorization. The current source also distinguishes
CAPTCHA code `20276` and frequency-limit code `100001` from successful code
delivery.

Before HD-019, the project modeled this as one process-local, cancellable
session with a random per-session device identity. Phone number and SMS code
did not implement `Debug`, cross the Bridge after authorization, or enter
persistence. That production path and its Flutter inputs were removed on
2026-09-02 rather than being presented as a supported account method.

The former request shape, error mapping, replacement/cancellation, credential
installation, secure-vault persistence, and adaptive-dialog tests were offline
only. No SMS was sent and no phone/account was accessed in this checkout. Those
tests and production implementation were removed with HD-019; this historical
description is not a current capability or future authorization.

### First network slice: WeChat QR bootstrap

The first concrete request is the unconfirmed WeChat web QR bootstrap. L-1124 and ylw1997 independently agree on:

- `GET https://open.weixin.qq.com/connect/qrconnect`;
- app ID `wx48db31d50e334801`, the QQ Music redirect URI, `snsapi_login`, `STATE`, and the QQ Music style URL;
- parsing the short-lived UUID from the returned page;
- fetching the image from `https://open.weixin.qq.com/connect/qrcode/{uuid}`.

This path was selected over QQ Music App QR because it does not require QIMEI/device bootstrap or MQTT, and over QQ Web QR because its remaining credential exchange is shorter and the inspected QQ implementations disagree on part of the polling redirect parameters. The implementation validates HTTP status, bounds response sizes, URL-encodes the UUID path segment, checks PNG/JPEG magic, and redacts the transient identifier/image in diagnostics.

The default suite uses synthetic sanitized responses. On 2026-08-25 an ignored, environment-gated integration test successfully fetched a new unconfirmed QR. It did not scan the code, access an account, print the UUID, or retain the response. This proves current bootstrap compatibility only.

### Second network slice: one-shot WeChat QR polling

L-1124, ylw1997, and the current yakult implementation agree on `GET https://lp.open.weixin.qq.com/connect/l/qrconnect` with the transient UUID, a millisecond cache-buster, and `https://open.weixin.qq.com/` as Referer. L-1124 and yakult explicitly map the complete observed state set, while ylw1997 independently agrees on the active authorization loop:

- `408` — waiting for scan;
- `404` — scanned and waiting for user confirmation;
- `405` — authorized, carrying `window.wx_code` for the next credential-exchange slice;
- `402` — QR expired;
- `403` — user refused.

The client performs one poll with a 35-second request budget, a 64 KiB streaming body limit, strict status parsing, an explicit error for unknown values, and a redacted authorization-code type. Repeated polling and stale-result suppression deliberately remain outside the raw protocol client.

On 2026-08-25 the opt-in live test created a fresh unconfirmed QR and received `408` from one poll. It did not expose the QR, scan it, obtain an authorization code, exchange credentials, or access an account.

### QR session cancellation boundary

The raw client intentionally exposes create and one-shot poll operations. `WechatQrLoginCoordinator` adds only protocol-session lifecycle, not Flutter state:

- starting a new generation supersedes any create or poll still in flight;
- explicit cancellation, dropping the active session, or dropping the coordinator invalidates the generation;
- cancellation races the network future, so the losing HTTP work is dropped rather than merely ignored later;
- every successful await is followed by a generation check before the result can surface;
- authorized, expired, and refused results finish the generation, while waiting/scanned results remain eligible for another explicit poll;
- a QR creation error clears its own generation without clearing a newer replacement.

Deterministic tests hold a synthetic request in flight and prove replacement, cancellation, and disposal suppress the late result. The separate overall deadline below is not implied by the per-request 35-second poll budget.

### QR session deadline and transport-failure policy

L-1124 defaults the WeChat QR session to 180 seconds and continues past transient request failures only while that deadline remains. Yakult independently uses a three-minute QR lifetime and permits three consecutive poll transport failures before terminating on the fourth. This agreement supports a bounded session policy without treating it as an upstream response field.

The coordinator therefore gives QR creation, polling, and credential exchange one shared 180-second monotonic deadline. The deadline races each in-flight request and drops the losing future. After a session exists, the first three consecutive transport failures remain explicit errors eligible for an explicit caller retry; the fourth finishes the generation. Any successful network response resets the transport-failure count, including a waiting response or a structured upstream rejection. Protocol, HTTP, parsing, and upstream errors are never relabeled as transport instability. QR creation does not auto-retry before a session is returned; its caller may explicitly begin a new generation.

There is deliberately no internal polling loop or hidden backoff yet: `advance` performs one observable step. Deterministic virtual-time tests prove the shared deadline aborts blocked QR creation, polling, and credential exchange, and sequence tests prove the failure limit and reset behavior.

### Third network slice: WeChat code exchange

L-1124, ylw1997, and yakult agree on the semantic RPC:

- `POST https://u.y.qq.com/cgi-bin/musicu.fcg`;
- module `music.login.LoginServer`, method `Login`;
- parameter `{code, strAppid: "wx48db31d50e334801"}`;
- common `tmeLoginType: 1`.

The implementations differ in envelope naming and device context. L-1124/yakult normally use `req_0` with an Android comm, while ylw1997 uses the named `music.login.LoginServer.Login` key and a lightweight `ct=11` comm. On 2026-08-25 a single no-account request with an explicitly invalid OAuth code confirmed the lightweight named form is still accepted: HTTP succeeded, the global code was `0`, and the login subrequest returned opaque code `1000`. The probe retained only status codes and response field names; it did not authenticate or access an account.

The project therefore implements the smaller envelope that has direct current evidence and does not introduce QIMEI merely for this channel. Both global and subrequest codes must be zero. Nonzero values remain structured opaque errors; upstream messages and bodies are not retained in errors.

Successful mapping is offline and cross-validated, not live-account verified. It prefers a nonzero `str_musicid` because current measured fixtures can carry placeholder numeric `musicid=0`, validates `musickey`, preserves WeChat login type when omitted, validates expiry pairs, and retains `openid`, access/refresh tokens, refresh key, union ID, and encrypted UIN in a diagnostics-redacted container.

The coordinator exchanges a 405 code inside the same attempt generation. Replacement/cancellation drops the exchange future before a credential can surface. An exchange failure retains the pending code for an explicit retry and does not silently re-poll or auto-retry.

The Provider layer now maps raw protocol image/state/error types into provider-neutral QR contracts and retains the resulting credential internally. The Flutter bridge returns an opaque Rust-owned session with explicit advance/cancel operations, image bytes/media type, coarse progress/failure enums, and an authenticated boolean. Generated Dart contains no protocol UUID, OAuth code, credential, account identity, key, or refresh material. This establishes the boundary only; it does not prove a live successful login or credential persistence.

## Evidence still required

Before claiming M1 authentication acceptance:

1. Confirm a clean-process restore after the successful maintainer-operated QQ Web QR credential exchange without retaining secret-bearing evidence.
2. Run the existing disposable secure-vault pattern on each distribution target; Linux passed on 2026-08-25, but plugin linkage alone does not prove the remaining platform implementations.
