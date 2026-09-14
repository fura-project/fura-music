# NetEase Remaining Work Audit

Date: 2026-09-12. Authority: HD-023 + HD-024 plus the Linux Human regression. Execution: `HUMAN_GATED_REGRESSION / MIXED`.

2026-09-14 addendum: Human runtime evidence rejected the embedded Linux WebKit
candidate after native EGL/DMABuf and GStreamer failures disconnected Flutter.
Embedded Android/Linux browser code is removed. Generic external-browser login
cannot return isolated cookies without provider OAuth. The replacement hands
the current QR's exact official scan-confirmation URL to the system browser or
NetEase app while its Rust session continues polling. URL validation,
cancellation and secret-free diagnostics are machine tested. Real OS routing,
provider confirmation and restart persistence remain
`HUMAN_EVIDENCE_REQUIRED`; this addendum does not change the final
`HUMAN_REVIEW` gate below.

This is the required final-stop audit. `DONE` means the authorized machine-verifiable implementation/evidence boundary is complete; it never promotes real-account, unavailable-host, playback, UI, or release evidence. This regression adds only the explicitly authorized NetEase phone-code form and its typed lifecycle; pre-existing QQ and unrelated Flutter working-tree edits remain preserved.

## Core hardening

| Item | Classification | Evidence / exact boundary |
|---|---|---|
| Canonical repository metadata | DONE | Canonical remote `fura-project/fura-music` was verified at the starting commit; workspace `repository` no longer points to the former personal URL. Internal crate/package IDs were intentionally retained. |
| One native NetEase Provider owner | DONE | Private `native_netease_provider()` is the only native initializer; media borrows it. Pointer-identity test plus provider session/media state tests prevent a second hidden owner. QQ owner and failure boundary remain independent. |
| QR confirmed transient recovery | DONE | Confirmed credentials become pending before account validation. Network/timeout/service retry retains pending; rejection, sign-out and replacement clear it; stale validation cannot install; pending cannot authenticate media or export. |
| QR browser-session correction | HUMAN_EVIDENCE_REQUIRED | Web `type=1`, scan-login URL, shared browser cookie/chain context, response-body/Set-Cookie credential extraction and explicit 8821 mapping are locked by request-shape tests. Anonymous challenge/801 passes; Human 802/803/account/persistence is not yet accepted. |
| Phone-code login candidate | HUMAN_EVIDENCE_REQUIRED | Mobile-EAPI send/login, encrypted response decoding, typed rejection/rate-limit/8821 results, active-operation plus completed-session cancellation and pending account verification are implemented and offline tested. Agent sent no SMS; Human must verify delivery, code acceptance, account correlation and vault persistence. |
| External QR-confirmation handoff | HUMAN_EVIDENCE_REQUIRED | 8821 and 8830 remain explicit STOP states. The generic web-login button and embedded WebViews are removed. During an active QR session, Fura can externally open only the exact validated official scan-confirmation URL while the same Rust session keeps polling. Human must verify OS/app routing, confirmation, credential acceptance and restart persistence. |
| Flutter artwork HTTP correction | HUMAN_EVIDENCE_REQUIRED | Human logs isolated real CDN HTTP 403. The duplicated `NetworkImage`/Dart User-Agent was reproduced; one default User-Agent plus host-scoped Referer returns HTTP 200 in the bounded live probe. Rebuilt application rendering remains Human review. |
| Human account-read harness | DONE | New ignored, explicit-opt-in, read-only, serial harness compiles. Exact 72-request ceiling; no names/IDs/cookies/bodies/URIs logged; no source body download. Agent did not run it. |
| Native Linux/Android packaging | DONE | Current worktree built Linux Release and one ARM64 Android debug APK containing the native Rust library. This is build evidence, not device runtime or release evidence. |
| Windows/macOS/iOS current build | ENVIRONMENT_EVIDENCE_REQUIRED | Target dependency graphs resolve with the existing rustls/reqwest/getrandom stack, but the host lacks those compilers/SDKs. No current-ref remote workflow can run without publishing the local commits, which is prohibited. |

