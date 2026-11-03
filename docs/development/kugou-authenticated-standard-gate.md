# Maintainer gate: KuGou official-Web Standard candidate

**Superseded workflow:** the first Human-operated V1 gate at `5add34e` stopped at
local identity binding before Rust replay. The current protocol model and future
maintainer workflow are in the [V2 two-stage guide](kugou-two-stage-gate-2026-11-02.md).
The one-songinfo budget and readiness claims below are dated V1 evidence, not
current authorization or V2 validation. Do not run either gate without fresh Human
authorization. The V1 failure is retained, not overwritten by synthetic success.

Date: 2026-11-02, bounded Rust-only Human harness follow-up to `c0dc091`.
**HUMAN GATE NOT_RUN**. The harness adds a caller, not a different CDP protocol.
See the [current contract and dated protocol evidence](../research/kugou-authenticated-standard-v1.md).
Neither this document nor a build/test command authorizes account access,
live traffic or production activation.

## Opt-in Rust harness: Search, ordinal, existing gate

The `kugou-human-gate` binary requires `kugou-cdp-gate` and Linux. There is no
default-feature, FRB, Flutter, BuiltInProvider, production MediaResolver or Vault
entry. The binary compiles the existing private Chromium module directly from
its original source; it does not copy CDP implementation or export a new API.
Its default invocation is inert. `--interactive` merely opens Phase A; other
arguments, redirected stdin/stdout/stderr and an unavailable controlling terminal
return `KUGOU_GATE result=NOT_RUN`. No environment/file/clipboard identity or
credential input exists. The retired entries below remain inert.

Only after **separate Human authorization for a live run**, from the repository:

```sh
cargo run --offline --locked -p rust_lib_flutterustmusic --features kugou-cdp-gate --bin kugou-human-gate -- --interactive
```

`--offline` constrains Cargo dependency resolution, **not** the authorized
runtime's HTTPS requests. Do not run this command unattended, with a terminal
recorder or tee; presentation is shown only on the controlling terminal.

1. Phase A displays `Budget: 1 anonymous KuGou public Search request`. Only the
   exact phrase `AUTHORIZE ONE PUBLIC SEARCH` proceeds to query input. The existing
   KuGou client/Provider performs page 1, size 10 once. A transport-owned atomic
   budget is consumed before await; cancellation/error/concurrency/re-entry
   cannot refill it. Public HTTPS transport now explicitly disables reqwest's
   default protocol retry, as well as redirects. No second query, second page,
   detail, ranking, automatic selection, fuzzy matching or source fallback exists.
2. The controlling terminal shows only ordinal/title/artist/optional Album title/
   duration. Human enters **one result number**, never opaque TrackId/hash/context.
   The harness borrows that in-memory `TrackSearchItem`'s exact Provider `TrackId`.
   Existing Provider `begin_capture` on a transport-less, disposable validation
   owner verifies eligibility before Phase B; no second identity decoder is added.
   This validation owner never captures/replays and cannot refill the real owner's
   budget. Missing Album identity or full duration, foreign/malformed identity,
   empty results, invalid ordinal, EOF or cancellation ends the run without CDP.
   An absent presentation Album title alone is not absent private Album context.
3. Phase B describes the isolated official browser, Human-owned login/account/
   entitlement confirmation, pre-network browser-songinfo abort, browser cleanup,
   at most one Rust songinfo and separately approved optional Range. Only the
   exact phrase `AUTHORIZE ONE AUTHENTICATED GATE` creates the real gate owner and
   calls existing `linux_system_chromium::kugou::run_gate` with the selected ID.
   Declining produces `KUGOU_GATE result=NOT_RUN`, even though Search was consumed.
4. Optional Range requires the later exact phrase `AUTHORIZE ONE RANGE`, after
   displaying only the actual returned normalized hostname. Neither earlier
   approval grants this request. Declining finishes with no Range.

During CDP, SIGINT/SIGTERM invalidate the real owner and await existing cooperative
cleanup rather than aborting its future. Close the isolated browser to cancel
official-page work. No account/password/SMS/QR action is automated. Every existing
risk/limit/verification stop remains fail-closed; a restart is not permission to
bypass a stop. Search failures end this run, not permission for another endpoint.

