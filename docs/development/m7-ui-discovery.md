# M7 UI Discovery — 2026-08-27

## Reference synthesis

Current QQ Music desktop references consistently use a persistent left navigation region, a prominent top Search entry, a broad artwork-led content canvas, green accents over neutral light/dark surfaces, and a persistent bottom player. Mobile references retain bottom primary navigation and emphasize content/artwork rather than desktop toolbar density. M7 translates those conventions into official Flutter Material 3 without copying QQ branding, promotional artwork, or unsupported feed data.

## Ranked candidates

### 1. Authenticated Shell and truthful Home first impression — Selected

- **Provenance:** HD-004; M7 exit criteria 1–3; maintainer report that the UI appeared essentially unchanged apart from playback order.
- **User value:** The application becomes recognizable as a deliberate music client immediately after login rather than only after discovering deep routes.
- **Current problem:** Wide layout uses a default narrow `NavigationRail`, the AppBar has no persistent Search affordance, and Home is three visually equal launcher cards with no strong listening/library hierarchy.
- **Scope:** Wide-only branded-but-generic sidebar treatment, top Search shortcut, and a responsive truthful Home hero plus existing destination cards. Compact bottom navigation and every existing callback/controller remain intact.
- **Acceptance criteria:** At wide desktop the sidebar is deliberate and labeled, Search is directly reachable from the top, Home has a clear primary listening/library action plus Discover/Search secondary destinations, 360 px has no overflow, and keyboard/touch activation reaches the exact existing destinations.
- **Effort:** Medium.
- **Risk:** Crowding medium widths, duplicating navigation semantics, misleading users with decorative fake content, or losing retained/focus behavior.
- **Explicit non-goals:** New Home data/API, personalized shelves, promotions, account profile, navigation rewrite, QQ logo, or playback changes.

### 2. Library and core browsing hierarchy/density

- **Provenance:** M7 exit criterion 4 and the high-frequency personal-library journey.
- **User value:** Playlists, Albums, Artists, and dense Track rows become easier to scan and feel like one music collection.
- **Current problem:** Individual surfaces share some components but page headers, section controls, artwork scale, metadata, and desktop density still read as separately accumulated screens.
- **Scope:** Library section framing plus Playlist/Album/Artist shared visual grammar over existing controllers and routes.
- **Acceptance criteria:** Consistent headers/actions, artwork-led collections, dense desktop Tracks, compact reachability, playing/context states, and retained return all pass focused regressions.
- **Effort:** High.
- **Risk:** Large cross-page diff, density regressions at 360 px, and accidental controller/navigation churn.
- **Explicit non-goals:** Mutation, new metadata, selection systems, or generic design-system framework.

### 3. Now Playing and Lyrics product presentation

- **Provenance:** PROJECT core experience; M7 exit criterion 4; current playback surface is the emotional center of a music client.
- **User value:** Artwork, transport, Queue, MV/comments, and synchronized lyrics feel intentional rather than like adjacent controls.
- **Current problem:** Expanded Now Playing is functional but still relies on generic gradient/panel composition and exposes secondary capabilities with equal visual weight.
- **Scope:** Presentation hierarchy and responsive composition over the existing one Queue/music/lyric/MV ownership model.
- **Acceptance criteria:** Clear artwork/track/transport/lyric hierarchy, appropriate compact/wide layouts, secondary actions remain discoverable, and all playback/seek/focus/semantic regressions pass.
- **Effort:** Medium to high.
- **Risk:** Playback-control regression, visually overwhelming lyric content, or expensive effects on Linux.
- **Explicit non-goals:** New audio behavior, artwork-derived global palette, visualizer, shader, gestures, fullscreen/PiP, or engine changes.

## Selection

Candidate 1 is selected because it addresses the maintainer's direct first-impression evidence, establishes the composition used by every later page, and can be completed without new product data or architecture. Candidates 2 and 3 remain ordered hypotheses until the first slice is manually reviewed.