## Large collections

| Item | Classification | Evidence / exact boundary |
|---|---|---|
| Public Playlist over 1,000 | DONE | Deterministic 1,001-row paging test and a separate anonymous three-request live gate reading raw offset 1,000 both pass. No full Track-detail drain. |
| Liked IDs over 1,000 | DONE | Synthetic authenticated 1,001-ID route preserves exact liked identity, raw cursor/order and at-most-100 detail selection. Real account observation remains separately Human-gated. |
| Album over 1,000 | DONE | Deterministic 1,001-song Album window passes; over-budget fixtures fail explicitly. Upstream still returns whole Album content. |
| Bounded identity strategy | DONE | 2 MiB response cap derives 16,384 bare identities at 128 bytes of memory policy per row and 4,096 Album rows at 512 bytes per richer row. Duplicate/identity/body checks remain strict; no silent truncation. |
| Repeated whole-metadata cost | HUMAN_EVIDENCE_REQUIRED | TD-011 records possible distant-page latency. A generation-bound cache is not justified until real usage demonstrates the cost or a true server cursor is evidenced. |

## Provider-neutral read parity

| Item | Classification | Evidence / exact boundary |
|---|---|---|
| Track Comments | DONE | Exact `R_SO_4_<track>` read, offset/limit/total/more, latest comments and initial hot comments, bounded/redacted mapping, valid empty and malformed/duplicate tests; anonymous gate passed. |
| Related Tracks | DONE | Exact `simiSong` seed, at most 50 results, seed/duplicate rejection and TrackSummary mapping; anonymous gate passed. No history/autoplay/fuzzy/cross-provider claim. |
| New Songs | DONE | Bounded whole response, no fake cursor. Latest(All), Western, Japan and Korea map exactly; narrower Chinese-region values reject before transport. Anonymous gate passed. |
| New Album Releases | DONE | Real offset/limit/total pages for Western/Korea/Japan. Incompatible existing region values reject before transport; raw publish time is retained client-side but no timezone/display date is fabricated. Anonymous gate passed. |
| Track-associated MV | DONE | Exact Track detail `mv` to MV detail to one requested-1080 source; exact 0/1 semantics, actual returned profile, HTTPS/authority validation and redaction. No media body fetch. Anonymous gate passed. |
| Provider capability advertisement | DONE | `Comments` and `MusicVideo` are advertised only after complete trait mapping/tests. Existing Catalog/Recommendations cover the other three reads. `RecentHistoryRead` remains absent. |
| Recent History research | EXTERNAL_BLOCKED | Current references expose `play-record/song/list` with only a limit and `pc/recent/listen/list` with no input. Clear ordinary-session paging/continuation evidence is absent; no QQ semantics, write route or device impersonation is reused. |

## Validation

