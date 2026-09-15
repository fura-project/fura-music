# KuGou protocol and product evidence

Status: active bounded research for HD-031

Last updated: 2026-09-15

Implementation rule: independent Rust, direct HTTPS, no sidecar and no copied
third-party source.

## Product and legal boundary

Fura is an unofficial third-party client. Current official KuGou pages expose
public Search, playlists, rankings, new releases, Artists and Albums, while the
current KuGou user agreement places material restrictions on unauthorized
third-party access and software/data interaction. Technical compatibility does
not establish permission for public or commercial distribution; that remains a
Human/legal decision.

TME's current official company material lists QQ Music, KuGou Music, Kuwo Music
and WeSing in one group and describes a central music library. That supports a
shared-ecosystem research hypothesis only. It does not make Provider identity,
credentials, entitlement or media sources interchangeable.

## Provenance audit

All commits below were inspected directly on 2026-09-15. No repository was run,
vendored or copied into Fura.

| Source | Inspected commit | License | Independence and permitted use |
| --- | --- | --- | --- |
| MakcRe/KuGouMusicApi | `4504b5d78432fd426dac0d0674d8fb27abe5a8c5` | MIT | Primary current wire-behavior source. Read-only reference; never a sidecar. |
| MoeKoeMusic/MoeKoeMusic | `2c2be40fc10c4132fe78d0a5e8b8bc3971c18f98` | GPL-2.0 | Real-client product evidence. Its `api` gitlink is MakcRe commit `a5a98013cce79fe0ae2ad65fc84b68176ebcfc1e`; not independent wire evidence. Behavior only; no code copying or translation. |
| hoowhoami/EchoMusic | `ea7e8f8689e8f0121f3c0d39764907a3c90377d1` | GPL-3.0 | Second active real-client compatibility reference. Its `server` gitlink is MakcRe commit `4504b5d78432fd426dac0d0674d8fb27abe5a8c5`; not independent wire evidence. Behavior only; no code copying or translation. |
| Linsxyx/KugouMusic.NET | `334516bb31599b33d90b520c12fad694a0cf665a` | MIT | Independent modern direct-client cross-check for request, identity, pagination and session semantics. No C# port. |
| lyswhut/lx-music-desktop | `abcbf5fa00b0b9f2c532a80b10ad8906ee4b22ab` | Apache-2.0 | Independent public Search/catalog field cross-check. Its current media URL path delegates to an external API and is not playable-source corroboration. |
| listen1/listen1_chrome_extension | `3f24efa045125875a609dcb0f3f3f0be4edb8b37` | MIT | Older independent public endpoint/field-name cross-check with lower recency weight. |
| bamboostrip/KugouMusic.rs | `b7a251d3aabb44e26382e8fca01bc7d70b34fc39` | No declared repository license at inspection | Evidence-only. Its README states that KugouMusic.NET supplied its protocol/algorithm foundation, so it is derivative provenance and not independent corroboration. |

The honest protocol count is therefore not “MoeKoe + EchoMusic + MakcRe =
three.” It is one MakcRe wire family with two continuing real-product
integrations. Those clients raise confidence that the family is used in actual
products, but they add no independent wire vote.

## Source/device classification

| Item | Current class | Production consequence |
| --- | --- | --- |
| Public legacy Search parameters (`platform`, correction flag, page, size) | Public web/client request shape, independently live-observed | May be implemented with strict bounds. |
| `MixSongID`, `FileHash`, `Audioid`, Album/Artist fields | Provider-owned response data | May be decoded; canonical identity remains under investigation. |
| Random request/session ID with no persistence | Locally random non-secret candidate | Only if an exact endpoint requires it and evidence proves no tracking/impersonation role. |
| `dfid` from `register/dev` | Unknown server/device identity | Do not implement until request, secret, lifetime and privacy classification are complete. |
| Android client salts, embedded app keys, package/signature or fabricated hardware fields | Potential official private/impersonation material | Must not enter Fura without independent proof of a public documented constant; affected capability stops. |
| CAPTCHA/SSA simulated behavior, device-fingerprint rotation | Risk-control bypass | Forbidden. |

