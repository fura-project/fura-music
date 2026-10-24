# NetEase official Web session capture and restore V1

Date: 2026-10-24. Human-directed Core task. Implementation baseline:
`7435c5178cb33d8b5114fddf5f7a5d8189435bd0`.

## Accepted product boundary

Official Web login remains the product entry point: Linux uses the existing
isolated system Chromium/CDP owner; other supported platforms use the existing
official WebView broker. Their lifecycle, cleanup-before-staging, cancellation,
timeout and isolation rules are retained. No ordinary browser profile or Cookie
database is read. QQ WeChat/Type 2, Settings and packaging are outside this task.

Both capture adapters now retain exactly `MUSIC_U`, optional independent
`MUSIC_R_U`, and optional `__csrf` on `music.163.com` / `.music.163.com`.
`MUSIC_U` remains required. Missing R does not prevent ordinary authentication.
No other value is used to synthesize R. Same-value duplicates are accepted;
conflicting duplicates, empty known values, unsafe characters and field/total
bounds fail closed. Foreign names/domains are ignored. Native Cookie snapshots
do not expose Set-Cookie deletion attributes through the WebView API; an empty
known Cookie is rejected, and the adapter does not invent expiry metadata.

The existing Credential V2 parses the minimal candidate, keeps it Pending in
the Provider, and exports it only after the normal account verification.
V1 imports remain supported with no refresh material. The existing independent
NetEase vault key stays `netease_cloud_music_credential_v1`; that stable storage
key does not imply the document is still V1. No Bridge signature or DTO changed,
so FRB regeneration is unnecessary. The Bridge body adds only a fixed-schema
Linux verification checkpoint.

Every accepted Rust credential must fit the existing 8192-byte serialized
document bound. A new regression first demonstrated that a Cookie header below
8 KiB could produce V2 JSON above 8 KiB and become impossible to restore. The
Client now rejects such a candidate before it can authenticate or be exported;
the import limit was not raised.

## Restore ownership and failure rules

Rust remains the only authentication owner. NetEase's existing account
generation rejects late verification responses after cancellation, logout and
replacement. Flutter handles only opaque vault bytes and operation lifetime.

The NetEase gateway coalesces concurrent vault restores. After the read it
revalidates its local operation epoch before importing anything into Rust.
Logout, a new official login, Controller cancellation and Controller disposal
invalidate a pending read. Every temporary Dart byte buffer is cleared even
when its operation is retired. This closes the gap where Controller generation
checks hid a late UI result but the stale vault read still staged a Rust session.

Normal restore reads only this Provider's vault, imports Pending, then performs
one account verification. Network/service/shape failures retain the stored
credential and pending candidate for explicit verification retry without a
browser. An already authenticated, verified in-process session keeps the
existing fast path; it does not need to reopen login or read another vault.

Explicit rejection of a restored credential deletes only its owning vault
epoch. A newer login/publication wins over late rejection cleanup. A newly
captured, not-yet-persisted Web candidate is different: rejection discards that
candidate without deleting the previously saved session. A regression exposed
that distinction during this task and now checks it directly. Failed secure
publication leaves the previous document in place and reports the existing
storage failure result. Logout still performs the existing browser cleanup,
Core sign-out and vault deletion sequence.

## Opt-in observation schema

The new switch is `FURA_NETEASE_WEB_REFRESH_DEBUG=1`. Rust uses the process
environment; Flutter accepts that environment on desktop or
`--dart-define=FURA_NETEASE_WEB_REFRESH_DEBUG=1` on supported mobile WebViews.
Ordinary runs leave it off. The API accepts only fixed path/checkpoint values
and booleans. Example fields (synthetic, not a real result):

```text
FURA_NETEASE_WEB_REFRESH_DEBUG path=linux_isolated_chromium phase=capture observed_music_u=true observed_music_r_u=false observed_csrf=true candidate_valid=true
FURA_NETEASE_WEB_REFRESH_DEBUG path=linux_isolated_chromium phase=account_verification_entered success=true
FURA_NETEASE_WEB_REFRESH_DEBUG path=linux_isolated_chromium phase=secure_persistence success=true
```

The WebView path reports `path=web_view`. `candidate_valid` describes adapter
structure checks; Rust still independently validates the candidate and its
serialized document bound before account verification. No observation contains
values/fragments, hashes, lengths, account information, URLs, Profile paths,
ports or CDP identifiers. `observed_music_r_u=false` means this capture adapter
did not observe the field. It does not establish that the server never issued
it, or that another login path would have the same result.

## Human restart observation and remaining capture gate

