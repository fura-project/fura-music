# QQ real-data compatibility and Linux MPRIS

Baseline `31bd72d91211acd29634ce673cf0529e91bc59f0` matched local HEAD and
`origin/main`. The worktree started clean. This investigation ran under
`HUMAN_DIRECTED / MIXED`, with HD-032 response integrity, HD-035 continuation,
HD-036 Heart ownership, and HD-037 playback ownership in force.

## Live scope and request accounting

A temporary Linux Fura entry point restored the existing QQ session through
the normal Rust authentication gateway. The app's secure-storage adapter
permitted reads and refused writes and deletes. The normal account
verification ran once per entry point. Session continuation was unbound in
the probe. Anonymous comments used the production QQ comment gateway, with
the candidate rows selected in process. Instrumented QQ transport disabled
redirect following and stopped on HTTP failures or unclassified business
responses. Requests ran serially.

| Window | Authenticated library-related HTTPS | Anonymous comments HTTPS | Result |
| --- | ---: | ---: | --- |
| Baseline | 10 | 6 | Verification, library discovery, seven detail pages, four comment first pages and two continuations |
| Candidate | 6 | 4 | Verification, library discovery, three detail pages, two comment first pages and two continuations |
| Omission classification | 4 | 0 | Verification, library discovery, one previously observed detail page |
| Previously evidenced public cases | 0 | 3 | Three anonymous legacy comment pages |
| Total | 20 | 13 | Caps were 20 and 16 |

Library discovery used an owned request and a favorites request. All read
operations returned without a credential rejection or risk-control
challenge. Account writes, credential export, refresh and playback history
reporting were zero. Temporary diagnostics and entry points were removed.
No response bodies, account or track identities, content or search terms
were retained.

## A. Liked Songs

| Case | Layer | Evidence |
| --- | --- | --- |
| L01 | Real Fura gateway | Baseline restored and verified the account and discovered the Liked Songs collection. All seven 100-position pages advanced. |
| L02 | Real Rust client and Flutter gateway | The page at offset 400 consumed 100 raw rows, returned 99 display rows and one omission, advanced to 500 and retained exact numeric membership. The isolated classification probe observed `omission_field=SongMid` and `rust_client_omitted=1`. Rust rejected the display row. Membership remained authoritative for that row. |
| L03 | Real Fura gateway | The same omission persisted on the candidate, as expected. The later full page advanced into a 17-position terminal page that completed normally. |
| L04 | Local index over real loaded rows | Exact title lookups found the original provider identities at sampled positions. A synthetic unmatched query stayed empty. No request came from the index. |
| L05 | Deterministic Rust | A legal `songlist` containing good, wrong-type album and good rows failed before the old row mapper with redacted `InvalidJson`. With raw rows, the fixture retains two display rows, counts one omission, advances three positions, and retains all three numeric membership identities. |
| L06 | Deterministic Rust | A string-typed song type and a positional array cannot confer numeric membership. The terminal page advances over both, reports their omissions, and marks membership inexact. |

The reproduced partial-results notice is legitimate. The affected row failed
the SongMid validation needed for a displayable and playable track. The
probe identifies the failing field but does not distinguish missing, blank
and malformed MID values. The original intermittent whole-page rejection
did not occur in this read window. The deterministic album-field failure
shows a separate way the old client could cause that symptom. Exact numeric
membership comes from the typed row or a separate, strict identity parse,
including duplicate-key detection. Malformed collection containers,
business errors and invalid page bounds still fail. No search index,
membership cache, account routing or queue continuation policy changed.

## B. Comments

The current client consumes the legacy anonymous endpoint using exact
numeric song IDs and aligned request offsets. Liked Songs, Search and Album
normal track mapping supplies that numeric component. Now Playing carries
the selected track identity. A MID-only history identity is accepted for
the separately supported playback path and fails comment preflight before
transport. The regression verifies zero requests for MID-only and foreign
provider identity.

| Case | Result |
| --- | --- |
| C01 | Real first and second pages accepted. Second page consumed 20 raw positions and exposed 19 latest comments plus one omission. |
| C02 | Real first and second pages accepted with aligned continuation. |
| C03 and C04 | Two additional first pages accepted. |
| C05 and C06 | Candidate first and second pages accepted for two sampled identities, including one with a drifting reported total. |
| P01 and P02 | Historical public stale-total cases still accepted, including the next offset. Exact nested-reply selection is covered by a deterministic fixture. |
| P03 | Historical public short-page assertion failed. The current endpoint returned a full nonterminal page for this case. The old live assertion is preserved as evidence of data drift. |
| D01 | Before the fix, Flutter returned `invalidResponse` for an accepted QQ terminal result with raw range 20–22 and reported total 23. After the fix it retains preceding content, appends the last valid row and signals the omission. |
| D02 | A malformed hot container is rejected on the first page and ignored on a later page, where QQ only supplies latest comments to Fura. The test also covers Unicode and a deleted row in a terminal page. |
| D03 | A short nonterminal raw page fails with `InvalidPagination`. Its raw continuation is not aligned and cannot be requested through the established endpoint. No guessed stride or skipped range is introduced. |

