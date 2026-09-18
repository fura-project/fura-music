# Roam playback contract

Date: 2026-09-18
Decision: HD-035

## Scope and ownership

Roam is a session-local playback continuation policy. It is not a second Queue,
Radar, Personal FM, a hidden recommendation buffer, Search fallback, or a media
resolver fallback.

- `music-domain::PlaybackQueue` remains the sole owner of public order, current
  position, shuffle and repeat.
- the existing `RelatedTracksProvider` supplies one bounded candidate batch for
  the exact completed Track;
- `QueuePlaybackController` only coordinates the asynchronous request and one
  authoritative Queue mutation;
- the foreground audio engine and system-media adapters continue to observe the
  same controller and do not choose continuation Tracks.

`roamEnabled` records the session-local user preference. `roamEffective` is
true only when that preference is enabled, a Related Tracks gateway exists, the
current Provider is supported, order is sequential, and repeat is off. The
preference is not silently disabled by shuffle or repeat, but the policy is not
effective in those modes. Persistence and new UI are intentionally outside this
checkpoint.

## Trigger and precedence

Roam runs only after automatic natural completion calls Rust
`completeCurrent()` and Rust reports no playback request at the actual Queue
terminal.

1. A real next Queue entry always wins and plays normally.
2. Repeat One replays current; Roam does not request.
3. Repeat All wraps by Queue semantics; Roam does not request.
4. Shuffle is unsupported for Roam v1; Queue remains shuffled and Roam does not
   request.
5. Sequential + Repeat Off + Roam Off stops at terminal.
6. Sequential + Repeat Off + Roam On requests one related batch at terminal.

Manual Next is unchanged and never starts Roam. No candidates are prefetched.
After an appended batch plays to its own terminal, exactly one new request may
start from that newly completed exact Track.

## Provider and identity boundary

The seed is the exact `(provider_id, opaque_track_id)` of the completed Queue
entry. Current Provider coverage is QQ Music and NetEase because both already
implement the existing Related Tracks capability. Unsupported Providers stop
normally with `RoamStage.unsupported`.

Every returned candidate must have the same exact Provider ID as the seed. A
foreign Provider makes the whole result fail without mutation. There is no
title/Artist/ISRC matching, cross-Provider lookup, Search substitution, media
source fallback, or new protocol endpoint.

Candidates preserve Provider order. Exact `(provider_id, opaque_track_id)`
duplicates already present anywhere in the public Queue and duplicates within
the returned batch are removed. No fuzzy deduplication is performed. An empty
post-filter batch is a normal terminal result with `RoamStage.empty`.

## Atomic Queue transition

`PlaybackQueue::extend_and_advance_from_terminal` is the only continuation
mutation. It validates a nonempty batch and requires sequential, repeat-off,
current-at-last state before changing anything. It appends the full batch,
selects its first entry, rebuilds internal shuffle bookkeeping, and returns one
playback request. Any validation failure leaves entries and current position
unchanged.

The Flutter Bridge converts every Track before taking the Queue lock. A malformed
candidate therefore cannot produce a partial append. Flutter passes the whole
filtered list once; it never loops over `push` and never computes the new Queue
position.

## Lifecycle and races

Each request captures a generation, seed identity, expected Queue length,
sequential/repeat-off modes, terminal state and enabled preference. The result
is accepted only if all still match.

Selecting, replacing, pushing, removing or clearing Queue entries; manual
navigation; changing order or repeat; disabling Roam; and disposing the
playback host cancel the operation and invalidate its generation. Sign-out uses
the existing playback stop/Queue clear path and therefore invalidates Roam as a
Queue mutation. A late result cannot append to a replacement Queue or start
playback.

The typed stages are:

- `idle`: no request, or an earlier request was invalidated;
- `loading`: one Related Tracks request is active;
- `continued`: one atomic extension succeeded and its first Track started;
- `unsupported`: the exact current Provider has no supported capability;
- `empty`: the Provider returned no usable same-Provider candidate after exact
  deduplication;
- `failed`: request, response/provider validation, atomic mutation, or playback
  transition could not be accepted.

Network, service, malformed response, unsupported Provider, and empty results
do not remove the completed Track, alter the Queue, switch Provider, or start an
automatic retry. Playback remains normally completed at terminal.

## Resource boundary

One terminal event requests at most one bounded Related Tracks batch. The batch
is appended to the same public Queue; there is no hidden buffer. Long-session
Queue compaction requires a separately designed provenance/product contract and
is future work, not an HD-035 mutation.

No live account, private library, playback-history write, or online protocol
probe is required for this contract. Domain, Bridge and Flutter tests use
synthetic exact identities and deterministic operations.
