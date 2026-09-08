# QQ Music playlist-detail evidence

- **Status:** Production route with separate public-anonymous and account-authenticated contexts
- **Last checked:** 2026-09-08
- **Scope:** Public catalog, account-owned/favorite, and built-in liked-songs playlist pages.

This note records protocol behavior and boundaries, not reusable third-party source code. No account credential or response body was read; Human-operated account checks contribute only coarse counts and outcomes.

## Sources inspected

1. [L-1124/QQMusicApi at `108617f`](https://github.com/L-1124/QQMusicApi/tree/108617ffe80abefec6358717b9f4d3677550db10), especially the ordinary song-list module, authenticated liked-songs module, shared response models, and live integration assertions.
2. [ylw1997/qqmusic-api at `5f87b07`](https://github.com/ylw1997/qqmusic-api/tree/5f87b07b85923f8862d7b57f9d558ce0314ba1a7), especially `get-playlist-detail`, `get-my-favorite`, and their executable request client.
3. [yakult-green-tea/qq-music-api at `2c27d6b`](https://github.com/yakult-green-tea/qq-music-api/tree/2c27d6b90dd56bcf0796883e27216f69189d8f68), especially the authenticated liked-songs service and its request-shape tests.
4. [feeluown-qqmusic at `241a967`](https://github.com/feeluown/feeluown-qqmusic/tree/241a9678bcd26e88d19e08e5da8048018f06e330), especially its sanitized `get_diss_info` fixture and playlist-to-track mapping. Its current ordinary playlist call uses a legacy endpoint, so it corroborates response fields rather than this request envelope.
5. A no-account probe against a public playlist on 2026-08-26. It returned zero global, named-result, and data codes, one requested row, `total_song_num`, numeric `hasmore`, and the documented song/artist/album fields. A 100-row request returned about 128 KiB. The public playlist ID and all content values are deliberately absent from project fixtures and diagnostics.
6. The default-ignored production-path gate on 2026-09-03 made exactly two serial anonymous reads: three public recommendation summaries followed by one requested playlist row. The request and decoder passed without Cookie or account fields. It retained no playlist identity, title, Track content, response body, or account material.
7. A second default-ignored, explicitly opted-in anonymous gate on 2026-09-08 selected an unrecorded public recommendation whose reported count exceeded 300. A request for 100 rows at offset 200 returned a non-empty page and still reported continuation; a one-row request at offset 300 also returned one row. The gate logs and fixtures retain no playlist identity, title, Track metadata, response body, or account material.
8. A maintainer-operated authenticated check on 2026-09-08 reported that Liked search consistently stopped after 300 of more than 1,000 rows and that an immediate retry did not advance. This disproves the earlier assumption that public offset-300 compatibility plus Flutter pagination was sufficient. The coarse observation does not distinguish a temporary QQ request limit from one unrepresentable account row, so the repair covers both without recording the query, playlist identity, Track content, or response body.
9. A maintainer-operated follow-up with the cursor/omission repair reached all 1,032 reported Liked rows and disclosed one omitted row, without sharing account or Track identity. This establishes authenticated continuation beyond 300 for that account and closes the original depth failure. The same observation found the complete local search perceptibly slow; it does not establish a universally safe request rate, so the UI retains serialized bounded pages and transient backoff while tuning only the successful-page cadence.

## Shared endpoint and response

Both paths use:

```text
POST https://u.y.qq.com/cgi-bin/musicu.fcg
module music.srfDissInfo.DissInfo
method CgiGetDiss
```

The page offset and size are `song_begin` and `song_num`. Current implementations read `songlist`, `total_song_num`, and `hasmore` from the named result's `data`. `hasmore` is observed as numeric `0` or `1`; the project also accepts the independently observed boolean form but rejects other values. Global and named-result codes are required and checked; the nested data code is checked when present because independently tested liked-songs fixtures omit it. Response bodies are capped at 2 MiB with a 30-second timeout, and page size is restricted to `1..=100`.

The `1..=100` restriction is a per-request safety bound, not a total playlist limit. The 2026-09-08 anonymous gate proves that the public route accepts offsets beyond 300. The product therefore advances a distinct continuation cursor by the number of raw rows returned rather than by the number of usable Track summaries. A row without the minimum safe identity is counted as omitted and does not block later pages; a response with no raw row and a claimed continuation remains incompatible because it cannot advance. Full-playlist drains pace requests by 500 ms and apply a finite one-second/three-second backoff to transient network or service failures, while a permanent failure still stops for explicit retry. Account-scoped liked depth beyond 300 remains Human-operated acceptance because automated tests must not load stored credentials.

The minimum raw track boundary preserves:

- numeric song ID, song MID, primary type, and optional `file.media_mid`;
- display title with `name` fallback, optional subtitle, and duration in seconds;
- artist numeric ID, media MID, and name;
- optional album numeric ID, media MID or picture MID, and name.

These are QQ-specific protocol summaries. `QQMusicProvider` maps them into provider-neutral track summaries and keeps QQ song ID, song MID, primary type, and optional file-media MID behind a provider-owned opaque identity for media and lyrics. The response's separate `songtype` field is deliberately not retained after a controlled probe disproved its use as the vkey song-type parameter. Album artwork uses the independently documented `photo_new/T002R300x300M000{mid}.jpg` form only when the MID is a safe URL component. File-quality, payment, action-bit, tracing, MV, and other raw response structures remain excluded.

## Public and account-scoped ordinary routes

Independent current musicu implementations agree on:

```text
disstid: playlist ID
dirid: 0
tag: true
song_begin: offset
song_num: size
userinfo: true
orderlist: true
onlysonglist: false
```

Provider-owned `catalog:<id>` identity selects the anonymous route and sends no
Cookie or account fields, even when a user is signed in. `favorite:<id>` and
non-liked `owned:<id>:<dirId>` identities retain the authenticated envelope and
single credential owner because they are account-scoped. Anonymous
credential-like codes are not guessed into `CredentialRejected`; observed
musicu code `2001` is a rate-limit STOP in either context. Both routes keep the
same bounded page and decoder contract.

## Built-in liked-songs route

The account-owned row with `dirId: 201` is not fetched as an ordinary `disstid`. Three current implementations agree on:

```text
disstid: 0
dirid: 201
tag: true
song_begin: offset
song_num: size
userinfo: true
orderlist: true
enc_host_uin: credential.encryptUin
```

The project omits `onlysonglist` on this route, matching the cross-validated request. A missing encrypted UIN fails before transport rather than silently trying the wrong playlist identity.

## Evidence still required

1. A sanitized account-scoped ordinary-playlist response or controlled account integration beyond the existing broad user-library observation.
2. A sanitized authenticated liked-songs response or controlled account integration.
3. Evidence for unavailable or region-filtered song entries before deciding their long-term Domain and playback representation.