## Bounded anonymous observation

Observation date: 2026-09-15. The complete workstream used exactly 20 HTTPS
requests plus one 4 KiB HTTP artwork Range request. Every request was anonymous,
read-only and single-attempt, with at least one second between requests in a
multi-request gate. Search responses were limited to two rows. No Cookie, token,
dfid, persistent device ID, proxy, retry or response content was logged. The
HTTPS research budget is closed; no further KuGou network request is permitted
in this workstream.

1. The legacy public Track Search surface returned HTTP 200, a success envelope,
   two rows, numeric total and present `MixSongID`, `FileHash` and `Audioid`
   identity fields without a request signature.
2. The corresponding modern `/v3/search/song` shape without its client
   signature returned HTTP 200 with a non-success business envelope and no
   rows. It is not a production candidate unless its signing boundary is later
   proved safe; no signing constant will be imported merely to make it pass.
3. Exact-path HTTP and HTTPS Range requests for the returned
   `imge.kugou.com` artwork were byte-identical JPEG content. Production upgrades
   only that exact host; QQ's separately evidenced artwork host family is not
   reused or generalized.
4. The committed opt-in compatibility test performed exactly one additional
   unsigned Track Search request through the bounded Rust transport and passed.
   It retained and printed no query, response body, title or identity.
5. The legacy mobile detail surface accepted the Search-owned standard
   `FileHash` and returned an `album_audio_id` equal to Search `MixSongID`, an
   equal standard hash, the same Album ID and true `authors[].author_id` values.
   Anonymous media URL data was empty. An all-zero hash returned a provider
   business error whose semantics are not independently established; it is not
   mapped to `None` or a generic not-found result.
6. Two extended Search-to-detail live gates rejected the independently written,
   strict response decoder with `ResponseShapeMismatch`. Relaxing only the
   separately unproved `Audioid` equality did not change the outcome. The entire
   uncommitted Track-detail implementation was therefore withdrawn. No Catalog
   capability is advertised and no permissive decoder was retained merely to
   accept the observation.
7. Current official public page assets did not reveal a closed, unsigned detail
   route keyed directly by `MixSongID`. The modern detail family instead uses
   signatures plus device/install-looking fields whose public-versus-private
   status is unresolved. Those constants and identities were not imported,
   fabricated or replayed.

This proves only current bounded anonymous Search compatibility. It does not
prove stable identity across catalog operations, content completeness, media
availability, entitlement, recommendation quality or another network/region.
The failed strict detail gates are evidence of an unresolved response contract,
not evidence that a broader or more permissive parser would be correct.

## Capability evidence matrix

