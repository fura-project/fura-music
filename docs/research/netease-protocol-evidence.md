# NetEase protocol evidence

Date: 2026-09-09. Authority: HD-023. Core-only, independent Rust implementation. No real account, credential extraction, media download, alternate source, or UI integration.

## Reference provenance and deduplication

- [api-enhanced at `d55d92cd0031`](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/tree/d55d92cd0031d7c7746b7068faecd7ade1d354ac) — active, pushed 2026-09-08; [MIT license](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/blob/d55d92cd0031d7c7746b7068faecd7ade1d354ac/LICENSE) inspected. Endpoint modules and `util/crypto.js`, `util/request.js` inspected as wire behavior references. No implementation copied; unlocking modules/dependencies excluded.
- [MusicBox at `9c405f4bae23`](https://github.com/darknessomi/musicbox/tree/9c405f4bae2384d0410e63f8b816a707553d72d3) — active, pushed 2026-08-27; [MIT license](https://github.com/darknessomi/musicbox/blob/9c405f4bae2384d0410e63f8b816a707553d72d3/LICENSE) inspected. `NEMbox/api.py` and `encrypt.py` corroborate request families, current QR, catalog and ordinary media. Its eapi implementation explicitly references api-enhanced, so it is **not independent corroboration** of that algorithm.
- `SPlayer-Dev/ncm-api-rs` metadata was screened (WTFPL, last push 2026-04-07); no source adopted. No GPL or license-unclear implementation copied.
- Current module history checked: Search shape unchanged since 2024-08-10; QR poll fix 2024-10-03; media module updated 2026-08-20. Latest media reference defaults to xeapi, while MusicBox retains eapi. These are evidence variants, never automatic fallback choices.

## Protocol families

| Family | Wire behavior | Fura decision |
|---|---|---|
| weapi | AES-128-CBC twice, Base64 between stages, reversed random session key with RSA exponent 65537 | Independent Rust; deterministic OpenSSL/integer known answers; direct `music.163.com/weapi` |
| eapi | MD5 over path/JSON markers, AES-128-ECB, uppercase hex | Independent Rust; deterministic known answer; one standard media route at `interface.music.163.com/eapi`, JSON response requested |
| linuxapi | AES-128-ECB forward envelope | Investigated; no current requirement justifies another production path |
| plain api | Older/public unencrypted envelope over HTTPS | Investigated; no compatibility gap requires it |
| xeapi | New request session/envelope family in current Enhanced media code | Evidence-only; ordinary eapi sample works; no profile rotation or new runtime |

Runtime is Flutter → in-process Rust → direct HTTPS. RustCrypto AES/CBC and num-bigint implement wire primitives. Development-only independent known answers used OpenSSL and Python integer arithmetic; no subprocess or interpreter exists in runtime.

## Anonymous endpoint inventory

| Capability | Exact protocol path after `/api/` | Bound / semantics |
|---|---|---|
| Four Search types | `search/get` (weapi), types 1/100/10/1000 | 30 rows, 256-byte query; one-based Domain pages converted to offset; exact total and continuation |
| Song detail | `v3/song/detail` (weapi) | 100 requested exact IDs, no unrelated/duplicate output |
| Public playlist | `v6/playlist/detail` (weapi), then requested window through Song detail | `n=100`, identity-list ceiling 1,000; at most two requests per page, no full Track drain; omissions consume raw cursor |
| Album | `v1/album/<id>` (weapi) | Whole response strictly ≤1,000 songs; local bounded windows, exact Album correlation |
| Artist Tracks | `v1/artist/songs` (weapi) | 100 rows; public context, no private-cloud assumption |
| Artist Albums | `artist/albums/<id>` (weapi) | 100 rows, exact Artist correlation and total/continuation |
| Lyrics | `song/lyric` (weapi) | 512 KiB text, ≤10,000 lines; exact-time translation, no invented words or duration |
| Rankings | `toplist` (weapi) | ≤100 summaries; ranking identity is provider-owned playlist identity |
| Public recommendations | `personalized/playlist` (weapi) | Explicit bounded, non-paged sample; offset 0 only, no fabricated continuation/personalization |
| Standard source | `song/enhance/player/url/v1` (eapi) | One exact ID, standard only, normal service response; trial STOP, returned TTL, redacted URI |

HTTP has a 20-second deadline, no redirects, a 2 MiB streaming body ceiling, and no retry. Network diagnostics omit URL parameters, encrypted bodies, cookies and content. Artwork upgrades only the service's own `.music.126.net` HTTP CDN URLs to same-host HTTPS; all other HTTP artwork is rejected.

## Live observations

2026-09-09: four one-request Search observations (first three identified a structural mapping issue; fourth passed after regression repair). Public artist credits can have ID 0 with a valid display name; retain the name, do not fabricate a navigable Artist identity. No endpoint was changed.

Then one explicit ignored serial catalog gate, hard budget 16 HTTPS requests and a one-second minimum cadence, passed all 13 observed capability points: Track/Artist/Album/Playlist Search, Song detail, Lyrics, standard Media, Album content, Artist Tracks/Albums, public Playlist, Rankings and public recommendations. The playlist path made two requests. Only coarse outcomes and redacted field/type diagnostics were retained, never raw bodies, song titles, account data, lyrics or media URIs. The test's selected samples establish compatibility, not all-catalog availability, licensed-region coverage or account behavior.

## Error interpretation

`Result::Ok` with actual empty collections is ValidEmpty; it is distinct from malformed output and missing count fields. HTTP 429 is RateLimited. Envelope 301 is AuthenticationRequired. Unknown envelope or media codes are UpstreamUnknown and STOP. Explicit returned trial metadata is EntitlementDenied for this full-source contract; a null source is TrackUnavailable, not an inferred copyright/region/VIP reason. The private error vocabulary also reserves credential rejection, security verification, account restriction, copyright and region outcomes, but no undocumented code is assigned these meanings. Live observations conservatively stop their window on any non-success envelope.

## Remaining Work Audit

This audit must contain zero `REMAINING_AUTONOMOUS_WORK` before a final report. A local Human/live blocker never blocks independent fixture, mapping, documentation or architecture work. Ordinary implementation/test failures are work to repair. Checkpoints do not end the active workstream.

| Area | Status | Remaining acceptance |
|---|---|---|
| P0 public catalog, lyrics, media | REMAINING_AUTONOMOUS_WORK | Public live sample passed; finish negative fixtures, mapping and regression review |
| Protocol crypto/error/redaction/bounds | REMAINING_AUTONOMOUS_WORK | Expand transport/request and error STOP tests |
| P1 QR/session/restore/account/library/media/recommendations | REMAINING_AUTONOMOUS_WORK | Evidence-backed offline implementation and race tests |
| Static built-in composition and exact Resolver dispatch | REMAINING_AUTONOMOUS_WORK | Wiring and dispatch regression checks |
| Full tests/fmt/Clippy/docs/complexity review | REMAINING_AUTONOMOUS_WORK | Final checkpoint gates after all changes |
| Real account confirmation and authenticated behavior | HUMAN_EVIDENCE_REQUIRED | Human approval and actual-account read/restore observation |
| UI integration | NOT_APPLICABLE | Frozen by HD-023; no picker or page changes |
