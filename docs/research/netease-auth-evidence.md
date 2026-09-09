# NetEase authenticated foundation evidence

Date: 2026-09-09. Authority: HD-023 + HD-024. **HUMAN_EVIDENCE_REQUIRED for every real-account claim.** No real QR login, stored-account access, account write, cookie extraction or authenticated live call was performed by the Agent.

## Protocol and ownership

The pinned current Enhanced/MusicBox sources and licenses are in [protocol evidence](netease-protocol-evidence.md). Direct weapi paths are `login/qrcode/unikey` (type 3), `login/qrcode/client/login` (key/type 3), and `w/nuser/account/get`. Codes 800/801/802/803 represent expired/waiting/scanned/confirmed. Unknown codes stop. Only confirmed responses with a structurally valid MUSIC_U cookie proceed to server account/profile correlation before installation. The raw key never leaves the opaque Rust object: a locally encoded PNG is the presentation challenge. No password is collected.

One process-level Provider owns one credential state. Starting QR or importing a replacement supersedes pending work; starting QR clears previous active state. A watch generation drops stale requests and prevents late success/rejection from modifying replacement state. Installing a verified credential advances the generation again. A separate generation-bound cancellation handle can interrupt a poll while the session is mutably borrowed; old handles cannot cancel new attempts. Drop, cancel, expiry, unknown QR outcome, the three-minute deadline and three consecutive transport failures terminate the attempt. There is no autonomous account confirmation.

QR code 803 no longer loses a service-issued credential when the immediately following account verification has a transient network/service failure or times out. The credential is first retained as a pending, unverified candidate; explicit retry uses the same server account check. It remains excluded from `has_authenticated_credential`, export, authenticated media and account reads until validation succeeds. Explicit credential rejection, sign-out or a newer QR/import generation clears it, and an in-flight old validation cannot install after replacement. Synthetic tests cover every transition. This recovery does not turn 803 itself into authentication.

Version-1 secure-storage bytes are namespaced to `netease-cloud-music` and contain only the provider-owned session and CSRF. Public Credential has no general Serialize/Deserialize implementation: import/export validate strict fields, version, provider, size and cookie syntax. No filesystem/vault is read by Core. Imported data remains pending until service verification; no invented cookie expiry is used. Transient/unknown/shape failures retain the candidate. Explicit authenticated 301 or null account/profile rejects it. Rejection clears only the owning generation; future UI integration must use its own namespaced vault cleanup. QQ and NetEase storage/session owners remain independent.

The authenticated eapi media request includes its explicit cookie plus encrypted MUSIC_U/__csrf header and CSRF payload. It shares exact source correlation, standard quality, real TTL, URI validation and trial/access-control STOP behavior with anonymous media. No source is saved or downloaded.

## Read foundation

| Read | Protocol | Machine evidence |
|---|---|---|
| Account summary / restore verification | weapi w/nuser/account/get | Correlated account.id/profile.userId; bounded name/avatar; candidate/active/rejection/race tests |
| User/owned playlists | weapi user/playlist | Explicit user ID; ≤10 serial pages of 100; owned/saved relations; no hidden unbounded drain |
| Ordinary/private playlist details | weapi v6/playlist/detail, v3/song/detail | Explicit same credential in both requests; generation checked between requests; raw omissions/cursor; rejection never retries as anonymous |
| Liked songs | weapi song/like/get, selected IDs through bounded Song detail | Complete unordered ID table bounded to 16,384 by the transport-derived memory policy; provider-owned `liked:<account>:<actual playlist ID>` route, exact owner checks, raw cursor/omissions; no recent-order claim |
| Favorite Albums/Artists | weapi album/sublist, artist/sublist | Bounded data/count/hasMore decoders and existing Domain pages |
| Daily Tracks | weapi v3/discovery/recommend/songs | ≤100 dailySongs; neutral Track batch, no invented daily Playlist |
| Personal FM | weapi v1/radio/get | ≤10 songs, one read only; no autoplay, scrobble, trash or like |
| Personalized playlists | weapi v1/discovery/recommend/resource | ≤100 recommended summaries, no public substitute |
| Media | eapi song/enhance/player/url/v1 | Explicit context; successful standard and rejection fixtures; Human entitlement/source evidence pending |

All listed reads have synthetic fixture/mapping coverage. Fixtures contain project-authored identities/content and dummy invalid-domain artwork/media, never real credentials or responses. Source-level correspondence and tests do not prove current account behavior.

## Human observation entry point

`crates/provider-netease/tests/human_qr.rs` is ignored by default and was **not run**. It reads no stored credential. A Human may explicitly opt into QR approval and Account Summary/restore reads with:

```sh
FURA_NETEASE_HUMAN_QR=I_APPROVE_QR_AND_ACCOUNT_READS cargo test -p provider-netease --test human_qr -- --ignored --nocapture --test-threads=1
```

The Human opens the temporary PNG path and approves in the official app only if intended. The file has tempfile's secure creation and is removed on normal completion/unwind. The gate has at most 45 polls separated by two seconds, an underlying 60-request hard ceiling, and no account writes. Restore bytes stay in memory and the handoff buffer is zeroed after import. Logs show only coarse PASS states, never names/cookies/QR keys. A passing run proves only confirmed QR, Account Summary and in-memory export/import/server verification, not platform-vault persistence, liked collections, recommendations, media entitlement, or another account/region. Those remain separately Human evidence.

`crates/provider-netease/tests/human_account_reads.rs` is a separate ignored gate and was also **not run by the Agent**. After one explicit Human QR approval it checks Account Summary, complete bounded user playlists and ownership, the exact liked route, one ordinary/private Playlist page, favorite Album/Artist pages, daily Tracks, Personal FM, personalized playlists, and authenticated standard source authorization. It is serial, sleeps between requests, has an exact 72-request ceiling (including up to 45 QR polls and worst-case ten user-playlist pages), stops its transport window on the first unexpected/risk envelope, performs no mutation and never GETs the audio body. Logs contain only PASS categories and a temporary QR file path—no names, titles, IDs, cookies, bodies or source URI.

```sh
FURA_NETEASE_HUMAN_ACCOUNT_READS=I_APPROVE_QR_AND_BOUNDED_ACCOUNT_READS \
  cargo test -p provider-netease --test human_account_reads -- \
  --ignored --nocapture --test-threads=1
```

A pass would be one-account/one-time evidence only. It would not establish collection completeness above observed pages, playback, account writes, another membership/region/device, platform-vault persistence, or UI acceptance.