| Capability | State | Evidence and next proof |
| --- | --- | --- |
| Track Search | `IMPLEMENTED_CORE` | Independent bounded Rust client and Provider mapping; five offline client contracts, two Provider contracts, strict Clippy and the one-request opt-in live gate pass. Bridge/UI not yet exposed. |
| Artist Search | `SUPPORTED_EVIDENCE` | MakcRe and KugouMusic.NET expose a direct type; live and identity proof pending. |
| Album Search | `SUPPORTED_EVIDENCE` | MakcRe and KugouMusic.NET expose a direct type; live and pagination proof pending. |
| Playlist Search | `SUPPORTED_EVIDENCE` | MakcRe and historical Listen1 expose direct public results; current live proof pending. |
| Track detail | `EXTERNAL_BLOCKED` | The legacy mobile response partially corroborates `MixSongID`/hash/Album/Artist linkage, but two strict Search-to-detail live gates failed with `ResponseShapeMismatch`; the implementation was completely withdrawn. A scrubbed structural fixture or a future bounded evidence window must explain the variance before retrying. Modern signed/device-shaped routes require separate Human classification. |
| Playlist detail | `SUPPORTED_EVIDENCE` | Current MakcRe and real-client products expose it; identity/pagination live proof pending. |
| Playlist Tracks | `SUPPORTED_EVIDENCE` | Current implementations expose explicit Track collections; raw cursor and unavailable-row semantics pending. |
| Album detail | `SUPPORTED_EVIDENCE` | Current MakcRe/KugouMusic.NET evidence; exact Album identity proof pending. |
| Album Tracks | `SUPPORTED_EVIDENCE` | Current MakcRe/KugouMusic.NET evidence; paging and Track identity proof pending. |
| Artist Tracks | `SUPPORTED_EVIDENCE` | Current MakcRe/KugouMusic.NET evidence; true Artist ID and paging proof pending. |
| Artist Albums | `SUPPORTED_EVIDENCE` | Current MakcRe/KugouMusic.NET evidence; true Artist ID and paging proof pending. |
| Lyrics | `SUPPORTED_EVIDENCE` | MakcRe, KugouMusic.NET and both product clients expose lyrics. KRC/LRC representation and access-control boundary pending. |
| Rankings | `SUPPORTED_EVIDENCE` | Official public page plus current implementations expose rankings; canonical ranking ID/paging pending. |
| Recommended Playlists | `SUPPORTED_EVIDENCE` | Official public curated playlists and current clients exist; exact non-personalized semantics pending. |
| New Songs | `SUPPORTED_EVIDENCE` | Official public region tabs exist; exact mapping to Fura categories pending. |
| New Albums | `PARTIAL_EVIDENCE` | Current APIs expose Album listings; exact new-release category semantics pending. |
| Related Tracks | `PARTIAL_EVIDENCE` | Current implementation candidates exist; exact public seed semantics pending. |
| Comments | `SUPPORTED_EVIDENCE` | MakcRe and EchoMusic product behavior expose read-only comments; independent request/pagination proof pending. |
| Track-associated MV | `PARTIAL_EVIDENCE` | Search/detail fields and product behavior suggest an association; exact HTTPS media path pending. |
| Media source | `HUMAN_DECISION_REQUIRED` | The observed anonymous legacy detail response carried no playable URL. Current modern routes combine signing/device-shaped inputs and newer evidence mentions V5/encrypted responses. No official secret, device impersonation, encrypted-audio cracking or entitlement bypass is permitted. |
| Authentication | `OUT_OF_SCOPE` | Not authorized in the first phase. |
| Account Summary | `OUT_OF_SCOPE` | Depends on a future independently authorized authentication workstream. |
| User Playlists | `OUT_OF_SCOPE` | Private account read is not authorized. |
| Favorites | `OUT_OF_SCOPE` | Private account read/mutation is not authorized. |
| Recent Plays | `OUT_OF_SCOPE` | Private history/reporting is not authorized. |

## Canonical identity investigation

Search exposes quality-dependent `FileHash`/`HQFileHash`/`SQFileHash`, numeric
`Audioid`, and `MixSongID`/`AlbumAudioID`. A quality hash cannot be the canonical
Track identity merely because older clients used it. Search currently owns the
provider-scoped, opaque `MixSongID`, while the standard hash remains private
Search context rather than a public Fura identity. The legacy detail observation
supports this candidate but the strict live decoder failed twice, so production
identity is not accepted. Search, detail, Playlist, Album, Artist, lyrics,
comments and media evidence must eventually link the same recording/version
without title/Artist matching.

No QQ song MID, NetEase numeric ID, title/Artist lookup or cross-service Search
may fill an identity gap.

## TME shared-infrastructure hypothesis

These labels describe only evidence as of the last update.

