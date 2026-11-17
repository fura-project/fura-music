# QQ Music / NetEase session constraint audit

Date: 2026-11-17. Execution mode: `HUMAN_DIRECTED`. Work domain: `CORE`.

This began as a static/community/implementation audit. Its 2026-11-17 bounded
follow-up used one disposable Human-operated QQ Type 2 login, one refresh and
one same-account verification; it did not read an application vault or reuse a
stored credential. The evidence labels below are:

- `A`: upstream protocol/runtime evidence;
- `B`: active independent implementation evidence;
- `C`: Human Decision or security boundary;
- `D`: Fura architecture/correctness requirement;
- `E`: historical implementation preference;
- `F`: historical research assumption;
- `G`: unknown;
- `H`: bounded Human-operated live observation.

## Constraint matrix

| Provider | Constraint | Current Fura position | Source | Evidence strength | Audit disposition |
| --- | --- | --- | --- | --- | --- |
| QQ | Refresh scheduling | Five-minute pre-expiry checkpoint; authenticated rejection may refresh immediately | B/E | `CONFLICTING` | Five minutes is a conservative product policy, not a proven wire precondition. Keep it for production scheduling for now; do not use it to suppress a bounded protocol gate. |
| QQ | Type 2 request `musicid` | Previously serialized as a JSON string | B plus resolved runtime issue | `STRONG` | `RESULT B`: direct implementations and an upstream issue require a JSON number. Fixed with a deterministic regression. |
| QQ | Type 2 endpoint/profile | Fura Web outer profile plus `music.login.LoginServer/Login` | B/F | `CONFLICTING` | Current direct clients use both `LoginServer/Login` and `QQConnectLogin/QQLogin`, and Web/Desktop/Android outer profiles. Do not add fallback or switch profile without one discriminating live observation. |
| QQ | Music-key lifetime vs OAuth expiry | Stored separately | B plus issue/runtime reports | `STRONG` | Retain. `musickeyCreateTime + keyExpiresIn` owns local key validity; opaque `expired_at` owns Type 2 refresh serialization. |
| QQ | `needRefreshKeyIn` | Parsed by external implementations but not retained/used by Fura | B/G | `WEAK` | Its existence is corroborated; its unit and scheduling semantics are not. Do not invent a deadline from it. |
| QQ | Stable client/device profile | Fura refresh uses a bounded Web profile with no installation identity | B/C/G | `CONFLICTING` | HD-036 permits a Fura-owned stable identity, but current evidence does not prove it is required for this capability. No change. |
| QQ | Same-account verification, staged publish, generation dominance | Required before installing a refresh candidate | C/D | `CONFIRMED` | Retain regardless of wire profile. |
| QQ | Read retry vs mutation replay | Safe read may retry once after refresh; mutation never replays | C/D | `CONFIRMED` | Retain. |
| QQ | Type 2 production activation | Enabled independently alongside verified WeChat continuation after the corrected bounded gate passed | C plus bounded live evidence | `CONFIRMED` | Production construction enables both verified login types; activation bits and lifecycle ownership remain independent. |
| NetEase | Login-source equivalence | Official Web, QR, imported cookie and App/EAPI material are treated as potentially different | A/B/G | `HIGH-CONFIDENCE` | Retain distinction. Available evidence does not prove that every source yields a refreshable session. |
| NetEase | Persisted cookie set | Only `MUSIC_U`, optional independent `MUSIC_R_U`, and optional `__csrf` | E/F | `CONFLICTING` | Active clients generally use a CookieJar, but that alone does not prove which additional cookies are semantically required. Current minimal document is not externally proven complete. |
| NetEase | Refresh eligibility | Credential-family specific | B/F/H | `CONFIRMED` for one bounded Desktop/EAPI session | Official Web supplied U/CSRF but no R and remains disconnected from refresh. A separate type-3 Desktop/EAPI gate issued U/R/CSRF/NMTID and then passed one EAPI refresh and same-account verification even though the refresh request deliberately omitted R. Never copy U into R and never route Official Web into EAPI. |
| NetEase | Refresh endpoint | WEAPI `/weapi/login/token/refresh` (wire path `/api/login/token/refresh`) | B | `STRONG` | Multiple active implementations corroborate it. EAPI exists but is a different profile and is not a fallback. |
| NetEase | Refresh response rotation | Fura requires changed `MUSIC_U` and changed `MUSIC_R_U` in one response | D/F | `WEAK` | Atomic durable candidate install is required, but the exact requirement that both named cookies rotate in the same response is Fura-specific and needs a bounded observation. |
| NetEase | Full `Set-Cookie` retention | Known non-auth cookies are currently ignored | B/E/G | `CONFLICTING` | CookieJar clients accept all server rotation; wrappers do not isolate the minimal set. A controlled allowlisted session document is a candidate, not yet a justified redesign. |
| NetEase | Installation identity / App profile | Desktop/EAPI uses one separately persisted Fura-owned 52-hex identity; Official Web remains unchanged | B/C/H | `HIGH-CONFIDENCE` profile evidence; causal necessity `UNPROVEN` | The identity was stable across the bounded gate and is never copied from a physical device or rotated after rejection. No A/B request was made to prove the service rejects an otherwise identical request without it. |
| NetEase | Same-account verification, staged publish, generation dominance | Required before installing a refresh candidate | C/D | `CONFIRMED` | Retain regardless of future session representation. |
| NetEase | Production activation | Enabled only for explicit `desktop_eapi`; disabled for `official_web` | C/H | `CONFIRMED` | One disposable type-3 Desktop/EAPI login, one refresh and one same-account verification passed. Credential V3 family routing prevents Official Web, migrated V1/V2 documents or unknown families from entering EAPI continuation. |

