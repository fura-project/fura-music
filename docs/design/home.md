# Home Design Source

**Status:** Human Approved

**Approval date:** 2026-08-28

## Stitch identity

- **Project:** `3692648008202843392` — Melodia for QQ Music
- **Desktop screen:** `4c16572ce333440883482fbc7c4314d0` — 首页优化 - flutterustmusic (高密度桌面版)
- **Mobile screen:** `08d3ac0bb0934ce1a06db6bef58ce170` — 首页 - flutterustmusic (移动端正式版)

These frames are the visual source of truth for the current Home implementation. Temporary Stitch PNG/HTML exports are implementation artifacts and are not repository assets.

## Human constraints

- The desktop Sidebar remains a persistent top-to-bottom application structure beside the Main Region; the Main Region owns its Top Bar, page content, and active player.
- Mobile uses a separate Mini Player and Bottom Navigation composition rather than compressing the desktop Shell.
- Material 3 remains the component language while the approved composition controls visual hierarchy and geometry.
- Production content must remain truthful to Provider, Domain, account, recommendation, and availability semantics.
- Grey or missing artwork in the approved frames reflects unavailable design assets only. Supported production slots render the exact Provider result and its artwork when supplied; the application uses a neutral fallback only when a real result has no usable artwork.
- Popular Programs is intentionally absent from the first-release Home; no unavailable placeholder, podcast surface, or unrelated substitute is shown.
- `More from your listening` is distinct from the authenticated personalized Track shelf. The 2026-09-08 Human follow-up supersedes the current-queue-only seed: use actual recent listening, preserve one set through Track changes, and visibly identify the selected seed. Empty recent history must remain truthful.
- No QQ Music branding, proprietary artwork, promotional content, or exact trade dress is copied into the project.

Home remains pending maintainer visual acceptance. This record preserves source identity; it does not itself establish visual completion.

## 2026-09-08 recommendation regression candidate

The Human supplied four Fura/official QQ screenshots and requested signed-in vs guest sources, fresh account-driven spotlight, removal of the personal-shelf Liked link, overflow-safe horizontal shelves, and recent-listening-based related songs. These targeted corrections preserve the approved Shell and are pending Human visual review. The public hero is guest-only; the signed-in hero uses the existing account playlist feed. Playlist shelves stay on one scrollable row at all widths, with desktop navigation when they overflow. Refresh is separate from carousel rotation and active only in visible foreground Home. Exact policy, references and session-only history limitations are in [the implementation research](../research/home-recommendation-strategy.md).
