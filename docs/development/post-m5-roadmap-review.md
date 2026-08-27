# Post-M5 Roadmap Review — 2026-08-27

## Ranking outcome

M5 checkpoint completion did not itself create a new feature requirement. The next work is selected from risks and evidence already recorded by the M5 completeness audit.

1. **Anonymous comments/MV live compatibility — Selected.** Both are implemented first-release capabilities with current independent source evidence and full offline coverage, but neither direct project operation has been exercised against the live anonymous service. A bounded opt-in probe can reduce a real compatibility risk without credentials, product expansion, or returned-content retention.
2. **M1 authenticated playback/Queue/Lyrics observation — Higher intrinsic value, not currently executable by the agent.** It remains user-operated and immediately preempts M6 when the maintainer supplies a coarse secret-safe result.
3. **Additional platform/release evidence — Not currently executable.** Physical Android and Apple/Windows need their real environments; production identity/signing and native-video notice assembly remain blocked by HD-001/TD-006. Existing Linux and emulator evidence does not justify emulation or broader claims.

No cache, fallback/local Provider, background playback, history persistence, mutation, Focus experience, or new catalog feature is selected: current governance requires evidence or human authority that does not yet exist.

## Selected finite milestone

M6 Core Compatibility Evidence is intentionally narrow. M6.1 adds default-ignored live tests for one anonymous comment page and one exact Track-associated MV path. Tests assert only coarse structural invariants and must never print or retain returned comment text, author identity, MV metadata/identity, artwork, response bodies, or media source. Any protocol correction requires a repeatable observed discrepancy and an offline regression; otherwise the implementation remains unchanged.
