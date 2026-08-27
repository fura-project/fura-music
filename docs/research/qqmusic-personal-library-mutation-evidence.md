# QQ Music personal-library mutation evidence

- **Status:** Liked Track, owned-playlist Track, and playlist-creation foundations implemented; maintainer-operated acceptance pending
- **Last checked:** 2026-08-28
- **Scope:** One reversible single-Track like/unlike operation, one Track add/remove operation for a structurally validated owned playlist, and one bounded owned-playlist creation. Rename/delete and catalog-entity mutations remain separate work.

This note is the durable evidence base for bounded personal-library writes. No
stored project credential was read, no request was sent with a real account,
and no account content or identifier was retained.

## Current independent sources

1. [L-1124/QQMusicApi at `108617f`](https://github.com/L-1124/QQMusicApi/tree/108617ffe80abefec6358717b9f4d3677550db10), especially [`qqmusic_api/modules/songlist.py`](https://github.com/L-1124/QQMusicApi/blob/108617ffe80abefec6358717b9f4d3677550db10/qqmusic_api/modules/songlist.py) and [`tests/test_songlist.py`](https://github.com/L-1124/QQMusicApi/blob/108617ffe80abefec6358717b9f4d3677550db10/tests/test_songlist.py). Its current authenticated integration performs a like followed by unlike on one recommendation and requires both operations to succeed.
2. [feeluown/feeluown-qqmusic at `241a967`](https://github.com/feeluown/feeluown-qqmusic/tree/241a9678bcd26e88d19e08e5da8048018f06e330), especially [`fuo_qqmusic/api.py`](https://github.com/feeluown/feeluown-qqmusic/blob/241a9678bcd26e88d19e08e5da8048018f06e330/fuo_qqmusic/api.py) and [`fuo_qqmusic/provider.py`](https://github.com/feeluown/feeluown-qqmusic/blob/241a9678bcd26e88d19e08e5da8048018f06e330/fuo_qqmusic/provider.py). It independently uses the same playlist-detail write module and Add/Del methods and invalidates its cached playlist songs after writes.
3. [ylw1997/qqmusic-api at `5f87b07`](https://github.com/ylw1997/qqmusic-api/tree/5f87b07b85923f8862d7b57f9d558ce0314ba1a7), especially its add/remove playlist documentation and opt-in dry-run/execute harness. It independently emits the same minimal `dirId` plus `v_songInfo` request and refuses to execute without a separate explicit flag.

## Selected narrow contracts

The first slice requests one desired state rather than exposing an unbounded
batch write:

```text
Liked
  -> music.musicasset.PlaylistDetailWrite / AddSonglist

NotLiked
  -> music.musicasset.PlaylistDetailWrite / DelSonglist

param
  dirId: 201
  v_songInfo: [{ songId: validated numeric Track ID,
                 songType: validated primary Track type }]
```

Directory `201` is identified as the built-in liked-song collection by the
current L-1124 implementation and already appears as that collection in this
project's authenticated playlist mapping. Optional `tid` and `bFmtUtf8` fields
are omitted because the two other current implementations use the smaller
shape. The request uses the project's existing authenticated musicu envelope
and cookie boundary.

The same request accepts a nonzero directory ID parsed only inside
`QQMusicProvider` from its own `owned:<playlist-id>:<directory-id>` opaque
identity. Both opaque components must be nonzero and structurally exact. The
Provider rejects public `catalog:`, externally favorited `favorite:`, foreign,
and malformed targets before transport. Presentation and Bridge code never
parse those source-specific forms.

Success requires zero global, named-request, and `data.retCode` values. An
explicit nonzero service or mutation code is a service failure. Credential
rejection keeps the existing exact sign-out rule. Invalid opaque input is
rejected before transport.

## Remote-outcome boundary

A write can reach QQ Music before a transport failure, cancellation, malformed
response, or account replacement becomes visible locally. Those outcomes are
therefore typed as unknown rather than presented as a confirmed failure. The
later UI must refresh the liked collection before displaying a definitive
state. Cancelling the Bridge drops only the local wait; it cannot recall a
request already sent to QQ Music.

No live test is added for this operation. It cannot be exercised meaningfully
without an authenticated persistent account mutation, which remains explicitly
maintainer-operated. The current third-party authenticated roundtrip is useful
protocol evidence, not acceptance evidence for this repository or account.

## Playlist-container creation

The implemented bounded non-destructive write is playlist creation:

```text
music.musicasset.PlaylistBaseWrite / AddPlaylist
param: { dirName: bounded nonblank name }
```

Current [L-1124/QQMusicApi at `108617f`](https://github.com/L-1124/QQMusicApi/blob/108617ffe80abefec6358717b9f4d3677550db10/qqmusic_api/modules/songlist.py)
and [tlyanyu/multiPlatformMusicApi at `0fd583b`](https://github.com/tlyanyu/multiPlatformMusicApi/blob/0fd583b384f5d6477067ff3d29ccedd97fc3a317/platforms/qqmusic/module/playlist_create.js)
independently agree on that module, method, and input. L-1124 maps the created
playlist identity from `result.tid`, while the second implementation reads
`result.id`; the client must accept either nonzero field and reject conflicting
values. Both use `result.dirId`; the returned server name matters because
L-1124 records that duplicate input names may receive a server-added suffix.

L-1124 and tlyanyu also agree on `DelPlaylist` with `dirId`, but deletion is a
separate destructive slice. Only tlyanyu currently provides a sufficiently
detailed `EditPlaylist` shape, so rename is not selected from one source alone.
Neither repository provides this checkout with a sanitized create response
fixture or a current authenticated create/delete roundtrip. This repository
therefore verifies the exact request and both independently observed response
field forms with synthetic offline fixtures only. Client, Provider, cancellable
Bridge, generated bindings, Dart gateway, credential rejection cleanup, account
replacement, and packaged-Bridge cancellation are covered; live acceptance
remains explicitly maintainer-operated.

## Catalog-entity mutation discovery

Album favorite state has enough bounded evidence for an offline foundation:

```text
Favorite
  -> music.musicasset.AlbumFavWrite / FavAlbum

NotFavorite
  -> music.musicasset.AlbumFavWrite / CancelFavAlbum
```

Current [L-1124/QQMusicApi at `108617f`](https://github.com/L-1124/QQMusicApi/blob/108617ffe80abefec6358717b9f4d3677550db10/qqmusic_api/modules/album.py)
uses `v_albumId: [numeric ID]`. Its current
[`test_album.py`](https://github.com/L-1124/QQMusicApi/blob/108617ffe80abefec6358717b9f4d3677550db10/tests/test_album.py)
selects one current new Album, favorites it, and cancels that favorite in an
authenticated reversible integration. Its response model treats `result == 0`
with no `v_failedAlbumId` entries as success.

[tlyanyu/multiPlatformMusicApi at `0fd583b`](https://github.com/tlyanyu/multiPlatformMusicApi/blob/0fd583b384f5d6477067ff3d29ccedd97fc3a317/platforms/qqmusic/module/album_sub.js)
independently agrees on the module and two methods but uses `v_albumMid` plus
`uin`. That is a real request-identity variation, not permission to put both
shapes in one request or to retry a write. The selected first foundation uses
the L-1124 numeric-ID form because it has the stronger current reversible-test
evidence. QQ Album opaque identity already retains numeric ID plus MID; a row
without a nonzero numeric ID must be rejected before transport rather than
falling back after an uncertain write.

No sanitized response is available in this checkout and no real account write
will be issued. Offline success must require zero global, named-request, and
mutation `result` values plus a present empty failed-ID list. A missing,
nonempty, or malformed failed list is an unknown response outcome, not
confirmed success. Artist follow/unfollow remains `EVIDENCE_BLOCKED`: current
sources agree on reading `GetFollowSingerList`, but this discovery found no two
current detailed write contracts or authenticated reversible test.

## Explicit non-goals of this slice

- playlist rename or delete;
- Artist follow/favorite mutation;
- optimistic UI or final verification controls;
- automatic retries after an unknown outcome;
- reading the maintainer's stored credential;
- claiming live-account compatibility from offline fixtures.