| Item | Classification | Evidence / exact boundary |
|---|---|---|
| Targeted deterministic tests | DONE | Singleton, pending credential lifecycle, over-1,000 collections, Comments, related Tracks, new songs, new Albums, MV, URI/redaction and capability tests pass. |
| Anonymous read-parity live gate | DONE | One serial nine-request-maximum gate used eight requests and passed all five new capabilities plus seed Search. |
| Anonymous large-Playlist live gate | DONE | One serial three-request-maximum gate passed above the former 1,000-row boundary. |
| Live risk STOP | NOT_APPLICABLE | Neither executed anonymous window returned HTTP 429, access-control, security-verification or risk abnormality. No authenticated gate ran. |
| `cargo test --locked --workspace` | DONE | Final workspace test gate passes; exact aggregate is recorded in the final report. |
| `cargo test --locked --workspace --all-targets` | DONE | Final all-target host gate passes; ignored live/Human tests remain opt-in. |
| `cargo fmt --all -- --check` | DONE | Final format gate passes. |
| Strict workspace/all-target Clippy | DONE | Final `-D warnings` gate passes after removing one identity error-map warning. |
| Flutter shared authentication gate | DONE | Pinned FRB generation, 248-file Dart format, `dart analyze` and all 567 Flutter tests pass, including phone-code success/retry/8821/cancel/dispose and compact form interaction. |
| Linux Release | DONE | `flutter build linux --release` produced the x64 bundle. No runtime/user-account claim. |
| Android development build | DONE | `flutter build apk --debug --target-platform android-arm64` produced an APK with `lib/arm64-v8a/librust_lib_flutterustmusic.so`. No physical-device claim. |
| Remote cross-platform workflow | ENVIRONMENT_EVIDENCE_REQUIRED | Workflow exists, but current local commits cannot be selected without push; HD-024 forbids push. |
| FRB generation/orphan audit | DONE | Typed security-verification and phone-code request/login/cancel surfaces are present; pinned FRB 2.13.0 generation completed and generated Dart/Rust surfaces agree. |
| Documentation consistency | DONE | HD-024, architecture, roadmap, progress, technical debt and protocol/auth/audit evidence distinguish machine, Human and environment results. |
| Complexity review | DONE | Two focused client modules and one provider mapping module; no service locator, registry, Provider-specific Domain trait, sidecar, runtime plugin, UI state, fallback or source substitution. |

## Remaining Human and product boundaries

| Item | Classification | Exact boundary |
|---|---|---|
| QR/account/library/favorites/recommendations source authorization | HUMAN_EVIDENCE_REQUIRED | Explicit Human-only matrix exists and was intentionally not run by the Agent. Two Human application attempts now identify explicit 8821 after 802; Web QR 803/account/persistence remains unproven. |
| Phone-code delivery and account authorization | HUMAN_EVIDENCE_REQUIRED | Use the rebuilt UI with a Human-controlled number and code. Record only typed phase/outcome; never share the number, code, cookie or response body. STOP on 8821/rate limit and do not resend automatically. |
| Actual liked collection over 1,000 and latency | HUMAN_EVIDENCE_REQUIRED | Synthetic correctness exists; account-specific size/content/performance does not. |
| Actual authenticated standard media | HUMAN_EVIDENCE_REQUIRED | Only request/decoder/generation fixtures exist; no account entitlement or playback claim. |
| Phone-code UI and native-vault runtime | HUMAN_EVIDENCE_REQUIRED | The authorized responsive form, typed outcomes and existing namespaced vault handoff are implemented and machine-tested. Human must accept the actual compact/desktop presentation and verify a real successful login persists across a clean restart. |
| Writes, history report, cross-provider matching/substitution, third Provider, bypass | NOT_APPLICABLE | Explicitly excluded. No code or live action was added. |

## Final-stop answers

1. A second native NetEase owner: **no**; all native edges have one private owner.
2. QR confirmed plus transient verification forcing a new scan: **no**; pending retry is retained.
3. Safe Human read entry: **yes**; compiled, ignored, explicit, bounded and unrun.
4. Native validation: **maximum available local evidence complete**; unavailable hosts remain environment-gated.
5. Large collection boundary: **explicit and evidence-backed**; no silent 1,000-row truncation.
6. Comments, related Tracks, new songs, new Albums and MV autonomous work: **none remaining** under current contracts.
7. Recent history autonomous implementation: **none justified** without external pagination evidence.
8. Task-caused test/build failures: **none** after final reruns.
9. Documentation drift: **none known**; protected pre-existing working-tree edits remain intentionally uncommitted.
10. Additional provider-neutral mapping: **none supported by current evidence and authority**.

Final audit: no item remains in the autonomous-work classification. Remaining items require explicit Human account/visual action, unavailable target environments, external protocol evidence, or a new product decision. The correct stop gate is `HUMAN_REVIEW`, not `COMPLETE`, because real-account reads and authenticated source behavior remain unverified.
