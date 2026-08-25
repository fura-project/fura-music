# QQ Music authentication evidence

- **Status:** Active research for M1 authentication
- **Last checked:** 2026-08-25
- **Scope:** Credential lifecycle, restore semantics, and the first WeChat QR protocol slices.

This note records behavioral evidence, not source code. Reference implementations have different licenses, so implementation in this repository must be independent.

## Sources inspected

1. [L-1124/QQMusicApi at `108617f`](https://github.com/L-1124/QQMusicApi/tree/108617ffe80abefec6358717b9f4d3677550db10) (2026-08-05, GPL-3.0-or-later), especially `qqmusic_api/models/request.py`, `modules/login.py`, `modules/login_utils.py`, and authentication tests.
2. [yakult-green-tea/qq-music-api at `2c27d6b`](https://github.com/yakult-green-tea/qq-music-api/tree/2c27d6b90dd56bcf0796883e27216f69189d8f68) (2026-08-25, MIT), especially `src/services/auth/qrLogin.ts` and its QR/session tests. Its repository records a real QQ Music App QR acceptance run on 2026-08-04.
3. [feeluown/feeluown-qqmusic at `241a967`](https://github.com/feeluown/feeluown-qqmusic/tree/241a9678bcd26e88d19e08e5da8048018f06e330) (2026-03-26; no license file found in the inspected checkout), especially `fuo_qqmusic/login.py`, `provider.py`, and `provider_ui.py`. It is supporting evidence for cookie restore behavior, not a source to copy.
4. [ylw1997/qqmusic-api at `5f87b07`](https://github.com/ylw1997/qqmusic-api/tree/5f87b07b85923f8862d7b57f9d558ce0314ba1a7) (2026-04-27), especially its executable `wx_login_qr` flow and QR documentation. This independently matches the L-1124 WeChat bootstrap parameters.

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

Both current implementations recognize upstream codes `1000`, `104400`, and `104401` as credential/authentication rejection signals around validation or refresh. These codes are evidence for the future network error mapper; the local lifecycle model does not synthesize them.

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

Credential debug output redacts account identity and `musickey`. Persistence, refresh fields, and server-valid state remain unimplemented.

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

## Evidence still required

Before continuing beyond one-shot QR polling:

1. Confirm cancellation, overall timeout, retry, replacement, and late-event behavior; a QR session is a lifecycle, not a single request.
2. Cross-validate the exact `window.wx_code` credential-exchange request and error mapping before implementing it.
3. Add sanitized real-response fixtures or extend the repeatable opt-in integration test for each implemented transition.
4. Select a platform-safe secret persistence mechanism before claiming credential restore as a user-visible feature.
