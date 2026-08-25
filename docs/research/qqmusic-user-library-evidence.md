# QQ Music user-library evidence

- **Status:** Active research for M1 user library
- **Last checked:** 2026-08-25
- **Scope:** Authenticated account-owned and favorited playlist summaries.

This note records protocol behavior and boundaries, not reusable source code. No real account credential or user-derived response was used in this checkout.

## Sources inspected

1. [L-1124/QQMusicApi at `108617f`](https://github.com/L-1124/QQMusicApi/tree/108617ffe80abefec6358717b9f4d3677550db10), especially `qqmusic_api/modules/user.py`, `qqmusic_api/models/user.py`, and the shared song-list model.
2. [ylw1997/qqmusic-api at `5f87b07`](https://github.com/ylw1997/qqmusic-api/tree/5f87b07b85923f8862d7b57f9d558ce0314ba1a7), especially `docs/apis/get-my-playlists.md` and its executable `my_playlists` request.
3. [yakult-green-tea/qq-music-api at `2c27d6b`](https://github.com/yakult-green-tea/qq-music-api/tree/2c27d6b90dd56bcf0796883e27216f69189d8f68), especially `src/services/auth/qrLogin.ts`, the native QR probe, and authenticated service tests.
4. [feeluown-qqmusic at `241a967`](https://github.com/feeluown/feeluown-qqmusic/tree/241a9678bcd26e88d19e08e5da8048018f06e330), especially its separate legacy favorite-playlist request and `dissid`/`title` mapping. This corroborates collection/identity semantics, not the musicu RPC envelope.

## Account-owned playlist request

All three implementations agree on:

- `POST https://u.y.qq.com/cgi-bin/musicu.fcg`;
- module `music.musicasset.PlaylistBaseRead`;
- method `GetPlaylistByUin`;
- parameter `{uin: String(credential.musicid)}`;
- authenticated musicu comm plus the QQ Music credential Cookie;
- the created/owned list at `data.v_playlist`.

The implementations use different envelope labels and client identities. Ylw's current executable request uses the named `music.musicasset.PlaylistBaseRead` key with the lightweight `ct=11` comm already validated by this project's authentication work. L-1124 and yakult confirm the same module, method, parameter, credential semantics, and response path. The project therefore keeps the smaller named envelope rather than introducing Android device/QIMEI state for this request.

The client requires zero global and named-result codes, bounds the response to 1 MiB with a 30-second request timeout, and retains transport, HTTP, malformed response, non-rejection upstream errors, and the observed credential-rejection codes as distinct failures.

## Minimum response mapping

The account-owned list consistently identifies rows with:

- `tid` — the playlist ID used for ordinary playlist identity;
- `dirId` — the account directory ID used by built-in and mutation paths;
- `dirName` — display name;
- `songNum` — track count when present;
- `picUrl` — cover URL when present.

The client preserves both numeric IDs and rejects a row missing `tid`, `dirId`, or a nonblank name. Cover and track count are optional because current authenticated test fixtures do not always include them. Diagnostics redact playlist IDs and names, and offline fixtures use synthetic values only.

The `dirId: 201` built-in “liked songs” directory is not a generic `disstid`. Current implementations fetch its contents through `CgiGetDiss` with `disstid: 0`, `dirid: 201`, and an encrypted host UIN. Preserving `tid` and `dirId` separately now avoids making the later detail slice guess between incompatible identifiers.

## Deliberate boundary: favorited playlists

`GetPlaylistByUin` is the owned/created collection. L-1124 and yakult independently retrieve favorited playlists through `music.musicasset.PlaylistFavRead/CgiGetPlaylistFavInfo`, using the credential's encrypted UIN plus explicit `offset`/`size` pagination. Both read rows from `data.v_list`, total count from `data.total`, and continuation from `data.hasmore`; L-1124's authenticated test expects `hasmore` as `0` or `1`, while yakult defensively accepts either that representation or a boolean.

Favorite rows use a generic playlist ID (`id`, with current model aliases for `tid`/`dissid`), title, optional cover, and optional song count. They do not carry the account-owned `dirId` identity needed by the built-in liked-songs path.

The project now implements one bounded favorite page in `QQMusicClient`: page size is restricted to `1..=100`, response bodies remain capped at 1 MiB/30 seconds, missing encrypted UIN fails before transport, `hasmore` accepts only boolean or numeric `0`/`1`, and raw response models do not escape the protocol crate. Default tests use synthetic pages and cover exact request shape, pagination, aliases, missing identity, credential rejection, unrelated upstream failure, and redacted diagnostics.

Provider aggregation is deliberately separate. It must bound the number of pages, reject a non-advancing continuation, deduplicate against owned playlists by QQ playlist ID, and recheck the exact credential after every await. Until that exists, Flutter continues to expose only `owned_playlists` under the truthful heading “Playlists you created” and never parses its opaque QQ identity.

## Evidence still required

1. A sanitized real response fixture or controlled account integration before claiming live owned/favorite playlist compatibility.
2. Provider pagination, merge, and deduplication regressions before the UI presents a complete combined library.