On 2026-10-24 the maintainer reported that, after closing and rerunning
`flutter run`, the existing NetEase session automatically signed in. Read-only
process inspection confirmed a new Linux Debug application process. Record
this as one **Human-reported Linux automatic-restore PASS**. The Agent did not
inspect the vault, Cookie values or account identity, and did not initiate a
refresh. This is a local restart result, not long-duration/cross-platform soak.

The process did not enable Linux capture-presence diagnostics. Independent R
capture and the saved document's version therefore remain unknown; V1 and V2
can both restore. No logout or fresh login is necessary to preserve this valid
session. The diagnostic official-Web capture procedure below remains **NOT RUN**
and requires a deliberate maintainer-operated login when that evidence is needed.

The Agent did not open an official login, read a stored credential, call an
account endpoint or send a refresh request in this task. Run the following only
as a maintainer-operated experiment with an approved disposable account.

Linux, from `apps/flutter`, after building the current tree:

```sh
FURA_NETEASE_WEB_REFRESH_DEBUG=1 flutter run -d linux \
  --dart-define=FURA_NETEASE_WEB_REFRESH_DEBUG=1
```

1. Select NetEase and deliberately start its existing official Web login.
   Complete all login/account actions yourself in the isolated browser. Confirm
   the intended account locally; never share its identity or browser content.
2. Record only login success, the three presence booleans, adapter validation,
   entry into account verification and secure-persistence success. Missing R
   is a valid successful ordinary-login outcome.
3. Close Fura normally and reopen the same build. Confirm the saved session
   restores through account verification without a browser or a new QR. Do not
   print, inspect or export the vault document to establish its version.
4. Optionally exercise service switching, cancellation and explicit logout
   yourself and report only coarse outcome/cleanup status. Capture no raw
   browser, network, credential or account diagnostics.

For an independently supported WebView target, launch the current build with
the same Dart define and repeat the same product flow. Linux and WebView
observations are separate evidence; low-level type-1 QR is a separate control
and cannot replace the official-Web result.

Stop all service actions on HTTP 429, 8821, 8830, CAPTCHA, security/secondary
verification, account mismatch or a new device/signature/private-secret/client
identity requirement. Do not change profile/envelope or retry around a challenge.

The first observation never calls refresh. If R is not observed, the candidate
stays disabled. If independent R is observed, it is only a prerequisite for a
separately authorized disposable-session gate with at most one refresh and one
same-account verification. A PASS would still require a separate Release
activation decision.

## Refresh evidence boundary

The existing one-shot WEAPI candidate remains disconnected from production:
`/api/login/token/refresh` maps through the current WEAPI transport. It requires
independent R, U, CSRF and `os=pc`, outer success plus `bizCode=201`, and complete
changed U/R rotation. It has no EAPI Type 3 fallback or invented expiry window.

The pinned third-party implementations in
[the prior audit](provider-playback-session-audit-2026-10-06.md) are protocol
reference only. [Binaryify issue 1421](https://github.com/Binaryify/NeteaseCloudMusicApi/issues/1421)
is an old report that QR-derived cookies failed `/login/refresh`; it is negative
historical evidence, not proof of the current official-Web behavior. Fura has
no real refresh or same-account rotation PASS for this Provider.

## Machine evidence and final state

Deterministic regressions exercise all U/R/CSRF combinations, source filtering,
duplicate/conflict/deletion/character/size checks, redacted diagnostics,
cleanup/cancel/timeout, V1/V2 restore, Pending-before-verification, retained
transient failures, explicit rejection, repeated restore, logout/retirement,
replacement and late cleanup, Web handoff and secure publication failure.
Native Provider tests independently verify actual V2 import/export and account
generation behavior; injected Dart operations prove lifecycle and byte handling,
not service acceptance or native keychain correctness.

Final status:

- `AUTO_RESTORE_IMPLEMENTED`
- `WEB_REFRESH_MATERIAL_CAPTURE_READY`
- `LIVE_REFRESH_EVIDENCE_PENDING`
- `PRODUCTION_AUTO_REFRESH_DISABLED`

Physical WebView behavior, actual R delivery, restart on other platforms and
any real refresh remain pending Human evidence. One Linux Debug restart is
Human-reported PASS as recorded above. Machine build/test
results are recorded in `PROGRESS.md`: full locked Rust workspace/all-target
tests, all-target strict Clippy for the three affected packages, 122 Flutter
authentication tests, the complete Shell regressions, Dart format/analyze,
Linux Release build, privacy and diff checks pass. Whole-workspace strict
all-target Clippy still fails on the existing QQ test-only
`unused_async_trait_impl` diagnostics under Rust 1.98; none of those fixtures
or lint settings was changed.
