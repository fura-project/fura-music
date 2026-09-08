# QQ Music media-resolution evidence

- **Status:** Standard/HQ plus F000 SQ selection and evidence-selected low-M4A fallback implemented; exact authenticated quality result pending maintainer observation
- **Last checked:** 2026-09-07
- **Scope:** Anonymous/authenticated M500 MP3, authenticated M800 MP3 and F000 FLAC, C200 M4A last-resort fallback, actual-format/quality reporting, and bounded fallback policy.

This note records independently implemented protocol behavior and two bounded no-account probes. It does not copy reusable third-party code. No account credential, user library, media URL, vkey, or response content was retained.

## Sources inspected

1. [L-1124/QQMusicApi at `108617f`](https://github.com/L-1124/QQMusicApi/tree/108617ffe80abefec6358717b9f4d3677550db10), especially [`modules/song.py`](https://github.com/L-1124/QQMusicApi/blob/108617ffe80abefec6358717b9f4d3677550db10/qqmusic_api/modules/song.py), [`models/song.py`](https://github.com/L-1124/QQMusicApi/blob/108617ffe80abefec6358717b9f4d3677550db10/qqmusic_api/models/song.py), its download guide, and authenticated integration assertions.
2. [yakult-green-tea/qq-music-api at `2c27d6b`](https://github.com/yakult-green-tea/qq-music-api/tree/2c27d6b90dd56bcf0796883e27216f69189d8f68), especially [`src/services/auth/qrLogin.ts`](https://github.com/yakult-green-tea/qq-music-api/blob/2c27d6b90dd56bcf0796883e27216f69189d8f68/src/services/auth/qrLogin.ts), [`getMusicPlay.ts`](https://github.com/yakult-green-tea/qq-music-api/blob/2c27d6b90dd56bcf0796883e27216f69189d8f68/src/controllers/getMusicPlay.ts), and its request-shape tests. Its repository records a real authenticated vkey/CDN probe on 2026-08-06 and accepts explicit `128`, `320`, and `flac` request keys.
3. [feeluown/feeluown-qqmusic at `241a967`](https://github.com/feeluown/feeluown-qqmusic/tree/241a9678bcd26e88d19e08e5da8048018f06e330), especially its media-quality resolver and one-hour resolved-URL cache. It corroborates that a track resolves to temporary media rather than owning a permanent URL; its request envelope is legacy supporting evidence only.

## Shared request behavior

The two current implementations agree on the ordinary authenticated operation:

```text
POST https://u.y.qq.com/cgi-bin/musicu.fcg
module music.vkey.GetVkey
method UrlGetVkey
```

The parameter boundary contains:

```text
uin: authenticated account ID as a string
guid: request/device correlation value
songmid: one or more QQ song MIDs
songtype: one zero per song
filename: one requested file per song
ctx: 0
```

All three current implementations agree on `M500` plus `.mp3` for standard
128 kbps MP3 and `M800` plus `.mp3` for high 320 kbps MP3. L-1124 exposes
both as typed file kinds and its current download guide sends multiple exact
qualities; yakult accepts an explicit quality key in authenticated and legacy
paths; FeelUOwn independently models both qualities and tries a lower candidate
when a higher URL is absent. This is sufficient for the two-quality
first-release contract, but not for a claim about membership entitlement.

When no separate file-media MID is available, current implementations support
the existing doubled-song-MID fallback. The client retains that form.

The implementations differ when a separate `file.media_mid` exists: L-1124 uses the file-media MID as the filename body, while yakult concatenates song MID plus media MID; FeelUOwn independently corroborates the file-media-MID body on its legacy envelope. Two anonymous probes over documented public playlists found 61 rows where song MID and `file.media_mid` differed. Both filename forms produced identical vkey item outcomes, including 46 nonempty paths. The project therefore selects the file-media-MID body supported by two implementations, while retaining no path, vkey, response body, or content identifier.

L-1124's URL helper defaults an unspecified song type to zero, and yakult's current authenticated path always sends zero. A controlled 20-row public-playlist probe then falsified the project's earlier assumption that the playlist response's separate `songtype` field was vkey input: all observed rows carried `songtype: 13`; forwarding 13 produced 20 item results of `101404` and no paths, while zero or the primary type produced 11 nonempty paths. The client now always sends zero. The primary track type remains only for lyric requests.

## Response and CDN behavior

`UrlGetVkey` returns page-independent source data:

```text
expiration
midurlinfo[]
  songmid
  filename
  purl
  vkey
  result
```

`purl` is a relative, short-lived authorization path. It is joined to a QQ Music CDN base; it is not a permanent Track property and must not be logged or persisted beyond its validity. A successful item needs both a zero item result and a nonblank relative `purl`. Nonzero item results remain raw protocol outcomes in `QQMusicClient`; until restriction evidence exists, the Provider maps them only to a provider-neutral unavailable result rather than inventing login, payment, region, or copyright semantics.

Current `UrlGetVkey` responses can carry an empty `sip`. L-1124 separately calls:

```text
module music.audioCdnDispatch.cdnDispatch
method GetCdnDispatch
```

and uses `sip`, `expiration`, `refreshTime`, and `cacheTime`. Yakult independently falls back to the measured `dl.stream.qqmusic.qq.com` host when vkey `sip` is empty. The project client now uses the explicit dispatch operation and validated relative paths instead of inventing a host or silently treating a bare filename as a URL. When that measured host is among the returned candidates it is preferred over `ws`/`isure`; it is never added when absent. Dispatch caching can follow its response fields after the single-resolution path is correct; it is not required to prove the first operation.

The resolved provider-neutral source needs only:

- a redacted-in-diagnostics HTTP(S) URI;
- the actual MP3/M4A/FLAC format plus low/standard/high/lossless quality that produced the source;
- the response validity in seconds.

It does not expose QQ filename, vkey, result code, CDN list, payment payload, or raw response models. When signed out, the Provider first requests M500 standard quality with QQ Music's anonymous `uin=0` comm, sends no Cookie or synthetic credential, and accepts only an exact correlated source. It tries C200 M4A only after an explicit per-item unavailable result. If both profiles are unavailable, the product offers sign-in without claiming a subscription, copyright, or region reason. Authenticated global or request-level credential rejection follows the existing explicit rejection rules; transport and unrelated upstream failures do not sign the user out. Authenticated account state is rechecked after every await.

The reusable fallback rule is intentionally narrower than a generic codec
ladder. A `Standard` preference requests `M500`, then `C200` only when the MP3
item is explicitly unavailable. A signed-in `High` preference requests `M800`,
then `M500`, then `C200`. A signed-in `Lossless` preference requests the
independently corroborated `F000` FLAC profile before the same High, Standard,
and Low ladder. Every step advances only after typed item unavailability.
Network, HTTP, service, credential, randomness, malformed-response, and
replacement failures never trigger fallback. The returned source reports the
actual format and quality, so an HQ/Standard/Low fallback is never relabeled as
SQ. OGG, encrypted media, payment state, and VIP inference remain outside this
slice.

## Controlled live probes

On 2026-08-26 a lightweight no-account `UrlGetVkey` request for one public song MID returned HTTP success, global code `0`, named-request code `0`, `expiration: 7200`, an empty `sip`, and one `midurlinfo` row. That row had `result: 101404`, a filename, and no `purl` or `vkey`. Only codes, field names, counts, and booleans were printed. This proves the current request/schema and unauthenticated refusal only; it does not prove an authenticated source or the meaning of `101404`.

A separate no-account CDN-dispatch probe returned zero global, request, and dispatch codes; four `sip` entries; `expiration: 86400`; `refreshTime: 1800`; and `cacheTime: 86400`. The returned bases used cleartext HTTP. No host or path was retained. This proves current dispatch structure, not that every returned node will serve an authenticated source or that HTTPS substitution is valid.

After the standard implementation, the opt-in `live_media_resolution` test ran the actual bounded Rust client path against the same non-account boundary. On 2026-08-27 the gate was expanded and passed for both exact M500 and M800 requests after one CDN dispatch. Each vkey call produced an accepted non-account outcome without printing or retaining its body, URL, or vkey. This confirms both implemented request/response schemas at the unauthenticated boundary; it still does not prove authenticated playback, entitlement, or source quality.

On 2026-08-31 the gate stopped using a fake credential and instead loaded one
bounded anonymous Search page, then requested M500 with `uin=0` and no Cookie.
At least one of the ten public results returned a correlated playable source;
the remaining rows were allowed to remain unavailable. The test retained no
query result content, Track identity, source URL, vkey, or response body. This
proves that current guest playback is possible for some public catalog results,
not that every search result is anonymously playable or that authentication
would make every unavailable Track playable.

On 2026-09-01 repeated bounded Search requests began returning result code
`2001` after earlier successes. Two current independent clients classify that
code as rate limiting. Because Search availability is not part of media-source
resolution, the gate now draws at most ten candidates from the existing public
new-song collection instead. The updated gate passed and found an anonymously
playable source without retaining Track or source data. This prevents an
independent Search rate limit from creating a false media-resolution failure;
it does not weaken either capability's failure semantics.

On 2026-09-07 a deeper anonymous comparison sampled four Tracks from each of
six public new-song categories (24 total). The test submitted the same 165
bounded candidates to `UrlGetVkey` and `CgiGetVkey`, chunked below an observed
100-item response limit, and recorded only aggregate outcomes. Both routes
resolved the same 17 Tracks; neither had an exclusive success. Canonical
file-media-MID and song-MID-plus-file-MID forms covered the same Tracks, while
song-MID-only was worse. M500 and C400 also covered the same 17 Tracks, so
neither endpoint switching, alternate filename construction, nor C400 added
coverage in this sample.

The seven base failures then received 42 canonical extended-format candidates
on both routes. Both routes again agreed exactly. One Hong Kong/Taiwan sample
Track was rescued by O600, O400, and C200; F000, O800, and C600 rescued none.
Bounded range reads validated representative M500 as MP3 and C400/C200 as
M4A, plus O600 as Ogg, without printing or retaining URLs, keys, identities,
filenames, or response bodies. The production fallback therefore keeps the
already-primary `UrlGetVkey` route and canonical filename, and selects C200
M4A as the smallest demonstrated coverage gain. Ogg is not selected for the
cross-platform path because Apple playback compatibility remains unproven.
This sample is comparative evidence, not a catalog-wide availability rate.

On 2026-09-07 the maintainer reported one exact signed-in Track as unavailable
in Fura but fully playable with the same account in official QQ Music. A
bounded public reproduction requested that exact Track through both
`UrlGetVkey` and `CgiGetVkey`, across F000/M800/M500/C400/C200 and the three
previously compared filename identities. All 30 items returned `104003` with
no source; public catalog metadata simultaneously reported encoded MP3 files,
disabled ordinary play actions, and a separate 60-second trial. This rules out
quality, filename, and anonymous endpoint selection as the cause while the
maintainer's official-client result establishes a signed-in route compatibility
gap. Production therefore retains `UrlGetVkey` as the first authenticated
request, but an exact per-item `104003` now permits one same-profile
`CgiGetVkey` request using the independently evidenced desktop `ct=19`
credential envelope. Every other unavailable code continues directly through
the existing quality ladder; credential, replacement, network, service, and
malformed outcomes still stop. Offline fixtures prove request shape, order,
redaction, STOP behavior, and the credential recheck after both awaits. Whether
the compatibility route resolves this exact real-account Track remains a
maintainer-operated retest.

The packaged Linux playback integration also decoded offline synthetic
AAC-in-M4A and FLAC fixtures through the same project adapter and explicit
`audio/mp4`/`audio/flac` selection, observed positive playback progress, and
stopped cleanly. This proves the selected codecs on the current Linux/GStreamer
environment; it does not prove a remote QQ source, Android hardware, or
Apple/Windows decoding.

The first authorized Linux product smoke restored the user's real account and loaded playlist/detail data, but every attempted ordinary or VIP track mapped to unavailable before reaching the audio engine. The anonymous batch probe above reproduced the exact all-`101404` behavior from the forwarded `songtype: 13`, establishing a protocol-mapping root cause without inspecting the user's credential, identifiers, source URLs, or response bodies. After the correction, the maintainer reported on 2026-09-07 that authenticated product playback succeeds. Because that build did not expose the actual resolved profile, this is evidence for the corrected end-to-end playback path, not evidence that M800, F000, or a particular fallback succeeded.

## Evidence still required

1. A maintainer-operated retry of the reported official-client-playable Track,
   recording only whether full playback starts and the displayed actual
   F000/M800/M500/C200 quality.
2. Sanitized outcomes for unpaid, region-filtered, unavailable, and device-restricted tracks before exposing specific restriction reasons.
3. Platform evidence for QQ Music's cleartext CDN bases. Do not globally enable Android cleartext traffic or silently rewrite the scheme without a narrow host policy and a real playback probe.
4. A maintainer-operated authenticated observation of SQ/HQ success or truthful lower-quality fallback before calling account-specific quality behavior live-verified.
5. Real-device C200 and FLAC decoding on every distributed target, especially Apple targets; current Core/Bridge/Flutter tests prove typed routing rather than hardware decoding.
6. Separate evidence and product authority before considering Hi-Res, encrypted media, decryption, download, or membership-specific behavior.
