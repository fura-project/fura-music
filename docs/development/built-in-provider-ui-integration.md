# Built-in Provider UI integration

Date: 2026-09-12. Authority: HD-025. Execution:
`AUTONOMOUS_DEVELOPMENT / MIXED`.

## Product semantics

Settings persists exactly one catalog/account presentation choice:
`qq-music` or `netease-cloud-music`. Missing and legacy settings select QQ
Music. A selection changes subsequent Home, Discover, Search, Library and
authentication work; it is not a sign-out and does not merge services.

The Queue is deliberately independent. Every queued Track keeps its original
provider-scoped opaque identity, so media, lyrics, comments, MV and related
reads route to the owning Provider even after Settings changes. No identity is
parsed or translated by Flutter, and no failed source is substituted from the
other service.

## Credential and authentication boundary

QQ Music and NetEase Cloud Music use separate secure-storage keys, serialized
access and Rust session owners. Rejection cleanup may delete only the owning
Provider's stored credential. Startup restores only the selected Provider;
switching to another Provider activates its own lazy restore flow without
probing inactive accounts.

QQ retains desktop Quick Login plus QQ and WeChat QR where supported. NetEase
uses only its native Provider-default QR channel. Neither flow collects a
password or imports browser/local-client cookies.

## Capability mapping

Both Providers supply typed Search, catalog details, rankings, public
recommendations, supported new releases, related Tracks, lyrics, comments, MV,
media and an authenticated library foundation. NetEase Daily Tracks and
Personal FM keep those names and do not impersonate QQ Daily 30 or Radar.

QQ currently owns Radar, cloud Recent Plays and remote library mutations.
Those controls and destinations are absent for NetEase. Unsupported regional
choices are omitted rather than sent as speculative requests. A smaller Home
is valid when a Provider has fewer truthful slots.

## Switch lifecycle

Changing selection increments a presentation generation, cancels operations
owned by the old catalog/account context where possible, resets nested detail
navigation to the new Provider root and suppresses every late old-generation
completion. Playback work already attached to a queued provider-owned Track is
not part of that reset.

## Evidence boundary

Offline fixtures and Widget tests can prove routing, isolation, persistence,
rollback, stale-result suppression, capability hiding and Queue retention.
They cannot prove a real NetEase QR approval, account Library contents,
personalized recommendations, authenticated media entitlement, target secure
storage behavior or visual acceptance. Those remain explicit Human or
environment evidence.
