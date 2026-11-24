# QQ Music Track-like resolver research

Date: 2026-11-20\
Baseline: `b9dbb1de85c96fad95f9206b17cb5a4bcfaca835`\
Execution: `HUMAN_DIRECTED / CORE`\
Status: `RESEARCH_ONLY`

## Decision

`HYBRID_RECOMMENDED`

More precisely: `DIRECT_STATUS_RECOMMENDED_FOR_HEART_ONLY`. The complete Liked
Songs snapshot should remain the owner of Liked Songs page data, whole-account
numeric-ID/type membership and warm bulk lookup. The Fura-owned bounded live
gates now prove that `SongFavRead/IsSongFanByMid` is accepted by the current
Fura Web profile for both a disposable Type 2 session and a fresh disposable
WeChat session. In each login family, a single-MID read and a two-MID batch
returned complete booleans, and both explicit `false` results agreed with a
complete exact snapshot under the same immutable credential/session.

This materially improves the evidence for latency-sensitive current/visible
Heart resolution: one track requires one direct read instead of waiting for up
to the observed 12-page account scan, while 20 visible tracks fit in the
bounded one-batch research model. Request geometry is measured; live latency
and byte totals remain unavailable and are not invented.

Production promotion is still blocked pending Human review and a separately
authorized implementation phase. In addition, the bounded targets happened to
be unliked, so Fura live evidence now proves explicit `false` but not a live
`true` result or an upstream missing/partial-key response. Those gaps do not
invalidate the Heart-only architecture recommendation, but they remain hard
acceptance gates for treating every direct response shape as production
authority.

## Frozen Fura evidence

Commit `abc77694e4624c9474a2477f808bdd6aab1cb48e` remains the baseline:

- the real stored session read 12 Liked Songs pages;
- one historical raw row had numeric song ID and primary song type but no
  usable playback MID;
- membership is now retained from numeric ID plus type independently of
  presentation/playback mapping;
- the same account then completed the same 12-page scan successfully;
- a terminal inexact snapshot retries from offset zero and replaces authority
  atomically only after a complete exact scan.

The current production resolver is not changed by this research.

## Operation-specific identity model

QQ does not expose one universal Track primary key for every operation.

| Identity domain | Fields in Fura/current protocol | Evidence and conclusion |
| --- | --- | --- |
| Liked membership scan | `song_id + primary_song_type` | **CONFIRMED** by Fura code, deterministic tests and the 12-page live repair. A missing MID does not make this identity inexact. |
| Like/unlike mutation | `songId + songType`, directory 201 | **CONFIRMED** by Fura signed-Web mutation code/tests and corroborated by current community implementations. MID is not sent in `v_songInfo`. |
| Direct favorite status candidate | `songMid` in `v_songMid` | **CONFIRMED for explicit false** by Fura Type 2 and WeChat bounded live gates using the current Web profile. Live true and partial/missing-key behavior remain **UNPROVEN**. |
| Playback | numeric ID/type for the provider Track identity plus `song_mid` and optional `file_media_mid` for resolution | **CONFIRMED** by Fura mapping/resolver tests. The file MID is capability-specific and may be absent. |
| Lyrics | `song_mid` plus song type | **CONFIRMED** by Fura client/provider tests. |
| Presentation | title, artists, album and a usable `song_mid`, with artwork optional | **CONFIRMED** by Fura mapping tests. A row can be membership-identifiable while not presentation-identifiable. |
| Cross-source identity | exact Provider ID plus Provider-owned opaque Track ID | **CONFIRMED**. No fuzzy or cross-Provider substitution is permitted. |

The capability classification for historical rows is therefore independent:

| Row evidence | Membership-identifiable | Presentation-identifiable | Playback-capable |
| --- | --- | --- | --- |
| numeric ID + type only | yes | no | no |
| numeric ID + type + MID, incomplete display data | yes | no | potentially, but not assumed |
| valid display row + MID, no file MID | yes | yes | resolver-dependent fallback |
| all validated fields | yes | yes | yes, subject to entitlement/source resolution |

## Community evidence and provenance

No third-party implementation was copied. GPL sources were used as evidence
only. Permissive sources were still reimplemented from the protocol model and
Fura's existing transport/profile types.