Structured diagnostics contain only budget=1, bounded result count (0–10), fixed
selection/authority confirmation and fixed stop categories. Query/presentation,
TrackId/hash/context, credentials and full URLs never enter those diagnostics or
an application-created log. Public presentation is not persisted by the harness.

The two-stage live request budget supersedes the earlier caller-only ban on new
Search solely for this harness: **one Human-authorized anonymous Search**, then
independent Phase B authority. It does not reopen old anonymous probe budgets or
authorize any real run in this implementation task.

## Harness machine evidence, 2026-11-02

State: **LIVE_HUMAN_GATE_READY**; **KUGOU_HUMAN_PLAYBACK_GATE=NOT_RUN**.
This is readiness to request a separately authorized first Human test, not live
compatibility, account verification or production playback acceptance.

Current implementation: `bridges/flutter/src/kugou_human_gate.rs`,
`bridges/flutter/src/linux_system_chromium/kugou_harness.rs` and its `tests.rs`.
The only existing implementation changes outside feature registration/module
declaration are explicit `reqwest::retry::never()` in Public HTTPS transport.
No dependency version or lockfile changed. No Bridge API changed, so FRB
generation or Flutter integration is neither necessary nor claimed.

Starting HEAD: `c0dc0915171d40865275c393d5d68abb76b0e848`. Scoped source
SHA256: `532e02e4c73426074f1cf0e7e2f05b55a1491cf168c8c7a1022c706646bf8670`.
The hash includes all six changed/new Rust and Cargo files, sorted by relative
path; each contributes path, NUL, file bytes, NUL. Markdown is excluded. Temporary
logs are outside Git under `/tmp/fura-kugou-harness-20261102-c6Ekxj/`; no real
query, account, capture, cookie or media is present.

| Check | Actual offline/synthetic result |
| --- | --- |
| `cargo fmt --all -- --check` | PASS |
| `cargo test --offline --locked -p kugou-client -p provider-kugou --all-targets` | PASS: 53 tests; default public live test remains ignored |
| `cargo test --offline --locked -p rust_lib_flutterustmusic --all-targets` | PASS: 144 tests; installed-browser explicit test remains ignored |
| Same Bridge test with `--features kugou-cdp-gate` | PASS: 165 tests, including 21 new Harness tests; executable test target is inert |
| `cargo clippy --offline --locked -p kugou-client -p provider-kugou --all-targets -- -D warnings` | PASS |
| `cargo clippy --offline --locked -p rust_lib_flutterustmusic --all-targets --features kugou-cdp-gate -- -D warnings` | PASS |
| Existing exact installed-Chromium loopback command below | PASS: browser upstream=0, Rust replay=1, Range=0, profile deleted |
| `cargo test --offline --locked -p rust_lib_flutterustmusic --lib linux_system_chromium::tests::` | PASS: all six unchanged NetEase Chromium tests |
| `python3 scripts/research/test_kugou_web_playback_gate.py` | PASS: three retired-entry/privacy tests |
| `python3 scripts/ci/audit_privacy_hygiene.py` and `python3 scripts/ci/verify_application_identity.py` | PASS |
| `git diff --check` | PASS |

The 21 deterministic Harness tests cover unauthorized Search (0 sends), exact
first-page Provider mapping and selected ordinal (identical titles with distinct
identities), at most one send under error/completion/re-entry/concurrency/dropped
future, empty/all-omitted pages, query/selection cancellation, invalid ordinal
and pasted opaque context rejection, foreign Provider/malformed ID rejection,
missing Album/full-duration context without detail, optional Album title,
Phase B refusal with zero CDP admission, separate Range approval, bounded input,
diagnostic/presentation separation, default Cargo feature/dependency fencing and
owner retirement before awaited cleanup. The handoff test uses the real client
decoder and Provider mapping with a synthetic public response; its gate recorder
proves the exact ID passed at the boundary, while the existing unchanged CDP
tests separately prove abort/cleanup/single replay. It is not a live Search test.

