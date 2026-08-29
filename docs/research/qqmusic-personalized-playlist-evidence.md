# QQ Music Personalized Playlist Shelf Evidence — 2026-08-28

## Product boundary

The accepted Home direction includes a playlist-discovery shelf distinct from
the user's own Library and the existing anonymous public recommendations. The
human-facing “Treasure Playlist Library” wording is presentation language, not
a QQ protocol contract.

The reusable capability is therefore a bounded authenticated list of
personalized playlist summaries. It does not expose the heterogeneous Home
feed, preserve source shelf titles, or authorize a generic feed runtime. A
later Flutter surface may choose truthful product wording after observing the
actual account result.

## Current primary evidence

- `L-1124/QQMusicApi` commit
  `108617ffe80abefec6358717b9f4d3677550db10` implements
  `music.recommend.RecommendFeed/get_recommend_feed` with `direction`, `page`,
  `s_num`, and `v_cache`, and models `v_shelf` → `v_niche` → `v_card`.
- `feeluown/feeluown-qqmusic` commit
  `241a9678bcd26e88d19e08e5da8048018f06e330` independently uses the same feed
  method through its older module alias. Its provider selects the first shelf
  whose `extra_info.moduleID` starts with `playlist`, then maps only cards with
  playlist jump type `10014`.
- That feeluown commit includes a public real-response fixture containing one
  `playlist@135@0` shelf titled `你的歌单补给站`. All twelve cards in the shelf
  use jump type `10014` and carry playlist identity, title, artwork, and play
  count. This project deliberately retains only identity, title, and artwork.

The two current implementations use different module aliases. The project
selects the newer `music.recommend.RecommendFeed` name from L-1124.

## Bounded structural checks

The initial credential-free probe used the project's former hybrid desktop
profile (`ct: 19`, `cv: 0`). It returned successful codes and eight shelves,
but no shelf-level `playlist` marker. A maintainer-run authenticated Home later
reproduced the same empty personalized-playlist result while other
credential-bearing QQ capabilities remained available.

On 2026-08-29 a second credential-free comparison kept the endpoint and
first-page semantics fixed but used FeelUOwn's evidenced `wk_v17` request
profile (`ct: 20`, `cv: 1770`, `platform: wk_v17`, plus empty `v_uniq`). It
returned successful codes, four shelves, one shelf-level `playlist` marker,
and thirteen playlist-jump cards. The former profile still returned no
matching shelf in the same comparison.

Only codes, counts, and marker booleans were observed; no title, identifier,
trace value, response body, credential, or account content was printed or
saved. This proves the former request profile selected the wrong feed shape.
It does not prove authenticated personalization quality or broad account
compatibility.

## Implemented contract

- `QQMusicClient` sends one bounded credential-cookie-bearing `wk_v17`
  first-page request with `direction: 0`, `page: 1`, `s_num: 0`, and empty
  `v_cache` / `v_uniq`.
- Exactly zero or one shelf may have a module ID beginning `playlist`. Absence
  is an empty successful result; multiple matching shelves are invalid rather
  than selected arbitrarily.
- Only cards with playlist jump type `10014` are mapped. At most 64 unique
  positive numeric playlist IDs are accepted, each with a bounded nonblank
  title and optional bounded HTTPS artwork.
- `QQMusicProvider` maps each item to the existing opaque `catalog:<id>`
  playlist route and rechecks the exact credential generation after the
  await. Explicit rejection alone clears provider credential state.
- The Bridge exposes one single-use cancellable list operation. Dart provides
  typed validation and serialized-vault cleanup only after explicit rejection.
- No Home controller, page, source shelf title, tracking field, raw card, or
  product label is included in this capability slice.

## Validation and claim limits

Rust formatting, 366 offline Rust tests, strict all-target Clippy, Dart
formatting and analysis, 381 Flutter tests, Linux x64 Release packaging, and
all required Linux integration gates pass. Six unrelated live tests remain
default-ignored. Coverage includes request serialization, strict shelf
selection, bounds, deduplication, redacted mapping, credential rejection,
account replacement, cancellation, Bridge mapping, Dart validation, vault
cleanup, and generated packaged-Bridge reachability. Generated bindings expose
the operation without a new API module or orphaned generated file.

These checks do not prove that the maintainer's account receives this shelf,
that QQ will continue to use the same label, that recommendations are useful,
or that a returned playlist currently loads or plays. A later UI integration
must treat an empty result truthfully and must not hard-code the fixture title
as guaranteed account behavior.
