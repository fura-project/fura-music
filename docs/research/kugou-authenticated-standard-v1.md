# KuGou authenticated Standard playback V1 — offline candidate

## Current superseding contract: Rust caller and CDP

Date: 2026-10-27, after the initial offline checkpoint. The Human clarified that
the gate may be entered **only by a Rust caller already holding the existing,
currently selected Fura KuGou `TrackId`**. No standalone CLI may manufacture that
claim from pasted opaque context, an export/file or a new lookup. The manual
secret-entry/Python live workflow below is dated history, not an available
fallback. This refinement adds no new protocol research or live authority.

Current implementation sources are
`bridges/flutter/src/linux_system_chromium/kugou.rs`,
`crates/kugou-client/src/web_playback_candidate.rs` and
`crates/provider-kugou/src/web_playback_candidate.rs`, with their offline
fixtures. Current offline machine verification is **HUMAN_GATE_READY** for the
disconnected Rust-caller entry; exact checks, resolved negative evidence and the
synthetic request-count oracle are recorded in the
[gate evidence](../development/kugou-authenticated-standard-gate.md#stops-evidence-and-state).
Do not reuse historical SHA256 or test counts below as validation of this changed
worktree. **HUMAN GATE NOT_RUN.**
No real Human/live run or production enabling is performed by this refinement.

### Entry and one-shot ownership

`linux_system_chromium::kugou::run_gate` is a private, crate-visible Linux Rust
entry, compiled under tests or the opt-in `kugou-cdp-gate` feature. It is not an
FRB export, Flutter action, production Provider/Authentication implementation or
MediaResolver route. Feature compilation alone does not invoke it. A future
authorized in-crate caller must own the actual selected `TrackId`, explicit
Human one-request authority and current-selection/lifecycle checks; there is no
live command or production wiring to stand in for that caller.

The Python entry now unconditionally reports
`KUGOU_GATE result=NOT_RUN reason=RUST_CALLER_REQUIRED`. The legacy Rust example
reports `KUGOU_GATE result=NOT_RUN reason=OFFICIAL_WEB_CDP_OWNER_REQUIRED
production_enabled=false` on one line. Neither accepts secret/TrackId input or
launches IO. Old `--human-authorized-once` and `--probe-range` flags cannot
reactivate the wrapper. No command performs a Human run.

The Provider's `begin_capture(id)` consumes admission synchronously **before
browser startup or any await** and binds a non-Clone token to that owner,
generation and exact `TrackId`. `finish_capture` admits only that still-current
reservation; `resolve_captured_once` consumes replay admission before transport
await. Failure, dropped capture, cancellation, logout, Provider/account
replacement or same-account relogin cannot refill the budget. Retiring the owner
invalidates late results; risk/rate stops remain sticky. Callers must retire the
generation, make `is_current` false and await cooperative cleanup rather than
abort/drop the gate task to cancel browser work.

### Official generation, pre-network abort and cleanup

The browser starts at `about:blank` in a fresh isolated temporary `0700` profile,
not a default/everyday browser profile or a QQ/NetEase session. CDP auto-attaches
with page/iframe/worker targets paused, arms request-stage `Fetch` for the
songinfo path family on every attached target before resume, including
workers/popups (not unsupported tab/browser control targets), and only then navigates to
`https://www.kugou.com/`. Ordinary website login/consent/account confirmation
remain Human actions under separate explicit authority, not manual secret input
to the gate. No ordinary browser Cookie database or Fura vault is read.

Songinfo candidates are aborted first, including wrong-host/method/identity
shapes. Only an exact HTTPS `wwwapi.kugou.com/play/songinfo` `GET` without body
from a proved official `www.kugou.com` page/frame XHR/Fetch can be admitted.
The owner awaits `Fetch.failRequest` acknowledgement **before** reading this
profile's `Storage.getCookies`; it never continues a candidate or captures an
already-delivered response. Interception stays armed through shutdown.
Browser exit, profile-process termination and temporary-profile deletion must
succeed before binding/replay. Fetch stays attached until the owned child and
profile processes are dead, including rejected-close/forced-reap paths; closing
CDP first could release paused requests. Cleanup failure blocks Rust replay.
The actual installed-Chrome synthetic TLS test passes browser upstream=0 and
Rust total=1. It is not a live KuGou/runtime compatibility PASS.

Thus the budget is at most **one Rust songinfo request**, not one browser
authorization plus another replay. There are zero Fura login/refresh/device
registration or independent account-summary calls, no retry/redirect/fallback,
and at most one separately approved `Range: bytes=0-4095` media probe. Normal
official-page/login traffic also needs explicit Human authority; offline tests
do not grant it. No manual Cookie/token/signature/signed-URL/HAR/clipboard/stdin
or environment import is an alternate capture source. A public constructor's
source label alone is not cryptographic provenance for arbitrary callers.

### Exact identity and unchanged query

Only the Provider decodes its existing
`v1:<MixSongID>:<Standard hash>:<Audioid>:<duration seconds>:<Album ID>` context
from the caller's actual KuGou `TrackId`. Known Album and full-duration context
must already be present; no additional Fura Search/detail request fills gaps.
The intercepted `hash` plus `album_id` must match that selection. Supplied
`MixSongID`/`mix_song_id` and `album_audio_id` aliases, with normalized
case/underscore/hyphen spellings, must agree with each other and with its
MixSongID, not Audioid. Missing/conflicting identity or an unsupported alternate
shape such as `audio_id`, `songid` or `encode_album_audio_id` stops as
`OFFICIAL_WEB_TRACK_IDENTITY_UNPROVEN`, not a guessed conversion or second hop.

Preserve the original URL/query unchanged. Optional signature, mid/uuid/dfid,
userid/token, clienttime and profile selectors are not synthesized, repaired or
made mandatory just because a reference client uses them. The old fixed
appid/clientver prerequisite is superseded; no locally generated profile or
signer replaces the official request. Supplied session fields must agree with
the eligible Cookies; unrelated opaque query fields stay unchanged. A local
300-second freshness bound starts at capture and is shortened by an older
captured clienttime when present; it is not a claimed upstream expiry.

### Minimal header and Cookie contract

Replay preserves captured `User-Agent`, `Origin`, `Referer` and, if present,
`Accept`. UA/Origin/Referer are required; Origin is exactly
`https://www.kugou.com` and Referer has that exact HTTPS origin. This supersedes
the historical Fura-UA variation without authorizing a manually forged UA.

Only applicable-domain/path `KugooID` and `t` from the fresh profile's
`Storage.getCookies` form the replay Cookie. Both are required; ambiguity,
session mismatch or composite-only `KuGoo` fails closed. When CDP provides a
captured Cookie header it must contain exactly those same two Cookies: extra
device/analytics/composite Cookies reject the attempt rather than being
silently discarded or blindly forwarded. An absent captured Cookie header does
not prove the browser used no extra context; minimal replay compatibility is
still unproved.

`sec-*` client/fetch hints and language hints are deliberately omitted, as are
browser encoding/transport headers. Arbitrary additional semantic headers such
as Authorization, custom `x-*` signing fields, Range or Content-Type are rejected,
not guessed or stripped. This is minimal replay, not byte-for-byte browser
emulation. The separate API transport remains HTTPS-only with a 256 KiB bound,
no system proxy, redirects or retries; the existing public transport allowlist
is unchanged. Rejection does not authorize adding context or changing profiles.

### Standard tier, three supported format classes

**Standard is not MP3.** Format and quality are independent: the candidate has
`Mp3`, `Ogg` (Opus/Vorbis) and `Mp4Aac` (`m4a`/`mp4`, bounded AAC-LC subset)
format classes. The exact `data.quality == "standard"` rule is an explicitly
**synthetic offline contract**, not live-observed songinfo semantics. Only
absent quality metadata permits the legacy MP3 plus 128/128000 bitrate fixture
to serve as conservative Standard evidence. Explicit null/unknown/higher or
differently cased labels cannot fall back; `audio_name` is not a proved tier
alias. Ogg/MP4Aac Standard fixtures require that explicit synthetic quality
metadata. Source/tests do not establish that live KuGou emits it.

All formats still require explicit non-preview/full-track permission, matching
identity, known full duration and plausible full-file size. Neither a URL nor a
quality label grants entitlement. Unsupported/encrypted formats, raw AAC, FLAC,
unknown quality and quality escalation are excluded; no request negotiates a
higher tier. Extensions and MIME labels alone are not media evidence.

The optional prefix probe requires 206, exact Content-Range/total size,
compatible MIME (or bounded octet-stream) and format-specific signatures within
4096 bytes: two compatible MP3 Layer-III frames after any bounded ID3 tag; a
complete Ogg identification packet/page with CRC; or MP4 initialization with a
sound track and `mp4a` AAC-LC decoder configuration before media data. Malformed,
truncated, encrypted or unsupported layouts fail closed. This bounded subset
does not accept arbitrary media and does not prove audible/full playback or
full-file integrity.

### Response-derived, ephemeral media approval

The old independently preobserved exact-KuGou-host allowlist is superseded. A
validated HTTPS response may yield a new normalized public DNS hostname; no
media request follows automatically. DNS-name checks reject IP/local/reserved
name shapes but are not proof of ownership or resolved-address safety.

`run_gate` reports `NEW_MEDIA_HOST_REQUIRES_APPROVAL` before asking Human to
approve the optional one-range budget for **only that normalized hostname**.
Never display/log the full media URL, path or query. Declining makes no media
request. An approval token is ephemeral and bound to that exact returned source,
not reusable for another source even on the same host. There is no wildcard,
persistent allowlist or automatic trust expansion from a response. The media
probe sends no API Cookie or added account token.

### Current evidence boundary

Current source fixtures cover client construction/identity/headers/Cookies,
Standard Ogg/MP4Aac and legacy MP3 classification, bounded signatures, source-bound
approval, Provider generations/one-shot admission and CDP abort/cleanup paths.
The installed-Chrome runtime fixture is explicitly ignored by default and uses
synthetic local TLS/site data. It was explicitly executed and passes browser
upstream=0, Rust total=1, Range=0 and browser/profile isolation/cleanup. Locked
workspace/all-target tests, affected strict Clippy with and without the opt-in
gate feature, formatting, 122 Flutter authentication tests, three Python
retirement/privacy tests and source privacy/diff checks pass. The candidate
crates pass 53 tests; 29 new KuGou CDP/lifecycle tests and all six unchanged
NetEase Chromium tests pass. **HUMAN_GATE_READY** describes only that offline
Rust-caller machine contract. Historical results below still apply only to their
dated implementation, and no synthetic result proves live compatibility.

Diagnostics are fixed capture-source/presence flags and coarse outcomes, not
credentials, their lengths/hashes, TrackId/hash/title, raw response/media, full
URLs, CDP identifiers or private profile paths. Owned secret buffers have
best-effort wiping, not guaranteed zeroization of every CDP/parser/HTTP copy.
Risk/limit challenges dominate ordinary errors; undocumented codes do not prove
region, copyright or expiry. The Rust entry's boolean describes only the optional
prefix outcome, not full playback or global account verification.

The Human gate remains **NOT_RUN**. Account-summary verification is still false;
production resolution, secure KuGou credential persistence, ordinarily
authorized autonomous request generation, capability/static routing and FRB/UI
integration remain unenabled. Even future source/probe success cannot grant
those scopes. The [maintainer gate](../development/kugou-authenticated-standard-gate.md)
is the current operational contract, with no Human-run command.

## Dated baseline evidence: before the CDP refinement

The remainder records the initial 2026-10-27 protocol investigation and offline
checkpoint. Its clean baseline, source hash, implementation descriptions,
manual-wrapper instructions and PASS counts are **historical**, not claims
about the current worktree. The current contract above supersedes the manual
secret entry, Fura-UA/fixed-profile prerequisites, MP3-only rule and pre-run media
allowlist. Pinned external protocol observations are preserved without new
research or reinterpretation as live Fura evidence.

Date: 2026-10-27. Mode: `HUMAN_DIRECTED / CORE`.
Implementation baseline: `6f67814d3ea9f8db02d47bcea1b69269493c4b71`, clean worktree.
Authority: the Human's **KuGou Authenticated Standard Playback V1** task.
This authorizes static research, independent offline Rust and gate preparation,
not real-account automation, an authenticated network window or production activation.

Verified code/tooling snapshot SHA256 (changed non-Markdown relative name +
NUL + bytes + NUL, sorted):
`fe6bd2979116ab258c071dba3290a7814e07610dd1de8b42eeaaa0f03dd8f736`.

### Historical decision and proof boundary

Prefer **A: the user's isolated official website session → its own signed
`GET https://wwwapi.kugou.com/play/songinfo` request → a strictly checked full
Standard MP3**. The implemented candidate consumes a fresh, exact request
captured by the maintainer; it does not generate signatures or identifiers.

This is intentionally a **capture-only experiment**, not an autonomous
Cookie-to-URL implementation. None of the reviewed source proves that the
website currently issues all necessary context without additional device or
security requirements. No official website assets or KuGou service endpoint
were requested in this task. The old 40/40 anonymous window remains closed.

The concrete next evidence is: the maintainer's isolated website generates this
hash/Album request using its ordinary session; the parameters' website origin
is confirmed; one separately authorized Fura request returns a full Standard
source without a new device/signature challenge. No other route is tried when
this shape fails. A public-Web signer is **not implemented**: public distribution
and purpose of its salt still lack first-party evidence. Passing through the
website's existing signature is not permission to copy that salt into Fura.

### Historical pinned source comparison

All repositories were read as source, never executed or vendored. Sources
outside Git are in the task-local `/tmp/fura-kugou-auth-20261027-YdB9aJ/`.
No real Cookie, account, media URI or personal response is stored there.

| Reference | Exact revision | Observed behavior and limits |
| --- | --- | --- |
| [Aerome](https://github.com/Akilaea/Aerome/blob/26677dbffc91e79c55250267d3a8174c48aed983/server.js#L2843) | `26677dbffc91e79c55250267d3a8174c48aed983` | `parseKugouLoginInfo` derives userid/token from `KugooID`/`t` or the `KuGoo` composite. `handleKugouSongUrl` requires both, signs songinfo and sends Cookie. It separately creates and persists random `mid/dfid`, reuses mid as uuid and presents a Chrome UA. Thus not Cookie-only or evidence of official-issued device context. GPL-derived product; GitHub SPDX is NOASSERTION, so behavior-only reference. Its broader cross-source fallback is excluded. |
| [EchoMusic music API](https://github.com/hoowhoami/EchoMusic/blob/d701691c44a5999524c65518e8fb7374817eb4c1/src/renderer/api/music.ts#L120) | `d701691c44a5999524c65518e8fb7374817eb4c1` | `getUserVerify()` must return auth before `getSongUrl` calls the third-party `/song/url/auth/merge`. It guards an account change between those steps. This is real-client integration code, not a real-account PASS from Fura. GPL-3.0, behavior only. |
| [MakcRe modules](https://github.com/MakcRe/KuGouMusicApi/tree/62730f900dc9fdc51396a663b3d33a6c4c704046/module) | `62730f900dc9fdc51396a663b3d33a6c4c704046` | Echo's `server` gitlink is exactly this commit. `user_verify` → `song_auth` → `song_url_auth` combine session, auth/open_time and Android gateway context. MIT wire-family source; no sidecar or signer port. Echo/MoeKoe do not add independent wire votes. |
| [KugouMusic.NET](https://github.com/Linsxyx/KugouMusic.NET/blob/c63b9cf68b4bd9771d941ec262387eaa4d6f8b4f/src/Libraries/KuGou.Net/Protocol/Raw/RawSongApi.cs#L421) | `c63b9cf68b4bd9771d941ec262387eaa4d6f8b4f` | `SongClient.GetPlayInfoAsync` calls RawSongApi v5; `SignatureHandler` adds session/default parameters, V5 key and general signature. Session manager persists independent token/install identity. Device registration constructs virtual hardware. MIT independent C# cross-check, not a port source. No static proof registration is universally mandatory for every v5 account; missing dfid is locally randomized, which Fura will not copy. |
| [dsh code](https://github.com/kendu76/dsh-music-player/blob/172355b147f91ae994631aa4cbd61adfe8a5fb66/lib/kugou.js), [research](https://github.com/kendu76/dsh-music-player/blob/172355b147f91ae994631aa4cbd61adfe8a5fb66/docs/kugou-integration-research.md) | `172355b147f91ae994631aa4cbd61adfe8a5fb66` | Code tries v5 quality variants then v6 HTTPS/HTTP fallback, registers hardware-shaped identity and refreshes token scope. The research contains both initial “real scan pending” and later selected-track success claims/corrections. Preserve both: they are third-party claims, not a supplied reproducible Fura account trace. It credits MakcRe signing; not independent wire corroboration. MIT. |
| [music-lib login](https://github.com/guohuiyuan/music-lib/blob/6353508e84cd357b5bc3acf32d95a16e01bbe20c/kugou/login.go), [download](https://github.com/guohuiyuan/music-lib/blob/6353508e84cd357b5bc3acf32d95a16e01bbe20c/kugou/download.go), [implementation](https://github.com/guohuiyuan/music-lib/blob/6353508e84cd357b5bc3acf32d95a16e01bbe20c/kugou/kugou.go#L800) | `6353508e84cd357b5bc3acf32d95a16e01bbe20c` | Login obtains token/userid and attempts device registration. Download checks VIP/App-cookie conditions before v5/v6/legacy fallbacks. Separate songinfo path needs `t/KugooID`, reads web mid/dfid and makes **two** songinfo requests via `encode_album_audio_id`. It uses milliseconds rather than Aerome's seconds. AGPL-3.0, behavior only. Do not merge this two-stage identity contract into Aerome's one-call hash profile. |

Important source-level correction: current MakcRe v5 modules specify `notSign`,
but `util/request.js` checks `notSignature`. Source inspection therefore does
**not** establish that these requests omit the general signature. No live
claim is made about that inconsistency. The older dated anonymous report is
retained as historical evidence, not reused as the current contract.
Independence is field-specific: .NET's device-registration comments explicitly
refer to the JS hardware map. A different implementation language is not an
extra independent wire vote; no such count is claimed for music-lib either.

### Historical executable route matrix

| Route | Login/session | Official target/method and shape | Signing/device; HTTPS | Evidence / Fura decision |
| --- | --- | --- | --- | --- |
| A, official-Web songinfo | `KugooID/t` or source's KuGoo decomposition; not a verified account merely by presence | GET `wwwapi.kugou.com/play/songinfo`, hash + Album, token/userid, web profile, timestamp/context, signature; no body. Success status/data include play_url and metadata. | Aerome generates installation-like mid/dfid and signs; website issuance remains unobserved. HTTPS target. | Priority **capture-only offline candidate**. Preserve captured request; no local signer, spoofed hardware or generated device identity. |
| B, user auth → track auth → URL | Provider session token/userid + user auth + track auth/open_time | GET `gateway.kugou.com/v1/user_verify` (`module_id=51`); GET `/v1/authorization` (`authorization`, module, hash, album_audio_id, clientver); GET `/tracker/v5/url` (auth/open_time, Standard quality, exact identities and page/profile parameters). First two use x-router `trackercdngz.kugou.com`. | Pinned modules explicitly select **HTTP** for first two. Common Android envelope/device/signing and randomized dfid. | Second research route, **not implemented**. `/song/url/auth/merge` is an API-server wrapper, not an official endpoint. No speculative HTTPS upgrade or Profile mixing. |
| C, session v5 | Session-owned token/userid; Standard hash + known Album context | GET `gateway.kugou.com/v5/url`, x-router `trackercdn.kugou.com`; quality 128, behavior play, IsFreePart=0, cmd/pid/page/client context; returns URL/backup and media metadata. | HTTPS; .NET V5 key plus general signature, dfid/mid-derived context. Device registration practical dependency is source/flow-specific, not proved universal. | Independent candidate, **blocked on acceptable profile/signing provenance**, not dismissed merely for having appid. No key/salt or fabricated install identity imported. |
| D, priv_url | token, userid, VIP tokens and entitlement | POST `tracker.kugou.com/v6/priv_url`; resource and tracker_param objects, qualities array; response multiple media candidates | Current .NET/music-lib HTTP, dsh tries HTTP fallback; signed hardware/install profile and possible protected media | **Not adopted**. No HTTP or encrypted-media fallback. |
| Legacy anonymous | None | Prior exact-hash probes already failed | Old budget closed | Not repeated; not a prerequisite for authenticated feasibility. |

#### Historical field-specific classification

| Field | Provenance / meaning | Candidate policy |
| --- | --- | --- |
| Standard hash, MixSongID, Audioid, Album | Existing exact KuGou catalog response, not QQ identity | Provider decodes its existing versioned TrackId. No fuzzy lookup or new Search request. |
| srcappid 2919, appid 1014, platid 4, clientver 20000 | Publicly visible nonsecret **profile selectors in reference code**; not proof of Fura authorization or current official-Web distribution | Match only this profile in an already captured website request. Never inject these into a new signed request. A mismatch blocks this candidate, not a reason to rotate profiles. |
| clienttime | Request clock, not a private key/device attestation | Preserve captured seconds or milliseconds; local 300-second age bound, not a fabricated upstream expiry. |
| KugooID/t, KuGoo userid/token | Claimed service-issued login material, account-specific | Pending only. Parser accepts bounded canonical `KugooID/t` from asserted exact website origin. KuGoo-only import is **not implemented**; no arbitrary alias guessing. Caller provenance is not cryptographically established by the constructor. |
| mid/uuid/dfid | Aerome persists locally generated installation-like identities; .NET mixes generated install IDs and server registration; website origin unknown | No Fura generation, hardware synthesis, persistence or registration. Pass through only within the user's captured exact request. Website origin/lifetime is an explicit live prerequisite, not “safe because random.” |
| signature | Web client signing dependency, not itself proof of server authentication | Preserve opaque captured value; validate shape only. No re-signing, embedded salt or private app key. Need first-party distribution evidence before implementing a signer. |
| Android salts/V5 key, hardware payload, kg-* identity headers | Client-profile/access-control or impersonation risk, distinct from ordinary timestamps | Not copied or sent. No App-vs-Web token exchange or device registration. |
| selected media hostname | A returned host is not an allowlist | Human must independently observe and approve one exact KuGou DNS host before the gate. No wildcard, other Provider, IP or response-derived expansion. |

### Historical engineering ownership and limits

`kugou-client::web_playback_candidate` independently implements validated
Pending credential capture, a non-Clone exact signed request, a separate
HTTPS-only transport, typed failure decoding and one optional prefix probe.
The public Transport's host/path whitelist, 2 MiB bound and redirect rules are
unchanged. Candidate transport is smaller (256 KiB), no redirects/retries/
system proxy, with an honest Fura UA rather than a copied Chrome/App identity.
It sends only minimal `KugooID/t` Cookie to the exact API origin; this minimal
Cookie/UA variation is another unverified compatibility condition. A failure
does not authorize adding arbitrary cookies, faking a browser or retrying.

`provider-kugou::web_playback_candidate::AuthenticatedStandardCandidate` is the
only Rust experiment session owner. It stages Pending, consumes one attempt
before await and checks an unforgeable in-process generation token after await.
Logout, Provider retirement, account replacement and same-account relogin
invalidate old results. Restaging cannot reopen the experiment budget. Risk/
rate-limit stops are sticky. Dropped futures spawn no detached operation.
Network/shape/rejection outcomes never claim logout or erase a vault.

No Authentication trait, server-verified AccountSummary, secure storage key,
credential export, production MediaResolver, built-in inventory, Bridge or
Flutter surface is added. Future vault integration must store only this
Provider's verified opaque credential under its own key; it must not persist
these short-lived captured requests. NetEase supplies ownership/isolation
principles only; none of its Cookie names, endpoint or storage owner is reused.

Source success requires status=1, explicit non-preview/free permission,
matching Standard hash, matching any supplied canonical/Album identity,
128/128000 bitrate, MP3 format, full known duration and plausible full file
size. Missing permission/full-track fields are **not inferred** from a URL.
Sources use only the separately approved exact HTTPS media host and MP3 path.
The 4 KiB probe sends no credential and requires 206, the exact Content-Range
and total size, an audio MIME type and compatible Standard Layer-III frame
headers (skipping a bounded ID3 tag). An ID3 label alone is rejected. This does not prove
audible full playback, copyright/region identity or full-file integrity.

Failure classes distinguish missing session, session/context rejection,
purchase/membership indication, preview, other rights denial, risk control,
rate limit, unsupported protocol, unclassified upstream rejection, network,
service outage, invalid input/response, bounds, replacement and consumed budget.
Unknown codes stay unknown; no region, entitlement or expiry code is invented.
The inspected .NET configuration keeps Lite appid 3116/clientver 11440 separate
from its official-App 1005/20489 constants; v5's own request overrides clientver
to 11430. None of those App-profile combinations enter Fura's Web candidate.
In particular 20017/20018 have conflicting token/device explanations in the
sources: they do not authorize deleting credentials or attempting a new profile.
There is no signature verifier: incorrect remote signatures remain coarse
upstream rejection unless an independently evidenced code identifies them.

### Historical HD-031 supplement — DRAFT, not accepted production authority

Proposed maintenance record:

> Extend HD-031 only to independently implemented, offline official-Web session
> and Standard source candidates, plus a separately authorized, maintainer-run
> disposable gate. Credentials, Track identity, vault and lifecycle remain
> KuGou-specific. No fake hardware, private signing material, risk bypass,
> mutation, cross-Provider fallback or production integration is authorized.
> Captured-request success is not permission to implement an automatic signer
> or ship the Provider. Each live budget and production activation requires
> explicit Human authority.

The task itself authorizes the current offline work. This draft does not edit
HD-031's accepted text or declare authenticated production use accepted.

### Historical machine evidence

Baseline existing KuGou tests passed (20 offline; one live test ignored).
New tests exercise real request construction and typed response decoding,
missing/unsafe/foreign credentials, exact identity/context/clock, permission,
preview, missing/HTTP/foreign URLs, encrypted/nonstandard formats, duplicate
authorization fields, challenge-first parsing, bounds and redacted Debug.
Provider tests cover one-shot/concurrent/cancelled attempts, expired captures,
logout/Provider replacement/account replacement/same-account relogin, sticky
challenge/limit and network failure without logout.

The explicitly invoked loopback TLS test uses only synthetic identities and
locally generated temporary certificates; DNS for both test hostnames is
overridden to `127.0.0.1`. It exercises actual reqwest, validates certificates,
Cookie scope, redirect refusal, 403/429/SSA, response bounds and correct/wrong
Range responses. Its first fixture used a CA certificate as the leaf and failed
with Network; changing only that synthetic certificate to an end-entity
certificate made the checks pass. No TLS verification is disabled. This local
fixture failure is not a KuGou server result. Python/OpenSSL-dependent test is
ignored by default and must be invoked explicitly; the real-service test stays
ignored and was **not** run.

The manual wrapper defaults to NOT_RUN and refuses noninteractive authorization
or an echoing getpass fallback. Consent precedes collection, sensitive fields
never enter argv/environment/files, Cargo runs before collection, output is
fixed-schema and unexpected child output is suppressed. Memory buffers are
short-lived; no claim of cryptographic zeroization of all runtime copies.

Validation: 34 Rust offline tests pass under the required locked all-target
command; two default ignores are the pre-existing real-service probe and the
separately invoked Python/OpenSSL loopback fixture. The latter passes explicitly
(35 distinct Rust tests exercised). Four Python authorization/privacy tests,
strict all-target Clippy, Rust format, source privacy, identity and whitespace
checks pass. Both tool default entries return NOT_RUN. Commands and final
results are also recorded in PROGRESS. No QQ/NetEase,
macOS/Windows/AppImage/workflow, UI, Provider API or Bridge production change.
No account was accessed or KuGou service request sent. The implementation phase
performed no commit/push. Human subsequently authorized a normal Git checkpoint
and push, not the live gate, production activation or a manual Actions run.
Final Rust and loopback outputs are `final-rust-tests.log` and
`final-loopback-tls.log` in the task-local temporary evidence directory above;
they contain synthetic/offline results, not service/account evidence.

### Historical state

| Claim | State | Proof boundary |
| --- | --- | --- |
| KUGOU_AUTHENTICATED_PROTOCOL_RESEARCH | PASS | Pinned code-level comparison and executable route decision, not a live protocol PASS. |
| KUGOU_STANDARD_MEDIA_OFFLINE_CANDIDATE | PASS | Capture-only Rust construction/decoder/owner and bounded tools; no autonomous signer. |
| KUGOU_HUMAN_PLAYBACK_GATE | NOT_RUN | No separate account/network authority; first-party context and real permission/URL remain unobserved. |
| KUGOU_PRODUCTION_MEDIA_RESOLVER | BLOCKED | No live source proof, verified-account/vault integration or production authority. |
| KUGOU_FLUTTER_INTEGRATION | NOT_RUN | Intentionally outside this offline task; QQ/NetEase-only composition unchanged. |

See the [maintainer gate](../development/kugou-authenticated-standard-gate.md)
for the superseding Rust-caller prerequisites, budget and hard stops, not the
retired manual-wrapper workflow. No command performs the Human run.