Flutter relaxes terminal-total equality only for QQ comments. Exact provider
routing, raw cursor bounds, genuine upstream rejections, section omission
counts and strict page-one hot validation still apply. The sampled live
tracks did not reproduce the reported comment failure. The two deterministic
faults and the established historical stale-total behavior have distinct
evidence. No Track Detail fallback was added.

## C. Direct Linux MPRIS

Before the change, resolving and loading disabled `CanPlay` and paused
playback disabled `CanPause`. GNOME Shell 49 derives message presence from
`CanPlay`. Replacing a normally playable track could remove and later
recreate the message. GNOME prefers desktop-entry activation and calls
`Raise` when it lacks a matching Shell App and the player advertises that
capability. Fura's root previously advertised `CanRaise=false` and did
not handle the method.
[GNOME MPRIS source](https://raw.githubusercontent.com/GNOME/gnome-shell/49.0/js/ui/mpris.js)
[GNOME message list source](https://raw.githubusercontent.com/GNOME/gnome-shell/49.0/js/ui/messageList.js)

The MPRIS projection now keeps the selected track playable during resolution
and open, and makes the genuine authentication block visible. `CanPause`
covers playing and paused sources. Paused and stopped navigation selects
through the existing Queue without opening the new source until Play.
`PlayPause` evaluates the playback state at dispatch. Root activation uses
the existing GTK window and respects the compositor's focus decision.
`CanQuit` stays false. The stable desktop-file stem is
`com.fura.flutterustmusic`, with the formal product label `fura music`.

Position uses one monotonic time base. Acknowledged UI or remote seeks and
the retained-source Repeat One rewind emit `Seeked`. Normal position ticks
do not emit it. Queued seeks bind both the current selection occurrence
and the playback source generation. Replacing a song at the same index
with the same provider identity invalidates the stale command. A stale
engine acknowledgement cannot publish a seek for the new selection.
[Player interface](https://specifications.freedesktop.org/mpris/latest/Player_Interface.html)
[Root interface](https://specifications.freedesktop.org/mpris/latest/Media_Player.html)

| Check | Evidence |
| --- | --- |
| Direct D-Bus, Rust Queue and MediaKit | Native Flutter integration used a fresh real session-bus daemon and loopback MP3. It exercised registration and reacquisition, metadata, pause freeze, root Raise and disabled Quit, Play/Pause/Next/Previous/Stop, phase-stable CanPlay, stale absolute seek, both seek methods and UI Seeked, shuffle, loop and volume. |
| Wayland identity | The GTK runner sent `xdg_toplevel.set_app_id("com.fura.flutterustmusic")`. The installed desktop-file and icon identity passed the local verification. |
| XWayland identity and activation | The synthetic runner advertised the matching X11 resource name in `WM_CLASS`. Native Raise restored the minimized window with the same X11 window ID and one window for the process. |
| Plasma 6.7.5 | The installed `org.kde.plasma.private.mpris` QML consumer, over a real isolated bus with MediaKit, discovered the player and decoded a loopback PNG. It exercised Pause, paused Next, Play, SetPosition, Previous, shuffle, Repeat One, volume and Raise. It removed the player when the owner process exited. Independent `gdbus`, `busctl` and `playerctl` read back volume, loop and stopped state. |
| GNOME artwork | Shell uses the URI directly with Gio FileIcon. The local Gio backend could read the exact PNG bytes from a file and did not make an HTTP request for either loopback URL. The conditional-header fixture returned the image when fetched with the public Referer. This reproduces a consumer transport/header gap without establishing the installed-GNOME rendering outcome. No persistent or temporary artwork cache was added. |
| GNOME native cards | `GNOME_NATIVE_RUNTIME_NOT_RUN`. The host does not have GNOME Shell. Card artwork on the target GNOME configuration, desktop-entry click routing, Wayland compositor foreground policy and live card transitions require that environment. |

Only safe public artwork transforms are projected. URI userinfo, fragments,
local file paths and unknown query fields are rejected. A track without
artwork clears the prior projection. Plasma decoded the ordinary network
resource with the current projection. GNOME's protected-CDN artwork remains
open. The present evidence supports testing GNOME plain and header-sensitive
images in its native card before introducing a local image-export owner.

## Local validation

- Rust 1.97.1 `cargo fmt --all -- --check`, locked offline workspace
  `test --all-targets` and strict Clippy passed. The suite reported 825
  passed and 36 ignored. The separately selected live comment gate's third
  assertion remains the negative evidence recorded in P03.
- Dart format check passed for `lib test integration_test`.
  `dart analyze` reported no issues. The full Flutter suite passed 1,162.
- The native Linux playback reliability integration passed both tests. The
  direct MPRIS integration passed again against the final source changes.
  `flutter build linux --release --no-pub` succeeded.
- Application identity, desktop file validation, privacy hygiene and
  `git diff --check` passed. No public FRB API changed.
