# NetEase authenticated foundation evidence

Date: 2026-09-12. Authority: HD-023 + HD-024 plus the 2026-09-12 Linux Human regression. **HUMAN_EVIDENCE_REQUIRED for every real-account claim.** Two rebuilt-Linux attempts reached 801 waiting and 802 scanned/awaiting confirmation, then terminated with the explicitly decoded 8821 security-verification outcome. No credential, account data, phone number, SMS code or cookie was supplied to or collected by the Agent.

## 2026-09-14 external QR-confirmation handoff candidate

The direct QR and mobile-EAPI phone-code implementations remain the first-line
paths and were not replaced. Response code 8821 remains
`SecurityVerificationRequired`; code 8830 is now separately propagated as
`SecondaryVerificationRequired` through Client, Provider, Bridge, controller
and localized UI. Opt-in SMS diagnostics add only transport status, numeric
business code and booleans describing whether known verification metadata is
present. They do not print response bodies, tokens, phone numbers, codes or
cookies.

Human Linux diagnostics supersede and reject the embedded-browser experiment.
The WebKit web process repeatedly failed EGL/DMABuf image creation and emitted
GStreamer invalid-range failures before Flutter lost its device connection.
The Android private WebView Activity, Linux `desktop_webview_window` dependency
and CI WebKitGTK packages are therefore removed rather than retained as a
second browser/authentication owner.

Opening `https://music.163.com/login` in an ordinary system browser cannot by
itself authenticate Fura: browser cookies are isolated from the application,
and Fura has no NetEase-issued OAuth authorization endpoint and redirect URI
that could return a code. The product does not imply that a completed generic
browser login can be imported, and it never reads Chrome/Firefox cookie stores.

The viable external-user-agent candidate reuses the active QR challenge. Rust
now exposes the exact short-lived official
`https://music.163.com/st/platform/scanlogin` URL already encoded into that
session's PNG. The URL carries the same bounded `codekey` and `chainId` plus the
fixed web fields. Flutter accepts only the exact HTTPS host/path, exactly those
five query fields and safe token syntax, then uses pinned `url_launcher 6.3.2`
in external-application mode. The existing Rust QR session and poll loop remain
active; a resulting 803 still has to pass the unchanged Account Summary
correlation before activation and namespaced secure-vault storage. The URL/key
is never logged. Cancellation, expiry or provider replacement clears the
handoff, and late launcher completion cannot revive a superseded session.

Deterministic tests cover URL/session correlation, secret-free Bridge debug,
strict Flutter URI rejection, continued polling during handoff and late-result
suppression. Pinned FRB 2.13.0 generation, full Rust workspace/all-target tests,
strict workspace Clippy, direct Dart analysis, all 574 Flutter tests, Linux
Release and Android ARM64 Debug builds pass. No Agent-operated real login
occurred: OS routing to the browser or NetEase app, approval-page usability,
803, account correlation and persistence across restart remain `HUMAN_REVIEW`.

## Protocol and ownership

The pinned references and licenses are in [protocol evidence](netease-protocol-evidence.md). The original Fura candidate used the current EAPI `type=3` key/poll route. Human evidence proved that route could reach both 801 waiting and 802 scanned, but did not yield an accepted authenticated session after confirmation. It remains historical evidence rather than a deleted compatibility attempt.

The current Human-gated candidate follows the service's web QR session instead: WEAPI `login/qrcode/unikey` and `login/qrcode/client/login`, both with `type=1` and `noCheckToken=true`. A securely random, non-credential browser cookie context and one `chainId` are retained across key and poll requests. The locally encoded QR contains `https://music.163.com/st/platform/scanlogin` with the opaque `codekey`, the same `chainId`, `hdw_device=web`, `hdw_appid=web` and `hitExp=1`. Polling adds the observed web login headers and an empty `ydDeviceToken`. Codes 800/801/802/803 still represent expired/waiting/scanned/confirmed. The 803 credential may arrive in response `Set-Cookie` fields or the bounded response `cookie` string; both sources are merged and structurally checked before account verification. The raw key, browser context and credential never leave the opaque Rust session or enter diagnostics. No password is collected.

