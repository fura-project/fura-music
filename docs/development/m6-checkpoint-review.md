# M6 Core Compatibility Evidence Checkpoint — 2026-08-27

## Outcome

M6 is checkpoint-ready. Two explicit, default-ignored tests now exercise one anonymous public-catalog comments page and one exact Track-associated MV operation directly through `QQMusicClient`. Both gates pass with no account credential, Cookie, vault access, persisted response body, returned comment/author identity, MV identity/metadata/artwork, or media-source retention.

This is deliberately narrow protocol evidence. It is not a full Flutter application observation, broad catalog/content-quality sample, authenticated behavior, remote MV playback test, future service guarantee, release-readiness claim, or substitute for the open M1 user-operated playback/Queue/Lyrics observation.

## Exit-criteria evidence

1. **Explicit gated tests — Pass.** `live_comments` and `live_music_video` are normal Rust integration targets, carry `#[ignore]`, and run only when `QQMUSIC_LIVE_TESTS=1` is supplied explicitly. The default workspace suite performs no network request.
2. **Comments structural invariants — Pass after bounded reconciliation.** The selected public page maps successfully and validates offset, bounded hot/newest row counts, total/count consistency, nonempty newest content, and redacted value diagnostics. Returned content and identities exist only transiently for assertions and are neither printed nor written to fixtures or project state.
3. **MV association/source invariants — Pass.** The selected public Track still exposes one exactly correlated MV with bounded display metadata, positive duration, and an HTTPS source chosen by the existing MP4 policy. The source is not downloaded or played, and returned identity, metadata, artwork, and URI are neither printed nor persisted.
4. **Coarse redacted diagnostics — Pass.** Live output contains only test names and pass/fail state on success. Page, comment, and MV Debug assertions prove returned private/content-bearing fields are absent. Protocol errors continue to expose phase/field/index rather than body or values.
5. **No account material — Pass.** Both tests instantiate a fresh anonymous native HTTPS client and use only checked-in public catalog identity. No stored credential, Cookie, account endpoint, personal fixture, or platform vault entry is read or changed.
6. **Offline baseline — Pass.** Rust formatting passes; all 300 offline Rust tests pass with six live tests ignored; strict all-target Clippy passes. Dart formatting and analysis pass, and all 336 Flutter tests pass. M6 changes no Domain, Provider, Bridge, Dart, dependency, native adapter, or generated binding.
7. **Failure-budget discipline — Pass.** The comments gate supplied new coarse structural evidence on each failed run rather than repeating the same guess. The first discrepancy proved comment IDs are not necessarily numeric. The second proved a newest row can contain present-but-blank content. Each produced one minimal offline regression and correction; the third comments run passed. The MV gate passed on its first run. No fourth speculative attempt or endpoint change occurred.

## Evidence-backed corrections

- Comment IDs are accepted as either nonzero numbers or bounded, nonblank, control-free opaque strings. They remain provider-owned and redacted; no grammar is inferred from the observed value.
- A present-but-blank newest comment row is filtered as deleted/non-displayable. Missing or oversized content remains structural failure, blank hot-comment tolerance is deliberately not inferred, and pagination uses the raw newest-row count before filtering.

No returned service value from discovery was copied into a fixture, Markdown file, log, or commit.

## Architecture and scope review

- The change remains inside `QQMusicClient` raw protocol parsing plus its tests. Provider-neutral Domain values, Provider mapping, the typed Bridge, Flutter controllers, comments presentation, MV presentation, and both media owners are unchanged.
- No QQ protocol moved into Dart, no presentation state moved into Rust, no sidecar or Provider was added, and no new feature or dependency entered M6.
- The MV probe stops after source mapping. It does not involve `media_kit`, foreground music arbitration, Queue behavior, download, cache, fullscreen, PiP, related videos, or video Search.
- The comments probe remains read-only. It does not authorize posting, liking, reply, report, profile, or social-platform work.

## Remaining boundaries

- M1 still needs one coarse user-operated observation of corrected authenticated QQ playback, Queue navigation, synchronized lyrics, and word timing. M6 did not read or automate stored account material.
- One public comments page does not prove broad catalog coverage, content quality, authenticated differences, or long-term endpoint stability.
- One public Track-to-MV mapping does not prove broad MV availability, expiring-source playback, CDN transport through the Flutter adapter, hardware decode, audio focus, physical Android, or Apple/Windows runtime behavior.
- Production identity/signing remains locally blocked by HD-001, and MV-capable release notices remain tracked by TD-006.

## Post-checkpoint scheduling

M6 checkpoint completion returns to whole-project ranking. A next milestone is legitimate only if current product authority, repository evidence, and available execution environment support a bounded outcome. The checkpoint itself does not manufacture M7. `global_stop` remains false while M1 remains locally pending and evidence-gated Later Direction remains available for future substantiated work.
