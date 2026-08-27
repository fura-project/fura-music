# First-Release Core Capability Checkpoint — 2026-08-28

## Conclusion

The current reusable Core can support the already authorized mainstream QQ
Music-first UI without inventing data or feature semantics, provided later
presentation preserves the explicit blocked and unverified-live boundaries in
the capability audit.

This is a Core-capability checkpoint. It is not M1 real-account acceptance,
M7 visual acceptance, remote-mutation acceptance on the maintainer's account,
cross-platform release readiness, or a claim that every currently generated
gateway already has product UI.

## Whole-product capability review

| Product area | Core readiness for later UI | Exact boundary |
| --- | --- | --- |
| Account | QR authentication, restore/verification, replacement/sign-out, and bounded account summary have typed reusable paths. | Account-summary presentation is deferred; additional login methods are Later. |
| Home | Public playlists, Daily 30, personalized playlist discovery, and one bounded personalized Track set are truthful reusable capabilities. | Popular Programs requires a product decision. One personalized Track result cannot be disguised as two semantically distinct products; authenticated availability and quality remain unobserved here. |
| Library | Complete playlist reads, liked songs, favorite Albums/Artists, liked-Track state, owned-playlist Track membership, playlist create/delete, and Album favorite state have bounded contracts. | Playlist rename and Artist follow writes remain evidence-blocked. Mutation confirmation, refresh, UI, and maintainer-account acceptance remain later work. |
| Search and Discover | The four Search types plus playlist/Album/Artist details, recommendations, rankings, Radar, and new Songs/Albums remain typed and independently retained. | Broad live-catalog quality and deferred convenience searches are not claimed. |
| Playback and Queue | Foreground source resolution, Standard/High negotiation, one positional Queue owner, playback modes, seek, volume, failure recovery, and source replacement are implemented and regression-covered. | M1 authenticated QQ playback remains maintainer-observed evidence; background/system media sessions require a human product decision. |
| Lyrics | Synchronized/QRC and word timing can be driven by the single foreground playback position. | The playback-to-synchronized/word-timed real-account observation remains pending. |
| Comments and MV | Bounded read-only comments and one exact Track-associated MV contract exist, with local Linux media lifecycle evidence. | No social mutation, generic video product, remote MV playback claim, or unavailable target-runtime claim is added. |
| Settings | A versioned local model persists the existing Theme and Standard/High quality preferences and drives startup composition. | The Settings page is intentionally deferred; speculative preferences are absent. |
| Platform | Focused-app shortcuts, Linux storage/audio/video, Android x64 storage, and bounded Android development packaging have named evidence. | Physical Android and Apple/Windows runtime evidence remain environment-blocked; release identity and native-video notices remain release-gated. |

## Remaining blocked capabilities

- `EVIDENCE_BLOCKED`: playlist rename; current discovery found only one detailed
  write contract.
- `EVIDENCE_BLOCKED`: Artist follow/unfollow; read-side behavior does not prove
  write semantics.
- `EVIDENCE_BLOCKED`: M1 authenticated QQ playback → Queue → synchronized
  lyrics → word timing; only the maintainer can safely supply the current
  account observation.
- `ENVIRONMENT_BLOCKED`: physical Android plus Apple/Windows storage and media
  runtime claims.
- `HUMAN_DECISION_REQUIRED`: Popular Programs, because a spoken-audio root may
  conflict with the podcast/general-media non-goals.
- `HUMAN_DECISION_REQUIRED`: background playback/system media session, because
  it introduces a material lifecycle and platform architecture.
- HD-001 continues to block production identity, signing, distribution, and
  the release-time native-video notice package.

Implemented remote-write contracts have independent protocol evidence and
strict offline lifecycle coverage, so the reusable Core boundary is ready.
They have not mutated the maintainer's account. Later UI must confirm
destructive intent, refresh after confirmed or uncertain outcomes, and leave
real-account acceptance to the maintainer.

## Architecture and scope review

- QQ protocol remains in `qqmusic-client`; Provider identity and account
  generation checks remain in `provider-qqmusic`.
- Provider contracts and Domain summaries remain UI-free and provider-neutral.
- The generated Bridge remains typed, coarse, cancellable, and free of raw
  responses, credentials, radio feedback, or presentation composition.
- Dart gateways own generated-DTO validation and serialized vault cleanup only
  after explicit rejection. No page-level visual work was added.
- No Provider, sidecar, state/navigation framework, generic paging system,
  background service, download product, social mutation, or generic video
  surface was introduced.
- The six requested Home rows do not become six fabricated Core products:
  Popular Programs remains blocked, and two listening-related rows may reuse
  one capability only when that reuse is transparent.

## Validation

- Rust formatting passes.
- 372 offline Rust tests pass; 6 live QQ tests remain default-ignored.
- Strict workspace all-target Clippy passes.
- Dart formatting and analysis pass.
- 385 Flutter tests pass.
- Linux x64 Release packaging passes.
- Packaged Linux Bridge, secure-storage, Settings-storage, local/loopback audio,
  and local MV integrations pass.
- Generated API comparison contains only the expected Rust-only `mod` and
  private `remote_mutation` modules.

These gates prove the named offline/local contracts. They do not prove live QQ
recommendation usefulness, authenticated CDN playback, remote writes on the
maintainer's account, physical-device behavior, or release readiness.

## Scheduling consequence

The first-release Core capability workstream meets its finite checkpoint
criteria: no required executable capability remains `MISSING`; every remaining
gap has an exact evidence, environment, or human-decision boundary.

The checkpoint satisfies HD-008's Core-readiness precondition but does not
silently resume UI implementation. The current Home snapshot still needs
maintainer visual acceptance, and the current directive requires subsequent UI
work one page at a time under separate human visual direction. No additional
agent-only Core feature is created to keep development moving.