The real feature-enabled executable builds. Default, redirected `--interactive`,
and manual query/identity/cookie arguments all return only `KUGOU_GATE
result=NOT_RUN`. A controlling-PTY run displayed the Phase A budget, accepted
`NO` and exited with SEARCH_NOT_AUTHORIZED/NOT_RUN before query input. Cargo
metadata and the default normal-dependency graph exclude the harness's KuGou
dependencies. `cargo build --offline --locked -p rust_lib_flutterustmusic
--release --no-default-features --bin kugou-human-gate` is intentionally rejected
because the feature is required; no production binary is generated.

Resolved negative evidence: initial binary source placement confused private
submodule lookup; moving only the binary root beside the existing module fixed
compilation without copying CDP. Initial use of a nonexistent public reqwest
Policy API and a shadowed test helper were compile errors, corrected without
weakening assertions. Final lifecycle audit proved that a synchronous terminal
read on one runtime thread could delay cancellation while Range approval waited.
The feature-only two-worker runtime now handles signals independently, retires
owner/generation first and uses bounded `poll`-based terminal input. Regression
shows partial input cancels without another keystroke, late approval is rejected,
and the gate future is awaited to finish cleanup. No capture/replay-core change
was needed. None of these failures is evidence about the real KuGou service.

## Existing Rust gate ownership (unchanged)

The only gate entry is `linux_system_chromium::kugou::run_gate` in
`bridges/flutter/src/linux_system_chromium/kugou.rs`. It is a private,
crate-visible Linux Rust entry, compiled for tests or the opt-in
`kugou-cdp-gate` feature. It is not an FRB API, Flutter action, production
Provider, Authentication implementation or MediaResolver route. Enabling that
feature does not invoke the gate or enable production playback.

The caller must hold the selected **existing Fura KuGou `TrackId`** and its current
owner/generation. The harness obtains it only from existing Provider Search
mapping, never a pasted opaque string, export or manufactured identity. It adds
no production wiring and does not modify capture/replay implementation.

The old Python wrapper and Rust example are retired, inert entries:

| Entry | Fixed result |
| --- | --- |
| `scripts/research/kugou_web_playback_gate.py` | `KUGOU_GATE result=NOT_RUN reason=RUST_CALLER_REQUIRED` |
| `crates/provider-kugou/examples/kugou_web_playback_gate.rs` | `KUGOU_GATE result=NOT_RUN reason=OFFICIAL_WEB_CDP_OWNER_REQUIRED production_enabled=false` |

Neither reads secrets nor launches a browser or request. Former
`--human-authorized-once` / `--probe-range` arguments do not reactivate them.
The former hidden-input/manual-capture workflow is superseded, not an alternate
route. Do not run the old ignored anonymous probe.

## Separate authority and budget

Before any future Human run, the maintainer must explicitly approve this exact
official-Web route, a disposable account/session and one selected entitled
Standard track. Human performs ordinary website login, consent and local account
confirmation in the gate-created isolated browser, not by giving secrets to Fura.
An unavailable Rust caller or missing selection leaves the gate **NOT_RUN**.

- Normal official-page/login traffic requires that separate Human authority;
  it is not authorized by offline tests or this guide.
- Zero Fura QR/password/SMS/login/refresh/device-registration requests and zero
  independent Fura account-summary requests. A safe official-Web verified-account
  contract has not been established. Local Human account confirmation and one
  songinfo response are not server-verified global account identity.
- The browser-generated songinfo candidate must be intercepted and aborted
  **before network delivery**. It is not a first authorization request followed
  by a second request from Rust.
- At most **one** Rust `GET https://wwwapi.kugou.com/play/songinfo`, replaying the
  admitted official request for that exact current track after browser cleanup.
- Optionally, at most **one** `Range: bytes=0-4095` request, only after separate
  approval of the returned source's exact normalized hostname. No API Cookie or
  added account token is sent to media; never display the media URL.
- No redirect, retry, alternate profile/envelope, additional Fura Search/detail, another
  track, backup source, HTTP downgrade, third-party API or quality escalation.

A third-party README, synthetic fixture or previous checkpoint is not authority
to use the maintainer's account. This must not become an unattended live test.

## Capture, abort, cleanup, replay

