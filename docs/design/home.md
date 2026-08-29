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
- Unsupported Popular Programs and a second distinct personalized Track set remain explicit unavailable states; unrelated data must not substitute for them.
- No QQ Music branding, proprietary artwork, promotional content, or exact trade dress is copied into the project.

Home remains pending maintainer visual acceptance. This record preserves source identity; it does not itself establish visual completion.
