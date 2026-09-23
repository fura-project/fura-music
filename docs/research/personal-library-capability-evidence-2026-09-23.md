# Personal-library capability evidence (2026-09-23)

Execution mode: `HUMAN_GATED_REGRESSION`. This audit records fixed source
revisions and synthetic transport evidence. It does **not** record a maintainer
credential, real account identifier, Track/Album/playlist title, or an
Agent-operated account write.

## Status vocabulary

- `SUPPORTED`: sufficient protocol evidence exists, but it does not by itself
  claim a production implementation or live-account acceptance.
- `IMPLEMENTED_NEEDS_HUMAN`: production Provider/Core/Bridge support and
  synthetic tests exist; the reversible real-account gate has not run.
- `EVIDENCE_BLOCKED`: the minimum evidence bar is not met, so no production
  write is exposed.
- `UNSUPPORTED`: the service or current project policy explicitly cannot offer
  the capability.

## Capability matrix

| Capability | QQ Music | NetEase Cloud Music |
|---|---|---|
| Recent history | `IMPLEMENTED_NEEDS_HUMAN` | `IMPLEMENTED_NEEDS_HUMAN` |
| Track like / unlike | `IMPLEMENTED_NEEDS_HUMAN` | `IMPLEMENTED_NEEDS_HUMAN` |
| Album favorite / unfavorite | `IMPLEMENTED_NEEDS_HUMAN` | `EVIDENCE_BLOCKED` |
| Artist follow / unfollow | `EVIDENCE_BLOCKED` | `EVIDENCE_BLOCKED` |
| External playlist save / unsave | `EVIDENCE_BLOCKED` | `EVIDENCE_BLOCKED` |
| Owned playlist create | `IMPLEMENTED_NEEDS_HUMAN` | `IMPLEMENTED_NEEDS_HUMAN` |
| Owned playlist delete | `IMPLEMENTED_NEEDS_HUMAN` | `EVIDENCE_BLOCKED` |
| Owned playlist add Track | `IMPLEMENTED_NEEDS_HUMAN` | `IMPLEMENTED_NEEDS_HUMAN` |
| Owned playlist remove Track | `IMPLEMENTED_NEEDS_HUMAN` | `IMPLEMENTED_NEEDS_HUMAN` |

QQ statuses retain the request-shape and response evidence in
[`qqmusic-personal-library-mutation-evidence.md`](qqmusic-personal-library-mutation-evidence.md)
and the corrected bounded read contract in
[`qqmusic-recent-plays-evidence.md`](qqmusic-recent-plays-evidence.md). This
audit did not reimplement those protocols.

## NetEase bounded recent-song snapshot

Two current, separately maintained clients agree on one WEAPI request to
`/api/play-record/song/list` with only a bounded `limit` and no offset/cursor:

