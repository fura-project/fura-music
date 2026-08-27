# QQ Music Personalized Track Evidence — 2026-08-28

## Product boundary

The first-release audit requires a truthful listening-related Track
recommendation capability. Public recommendations, Daily 30, Radar, rankings,
and new Songs already have distinct semantics and must not be relabeled to fill
that gap.

The reusable result is therefore one bounded authenticated set of personalized
Track summaries. “Personal radio”, “Guess You Like”, source-side feedback,
continuation, and Home-section wording remain Provider or later presentation
concerns. One capability may be reused transparently; it must not be presented
as two different recommendation products without separate evidence.

## Current primary evidence

- `L-1124/QQMusicApi` commit
  `108617ffe80abefec6358717b9f4d3677550db10` implements
  `music.radioProxy.MbTrackRadioSvr/get_radio_track` as
  `get_guess_recommend`. Its request uses radio ID `99`, `num: 5`, `from: 0`,
  `scene: 0`, and an empty `song_ids`; its current test executes through an
  authenticated client and expects a returned Song MID.
- `feeluown/feeluown-qqmusic` commit
  `241a9678bcd26e88d19e08e5da8048018f06e330` independently calls the older
  `mb_track_radio_svr/get_radio_track` alias with radio ID `99`, `firstplay: 0`,
  and a bounded count. Its provider exposes the result as the current user's
  “Guess You Like” radio Songs.
- `tlyanyu/simple-music` commit
  `301d1ca159e88f6226acbc95fb01a28a99234e79` uses the modern module name with
  authenticated account material. Its live-observation notes describe
  `data.tracks` as the ordinary flattened QQ Track shape.

The implementations differ in optional legacy/current parameters and looping
policy. This project selects the current module and L-1124's exact bounded
five-Track first request; it does not copy source-side loops, feedback state,
or radio presentation.

## Bounded structural check

A credential-free request to the modern endpoint returned global code zero,
named code `1000`, a `data` object containing a `tracks` field, and zero Tracks.
Code `1000` is already independently classified by this repository as a
credential rejection. Only these aggregate codes, keys, and count were
observed; no response body, Track content, identifier, URL, cookie, or account
material was saved or printed.

This confirms endpoint reachability, named-result shape, and the need for
authentication. It does not prove authenticated content, recommendation
quality, broad-account behavior, media availability, or playback.

## Implemented contract

- `QQMusicClient` sends exactly one authenticated request for radio ID `99`
  and exactly five Tracks. It does not page, loop, continue, or submit feedback.
- A successful response must contain zero through five flattened Tracks. Each
  Track uses the existing bounded QQ Track mapping and requires valid positive
  identity, MID, title, type, and Artists. Duplicate numeric IDs or MIDs and
  over-limit results are rejected.
- `QQMusicProvider` maps the response to existing provider-neutral
  `TrackSummary` values and rechecks the exact credential generation after the
  await. Explicit rejection alone clears Provider credential state.
- The Bridge exposes one single-use cancellable list operation. Dart validates
  the generated summaries, rejects contradictory or duplicate output, and
  serializes vault cleanup only after explicit credential rejection.
- No Home controller, radio identity, source feedback field, continuation
  token, listening-history claim, raw QQ response, or presentation label is
  included in this slice.

## Validation and claim limits

Targeted Client, Provider, Bridge, and Dart-gateway tests cover request
serialization, response bounds, duplicate rejection, redacted diagnostics,
Domain mapping, authentication requirement, credential rejection, service
failure, account replacement, cancellation, generated DTO validation, and
vault cleanup. The packaged Bridge smoke also exercises cancellation after
the generated binding is built.

Rust formatting, 372 offline Rust tests, strict all-target Clippy, Dart
formatting and analysis, 385 Flutter tests, Linux x64 Release packaging, and
all five required Linux integration gates pass. Six unrelated live tests
remain default-ignored. Generated bindings expose this operation through the
existing recommendations API module without an orphaned generated API file.

None of these offline or anonymous checks prove that the maintainer's account
receives useful recommendations or that a returned Track resolves and plays.
Later presentation must treat an empty result truthfully and must not invent a
second semantic section from the same set.
