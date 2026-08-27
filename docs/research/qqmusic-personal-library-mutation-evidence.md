# QQ Music personal-library mutation evidence

- **Status:** Liked and owned-playlist Track desired-state foundations implemented; maintainer-operated acceptance pending
- **Last checked:** 2026-08-27
- **Scope:** One reversible single-Track like/unlike operation and one Track add/remove operation for a structurally validated owned playlist. Playlist-container and catalog-entity mutations remain separate work.

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

## Explicit non-goals of this slice

- playlist create, rename, or delete;
- Album/Artist favorite mutation;
- optimistic UI or final verification controls;
- automatic retries after an unknown outcome;
- reading the maintainer's stored credential;
- claiming live-account compatibility from offline fixtures.
