# QQ Music media-resolution evidence

- **Status:** Protocol client, Provider mapping, and Bridge implemented; playback pending
- **Last checked:** 2026-08-26
- **Scope:** One authenticated, standard-quality MP3 source for the M1 playback path.

This note records independently implemented protocol behavior and two bounded no-account probes. It does not copy reusable third-party code. No account credential, user library, media URL, vkey, or response content was retained.

## Sources inspected

1. [L-1124/QQMusicApi at `108617f`](https://github.com/L-1124/QQMusicApi/tree/108617ffe80abefec6358717b9f4d3677550db10), especially [`modules/song.py`](https://github.com/L-1124/QQMusicApi/blob/108617ffe80abefec6358717b9f4d3677550db10/qqmusic_api/modules/song.py), [`models/song.py`](https://github.com/L-1124/QQMusicApi/blob/108617ffe80abefec6358717b9f4d3677550db10/qqmusic_api/models/song.py), its download guide, and authenticated integration assertions.
2. [yakult-green-tea/qq-music-api at `2c27d6b`](https://github.com/yakult-green-tea/qq-music-api/tree/2c27d6b90dd56bcf0796883e27216f69189d8f68), especially [`src/services/auth/qrLogin.ts`](https://github.com/yakult-green-tea/qq-music-api/blob/2c27d6b90dd56bcf0796883e27216f69189d8f68/src/services/auth/qrLogin.ts) and its request-shape/fallback tests. Its repository records a real authenticated vkey/CDN probe on 2026-08-06.
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
songtype: one value per song
filename: one requested file per song
ctx: 0
```

Both default to standard MP3 through prefix `M500` and extension `.mp3`. When no separate file-media MID is available, both build `M500 + songmid + songmid + .mp3`. That is the only filename form selected for the first implementation.

The implementations differ when a separate `file.media_mid` exists: L-1124 uses the file-media MID as the filename body, while yakult concatenates song MID plus media MID. The current playlist-detail protocol intentionally does not retain `file.media_mid`, and the first media slice must not guess between these forms. Standard resolution may later add that raw field only after a real differing fixture or repeatable integration establishes the correct behavior.

L-1124 accepts a per-track song type; yakult's current path sends zero. This project already preserves the playlist response's optional vkey-specific song type inside the QQ-owned opaque track identity. `QQMusicProvider` may use that value when present and fall back to zero, while every generic layer continues treating the identity as indivisible.

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
- standard MP3 format/quality;
- the response validity in seconds.

It does not expose QQ filename, vkey, result code, CDN list, payment payload, or raw response models. Authentication absence is rejected before transport. Global or request-level credential rejection follows the existing explicit rejection rules; transport and unrelated upstream failures do not sign the user out. Account state is rechecked after every await.

## Controlled live probes

On 2026-08-26 a lightweight no-account `UrlGetVkey` request for one public song MID returned HTTP success, global code `0`, named-request code `0`, `expiration: 7200`, an empty `sip`, and one `midurlinfo` row. That row had `result: 101404`, a filename, and no `purl` or `vkey`. Only codes, field names, counts, and booleans were printed. This proves the current request/schema and unauthenticated refusal only; it does not prove an authenticated source or the meaning of `101404`.

A separate no-account CDN-dispatch probe returned zero global, request, and dispatch codes; four `sip` entries; `expiration: 86400`; `refreshTime: 1800`; and `cacheTime: 86400`. The returned bases used cleartext HTTP. No host or path was retained. This proves current dispatch structure, not that every returned node will serve an authenticated source or that HTTPS substitution is valid.

After implementation, the opt-in `live_media_resolution` test ran the actual bounded Rust client path against the same non-account boundary. CDN dispatch parsed successfully and the vkey call produced an accepted non-account outcome without printing or retaining its body, URL, or vkey. This confirms the implemented comm/request schema on 2026-08-26; it still does not prove authenticated playback.

## Evidence still required

1. A sanitized authenticated success or controlled account integration proving a standard source can be read by the selected Linux playback engine without exposing its URL.
2. A track whose song MID and `file.media_mid` differ before adding separate-media-MID filename handling.
3. Sanitized outcomes for unpaid, region-filtered, unavailable, and device-restricted tracks before exposing specific restriction reasons.
4. Platform evidence for QQ Music's cleartext CDN bases. Do not globally enable Android cleartext traffic or silently rewrite the scheme without a narrow host policy and a real playback probe.
5. Evidence for higher qualities and encrypted media before adding quality selection, download, decryption, or membership-specific behavior.
