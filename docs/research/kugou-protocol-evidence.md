# KuGou protocol and product evidence

Status: active bounded research for HD-031

Last updated: 2026-09-24

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

## 2026-09-24 resumed workstream

Human opened a new `KUGOU_PUBLIC_READ_EVIDENCE_WINDOW` with an independent hard
limit of 40 HTTPS requests. The window used exactly all 40 requests and is now
closed. Every request was anonymous, read-only, single-attempt, redirect-disabled,
byte-bounded and separated from the next request by at least one second. No raw
body was retained. Structural logs contained no query, title, Artist, Album,
Track/hash identity, media URI, Cookie, token, `dfid`, device or account value.
No HTTP 429, CAPTCHA, SSA, security-verification or other risk-control signal
occurred.

The earlier negative detail evidence remains valid: the two 2026-09-15 gates
really did reject their then-assumed shape. The new window explains the
variance rather than erasing it:

- the exact mobile detail document is a flat JSON object served as
  `text/html`; its Album key is `albumid`, not `album_id`;
- `errcode=0` is the stable success signal in the observed contract, while two
  exact successful rows used different `status` values (`0` and `1`);
- Search and ranking rows each matched detail on standard hash,
  `album_audio_id`/`MixSongID`, `audio_id` and Album ID. A ranking Track also
  matched through the same chain. This accepts `MixSongID` as the canonical
  recording/version identity and retains the standard hash, `Audioid`, duration
  and optional Album ID as Provider-private exact-resolution context;
- the independently current `musicdl` implementation at
  `e5c3bd51b518642c24027921e63f482865809b61` (PolyForm Noncommercial 1.0.0,
  evidence-only) still reads the same flat mobile detail and unsigned lyric
  pair. The current KugouMusic.NET tree at
  `0cf0db0752bc87e1bd9990b7ea7330a9965f3604` independently models
  `album_audio_id`/`MixSongID`, hash, `audio_id`, numeric/string variation and
  lyric candidate/download semantics. These current rechecks supplement rather
  than replace the pinned durable commits above;
- exact-hash lyric search returned server-issued candidates and an exact LRC
  download returned valid base64 UTF-8 with timed lines. No translation,
  romanization or word-timing field was observed, so the implementation claims
  line timing only;
- the unsigned public mobile ranking inventory returned 55 typed ranking rows.
  Ranking Tracks returned native 30-row pages, numeric total and true page 2;
  each inspected row carried the exact private Track context above;
- the public curated-playlist index returned 30 rows and real continuation
  metadata, but its detail route redirected from HTTPS to HTTP. It was not
  followed and neither Playlist detail nor Playlist Tracks was implemented;
- unsigned current Artist/Album/Playlist Search routes returned HTTP 200 with
  business error `20006`. Older catalog routes did not yield a current direct
  HTTPS contract. Search x4 therefore remains Track-only;
- four representative standard hashes were sent to the only deterministic
  legacy `kgcloudv2` candidate corroborated by a current independent source.
  All four returned HTTP 200, business `status=2`, and zero source candidates.
  Legacy detail also returned no URL. No media URI was opened or logged.
  Current modern implementations place media behind app signing plus
  device/install-shaped inputs. Those inputs were not copied, fabricated or
  replayed.

The independent Rust implementation now has strict offline fixtures for Track
detail, mixed numeric/string identity fields, rankings, native ranking paging,
exact-hash two-step lyrics, malformed rows, duplicate identities, contradictory
pagination, invalid base64 and secret-safe request diagnostics. It advertises
only Search, Catalog and Lyrics in `provider-kugou`; Catalog currently means
exact Track detail plus rankings, not the unimplemented Album/Artist/Playlist
surfaces. No Bridge or Flutter production composition was added because the
standard-media gate did not pass.

## Capability evidence matrix