- [api-enhanced `record_recent_song.js` at `a8c781fd64faab17fedfd46e0615a2609307f163`](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/blob/a8c781fd64faab17fedfd46e0615a2609307f163/module/record_recent_song.js)
- [go-musicfox `record_recent_songs_service.go` at `12169a71098f8b8607bcf655eaddabf57ca14daf`](https://github.com/go-musicfox/go-musicfox/blob/12169a71098f8b8607bcf655eaddabf57ca14daf/vendor/github.com/go-musicfox/netease-music/service/record_recent_songs_service.go)

The selected contract requests at most 100 rows once per credential generation.
It validates `resourceType=SONG`, `resourceId`, millisecond `playTime`, and the
embedded canonical song. Malformed rows consume their raw slot, duplicates and
upstream order are retained, and Flutter offset/size pages only traverse that
immutable snapshot. `data.total` is preserved only as an upstream observation;
every returned domain page says `totalIsExact=false`, so Fura never labels the
window as complete cloud history.

## NetEase Track like / unlike

The desired-state shape is independently present in:

- [api-enhanced `song_like.js` at `a8c781fd64faab17fedfd46e0615a2609307f163`](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/blob/a8c781fd64faab17fedfd46e0615a2609307f163/module/song_like.js)
- [MusicBox `NEMbox/api.py` at `9c405f4bae2384d0410e63f8b816a707553d72d3`](https://github.com/darknessomi/musicbox/blob/9c405f4bae2384d0410e63f8b816a707553d72d3/NEMbox/api.py)

Fura sends exactly one authenticated EAPI `/api/song/like` request with
provider-owned `trackId`, current account `userid`, and Boolean `like`.
Only envelope code 200 is confirmed. Network, malformed response, cancellation
after send, timeout, and account-generation replacement are typed as unknown
remote outcome; no automatic retry or toggle semantics exist.

The authoritative read source remains the existing current-account liked-ID
and Liked Songs collection. A write success may update presentation promptly,
but refresh/account switch/restart must return to that read source.

## NetEase owned playlist create and Track membership

Create is corroborated by:

- [api-enhanced `playlist_create.js` at `a8c781fd64faab17fedfd46e0615a2609307f163`](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/blob/a8c781fd64faab17fedfd46e0615a2609307f163/module/playlist_create.js)
- [FeelUOwn NetEase `api.py` at `baa02dcf1acdebbcb11cf5d05117133614538c8a`](https://github.com/feeluown/feeluown-netease/blob/baa02dcf1acdebbcb11cf5d05117133614538c8a/fuo_netease/api.py)
- [go-musicfox create service at `12169a71098f8b8607bcf655eaddabf57ca14daf`](https://github.com/go-musicfox/go-musicfox/blob/12169a71098f8b8607bcf655eaddabf57ca14daf/vendor/github.com/go-musicfox/netease-music/service/playlist_create_service.go)

Fura chooses one WEAPI `/api/playlist/create` request with a trimmed, non-empty,
bounded name, `privacy=0`, and `type=NORMAL`. It requires code 200 plus a valid
returned playlist identity/name and maps it as owned. It does not rotate among
the observed route variants.

Track add/remove is corroborated by:

- [api-enhanced `playlist_tracks.js` at `a8c781fd64faab17fedfd46e0615a2609307f163`](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/blob/a8c781fd64faab17fedfd46e0615a2609307f163/module/playlist_tracks.js)
- [FeelUOwn NetEase `api.py` at `baa02dcf1acdebbcb11cf5d05117133614538c8a`](https://github.com/feeluown/feeluown-netease/blob/baa02dcf1acdebbcb11cf5d05117133614538c8a/fuo_netease/api.py)
- [go-musicfox playlist-track service at `12169a71098f8b8607bcf655eaddabf57ca14daf`](https://github.com/go-musicfox/go-musicfox/blob/12169a71098f8b8607bcf655eaddabf57ca14daf/vendor/github.com/go-musicfox/netease-music/service/playlist_tracks_service.go)

Before the write, Provider code performs a fresh authoritative user-playlist
read and requires an exact owned, non-Liked-Songs target. It then sends one
WEAPI `/api/playlist/manipulate/tracks` request with `op=add|del`, exact `pid`,
one JSON `trackIds` value, and `imme=true`. Code 200 confirms the desired state;
code 502 confirms an already-present add only. Fura intentionally rejects the
api-enhanced duplicate-ID retry workaround because a second write after an
ambiguous first outcome violates the no-automatic-retry rule.

## Evidence-blocked writes

- NetEase Album favorite, Artist follow, and external Playlist save did not
  reach two independent current detailed implementations or one current source
  plus official wire evidence during this bounded audit.
- NetEase owned-playlist deletion sources disagreed on route family
  (`/playlist/remove` versus `/playlist/delete`). Without official wire or a
  Human-operated reversible test playlist, production deletion remains absent.
- QQ external Playlist save had one detailed current candidate
  (`PlaylistFavWrite/FavPlaylist` and `CancelFavPlaylist`) but no independent
  corroboration or official wire. It therefore remains blocked.
- The QQ candidate found for follow semantics represented following a user,
  not an Artist identity, so Artist follow remains blocked.

Blocked capabilities are not advertised and their actions must be absent from
the UI. They are not substituted with owned-playlist membership calls.

## Verification boundary

Synthetic transports cover request family/shape, provider identity rejection,
explicit success/failure, credential rejection, malformed response, network
unknown outcome, account replacement, cancellation, raw recent-history cursor,
duplicates/omissions, and no automatic retry. No real-account mutation ran.

Human acceptance must use a dedicated reversible object: read initial state,
perform one write, fresh authoritative read, perform the inverse write, and
fresh read to confirm restoration. Playlist deletion must use a newly created
test playlist only. Record only operation kind, coarse result, and read-back
state; never retain cookies, account IDs, raw response, or catalog titles.
