# M4 Post-Polish Global Ranking — 2026-08-27

## Ranking boundary

This whole-project ranking follows the bounded M4.6 audit and the completed Favorite Album/Artist state-language slice. It rechecked the active Roadmap, current blockers and risks, technical-debt triggers, accepted/pending Human Decisions, the authenticated shell breakpoints, and the existing compact/wide/resize regression evidence. It did not access QQ Music, stored credentials, unavailable target hardware, or deferred theme-persona work.

## Current evidence

- The audit's only directly reproduced integrated Material/accessibility gap is closed with focused and full validation.
- The authenticated shell switches saved-collection actions at 520 px and primary `NavigationBar`/`NavigationRail` presentation at 840 px. Existing regressions prove 360 px action reachability, a retained compact-to-wide transition, wide keyboard activation, focus restoration, and no layout exceptions. No failure at either exact threshold has been reproduced.
- Turning every numeric presentation threshold into a matrix would test implementation detail without new user evidence. A future exact-boundary regression remains legitimate if a resize, reachability, retention, or overflow failure is reproduced.
- M1's authenticated playback/queue/lyric observation remains user-operated and locally scoped. TD-001 and TD-005 triggers are unchanged; TD-002 remains locally blocked by HD-001; unavailable Apple/Windows instances of TD-004 do not displace executable review work.

## Ranked candidates

### 1. M4.7 checkpoint review — selected

- **Provenance:** M4.7 and M4 exit criterion 7.
- **User value:** determine whether the integrated default Material baseline is coherent and stable, expose any remaining high-value gap, and preserve exact evidence limits before later direction is considered.
- **Current problem:** twelve finite M4 slices and the cross-platform audit have been individually validated, but the workstream has not yet received one criterion-by-criterion checkpoint, architecture/scope review, and debt-trigger review.
- **Scope:** assess all seven M4 exit criteria against repository evidence; review architecture boundaries, accessibility/adaptive regression evidence, scope drift, technical debt, Human Decisions, and live/platform limitations; fix only a blocking discrepancy discovered by the review.
- **Acceptance criteria:** every criterion has an evidence-backed pass or an explicit blocker; no untracked high-value Material gap remains; test and build evidence is stated precisely; M1, unavailable platforms, signing, live QQ, and deferred themes are not overclaimed; checkpoint completion returns to global task selection.
- **Effort:** Review.
- **Risk:** mistaking broad automated coverage for manual all-platform visual validation, or treating the checkpoint as project completion.
- **Explicit non-goals:** new UI implementation, breakpoint changes, theme personas, release work, live account access, Provider/Bridge/Rust changes, or a new product direction.

### 2. Exact shell threshold regression — deferred pending evidence

- **Provenance:** M4.6 and M4 exit criteria 2–4.
- **User value:** detect a future reachability, retention, or overflow regression immediately around a product-critical shell transition.
- **Ranking reason:** representative compact/wide/resize tests already pass and no exact-threshold failure is reproduced. Adding a numeric matrix now would be lower-value and more brittle than reviewing the integrated product.
- **Trigger:** a reproduced issue at or adjacent to 520/840 px, or a shell refactor that changes those boundaries.
- **Explicit non-goals:** enumerating every page-local breakpoint or changing thresholds for visual uniformity.

### 3. M1 real-account observation — retained local blocker

- **Provenance:** M1 acceptance.
- **Ranking reason:** it remains required evidence but must be performed by the user with a real account. It does not authorize credential access or block M4 review.

## Selection

M4.7 checkpoint review is the highest-value legitimate task. The repository has no reproduced shell-threshold failure to justify implementation, while a bounded integrated review is explicitly required before the default Material baseline can checkpoint.
