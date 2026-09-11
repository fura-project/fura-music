# Collection Detail Design

**Status:** Human-review candidate

**Scope:** Playlist, Album, Ranking and the shared dense Track-row grammar

## Product hierarchy

- A collection detail remains inside the authenticated application Shell. On
  wide layouts the existing navigation rail/sidebar and persistent player do
  not disappear merely because a Playlist, Album, Ranking, or nested Artist is
  open.
- The page canvas is the primary surface. The collection header does not add a
  second decorative card behind the artwork and metadata.
- Playlist, Album and Ranking use the same detail grammar: a local back action,
  artwork, semantic eyebrow, title, compact factual summary, optional supported
  metadata, and a dense Track table/list.
- Navigation retains the previous destination and nested catalog route. For
  example, Search → Artist → Album can return to the same Artist section and
  then the same Search query without reconstructing either page.

## Continuous collapse

`MusicCollectionDetailLayout` observes the collection's own vertical viewport;
it does not own paging or create another scroll controller. The first 132
logical pixels of forward scroll map continuously to `0...1` progress:

- artwork interpolates from 156/104 px to 64 px;
- artwork/copy spacing and outer padding tighten continuously;
- the eyebrow and expanded-only details fade and contract;
- the collection title interpolates from the page headline to Material
  `titleLarge` instead of jumping to a small secondary label;
- the summary remains available in the compact identity row;
- after the compact identity is established, the title and Back action hand off
  to the Shell top bar.

The hand-off is discrete so there is only one active application-bar action,
but the visible geometry leading into it remains scroll driven. Reduced-motion
mode preserves the same layout/state boundary without requiring decorative
motion.

## Shared Track rows

`MusicTrackRowSurface` and `MusicTrackRowContent` are the shared presentation
primitive used by Liked, ordinary Playlists, Recent Plays, Radar, New songs,
Albums, Rankings and Artists. The page still owns its controller, paging,
refresh/search policy, Queue operation and wording.

- Clicking the Track title or non-child row area plays from that position.
- Hovering/focusing the row reveals a dedicated Play affordance with a Material
  state layer and tooltip.
- Artist and Album text have independent bounded Ink responses and tooltips;
  blank space in their table columns remains part of the row rather than an
  oversized metadata hit target.
- A single credited Artist opens directly. Multiple credited Artists open an
  adaptive dialog/bottom sheet so the identity is never guessed.
- Queue and More remain separate actions. Desktop row-to-row Tab traversal is
  preserved; keyboard context-menu and compact long-press paths expose the
  complete action set.
- Long metadata remains constrained with ellipsis at narrow widths and does not
  widen the row or overflow.

## Adaptive Shell behavior

- At 840 px and above, details retain the desktop navigation rail; at 1100 px
  and above they retain the extended sidebar.
- Below the desktop Track-table breakpoint, the same rows switch to their
  compact title/Artist/Album composition and move secondary actions into More.
- Embedded pages omit their own player and outer Scaffold. The Shell remains the
  sole owner of the top bar, primary navigation and playback surface.
- Loading/error/empty panels can scroll within unusually short windows instead
  of overflowing while the Shell and compact navigation consume vertical room.

## Verification boundary

Widget tests cover continuous artwork contraction, Shell title hand-off,
stable route preservation, independent Track sub-actions, multiple-Artist
selection, compact overflow, keyboard traversal and direct/nested Album Shell
retention. Deterministic desktop renders exist for expanded Album/Ranking and
collapsed Playlist states. These establish layout and interaction behavior;
final motion feel and visual hierarchy remain Human review.