| Repository | Pinned commit | License observed | Evidence used | Weight |
| --- | --- | --- | --- | --- |
| [L-1124/QQMusicApi](https://github.com/L-1124/QQMusicApi/tree/c046788dd1f11daacc74da487cbbf1bcd8ac6f33) | `c046788d` | GPL-3.0 | Current add/remove code sends numeric song ID plus converted song type; the complete Song model separately requires MID for richer operations. No copied code. | current implementation, evidence only |
| [yakult-green-tea/qq-music-api](https://github.com/yakult-green-tea/qq-music-api/tree/2b7c4d4f0d3e9bc97ac55ec28b1a3e874e0be0ca) | `2b7c4d4f` | MIT | `SongFavRead/IsSongFanByMid`, `v_songMid`, boolean/unknown mapping, current Android session client; source comment records multi-ID Android measurement. Fixtures prove local semantics, not Fura live compatibility. | current implementation with stated Android measurement |
| [Viemean/qmtui](https://github.com/Viemean/qmtui/tree/339d6c08a2756d08631a7f54ddf92f4800b9756b) | `339d6c08` | MIT | Maintains both MID and numeric-ID sets; either identity can establish a positive cache hit and confirmed writes update both available identities. It also fixes mutation type to 0 and has weaker/contentful diagnostics, so it is not copied. | current product implementation |
| [feeluown/feeluown-qqmusic](https://github.com/feeluown/feeluown-qqmusic/tree/241a9678bcd26e88d19e08e5da8048018f06e330) | `241a9678` | no repository license file detected | Historical split: numeric song identifier for playlist writes, cached MID/media MID for lyrics/media. No code used because provenance is unclear and wire behavior is historical. | historical corroboration only |
| [Yyyangshenghao/simple-music](https://github.com/Yyyangshenghao/simple-music/tree/d1adb95b75df1d6089c3f183ffb1aa350c908cad) | `d1adb95b` | GPL-3.0 | Current product documents a real-account Web read returning `m_fan[MID]: boolean`, rejects missing/non-boolean keys, and uses direct status for Heart/post-write checking. Its protocol research cites L-1124 and others, so this is product/live compatibility evidence, not an additional independent wire family. No copied code. | current real-client integration evidence only |

### Community handling of incomplete identity

- L-1124 separates numeric write identity from the complete Song model; it
  does not establish that MID is necessary for membership.
- qmtui records both numeric IDs and MIDs and accepts a positive hit in either
  cache. A row with only one identity can still be recognized by that identity.
- FeelUOwn historically uses numeric identity for writes and caches MID/media
  MID for other capabilities.
- The surveyed direct-status implementations require MID for that one
  capability. They do not justify changing the full-snapshot membership key
  back to MID.

## Direct-status candidate

The disposable candidate is behind the non-default Cargo feature
`track-like-status-research`. It is absent from the ordinary production build,
is not exposed through FRB, Provider or Flutter, and cannot mutate account
state. Its current shape is:

```text
POST https://u.y.qq.com/cgi-bin/musicu.fcg
Fura current Web comm/profile
music.musicasset.SongFavRead / IsSongFanByMid
v_songMid: [MID...]
m_fan[MID]: true | false
```

The candidate enforces a Fura research limit of 20 MIDs. That is not claimed
as a protocol limit. The community 100-item validation is not adopted as wire
evidence. Missing keys and non-boolean values map to `unknown`, never
`notLiked`. HTTP, rate limit, credential rejection, upstream business failure,
transport failure and malformed shape remain separate.

### Protocol question matrix

| Question | Current answer | Evidence |
| --- | --- | --- |
| Endpoint still accepted by QQ | **CONFIRMED** for the bounded Fura reads | Type 2 and WeChat live gates both accepted it on 2026-11-20. |
| Type 2 accepted | **CONFIRMED** | fresh disposable Fura Type 2 gate passed account verification, single and two-target status reads. |
| WeChat accepted | **CONFIRMED** | fresh disposable Fura WeChat gate passed the same matrix independently. |
| Fura current Web profile accepted | **CONFIRMED** | both Fura live gates used the candidate's current Web comm/profile without fallback. |
| Android/App profile required | **NOT SUPPORTED** | both Fura Web-profile gates passed; no alternate profile was attempted. |
| Device context required | **NOT SUPPORTED for the bounded reads** | both Fura gates passed without adding device context. Broader service behavior is not claimed. |
| Single MID supported | **CONFIRMED** | both Fura login-family live gates returned one key for one requested target. |
| Multiple MIDs supported | **CONFIRMED at batch size 2 only** | both Fura live gates returned two keys for two requested targets. No larger live batch was attempted. |
| Maximum safe batch | **UNPROVEN** | 20 is only Fura's bounded research limit; 100 is a community client limit. |
| Missing key semantics | **UNPROVEN upstream meaning**; Fura maps to `unknown` | deterministic fail-closed test. |
| Boolean `false` authoritative | **CONFIRMED for the bounded targets/session** | four Fura live comparisons (two per login family) agreed with complete exact snapshot negatives. |
| Boolean `true` authoritative | **UNPROVEN by Fura live evidence** | the bounded public targets were not liked; no mutation or account-content-derived target was introduced. |
| Malformed/partial response | `unknown` per member or request failure, never negative | Fura deterministic tests. |
| Credential rejection | 301/current known rejection codes classified separately | Fura deterministic tests; live exact codes unproven. |
| Other upstream failure invalidates session | no | candidate reports upstream failure; it does not clear credentials. |
| Rate/risk behavior | HTTP 429 is fail-closed; service-specific behavior **UNPROVEN** | deterministic classification only. |

## Resolver disagreement hard gate

The Human gate now compares two public, non-account-derived catalog targets
under the same immutable disposable credential and session generation:

1. one single-MID direct query;
2. one two-MID direct query;
3. a complete exact Liked Songs membership scan, bounded to 20 pages of 100;
4. snapshot lookup by each public target's exact numeric ID/type and direct
   lookup by the same target's MID.

The public target identities remain in process and are never printed. The only
per-target comparison diagnostic is:

```ini
agreement=true/false snapshot_state=liked/notLiked/unknown direct_state=liked/notLiked/unknown
```

An authoritative `liked`/`notLiked` conflict, any unknown result, an inexact
snapshot, request failure, or exhausted page budget blocks the candidate. No
resolver overwrites the other and no last-write-wins rule exists. A conflict
must be investigated for MID alias/version, numeric ID/type mapping, credential
or account generation, propagation delay, snapshot freshness and mutation
timing before any production promotion.

## Responsibility comparison

Request counts are not used as a substitute for capability coverage.

| Responsibility | Full Snapshot | Direct | Hybrid candidate |
| --- | --- | --- | --- |
| Current Heart latency | positive when its page arrives; authoritative negative only after complete exact scan | potentially one direct request; live latency unmeasured | direct foreground if live-proven |
| Visible-track Heart state | zero extra reads after warm snapshot | one bounded batch per group, plus caching/coalescing if later justified | direct for visible unknowns, snapshot warm hits |
| Liked Songs page contents | owns presentation order/content | cannot supply it | snapshot owns it |
| Whole-library membership | owns complete exact numeric/type set | does not provide an account snapshot | snapshot owns it |
| Negative inference | absence only after complete exact scan | only explicit boolean `false`, after Fura live proof | each resolver retains its own evidence rule |
| Dirty-row isolation | valid membership ID/type survives missing presentation fields; a truly missing membership identity makes negatives unknown | missing MID affects only that direct target | direct can isolate MID-capable rows; snapshot preserves numeric-only membership |
| Warm cache | account-generation snapshot supports zero-request future lookups | per-session MID cache would be bounded/expiring | both, with explicit ownership |
| Session replacement safety | implemented generation invalidation | would require the same generation key | both results must share/check generation |
| Mutation reconciliation | confirmed local override plus targeted/full refresh on unknown | good candidate for post-write readback, but no live writes authorized | confirmed override first; direct readback only after promotion; snapshot remains fallback |
| Network amplification | proportional to account pages once per exact snapshot | proportional to unresolved target batches | foreground batches plus background pages; may use more total requests |

### Deterministic workload geometry

The model uses the observed 12-page account scale and a research batch bound of
20. It is request geometry, not live latency or a production scheduler.

| Workload | Full Snapshot | Direct candidate | Hybrid candidate |
| --- | ---: | ---: | ---: |
| current playing track | up to 12 requests; positive may resolve on its page, negative on page 12 | 1 | 1 foreground + 12 background |
| Expanded Now Playing immediately after login | same as current track | 1 | 1 foreground + 12 background |
| 20 visible tracks | 12 | 1 | 1 foreground + 12 background |
| 100 visible/recent tracks | 12 | 5 | 5 foreground + 12 background |
| warm account snapshot | 0 | 0 only for cached MIDs | 0 for snapshot hits; direct cache policy unimplemented |

The current Flutter controller test confirms 12 page requests and 15 listener
notifications for the 1,151-row deterministic fixture. Existing tests also
prove that a liked identity can become positive before the remaining scan
finishes. No safe byte count or real end-to-end latency was recorded in the
prior live session, so both remain **UNAVAILABLE** rather than estimated.

Memory shape is `O(N)` membership identities for a full snapshot, `O(K)` for a
future bounded direct cache, and `O(N+K)` for a hybrid. Actual bytes are
**UNAVAILABLE**.

## Recommended ownership model (not promoted)

Both Fura login-family gates and the disagreement gate passed. The smallest
defensible production candidate is therefore
`DIRECT_STATUS_RECOMMENDED_FOR_HEART_ONLY`, not replacement of the snapshot:

- **Full Snapshot owns:** Liked Songs page contents/order, whole-account
  numeric-ID/type membership, warm zero-request Heart hits, and historical
  rows without usable MID.
- **Direct Status owns:** only latency-sensitive current/visible Heart
  resolution for a valid MID, explicit boolean evidence, and possibly
  post-mutation readback after a separately tested implementation.
- **Mutation confirmed override owns:** the immediately confirmed target state
  in its account/session generation. It never changes unrelated rows.
- **Unknown owns:** disabled/no-blind-write presentation and targeted
  reconciliation. Missing/malformed direct data never becomes `notLiked`.

Override rules would be generation-scoped:

1. a confirmed mutation may temporarily override older read evidence for that
   exact target and generation;
2. a direct authoritative result may fill a snapshot `unknown` only after live
   protocol promotion;
3. a complete exact snapshot may fill a direct `unknown` using numeric/type
   identity;
4. two authoritative results that disagree block the target as `unknown` and
   trigger investigation; neither wins;
5. any session/credential generation mismatch discards both old results.

Until that ownership model is implemented and proved in a separately approved
phase, the production owner is unchanged: complete exact full snapshot plus
confirmed mutation overrides.

## Evidence matrix

| Statement | Fura live | Fura test | Community current | Community historical | Conclusion |
| --- | --- | --- | --- | --- | --- |
| song ID + type is mutation identity | existing signed-Web live mutation evidence | yes | L-1124/yakult/simple-music/qmtui corroborate | FeelUOwn corroborates | **CONFIRMED** |
| MID is required for membership | contradicted by repaired 12-page row | tests prove numeric/type survives missing MID | qmtui accepts numeric-only hit | FeelUOwn separates uses | **NOT SUPPORTED** |
| MID is direct-status identity | Type 2 and WeChat single/batch gates pass | request/parser tests pass | yakult/simple-music | none needed | **CONFIRMED** for the bounded reads |
| missing playback MID may coexist with valid membership | yes | yes | qmtui design is compatible | operation split corroborated | **CONFIRMED** |
| direct status supports batch | batch size 2 passes in both login families | deterministic 2-item shape/parser | yakult Android statement and simple-music Web product | none | **CONFIRMED at size 2**; maximum remains unproven |
| direct status works with Type 2 | fresh disposable Fura gate PASS | envelope/parser tests | supporting only | none | **CONFIRMED** |
| direct status works with WeChat | fresh disposable Fura gate PASS | envelope/parser tests | supporting only | none | **CONFIRMED** |

## Live gate and promotion boundary

The two ignored gates are compiled only with
`--features track-like-status-research`. Each creates a disposable session,
performs one account verification, one single direct query, one two-target
direct query, and the bounded snapshot comparison. It does not read Vault,
persist credentials, print identities, mutate account state, retry, change
profile, or integrate the result into production.

Type 2:

```bash
qr_dir=$(mktemp -d)
FURA_QQ_TRACK_LIKE_STATUS_GATE=1 \
FURA_QQ_TRACK_LIKE_STATUS_QR_PATH="$qr_dir/login" \
  cargo +1.97.1 test --locked -p qqmusic-client \
  --features track-like-status-research \
  --test live_qq_type2_refresh_gate \
  bounded_disposable_qq_track_like_status_gate \
  -- --ignored --exact --nocapture
```

WeChat, only after Type 2 passes:

```bash
qr_dir=$(mktemp -d)
FURA_QQ_TRACK_LIKE_STATUS_GATE=1 \
FURA_QQ_TRACK_LIKE_STATUS_QR_PATH="$qr_dir/login" \
  cargo +1.97.1 test --locked -p qqmusic-client \
  --features track-like-status-research \
  --test live_wechat_refresh_gate \
  bounded_disposable_wechat_track_like_status_gate \
  -- --ignored --exact --nocapture
```

### Bounded live result

On 2026-11-20 both gates passed independently:

| Evidence | Type 2 | WeChat |
| --- | --- | --- |
| account verification | PASS | PASS |
| one-target direct read | 1 key, explicit false, no unknown | 1 key, explicit false, no unknown |
| two-target direct read | 2 keys, two explicit false, no unknown | 2 keys, two explicit false, no unknown |
| single/batch consistency | PASS | PASS |
| complete exact snapshot comparison | two agreements | two agreements |
| authoritative conflict | none observed | none observed |
| rate/risk challenge | none observed | none observed |

The full snapshot completed inside the 20-page safety bound in both runs. The
gate did not log personal identities, content, response bodies or credentials,
and its transient QR files were removed. This is bounded live evidence, not a
claim about an unlimited batch size, every catalog identity, all failure modes
or service-wide rate behavior.

The architecture evidence now supports a staged and reversible candidate:

1. current Expanded Heart direct resolution, with complete snapshot fallback;
2. bounded/coalesced visible-row batches;
3. optional post-mutation readback without replaying the mutation;
4. a separate evidence-based decision on whether background snapshot warming
   remains enabled.

Production promotion remains blocked in this research turn: no Provider/FRB/
Flutter production path was added, Human review is required, live `true` and
partial/missing-key observations remain unavailable, and the ownership/cache/
generation implementation has not yet been built or tested. Current full-scan
authority remains intact.
