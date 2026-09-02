# QQ Music playlist-detail evidence

- **Status:** Production route with separate public-anonymous and account-authenticated contexts
- **Last checked:** 2026-09-03
- **Scope:** Public catalog, account-owned/favorite, and built-in liked-songs playlist pages.

This note records protocol behavior and boundaries, not reusable third-party source code. No account credential or user-derived response was used.

## Sources inspected

1. [L-1124/QQMusicApi at `108617f`](https://github.com/L-1124/QQMusicApi/tree/108617ffe80abefec6358717b9f4d3677550db10), especially the ordinary song-list module, authenticated liked-songs module, shared response models, and live integration assertions.
2. [ylw1997/qqmusic-api at `5f87b07`](https://github.com/ylw1997/qqmusic-api/tree/5f87b07b85923f8862d7b57f9d558ce0314ba1a7), especially `get-playlist-detail`, `get-my-favorite`, and their executable request client.
3. [yakult-green-tea/qq-music-api at `2c27d6b`](https://github.com/yakult-green-tea/qq-music-api/tree/2c27d6b90dd56bcf0796883e27216f69189d8f68), especially the authenticated liked-songs service and its request-shape tests.
4. [feeluown-qqmusic at `241a967`](https://github.com/feeluown/feeluown-qqmusic/tree/241a9678bcd26e88d19e08e5da8048018f06e330), especially its sanitized `get_diss_info` fixture and playlist-to-track mapping. Its current ordinary playlist call uses a legacy endpoint, so it corroborates response fields rather than this request envelope.
5. A no-account probe against a public playlist on 2026-08-26. It returned zero global, named-result, and data codes, one requested row, `total_song_num`, numeric `hasmore`, and the documented song/artist/album fields. A 100-row request returned about 128 KiB. The public playlist ID and all content values are deliberately absent from project fixtures and diagnostics.
6. The default-ignored production-path gate on 2026-09-03 made exactly two serial anonymous reads: three public recommendation summaries followed by one requested playlist row. The request and decoder passed without Cookie or account fields. It retained no playlist identity, title, Track content, response body, or account material.

## Shared endpoint and response

Both paths use:

```text
POST https://u.y.qq.com/cgi-bin/musicu.fcg
module music.srfDissInfo.DissInfo
method CgiGetDiss
```

The page offset and size are `song_begin` and `song_num`. Current implementations read `songlist`, `total_song_num`, and `hasmore` from the named result's `data`. `hasmore` is observed as numeric `0` or `1`; the project also accepts the independently observed boolean form but rejects other values. Global and named-result codes are required and checked; the nested data code is checked when present because independently tested liked-songs fixtures omit it. Response bodies are capped at 2 MiB with a 30-second timeout, and page size is restricted to `1..=100`.

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
