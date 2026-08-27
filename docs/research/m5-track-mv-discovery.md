# M5.5 Bounded Discovery — Track-associated QQ Music MV

## Boundary

This pass audited current Track identity, expanded Now Playing, audio/Queue ownership, official Flutter video support, one maintained cross-platform video engine, and current direct QQ Music song/MV implementations. It did not call QQ Music, access stored credentials, retain a real Track or MV identifier, add an MV catalog/Search destination, authorize downloads or video-social behavior, or replace the existing audio engine.

## Existing product context

The coherent first entry is the current Track in expanded Now Playing. That surface already retains one queue/audio/lyric owner and secondary Track context for Album, credited Artists, and comments. A Track-associated MV can therefore open above the same retained state and return to it without adding a root destination or changing catalog navigation.

The provider-owned opaque Track identity already retains QQ's positive numeric song ID, song type, song MID, and optional file-media MID. Flutter must continue forwarding that identity unchanged. The selected discovery operation can use the validated song MID inside `QQMusicProvider`; no QQ identity parsing or raw response model needs to cross the Provider boundary.

## Protocol evidence

Source snapshots were inspected without executing their QQ requests:

- `L-1124/QQMusicApi` commit `108617ffe80abefec6358717b9f4d3677550db10` (2026-08-05) models `mv.vid` on a song, resolves song detail through `music.pf_song_detail_svr/get_song_detail_yqq`, fetches MV metadata through `video.VideoDataServer/get_video_info_batch`, and resolves sources through `music.stream.MvUrlProxy/GetMvUrls` with `request_type=10003`.
- `feeluown/feeluown-qqmusic` commit `241a9678bcd26e88d19e08e5da8048018f06e330` (2026-03-26) independently reads `mv.vid` from song detail and maps MV MP4 file types `40`, `30`, `20`, and `10` to descending video qualities. Its URL module uses the older `gosrf.Stream.MvUrlProxy` spelling, so only the response quality semantics—not that older module name—support the selected implementation.
- `Yyyangshenghao/simple-music` commit `301d1ca159e88f6226acbc95fb01a28a99234e79` (2026-08-23) independently uses `music.pf_song_detail_svr/get_song_detail_yqq` with `song_mid`. Its product currently declines MV playback, so it supports the current Track-detail request only.
- `Rain120/qq-music-api` commit `d05420bf098bd2769866eba81cfd48a6d0c6f50c` (2026-08-21) independently uses `video.VideoDataServer/get_video_info_batch` and exposes MP4/HLS URL groups, but still uses the older `gosrf` URL module.
- `copws/qq-music-api` commit `e0fe56787833a72cacdab7bb89a571dd927914c8` (2025-09-14) independently matches the selected current URL module, method, `vids`, and `request_type=10003`. It uses a different detail module, so the detail request is selected from the L-1124 and Rain agreement.

The selected protocol is therefore two sequential bounded operations: exact current-song detail to discover an optional nonblank VID, followed by one combined metadata/source request for that exact VID. Response parsing must correlate the returned song and VID, bound the body and all display/source fields, reject malformed or mismatched entries, and keep every URI and content value out of diagnostics. MP4 candidates are considered in file-type order `40`, `30`, `20`, then `10`; the first successful HTTPS candidate in that order is selected. HLS, cleartext HTTP, unknown file types, and source rewriting are not needed for the initial slice.

This evidence does not prove that current live QQ Music returns an MV or a playable source to this repository. Offline synthetic fixtures must keep unavailable, service, malformed, and source-unavailable outcomes truthful.

## Video edge evidence and dependency decision

Flutter's official `video_player` 2.14.0 currently declares Android, iOS, macOS, and web, but not Linux or Windows. It cannot satisfy this project's Linux-first native boundary by itself.

`media_kit` 1.2.6 plus `media_kit_video` 2.0.1 and `media_kit_libs_video` 1.0.7 declares Android, iOS, Linux, macOS, web, and Windows support under a permissive package license. Upstream commit `f702a6433a4c46960aff31df3d3d64c499eb650a` (2026-08-06) is active and includes a current Linux raster-thread fix. The default native builds use the non-GPL playback flavor; release compliance still needs the normal dependency notices and the platform libraries' applicable LGPL obligations when distribution work is authorized.

A disposable project outside this repository used the current Flutter 3.47.1/Dart 3.13.1 toolchain and exact published versions. Strict analysis and a Linux Release build passed; the packaged executable initialized the native plugin and decoded a generated two-second MP4, falling back to software rendering because the probe display exposed no valid EGL context. An Android x64 Debug build also passed through the repository's documented ASCII logical Flutter root. The scratch APK was 107 MiB and contained extra ARM libraries because the scratch project deliberately lacked this repository's target-aligned ABI filter; the real build must prove that its existing filter keeps one complete requested ABI. No Android runtime, physical device, Apple, Windows, remote QQ source, hardware decode, or release-package behavior was proven.

The dependency is acceptable only behind a project-owned MV video adapter. It does not replace `audioplayers`, expose plugin types through controllers, own the music Queue, or provide a plugin playlist. The first UI uses project Material controls rather than the plugin's fullscreen/control routes.

## Music/video ownership rule

The MV surface owns exactly one disposable video session. Before any MV play or resume, it pauses the current foreground music session if that session is playing. While the MV session is active, a new or resumed music operation stops the MV session; a Track/Queue replacement cannot leave old video audio competing with the new Track. Closing or failing the MV always disposes the video session and never auto-resumes music, because automatic resume could race a user-selected Track or surprise the user. The Rust Queue, current Track, lyrics, and audio source remain intact.