## Evidence inventory and lineage

| Source | Pin / license | Direct observation | Independence note |
| --- | --- | --- | --- |
| [L-1124/QQMusicApi](https://github.com/L-1124/QQMusicApi/tree/c046788dd1f11daacc74da487cbbf1bcd8ac6f33) | `c046788d`, GPL-3.0 | `qqmusic_api/models/request.py::Credential` models key creation/lifetime, OAuth expiry and `needRefreshKeyIn` separately; `qqmusic_api/modules/login.py::refresh_credential` sends numeric Type 2 `musicid` to `LoginServer/Login`. [Issue 90](https://github.com/L-1124/QQMusicApi/issues/90) identifies a real string-versus-number Type 2 refresh rejection; [issue 105](https://github.com/L-1124/QQMusicApi/issues/105) reports a music-key lifetime shorter than OAuth expiry. | Direct wire implementation; evidence-only because of license. |
| [amtoaer/lyrune](https://github.com/amtoaer/lyrune/tree/84a50e13319c337970349524651edc6e10345f09) | `84a50e13`; root license unclear, API lineage identifies MIT AstronW upstream | `crates/lyrune-api/src/account.rs::ensure_fresh/is_expiring` uses a five-minute key-expiry window; `src/login.rs::refresh_login_token` sends numeric Type 2 `musicid` and its current open/access-token branch uses `QQConnectLogin.LoginServer/QQLogin` with Desktop `ct=19`. | Useful conflicting product evidence, not a clean second vote for all inherited protocol code. |
| [jrz233/wow-music-agent](https://github.com/jrz233/wow-music-agent/tree/bdc0b0e439beb6c0be188f75a5b360dc078cb0c6) | `bdc0b0e4`, MIT | `src/qq/client.ts::QQClient.refresh` uses an Android/App-shaped stable profile, a six-hour pre-expiry lead and bounded daily rotation; `RawNumber` preserves numeric account identity. | Independent product-policy evidence; its interpretation of `needRefreshKeyIn` is not an upstream specification. |
| [modenicheng/hutao-music-player](https://github.com/modenicheng/hutao-music-player/tree/1df3fa43f4c9386015aaa3d805504a806b338273) | `1df3fa43`, GPL-3.0 | Preserves the same QQ lifetime fields and numeric identity. | A port/derivative of L-1124; not counted as an independent wire vote. |
| [chaunsin/netease-cloud-music](https://github.com/chaunsin/netease-cloud-music/tree/77f510b48f9f7956f83fcf7fe8bdb348ae6ab92b) | `77f510b4`, MIT | `api/api.go::NewClient/Request` owns a persistent RFC6265 CookieJar; `api/weapi/login.go::TokenRefresh` uses WEAPI and `os=pc`, with a source note recording business code 400 without `MUSIC_R_U`; response cookies rotate through the jar. | Active direct implementation. Its `api/eapi/login.go::TokenRefresh` is not established as working. |
| [go-musicfox/netease-music](https://github.com/go-musicfox/netease-music/tree/912f2cf2b8bf772c804c6cd4b4f31f11773c7b93) | `912f2cf2`, MIT | `service/login_refresh_service.go::LoginRefresh` calls WEAPI through `util/request.go::GetGlobalCookieJar`; request strategy also applies profile cookies and stable-in-process device context. | Active real client with historical NeteaseCloudMusicApi lineage; proves product behavior, not minimal server requirements. Risk/unblock strategies are not adopted. |
| [NeteaseCloudMusicApiEnhanced/api-enhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/tree/75bf2e5ca209f4f1b3f822fa65d9f7b67e4b53ec) | `75bf2e5c`, MIT | `module/login_refresh.js` accepts a caller cookie object through `util/option.js`, calls `/api/login/token/refresh`, and returns response cookies. | NeteaseCloudMusicApi family; not an independent minimal-cookie proof. |
| [HyPlayer/HyPlayer.NeteaseProvider](https://github.com/HyPlayer/HyPlayer.NeteaseProvider/tree/c11cd1278ed0b3a232242eded7e6d14d1c9f8683) | `c11cd127`, MIT | `HyPlayer.NeteaseApi/Bases/ApiContractBases/ApiContractBase.cs::BuildRequestCookies/MergeSetCookies` retains a cookie dictionary; EAPI bases add device/profile state. | No independent refresh contract was found. |
| [AstronW/netease-qq-music-api](https://github.com/AstronW/netease-qq-music-api/tree/11d8c5c0e23fb74169292516592b5efe9ac59540) | `11d8c5c0`, MIT | `src/platform/netease/api.rs::refresh_login_token` sends R material and EAPI profile fields. | Its QR parser fallback copies U into R; that behavior is unproved and remains prohibited in Fura. |

Repository activity dates and source shape were checked on 2026-11-17. A
source being active or permissively licensed does not make its chosen profile,
timing or anti-risk behavior a service contract.

## QQ Music

### Current Fura assumptions

- The production checkpoint uses a five-minute pre-expiry window. An exact
  authenticated rejection can request continuation independently of that
  timer. The value is a conservative scheduling choice (`B/E`), not an
  upstream deadline.
- Type 2 refresh uses `music.login.LoginServer/Login`, Web `ct=11`, current Web
  version fields, the credential cookies and no installation identity
  (`B/F`, `CONFLICTING`).
- Music-key and OAuth lifetimes are independent (`B`, `STRONG`).
- A candidate cannot become current until same-account verification, durable
  staged publication and generation-safe commit complete (`C/D`,
  `CONFIRMED`).

### Externally corroborated

- **CONFIRMED:** Type 2 `musicid` is numeric in the active direct
  implementations examined. QQMusicApi issue 90 supplies runtime evidence that
  a string-shaped value is rejected. Fura's prior bounded
  `upstream_rejected` result used the string-shaped request and therefore could
  not prove a timing restriction.
- **HIGH-CONFIDENCE:** OAuth `expired_at` is not the music-key expiry. Active
  implementations model `musickeyCreateTime + keyExpiresIn` separately, and a
  real issue reports different observed lifetimes.
- **HIGH-CONFIDENCE:** Refresh material and the music key rotate as one account
  credential, but installation/persistence correctness remains Fura-owned.

### Fura-only assumptions

- **UNPROVEN:** Five minutes is the correct universal refresh window.
- **UNPROVEN:** A newly issued Type 2 credential is protocol-ineligible for an
  explicit refresh. The earlier claim was confounded by the wrong JSON type.
- **UNPROVEN:** The Web profile is superior to Desktop or Android/App for Type
  2 refresh.
- **UNPROVEN:** `needRefreshKeyIn` is a refresh-material lifetime or a usable
  scheduling interval. Only its presence is corroborated.

### Conflicting evidence

- **CONFLICTING:** Lyrune uses five minutes; wow-music-agent uses a six-hour
  lead plus daily policy; QQMusicApi retains timing fields without supplying an
  equivalent scheduler. These are client policies, not an upstream timing
  specification.
- **CONFLICTING:** `LoginServer/Login` and `QQConnectLogin/QQLogin` both exist
  in active implementations. Outer profiles include Web, Desktop and Android
  with different stable device/session fields.

### Implemented correction (`RESULT B`)

`credential_refresh.rs` now converts the already validated decimal account ID
to a JSON number for Type 2 and fails closed before transport if conversion is
impossible. Its regression asserts the exact numeric wire shape. The ignored
Human gate no longer treats the five-minute product scheduler as a protocol
eligibility check. It still requires explicit Human authority, sends at most
one refresh and one verification, performs no vault access and remains
production-disconnected.

The production checkpoint remains at five minutes pending better timing
evidence. This preserves a conservative, already tested schedule without
claiming it is protocol-mandated.

### Corrected bounded live result and production promotion

The separately authorized disposable gate returned the fixed secret-safe
result `classification=PASS phase=account_verification detail=accepted`.
Exactly one refresh request used the corrected numeric `musicid` candidate and
exactly one same-account verification accepted its result. The gate used no
vault, mutation, retry, endpoint/profile fallback or stored credential, and its
temporary QR material was removed after completion.

This proves the current `music.login.LoginServer/Login` Web candidate worked
for one newly issued disposable Type 2 credential. It also disproves the claim
that freshness alone necessarily makes such a credential ineligible. It does
not prove that five minutes is an optimal schedule, assign semantics to
`needRefreshKeyIn`, establish long-duration soak behavior, or prove all
accounts/profiles.

After the pass, the production lifecycle was re-audited before activation.
Startup, resume, proactive expiry and authenticated-read rejection all converge
on the existing app-lifetime session owner. The Provider retains one complete
refresh-decision flight; the candidate is staged, verified as the same account,
published, committed and cleaned up with generation/epoch protection. Logout,
account replacement and identical relogin dominate late work. Safe reads retry
at most once; mutations are never replayed. Native production construction now
enables Type 2 independently alongside WeChat. The five-minute checkpoint,
endpoint and Web profile are unchanged.

## NetEase Cloud Music

### Current Fura assumptions

- Credential v2 stores required U, optional independent R and optional CSRF;
  Web capture allowlists those names and exact domains (`E/F`).
- Missing R is `NotRefreshable` before network (`B/F`, `MODERATE`). U is never
  copied into R (`C`, `CONFIRMED`).
- The WEAPI candidate sends U/R/CSRF plus `os=pc`, then requires outer 200,
  `bizCode=201`, a changed complete U/R pair, same-account verification and
  staged durable install (`B/D/F`).
- Production continuation is disabled (`C/G`).

### Externally corroborated

- **HIGH-CONFIDENCE:** Login sources are not interchangeable. Official Web,
  QR, imported browser cookies and App/EAPI clients can supply different cookie
  and profile state. Fura's historical official-Web observation found U and
  CSRF but no independent R; it did not prove that R can never be issued.
- **HIGH-CONFIDENCE:** Active clients use WEAPI token refresh and a shared
  CookieJar; one active direct implementation specifically reports R is
  required for that request.
- **CONFIRMED safety boundary:** Copying U into R is not supported by current
  independent evidence and would fabricate refresh material.
- **CONFIRMED current live source:** One bounded isolated official-Web login on
  2026-11-17 produced music-domain U and CSRF, but no R on either the music or
  parent `163.com` domain. The gate stopped before refresh, verification and
  retry. This is evidence for this login source and session only.

### Fura-only assumptions

- **UNPROVEN:** U/R/CSRF is the complete durable Web session state.
- **UNPROVEN:** Both U and R must be newly returned in the same successful
  response. CookieJar clients accept the server's whole cookie rotation and do
  not independently establish this stricter contract.
- **UNPROVEN:** `deviceId=undefined` causes long-session rejection. That value
  belongs to a media compatibility profile; no reviewed observation connects
  it to Web refresh.

### Conflicting evidence

- **CONFLICTING:** Direct CookieJar clients preserve all scoped cookies, while
  small wrappers often surface only auth cookies despite sending a larger
  caller-provided cookie collection. Neither proves the minimal server state.
- **CONFLICTING:** WEAPI/pc and EAPI/App profiles use different cookie and
  device fields. Evidence that an App profile refreshes does not prove the
  official-Web credential can be upgraded by adding App fields.
- **UNKNOWN:** Whether another observed cookie can replace independent R, or
  whether absence of R simply marks a non-refreshable login source.

### Recommended code changes

No NetEase production wire change is justified by current static evidence
(`RESULT C`). Keep the provider-owned single-flight/stage/verify/publish owner
and production gate. Do not broaden persistent cookies or invent installation
identity until a bounded observation identifies which state actually
participates.

The next design candidate, if evidence requires it, is a provider-private,
allowlisted session document that preserves domain/path/expiry and relevant
server rotation. It is not an unrestricted browser CookieJar and is not yet an
authorized implementation conclusion.

### Bounded live evidence result

The isolated official-Web gate recorded presence-only U/R/CSRF plus bounded
domain/path/expiry/security classes. U and CSRF were present; independent R was
absent. The gate returned `MUSIC_R_U_MISSING` and sent no refresh or account
verification request. This rules out production activation for the current Web
source and current WEAPI precondition, but does not prove that another login
source is refreshable or that a different Cookie can substitute for R.

Source label `H` in the matrix denotes this bounded Human-operated official-Web
observation. A future App/EAPI or other login-source investigation must remain
separate; no profile or device substitution follows from this result.

## Governance impact

- `AGENTS.md`: no change. Its action/evidence stance does not prescribe a
  client profile or credential shape.
- `docs/agent/core-development.md`: no new change from this audit. Its existing
  proportional validation/live-gate cadence is compatible with this work.
- `HD-036`: no change. It already permits public official-client profiles,
  distributed constants and Fura-owned stable installation identity while
  retaining the relevant risk, identity, entitlement and privacy prohibitions.
- Old research: the conclusion that a fresh QQ Type 2 rejection proved a
  mandatory near-expiry gate is stale. It is retained as a dated observation
  but explicitly corrected because the request encoded `musicid` with the
  wrong JSON type. Older cautions against App/Desktop profiles or stable Fura
  identities are historical constraints superseded by HD-036, not current
  prohibitions. They still do not establish that such fields are necessary.

## Validation

- `cargo fmt --all -- --check`: pass.
- `cargo test --locked -p qqmusic-client --all-targets`: all non-live tests
  pass; real-service and Human gates remain ignored.
- `cargo test --locked -p provider-qqmusic --all-targets`: 124/124 pass.
- `cargo test --locked -p qqmusic-client credential_refresh -- --nocapture`:
  8/8 pass, including the exact numeric Type 2 wire assertion.
- `python3 scripts/ci/audit_privacy_hygiene.py`: pass.
- `git diff --check`: pass.
- Current Rust 1.99 strict all-target Clippy is not green: after fixing the
  new numeric-literal lint, it still reports the pre-existing
  `qq_web_crypto.rs` documentation Markdown lint and existing test-only
  `unused_async_trait_impl` / `assert_is_empty` diagnostics. Production library
  Clippy passes with only that already-recorded documentation lint excluded.
  None of those unrelated files or lint settings was changed.

## Remaining evidence boundary

Machine-actionable static investigation and the proven QQ serialization fix
are complete for this audit. Production activation remains outside the result.
QQ needs one newly authorized bounded live gate using the corrected request.
NetEase needs the existing bounded official-Web material observation before a
session-document redesign or refresh promotion can be selected.
