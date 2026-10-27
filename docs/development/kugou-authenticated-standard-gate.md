# Maintainer gate: KuGou official-Web Standard candidate

Date: 2026-10-27, Rust-caller/CDP refinement. **HUMAN GATE NOT_RUN**.
State: **HUMAN_GATE_READY**, scoped to the disconnected Rust-caller entry and
offline machine contract below, not a standalone CLI or live compatibility.
See the [current contract and dated protocol evidence](../research/kugou-authenticated-standard-v1.md).
Neither this document nor a build/test command authorizes account access,
live traffic or production activation.

## Rust caller only, no live command

The only gate entry is `linux_system_chromium::kugou::run_gate` in
`bridges/flutter/src/linux_system_chromium/kugou.rs`. It is a private,
crate-visible Linux Rust entry, compiled for tests or the opt-in
`kugou-cdp-gate` feature. It is not an FRB API, Flutter action, production
Provider, Authentication implementation or MediaResolver route. Enabling that
feature does not invoke the gate or enable production playback.

The caller must already hold the selected **existing Fura KuGou `TrackId`** and
its current owner/generation. A standalone CLI cannot establish that selection
by accepting an opaque string, manufacturing a `TrackId`, reading an export or
performing another lookup. There is no such CLI and no command in this guide
performs a Human run. A future authorized in-crate caller must supply the real
selection, explicit Human authority and cooperative lifecycle checks; do not
add production wiring merely to make the experiment callable.

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
- No redirect, retry, alternate profile/envelope, Fura Search/detail, another
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