| Layer | Classification | Evidence / boundary |
| --- | --- | --- |
| Corporate/content platform | `SHARED_CONFIRMED` | TME officially lists QQ, KuGou, Kuwo and WeSing together and describes a central catalog/content platform. |
| Direct QQ song MID ↔ KuGou `MixSongID`/hash mapping | `UNKNOWN` | No explicit mapping evidence. Fuzzy title/Artist matching is forbidden. |
| Group-level label/catalog rights | `SHARED_CONFIRMED` | Official TME materials describe central licensing/catalog availability across products. |
| User membership/entitlement | `UNKNOWN` | Shared catalog rights do not prove interchangeable subscriptions or playback authorization. |
| Media CDN host/signing/TTL/headers | `UNKNOWN` | Must be compared from exact provider responses; no shared resolver or fallback. |
| Artwork CDN normalization | `PROVIDER_SPECIFIC` | KuGou Search returns `imge.kugou.com`; QQ uses separately allowlisted `qpic.y.qq.com`/`p.qpic.cn`/`y.gtimg.cn` hosts. KuGou exact-path HTTP/HTTPS artwork bytes matched, but no shared TME host/pattern exists and no shared helper was created. |
| QQ/WeChat as upstream identity | `SIMILAR_BUT_DISTINCT` | Social identity may be offered by multiple TME products, but each service must exchange it for its own session. QQ credentials never enter KuGou. |
| Request signing/device/timestamp primitives | `UNKNOWN` | Similar-looking fields do not establish a stable shared primitive. |
| Error envelopes | `SIMILAR_BUT_DISTINCT` | Both expose status/business-code envelopes, but names and meanings remain provider-owned. |
| Track/Artist/Album/Ranking semantics | `SIMILAR_BUT_DISTINCT` | Domain concepts overlap; provider identities, categories and pagination remain distinct. |

Do not create `provider-tme`, `tme-client`, a unified Track, shared session or
shared media resolver. A small internal helper is allowed only after both
implementations prove an identical stable primitive with tests; current
evidence has not met that threshold.

## Required isolation regressions

- A QQ Track reaches only the QQ resolver, even if its opaque value resembles a
  KuGou identity.
- A KuGou Track reaches only the KuGou resolver, even if its opaque value
  resembles a QQ identity.
- QQ credentials/library state never enter KuGou dependencies.
- Future KuGou credentials/library state never enter QQ dependencies.
- KuGou catalog identity is never converted to QQ identity.
- Resolver failure stops at the owning Provider; common TME ownership never
  authorizes source fallback.

## Remaining work audit

| Area | State |
| --- | --- |
| Governance / source provenance / license audit | `DONE` |
| TME hypothesis and exact-isolation plan | `DONE` |
| Canonical Track identity | `EXTERNAL_BLOCKED` — Search owns opaque `MixSongID`, but the strict legacy detail contract failed both live gates and the modern signed/device boundary is unresolved |
| Bounded HTTP transport | `DONE` for the exact unsigned Search host |
| Track Search | `DONE_CORE` — Bridge/UI integration intentionally waits for a coherent public capability slice |
| Artist / Album / Playlist Search | `EXTERNAL_BLOCKED` — held behind the unresolved canonical Track identity gate; do not pile up endpoints |
| Track detail and public Playlist / Album / Artist reads | `EXTERNAL_BLOCKED` — strict legacy detail decoding failed twice; a scrubbed structural fixture or new evidence window is required |
| Lyrics / Rankings / evidenced recommendations | `EXTERNAL_BLOCKED` — held behind the identity/detail gate |
| Related Tracks / Comments / MV | `EXTERNAL_BLOCKED` — held behind the identity/detail gate |
| Standard Media and dfid/device safety | `HUMAN_DECISION_REQUIRED` — anonymous legacy detail yielded no URL; modern signature/device/encrypted-source boundaries are unclassified |
| High / Lossless Media | `NOT_SUPPORTED` — no proved ordinarily authorized direct unencrypted source and no entitlement model |
| Authentication / Account / User Library / writes | `NOT_APPLICABLE` |
| Provider API static routing / native singleton / Bridge | `EXTERNAL_BLOCKED` — one Search primitive is not a coherent Provider slice |
| Flutter selector / capability hiding / continuity / i18n | `EXTERNAL_BLOCKED` — Core gate is not coherent enough to expose truthfully |
| Public distribution authorization | `HUMAN_DECISION_REQUIRED` |
| Real-account acceptance | `NOT_APPLICABLE` for the public-only phase |

No safe KuGou capability remains autonomous under the current identity gate and
closed request budget. Resumption requires either a scrubbed structural fixture
that explains the legacy detail response variance, a separately authorized new
bounded evidence window, or a Human decision that classifies the modern public
signing/device boundary. None of those options authorizes a private secret,
fabricated official device, encrypted-media cracking or cross-Provider source
fallback.