This is local media arbitration, not a second music playback owner or a new background lifecycle.

## Minimum provider-neutral contract

The first slice needs only:

- provider-scoped opaque MV identity;
- title and credited Artist display names;
- optional HTTPS artwork URI;
- positive duration when returned;
- one redacted HTTPS MP4 source plus an evidenced coarse quality label;
- `unavailable`, `network`, `service`, `invalid response`, and `source unavailable` failures.

Description, play count, publisher/uploader identity, favorite state, related songs, HLS, quality selection UI, subtitles, comments, caching, and download metadata are omitted.

## Ranked candidates

### 1. Current Track to exact MV with an in-app disposable player

**Provenance:** HD-003; M5 phase M5.5 and exit criteria 6, 7, 8, 9, 10, and 11.

**User value:** From expanded Now Playing, a user can open the official MV associated with the exact current song, watch it inside the client, and return to the unchanged music context.

**Current problem:** The app has no provider-neutral MV model, protocol path, video edge, or ownership behavior. Opening a browser would fragment the retained playback journey, while widening every Track/Queue DTO is unnecessary for an on-demand secondary action.

**Scope:** Add one provider-neutral Track-MV capability returning optional metadata plus one playable source; implement the cross-validated two-request QQ path; expose one cancellable typed Bridge operation; add a Dart gateway/controller and project-owned MV-only `media_kit` adapter; open one adaptive surface from expanded Now Playing; and enforce the ownership rule above.

**Acceptance criteria:**

- Synthetic offline fixtures prove exact song-detail and combined metadata/source requests, optional/no-MV behavior, exact Track/VID correlation, response and field bounds, quality ordering, HTTPS-only source selection, and redacted failures.
- QQ identity parsing and protocol stay in Rust; Domain/Provider/Bridge/Flutter exchange only provider-neutral MV and opaque identity values.
- One cancellable operation has explicit loading, unavailable, retryable error, source-unavailable, content, stale, and disposal behavior.
- The adaptive MV surface is reachable only for a current Track, preserves the underlying expanded Now Playing state on return, and has 360 px plus desktop keyboard/pointer/touch regressions.
- Video play/resume pauses music; subsequent music activation or Track replacement stops video; close/failure disposes video and does not auto-resume music. These races have controller regressions.
- Plugin URIs and causes never enter diagnostics. No plugin player, playlist, or source leaks outside the project adapter.
- Strict Rust/Dart checks, relevant widget/controller tests, Linux Release plus packaged local-video integration, the packaged Bridge integration, and the target-aligned Android x64 build pass. Live QQ, physical-device, hardware-decode, and unavailable-platform claims remain explicit.

**Effort:** High but bounded.

**Major risks:** Unofficial QQ response drift; expiring or cleartext-only URLs; a large native dependency and Android artifact; libmpv/FFmpeg packaging obligations; video/audio races; Linux hardware-rendering variance; Android native-library ABI leakage; upstream mobile TLS limitations; and generated Bridge drift.

**Explicit non-goals:** Related-MV lists, Artist MV, MV Search/Discover, HLS fallback, manual quality selection, fullscreen, picture-in-picture, background video/audio, subtitles, video comments/social profiles, favorites, downloads, cache, external browser fallback, audio-engine replacement, generic media arbitration infrastructure, or live account probing.

### 2. Preserve optional MV identity in every Track and Queue value

**Provenance:** M5.5 authorizes Track-to-MV, but this broader data migration is not required for the first journey.

**User value:** Track rows could hide or expose MV actions without an on-demand discovery request.

**Current problem:** Every QQ Track parser, Domain Track summary, Queue snapshot, Bridge DTO, Dart summary, and many fixtures would change even though the first product entry is only expanded Now Playing. Some catalog operations may omit MV context, so absence would still not be globally authoritative.

**Scope:** Deferred until repeated Track-row MV discoverability or request-cost evidence justifies the wider model.

**Acceptance criteria:** A reproduced UX or correctness problem proves that on-demand current-Track discovery is inadequate and identifies the exact surfaces that need retained MV identity.

**Effort:** High.

**Major risk:** Broad churn and false absence semantics across independently shaped QQ responses.

**Explicit non-goals:** No implementation is selected from this candidate.

### 3. Related-MV gallery using `GetSongRelatedMv`

**Provenance:** M5 allows related MV when justified, but the first slice does not need a gallery.

**User value:** Users could browse alternate, live, or related videos around a song.

**Current problem:** It adds pagination/cursor, ranking, multiple-video navigation, and selection semantics before the exact associated MV journey exists. The exact request has one current and one older independent implementation, weaker evidence than the selected direct song context.

**Scope:** Deferred protocol/product discovery after the exact Track-associated MV works and real user value is demonstrated.

**Acceptance criteria:** Current evidence establishes cursor/result semantics and a product observation shows that one exact Track MV is materially insufficient.

**Effort:** High.

**Major risk:** Scope growth into a generic video catalog and ambiguous first-result selection.

**Explicit non-goals:** No implementation is selected from this candidate.

## Selection

Candidate 1 ranks first. It is the smallest complete M5.5 product slice, has current independent evidence for every selected protocol step, preserves the retained Now Playing and single music Queue, and uses a video dependency that has already passed bounded local toolchain probes. Candidate 2 is unnecessarily broad; candidate 3 is a later evidence/product question rather than a prerequisite.