1. `run_gate` checks explicit authority and calls the Provider owner's
   `begin_capture(id)` synchronously **before browser startup or any await**.
   Admission is non-Clone and bound to that owner, generation and exact `TrackId`.
   Failure, cancellation or replacement does not refund the one-shot budget.
2. The browser starts at `about:blank` in a fresh isolated temporary profile with
   mode `0700`, separate from everyday profiles and Fura QQ/NetEase sessions.
   The gate never reads an ordinary browser Cookie database or a Fura vault.
3. CDP auto-attachment pauses page/iframe/worker targets on creation (not the
   browser/tab control targets, which do not implement Fetch). Request-stage
   `Fetch` is armed with `*://*/play/songinfo*` before resume, including
   workers/popups; official
   navigation starts only after interception is armed. Capture is accepted only
   from a proved HTTPS `www.kugou.com` page/frame and its XHR/Fetch request.
4. Songinfo candidates are aborted first, including wrong-host, wrong-method or
   wrong-identity candidates. Admission requires an acknowledged
   `Fetch.failRequest` and the exact HTTPS `wwwapi.kugou.com/play/songinfo` `GET`,
   without body, credentials in the authority, fragment or explicit port.
   A candidate is never continued to the network or used as a response-stage
   capture. Unsupported provenance/shape stops the attempt, not a search for
   another successful candidate.
5. Only after the abort acknowledgement does `Storage.getCookies` supply the
   fresh profile's Cookie material. Manual Cookie/token/signature/signed-URL,
   HAR, clipboard, stdin, environment and default-profile imports are not inputs.
   Interception remains armed until shutdown; capturing once does not allow a
   later browser songinfo request through.
6. Browser exit, profile-process termination and temporary-profile deletion
   must complete successfully **before** capture binding or Rust replay. Cleanup
   failure blocks replay. Cancellation must retire the owner, make `is_current`
   false and await cooperative cleanup, not abort/drop the gate task as a cleanup
   strategy. Fetch's CDP connection remains attached until both the owned child
   and profile processes have exited, including rejected `Browser.close` and
   forced termination. Detaching first could release paused requests. The owned
   child is explicitly killed/reaped even when it lacks a profile-bearing argv.
7. The Provider admits the capture only for the same current reservation, then
   consumes replay admission **before transport await**. Logout, Provider/account
   replacement, same-account relogin and cancellation invalidate old results.
   Restaging/clearing cannot reopen either budget; a risk/rate stop is sticky.
   A retained generation/track check also rejects stale optional Range results.

These invariants pass synthetic CDP and installed-Chromium loopback tests below.
They do not establish real-website compatibility or account authentication.

## Exact track and request contract

The Provider alone decodes the existing private context
`v1:<MixSongID>:<Standard hash>:<Audioid>:<duration seconds>:<Album ID>` from the
caller-held KuGou `TrackId`. Required known Album and full-duration context must
already exist; do not paste this representation into a tool or fill gaps with
new Fura Search/detail traffic.

The official query must contain the exact Standard `hash` and `album_id` for
that selection. If supplied, `MixSongID`/`mix_song_id` and `album_audio_id`
aliases, including normalized case/underscore/hyphen spellings, must agree with
one another and with the existing MixSongID. They are not aliases for Audioid.
Missing/mismatched identity, contradictory aliases or unsupported alternate
identity such as `audio_id`, `songid` or `encode_album_audio_id` stops with
`OFFICIAL_WEB_TRACK_IDENTITY_UNPROVEN`. No fuzzy title/artist match, guessed ID
conversion or music-lib two-hop request is allowed.

The original URL/query is preserved, not rebuilt or re-signed. Optional
`signature`, `mid`, `uuid`, `dfid`, `userid`, `token`, `clienttime` and public
profile selectors are not required merely because reference clients use them.
Missing fields remain missing; Fura does not generate or repair them, force old
appid/clientver constants or invent an upstream expiry. Supplied session fields
must match the eligible profile Cookies. Unrelated opaque query fields remain
unchanged, not treated as permission to use another identity route. The local
freshness limit is 300 seconds from interception, conservatively shortened by
an older captured `clienttime` when present, not an upstream session-TTL claim.

