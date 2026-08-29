# QQ Music Daily 30 Recommendation Evidence — 2026-08-28

## Product boundary

The first-release capability audit requires a truthful small personalized
daily starting point. Existing public playlist recommendations, Radar Tracks,
new Songs, and the user's own playlists are distinct products and must not be
relabeled as Daily Recommendations.

The selected reusable result is therefore zero or one Daily 30 playlist
summary. It can later open through the existing public playlist-detail path.
The heterogeneous Home feed, tracking metadata, arbitrary editorial cards,
and a generic feed runtime do not cross the Provider boundary.

## Current primary evidence

- `L-1124/QQMusicApi` commit
  `108617ffe80abefec6358717b9f4d3677550db10` implements
  `music.recommend.RecommendFeed/get_recommend_feed` with `direction`, `page`,
  `s_num`, and `v_cache`, and models the current `v_shelf` → `v_niche` →
  `v_card` response structure.
- `feeluown/feeluown-qqmusic` commit
  `241a9678bcd26e88d19e08e5da8048018f06e330` independently uses
  `get_recommend_feed`. Its provider selects a playlist card only when
  `extra_info.moduleID` starts with `recforyou` and `jumptype == 10014`.
- The public response fixture at that same feeluown commit contains exactly
  one such playlist card. Its trace also contains `#daily30:`, independently
  tying that otherwise broad `recforyou` card to Daily 30 semantics.
- An older `jsososo/QQMusicApi` route establishes the separate authenticated
  “今日私享” product meaning, but its page-scraping implementation is not used
  as the selected protocol contract.

The two current implementations use different module aliases. The project
selects the newer `music.recommend.RecommendFeed` name from L-1124, not the
older `recommend.RecommendFeedServer` alias.

## Bounded structural checks

The initial credential-free probe used the project's former hybrid desktop
profile (`ct: 19`, `cv: 0`). It returned successful codes, eight shelves, three
playlist-jump cards, and no `recforyou` or `#daily30:` match. A maintainer-run
authenticated Home later reproduced the same empty Daily result while other
credential-bearing QQ capabilities remained available.

On 2026-08-29 a second credential-free comparison kept the endpoint and
first-page semantics fixed but used FeelUOwn's evidenced `wk_v17` request
profile (`ct: 20`, `cv: 1770`, `platform: wk_v17`, plus empty `v_uniq`). It
returned successful codes, four shelves, five `recforyou` cards, one
`#daily30:` marker, and thirteen playlist-jump cards. The former profile still
returned zero Daily markers in the same comparison.

Only codes, counts, and marker booleans were observed; no title, identifier,
trace value, response body, credential, or account content was printed or
saved. This proves the former request profile selected the wrong feed shape.
It does not prove authenticated personalization quality or broad account
compatibility.

## Implemented contract

- `QQMusicClient` sends one bounded credential-cookie-bearing `wk_v17`
  first-page request with `direction: 0`, `page: 1`, `s_num: 0`, and empty
  `v_cache` / `v_uniq`.
- A Daily candidate must simultaneously have playlist jump type `10014`, a
  module ID beginning `recforyou`, and a trace containing `#daily30:`.
- Zero matches is a successful unavailable result. More than one match is an
  invalid response rather than an arbitrary selection.
- A selected card requires a positive numeric playlist ID, bounded nonblank
  title, and optional bounded HTTPS artwork. Its Provider identity is the
  existing opaque `catalog:<id>` route.
- Explicit credential rejection, ordinary service failure, malformed shape,
  cancellation, and exact-account replacement remain distinct. Only explicit
  rejection clears credential state and asks Dart's serialized vault edge to
  delete the stored copy.
- The Bridge exposes one single-use cancellable operation. Dart currently
  provides only a typed gateway; no Home page, controller, or visual work is
  included in this capability slice.

## Validation and claim limits

Rust formatting, 350 offline Rust tests, strict all-target Clippy, Dart
formatting and analysis, 373 Flutter tests, Linux x64 Release packaging, and
all required Linux integration gates pass. Six unrelated live tests remain
default-ignored.

These checks prove request serialization, strict selection, redacted mapping,
credential lifecycle, cancellation, generated Bridge reachability, and local
packaging. They do not prove that the maintainer's account receives Daily 30,
that a returned playlist currently loads or plays, or the pending M1 real
playback/Queue/lyric observation.