| Capability | State | Evidence and next proof |
| --- | --- | --- |
| Track Search | `DONE` | Existing unsigned strict Search retained. Track IDs now carry a versioned Provider-private exact context while membership remains `MixSongID`; no title/Artist matching is used. Core only; UI remains media-gated. |
| Artist Search | `EXTERNAL_BLOCKED` | The current unsigned direct route returned business error `20006`; no safe current HTTPS alternative was established. |
| Album Search | `EXTERNAL_BLOCKED` | The current unsigned direct route returned business error `20006`; no safe current HTTPS alternative was established. |
| Playlist Search | `EXTERNAL_BLOCKED` | The current unsigned direct route returned business error `20006`; the older route is not a current direct HTTPS contract. |
| Track detail | `DONE` | The old mismatch is explained. Strict decoding accepts only `errcode=0`, observed status variants, bounded fields and exact equality for hash/MixSongID/Audioid plus known Album context. Core only. |
| Playlist detail | `EXTERNAL_BLOCKED` | Public index works, but current detail downgraded to HTTP. Fura did not follow or normalize it. |
| Playlist Tracks | `EXTERNAL_BLOCKED` | Depends on the blocked detail route; no title-based reconstruction is permitted. |
| Album detail | `EXTERNAL_BLOCKED` | Current safe unsigned HTTPS contract not established in the closed window. |
| Album Tracks | `EXTERNAL_BLOCKED` | Current safe unsigned HTTPS contract and paging not established. |
| Artist Tracks | `EXTERNAL_BLOCKED` | Current safe unsigned HTTPS contract and paging not established. |
| Artist Albums | `EXTERNAL_BLOCKED` | Current safe unsigned HTTPS contract and paging not established. |
| Lyrics | `DONE` | Exact hash + duration search, bounded first server-ranked candidate, LRC download, base64 UTF-8 and line timing are implemented. Translation, romanization, KRC and word timing are not claimed. Core only. |
| Rankings | `DONE` | Public inventory plus fixed 30-row native page contract, real page 2, total, duplicate/omission and exact Track-context mapping are implemented. Core only. |
| Recommended Playlists | `EXTERNAL_BLOCKED` | Public index is current, but the HTTPS detail/Tracks path did not remain HTTPS; no incomplete recommendation navigation is advertised. |
| New Songs | `EXTERNAL_BLOCKED` | Historical public region evidence exists, but no current exact category/pagination contract was accepted before the window closed. |
| New Albums | `EXTERNAL_BLOCKED` | Historical API evidence exists, but no current exact release-region contract was accepted before the window closed. |
| Related Tracks | `EXTERNAL_BLOCKED` | Candidate endpoints exist, but an exact safe public seed contract was not established. |
| Comments | `EXTERNAL_BLOCKED` | Product behavior exists, but independent safe request and pagination evidence remains incomplete. |
| Track-associated MV | `EXTERNAL_BLOCKED` | Association fields exist, but no exact safe HTTPS metadata/source contract was established. |
| Media source | `HUMAN_DECISION_REQUIRED` | Legacy detail returned no URL and four deterministic standard-source probes returned business `status=2` with no candidate. Modern routes still require unclassified app signing/device inputs. No resolver exists. |
| Authentication | `NOT_SUPPORTED` | No ordinary safe authentication contract was investigated or implemented; QQ/NetEase gateways are never reused. |
| Account Summary | `NOT_SUPPORTED` | Depends on a future independently authorized authentication workstream. |
| User Playlists | `NOT_SUPPORTED` | Private account read is not authorized or implemented. |
| Favorites | `NOT_SUPPORTED` | Private account read/mutation is not authorized or implemented. |
| Recent Plays | `NOT_SUPPORTED` | Private history/reporting is not authorized or implemented. |

## Canonical identity investigation

Search exposes quality-dependent `FileHash`/`HQFileHash`/`SQFileHash`, numeric
`Audioid`, and `MixSongID`/`AlbumAudioID`. The resumed evidence accepts
`MixSongID` as the canonical provider-owned recording/version key: independent
Search and ranking rows mapped it exactly to mobile detail
`album_audio_id`. The opaque Domain identity uses a versioned composite so the
Provider can carry the standard hash, `Audioid`, duration and optional Album ID
back to exact detail/lyrics without cache, title lookup or exposing protocol
field names to Flutter. Those fields are resolution context, not independent
cross-Provider identity. A quality-dependent hash is still not presented as the
canonical Track ID.

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
| Canonical Track identity | `DONE` — exact Search/ranking/detail linkage accepts `MixSongID`; versioned opaque context carries only Provider-private exact fields |
| Bounded HTTP transport | `DONE` for the exact allowlisted Search/detail/ranking/lyric hosts and paths; HTTPS-only, no redirects, 2 MiB ceiling |
| Track Search | `DONE` — existing implementation retained and migrated to the exact opaque identity |
| Artist / Album / Playlist Search | `EXTERNAL_BLOCKED` — current unsigned routes returned business `20006`; no older HTTP fallback is used |
| Track detail | `DONE` — strict exact-context client and Provider mapping are implemented |
| Public Playlist / Album / Artist reads | `EXTERNAL_BLOCKED` — Playlist detail downgraded to HTTP; Album/Artist reads lack a current safe contract |
| Lyrics / Rankings | `DONE` — exact LRC and native Ranking paging are implemented |
| Recommendations | `EXTERNAL_BLOCKED` — current public detail/navigation remains incomplete |
| Related Tracks / Comments / MV | `EXTERNAL_BLOCKED` — held behind the identity/detail gate |
| Standard Media and dfid/device safety | `HUMAN_DECISION_REQUIRED` — anonymous legacy detail yielded no URL; modern signature/device/encrypted-source boundaries are unclassified |
| High / Lossless Media | `NOT_SUPPORTED` — no proved ordinarily authorized direct unencrypted source and no entitlement model |
| Authentication / Account / User Library / writes | `NOT_SUPPORTED` |
| Provider API static routing / native singleton / Bridge | `EXTERNAL_BLOCKED` — Core has a coherent public read slice, but production composition remains behind standard media |
| Flutter selector / capability hiding / continuity / i18n | `EXTERNAL_BLOCKED` — `KUGOU_UI_PRODUCTION_GATE = BLOCKED_BY_MEDIA`; the ordinary selector remains QQ/NetEase only |
| Public distribution authorization | `HUMAN_DECISION_REQUIRED` |
| Real-account acceptance | `NOT_SUPPORTED` for the public-only phase |

The bounded safe autonomous implementation is complete for Track Search, exact
Track detail, Rankings and line-timed LRC. The live window is exhausted and
closed. Ordinary UI, Bridge production routing and native composition remain
unchanged because standard media is still blocked. Resumption of media or the
other catalog/search surfaces requires a separately authorized evidence window
or a Human decision that classifies the modern signing/device boundary. Neither
option authorizes a private secret, fabricated official device, encrypted-media
cracking or cross-Provider source fallback.