## Minimal replay headers

This is a **minimal replay experiment**, not a byte-for-byte browser emulation.

- Preserve the captured `User-Agent`, `Origin`, `Referer` and, when present,
  `Accept`. UA is not replaced with a Fura default or a manually forged Chrome
  string. Origin must be `https://www.kugou.com`; Referer must have that exact
  HTTPS origin. Missing required UA/Origin/Referer stops capture.
- Construct only `KugooID` and `t` from applicable domain/path entries returned
  by this profile's `Storage.getCookies`. Both are required; ambiguous matches,
  session mismatch or a composite-only `KuGoo` shape fail closed.
- If CDP includes a captured `Cookie` header, it must contain exactly that same
  two-cookie contract. Any extra captured Cookie, including device, analytics
  or composite context, fails closed instead of being silently dropped or
  blindly forwarded. Cookie-header absence does not prove the browser used no
  extra Cookies; live acceptance of the minimal subset is still unproved.
- Omit `sec-*` client/fetch hints and `Accept-Language`; browser encoding and
  transport headers are not copied. Arbitrary extra semantic headers, including
  `Authorization`, custom `x-*` signing headers, `Range` or `Content-Type`, are
  rejected rather than stripped or synthesized.

The separate transport remains HTTPS-only, no redirects/retries/system proxy,
with a 256 KiB API response bound. The existing public transport allowlist is
unchanged. Rejection does not authorize adding headers/Cookies, changing UA,
generating device context or trying another envelope.

## Standard is not a container

The candidate supports three format classes: `Mp3`, `Ogg` (Opus/Vorbis) and
`Mp4Aac` (`m4a`/`mp4`, bounded AAC-LC subset). Standard is a quality tier, not
synonymous with MP3, 128 kbps, an extension, MIME label or an arbitrary codec.

The exact `data.quality == "standard"` rule is a **synthetic offline contract**,
not a live-observed KuGou field/semantic. Only when quality metadata is absent
does the legacy MP3 plus 128/128000 bitrate fixture remain conservative Standard
evidence. Explicit null, unknown, differently cased or higher-quality labels
cannot use that fallback; `audio_name` is not a proved quality alias. Ogg and
MP4/AAC require the explicit synthetic Standard evidence. Fixtures cover those
Standard formats, not live service support or quality negotiation.

Every format still requires success, explicit non-preview/full-track permission,
exact track identity, known full duration and plausible full-file size. A URL or
Standard label alone grants neither entitlement nor full playback. FLAC,
encrypted/protected media, raw AAC and unsupported formats/configurations remain
rejected; no request is upgraded to higher quality.

The optional 4 KiB validation requires 206, exact Content-Range/total size,
compatible MIME (or bounded octet-stream) and container/codec signatures: two
compatible MP3 Layer-III frames after any bounded ID3 tag; a complete Ogg first
identification packet with page CRC; or bounded MP4 initialization with a sound
track, `mp4a`/AAC-LC configuration before media data. Labels alone, HTML,
malformed/truncated or unsupported layouts fail closed. This is not a decoder,
audible full-song playback test or full-file integrity proof.

## Ephemeral media-host approval

A validated API response may introduce a previously unknown normalized public
DNS hostname. This replaces the old pre-run exact-KuGou-host allowlist, not the
consent boundary. HTTPS and DNS-name validation reject IP literals/local or
reserved-name shapes; syntactic validation is not independent proof of host
ownership or resolved-address safety.

The gate reports `NEW_MEDIA_HOST_REQUIRES_APPROVAL` before asking its callback
for consent. Human may inspect **only the normalized hostname**, never the full
URL/path/query, and approve or decline the one bounded Range for that returned
source. Declining ends without a media request and does not retry songinfo.
Approval creates an ephemeral per-source token; another source, even on the
same host, cannot reuse it. No wildcard, persistent allowlist, preapproved
hostname argument or response-derived automatic approval is permitted.

## Stops, evidence and state

