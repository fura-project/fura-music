# QQ Music Related-Track Evidence

**Recorded:** 2026-08-29

## Bounded purpose

Support the existing Home label `More from your listening` with Tracks related to the current QQ Music queue Track. This is a public catalog relationship, not stored listening history, a second personalized feed, or autoplay radio.

## Cross-validation

- `L-1124/QQMusicApi` commit `108617ffe80abefec6358717b9f4d3677550db10` implements `music.recommend.TrackRelationServer/GetSimilarSongs` with `songid` and grouped `vecSongNew[*].songs[*].track` results. Its default Android request context also obtains device/QIMEI-backed session fields, so its non-empty test does not establish that the same method works with this client's anonymous Web request profile.
- `feeluown/feeluown-qqmusic` commit `241a9678bcd26e88d19e08e5da8048018f06e330` independently implements `rcmusic.similarSongRadioServer/get_simsongs` through a signed anonymous `musicu.fcg` GET and reads `songInfoList`.
- A bounded anonymous probe of the modern Web-profile method returned successful global/module/data codes but zero groups for multiple public fixture seeds and several Web profiles. This proves only an accepted empty envelope, not a usable Home capability.
- A bounded probe of the signed legacy method returned four or five Tracks for the same class of public fixture seeds. The ignored live regression now verifies only that at least one bounded public seed returns a non-empty set; it prints and retains no returned content or identity.

No credential, cookie, returned Track identity, title, artist, artwork, or media URL was printed or retained.

## Implemented boundary

The Client accepts one numeric QQ song identity, builds the evidenced signed anonymous request, and validates the bounded flat Track list. The Provider alone parses the opaque QQ Track identity and returns existing provider-neutral `TrackSummary` values. The Bridge exposes one cancellable typed operation, while Flutter owns the current-queue seed, visible section wording, loading/empty/error state, and queue actions.

The implementation does not expose group labels, tracking fields, aliases, continuation, feedback, history, or radio semantics.