Code 8821 is now a distinct `SecurityVerificationRequired` result through Client, Provider, typed Bridge and Flutter presentation. The current upstream proposal identifies its follow-up as an 易盾 behavioral CAPTCHA whose successful browser-side result is supplied as `secureCaptcha`; that is evidence for slide/behavior verification, not for a simple static image CAPTCHA. Fura does not embed, solve, reinterpret or bypass that challenge. The QR action remains a fresh attempt later; the independent phone-code option below is an alternative login protocol, not an automatic retry or a way around 8821. The referenced web-login repair is an open, unmerged proposal with a maintainer warning about web-flow risk, so this implementation remains a candidate until the Human completes the full 803 → account verification → secure-storage test.

One process-level Provider owns one credential state. Starting QR or importing a replacement supersedes pending work; starting QR clears previous active state. A watch generation drops stale requests and prevents late success/rejection from modifying replacement state. Installing a verified credential advances the generation again. A separate generation-bound cancellation handle can interrupt a poll while the session is mutably borrowed; old handles cannot cancel new attempts. Drop, cancel, expiry, unknown QR outcome, the three-minute deadline and three consecutive transport failures terminate the attempt. There is no autonomous account confirmation.

QR code 803 no longer loses a service-issued credential when the immediately following account verification has a transient network/service failure or times out. The credential is first retained as a pending, unverified candidate; explicit retry uses the same server account check. It remains excluded from `has_authenticated_credential`, export, authenticated media and account reads until validation succeeds. Explicit credential rejection, sign-out or a newer QR/import generation clears it, and an in-flight old validation cannot install after replacement. Synthetic tests cover every transition. This recovery does not turn 803 itself into authentication.

## Phone-code candidate

NetEase's phone SMS login is now exposed as a separate optional Provider capability and UI method. One Provider-owned session generates a random device context, sends the code through mobile EAPI `/api/sms/captcha/sent`, and submits the Human-entered code through mobile EAPI `/api/login/cellphone`. The two calls retain the same device/cookie context and use the mobile request fields and headers recorded by the current upstream PR. EAPI encrypted responses are decoded with strict PKCS#7 validation and bounded optional gzip handling. Fura performs no automatic resend or protocol fallback, so an uncertain send cannot produce a duplicate SMS.

The Flutter form keeps phone and code text only in widget-owned controllers; neither value enters app diagnostics, Domain models, generated Bridge outcomes or secure storage. App diagnostics report only the send/login phase and typed outcome. Core diagnostics, when explicitly enabled with `FURA_NETEASE_SMS_DEBUG=1`, add only the numeric service code and content-free credential-candidate/account-verification phase. Country code, phone and verification code are digit-only and bounded before transport. Code rejection remains retryable in the same challenge. A login response becomes only a pending credential and must pass the same Account Summary correlation before it becomes active or exportable. If that account check has a transient network failure, an explicit retry verifies the retained pending credential instead of submitting the SMS code again. Cancel, provider replacement, sign-out and disposal invalidate late results. Closing the form after a successful send uses a separate whole-session cancellation edge because the one-shot send attempt has already completed; this clears the retained phone challenge and pending candidate instead of merely hiding the Flutter state.

Request construction, encrypted response decoding, invalid input, rejection, rate limiting, 8821 STOP, active-operation and completed-session cancellation, replacement, pending verification retry and secure-storage handoff have deterministic tests. The Agent did **not** send a real SMS or submit a real code. NetEase can apply risk control to phone-code requests as well, so code delivery, code acceptance, account verification and vault persistence remain `HUMAN_EVIDENCE_REQUIRED`.

Version-1 secure-storage bytes are namespaced to `netease-cloud-music` and contain only the provider-owned session and CSRF. Public Credential has no general Serialize/Deserialize implementation: import/export validate strict fields, version, provider, size and cookie syntax. No filesystem/vault is read by Core. Imported data remains pending until service verification; no invented cookie expiry is used. Transient/unknown/shape failures retain the candidate. Explicit authenticated 301 or null account/profile rejects it. Rejection clears only the owning generation; future UI integration must use its own namespaced vault cleanup. QQ and NetEase storage/session owners remain independent.

The authenticated eapi media request includes its explicit cookie plus encrypted MUSIC_U/__csrf header and CSRF payload. It shares exact source correlation, standard quality, real TTL, URI validation and trial/access-control STOP behavior with anonymous media. No source is saved or downloaded.

## Read foundation