Stop on HTTP 429, CAPTCHA/SSA, verification/secondary confirmation, unexpected
device/private-secret/package/attestation demands, account mismatch, 403/denial
or unknown access control. Do not generate new mid/dfid, replace the owner,
change profile or restart to bypass the stop. Challenge/limit classification
dominates ordinary error fields before success decoding; unknown upstream
codes remain unknown, not guessed region/copyright/session-expiry semantics.

Capture diagnostics are fixed `KUGOU_CAPTURE_SOURCE=OFFICIAL_WEB` and presence
booleans `HAS_SIGNATURE`, `HAS_MID`, `HAS_DFID`, `HAS_USERID`, `HAS_TOKEN`.
Record only coarse request counts, capture/permission classifications, Human
login/account confirmation, HTTPS-source presence, optional range outcome and
stop reason. Never record credentials or their lengths/hashes, track/hash/name,
full URLs, raw responses, media bytes, CDP identifiers or private profile paths.
Short-lived owned buffers use best-effort wiping, not a guarantee that all CDP,
URL-parser or HTTP/TLS runtime copies are cryptographically zeroized.

Offline verification for this refinement passes the locked workspace/all-target
Rust tests, affected strict all-target Clippy (including `kugou-cdp-gate`), Rust
formatting, all 122 Flutter authentication tests, three Python retirement/privacy
tests, source privacy audit and diff whitespace checks. The six existing NetEase
Chromium tests are unchanged and pass. The candidate crates pass 53 tests;
29 new KuGou CDP/lifecycle tests pass, and default live probes remain ignored.

The installed headless Chrome test was explicitly executed against a generated
loopback TLS official-site surrogate, with synthetic HttpOnly profile Cookies,
exact official-looking URL/hosts mapped to loopback and all other DNS blocked.
It confirms **browser songinfo upstream=0**, **Rust TLS replay total=1**,
**Range=0**, `0700` isolation, an untouched synthetic default-profile sentinel,
confirmed browser exit and deleted profile. No real website, account, login,
songinfo or media request was sent. The separately tested continue control really
forwards to a physical loopback listener, so the zero-count oracle is not inert.

Initial runtime failures are retained as resolved negative evidence: attaching
unsupported tab control targets failed CDP; pausing the navigation document
blocked `Page.navigate`; and a reserved `.invalid` fixture media host correctly
failed public-DNS syntax validation. Target filtering, songinfo-only Fetch
patterns and a public-shaped synthetic media hostname corrected those causes
without relaxing capture, TLS, entitlement or host validation. Rejected-close,
unmatched-owned-child forced cleanup and stale Range regressions cover the
adjacent lifecycle findings.

Machine status (offline/synthetic evidence only):

```text
KUGOU_CDP_CAPTURE=PASS
OFFICIAL_REQUEST_PROVENANCE=PASS
BROWSER_REQUEST_ABORTED_BEFORE_NETWORK=PASS
ONE_UPSTREAM_REQUEST_DESIGN=PASS
TRACK_BINDING=PASS
STANDARD_MEDIA_MP3=PASS
STANDARD_MEDIA_OGG=PASS
STANDARD_MEDIA_M4A=PASS
SECRET_SAFE_CAPTURE=PASS
NETEASE_CDP_REGRESSION=PASS
KUGOU_HUMAN_PLAYBACK_GATE=NOT_RUN
```

The provenance PASS means only official-page/frame CDP material can enter this
gate's replay path; the runtime fixture is a synthetic official-site surrogate,
not proof of what live KuGou currently generates.

Exact offline runtime command (never use blanket `--ignored`):

```sh
cargo test --offline --locked -p rust_lib_flutterustmusic --lib linux_system_chromium::kugou::runtime_tests::offline_installed_chrome_intercept_abort_then_single_rust_tls_replay -- --exact --ignored --nocapture
```

`run_gate` returns whether the optional bounded range passed; `false` after
declined approval is not full playback failure, and `true` is not audible/full
playback PASS. The Human gate remains **NOT_RUN**, account-summary verification
remains false and production remains disabled. Even future source/probe success
requires separate decisions/evidence for verified account semantics, secure
KuGou-only persistence/sign-out/generation, ordinarily authorized request
generation, production MediaResolver/routing/capability/Bridge/UI integration
and cross-platform playback.
