# QQ Music authentication evidence

- **Status:** Active research for M1 authentication
- **Last checked:** 2026-08-25
- **Scope:** Credential lifecycle and restore semantics only; no endpoint implementation is authorized by this note.

This note records behavioral evidence, not source code. Reference implementations have different licenses, so implementation in this repository must be independent.

## Sources inspected

1. [L-1124/QQMusicApi at `108617f`](https://github.com/L-1124/QQMusicApi/tree/108617ffe80abefec6358717b9f4d3677550db10) (2026-08-05, GPL-3.0-or-later), especially `qqmusic_api/models/request.py`, `modules/login.py`, `modules/login_utils.py`, and authentication tests.
2. [yakult-green-tea/qq-music-api at `2c27d6b`](https://github.com/yakult-green-tea/qq-music-api/tree/2c27d6b90dd56bcf0796883e27216f69189d8f68) (2026-08-25, MIT), especially `src/services/auth/qrLogin.ts` and its QR/session tests. Its repository records a real QQ Music App QR acceptance run on 2026-08-04.
3. [feeluown/feeluown-qqmusic at `241a967`](https://github.com/feeluown/feeluown-qqmusic/tree/241a9678bcd26e88d19e08e5da8048018f06e330) (2026-03-26; no license file found in the inspected checkout), especially `fuo_qqmusic/login.py`, `provider.py`, and `provider_ui.py`. It is supporting evidence for cookie restore behavior, not a source to copy.

No real account, cookie, QR code, or live QQ Music response was captured in this task.

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

Credential debug output redacts account identity and `musickey`. No persistence, refresh fields, QR channel, HTTP transport, or server-valid state is implemented by this task.

## Evidence still required

Before implementing a concrete login channel:

1. Pin and compare the exact request parameters and state mapping in two independent implementations.
2. Add sanitized real-response fixtures or a repeatable opt-in integration test.
3. Confirm cancellation, timeout, retry, and late-event behavior; a QR session is a lifecycle, not a single request.
4. Select a platform-safe secret persistence mechanism before claiming credential restore as a user-visible feature.