| Read | Protocol | Machine evidence |
|---|---|---|
| Account summary / restore verification | weapi w/nuser/account/get | Correlated account.id/profile.userId; bounded name/avatar; candidate/active/rejection/race tests |
| User/owned playlists | weapi user/playlist | Explicit user ID; ≤10 serial pages of 100; owned/saved relations; no hidden unbounded drain |
| Ordinary/private playlist details | weapi v6/playlist/detail, v3/song/detail | Explicit same credential in both requests; generation checked between requests; raw omissions/cursor; rejection never retries as anonymous |
| Liked songs | weapi song/like/get, selected IDs through bounded Song detail | Complete unordered ID table bounded to 16,384 by the transport-derived memory policy; provider-owned `liked:<account>:<actual playlist ID>` route, exact owner checks, raw cursor/omissions; no recent-order claim |
| Favorite Albums/Artists | weapi album/sublist, artist/sublist | Bounded data/count/hasMore decoders and existing Domain pages |
| Daily Tracks | weapi v3/discovery/recommend/songs | ≤100 dailySongs; neutral Track batch, no invented daily Playlist |
| Personal FM | weapi v1/radio/get | ≤10 songs, one read only; no autoplay, scrobble, trash or like |
| Personalized playlists | weapi v1/discovery/recommend/resource | ≤100 recommended summaries, no public substitute |
| Media | eapi song/enhance/player/url/v1 | Explicit context; successful standard and rejection fixtures; Human entitlement/source evidence pending |

All listed reads have synthetic fixture/mapping coverage. Fixtures contain project-authored identities/content and dummy invalid-domain artwork/media, never real credentials or responses. Source-level correspondence and tests do not prove current account behavior.

## Human observation entry point

For a rebuilt Linux application regression, `FURA_NETEASE_QR_DEBUG=1` enables content-free Core phase diagnostics in addition to the Flutter diagnostics. It reports only the QR envelope code and whether 803 proceeded into account verification; it never prints the QR key, chain ID, cookie, account identity or response body. `phase=poll code=8821` proves provider security verification, while `phase=poll code=803` followed by `phase=account_verification outcome=failure` isolates the post-confirmation account check. Without 803, the failure remains in QR polling itself. The supplied Human log reached 801, 802 and then 8821 twice, so the present QR failure is conclusively before credential installation rather than artwork, vault or account-read code.

`crates/provider-netease/tests/human_qr.rs` is ignored by default and was **not run by the Agent**. It reads no stored credential. A Human may explicitly opt into QR approval and Account Summary/restore reads with:

```sh
FURA_NETEASE_HUMAN_QR=I_APPROVE_QR_AND_ACCOUNT_READS cargo test -p provider-netease --test human_qr -- --ignored --nocapture --test-threads=1
```

The Human opens the temporary PNG path and approves in the official app only if intended. The file has tempfile's secure creation and is removed on normal completion/unwind. The gate has at most 45 polls separated by two seconds, an underlying 60-request hard ceiling, and no account writes. Restore bytes stay in memory and the handoff buffer is zeroed after import. Logs show only coarse PASS states, never names/cookies/QR keys. A passing run proves only confirmed QR, Account Summary and in-memory export/import/server verification, not platform-vault persistence, liked collections, recommendations, media entitlement, another account/region, or absence of future risk verification. Those remain separately Human evidence.

`crates/provider-netease/tests/human_account_reads.rs` is a separate ignored gate and was also **not run by the Agent**. After one explicit Human QR approval it checks Account Summary, complete bounded user playlists and ownership, the exact liked route, one ordinary/private Playlist page, favorite Album/Artist pages, daily Tracks, Personal FM, personalized playlists, and authenticated standard source authorization. It is serial, sleeps between requests, has an exact 72-request ceiling (including up to 45 QR polls and worst-case ten user-playlist pages), stops its transport window on the first unexpected/risk envelope, performs no mutation and never GETs the audio body. Logs contain only PASS categories and a temporary QR file path—no names, titles, IDs, cookies, bodies or source URI.

```sh
FURA_NETEASE_HUMAN_ACCOUNT_READS=I_APPROVE_QR_AND_BOUNDED_ACCOUNT_READS \
  cargo test -p provider-netease --test human_account_reads -- \
  --ignored --nocapture --test-threads=1
```

A pass would be one-account/one-time evidence only. It would not establish collection completeness above observed pages, playback, account writes, another membership/region/device, platform-vault persistence, or UI acceptance.
