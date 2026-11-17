# NetEase Desktop EAPI session V1

Date: 2026-11-17. Execution mode: `HUMAN_DIRECTED`. Work domain: `CORE`.

This record separates three kinds of evidence:

- **static evidence**: pinned independent implementations and their request
  shapes;
- **deterministic evidence**: Fura's offline protocol, persistence, lifecycle,
  privacy and UI regressions;
- **bounded live evidence**: one disposable Human-operated QR login, one token
  refresh and one same-account verification.

It does not claim long-duration soak, universal account compatibility or that
every official NetEase client uses this exact profile.

## Selected protocol family

Fura treats the existing Official Web/WEAPI session and the new Desktop/EAPI
session as different credential families. There is no implicit conversion or
fallback between them.

The selected Desktop/EAPI contract is:

| Operation | Physical host and path | EAPI signing path | Required body |
| --- | --- | --- | --- |
| QR key | `https://interface.music.163.com/eapi/login/qrcode/unikey` | `/api/login/qrcode/unikey` | `type=3` plus the bounded Desktop profile |
| QR poll | `https://interfacepc.music.163.com/eapi/login/qrcode/client/login` | `/api/login/qrcode/client/login` | `type=3`, QR key plus the same installation/profile context |
| Refresh | `https://interface.music.163.com/eapi/login/token/refresh` | `/api/login/token/refresh` | the same bounded Desktop profile and current session cookies |

The poll host is intentionally `interfacepc.music.163.com`. Independent client
evidence records that another route can lose the login response's `Set-Cookie`
material. Fura does not retry with another host.

The accepted session document is Credential V3 and records its explicit family
plus bounded `MUSIC_U`, optional `MUSIC_R_U`, optional `__csrf` and optional
`NMTID`. Credential V1/V2 imports migrate only to `official_web`; old documents
are never guessed to be Desktop/EAPI.

## Installation identity

The selected profile uses one Fura-owned 52-character uppercase hexadecimal
installation identity. It is generated once, stored separately from the
account credential, restored before account restoration or login, and retained
across logout. It is not a copied physical-device identifier or attestation.

Evidence classification:

- the 52-hex shape and stable reuse within this protocol family:
  **HIGH-CONFIDENCE** static evidence;
- the same Fura identity being used throughout the bounded login/refresh gate:
  **CONFIRMED**;
- the proposition that the upstream would reject the same request without it:
  **UNPROVEN** because no A/B probe was authorized or performed.

An invalid stored identity fails closed before account credential import. Fura
does not silently rotate it to evade a rejection.

## Bounded live gate

The disposable gate used an isolated session and did not read or write the
application Vault. The Human performed the account login. Fixed, secret-safe
diagnostics reported:

- QR login: one QR-key request, bounded polling, `MUSIC_U`, independent
  `MUSIC_R_U`, `__csrf` and `NMTID` present;
- refresh: exactly one request; `MUSIC_U`, `MUSIC_R_U` and `__csrf` updated;
  `NMTID` was absent from the rotation and the merged candidate remained
  locally refreshable;
- verification: exactly one same-account comparison accepted the candidate;
- final classification: `PASS / account_verification / ACCEPTED`.

The refresh request deliberately omitted `MUSIC_R_U`. The server still accepted
the request and issued a new `MUSIC_R_U`. Therefore, for this selected EAPI
contract and observed session, pre-request R is **CONFIRMED NOT REQUIRED**. This
does not prove that R is irrelevant to every NetEase endpoint or login family.
No value is copied from `MUSIC_U` to invent R.

The gate made no retry, no alternate-host request, no Official-Web fallback and
no device/profile rotation. Temporary QR material was removed after completion.

## Production architecture

Production construction enables the existing NetEase continuation owner, but
the owner dispatches strictly by the credential's explicit family:

| Credential family | Login source | Automatic continuation | Refresh protocol |
| --- | --- | --- | --- |
| `desktop_eapi` | native type-3 QR | **enabled** | selected EAPI contract above |
| `official_web` | isolated Chromium/WebView compatibility login | **disabled** | existing WEAPI candidate remains unproven and disconnected |

Desktop/EAPI refresh reuses the existing Provider-owned single-flight and
durable lifecycle: current/staged Vault slots, candidate verification,
publish-before-commit, account-generation dominance, startup/resume recovery,
safe-read retry-once and mutation no-replay. A refresh response may update only
a subset of the four allowlisted session cookies; omitted values are retained,
explicit deletions are respected, and the complete merged candidate is verified
before install.

The installation identity has its own durable key and owner. Account logout
deletes the account transaction but preserves the installation identity.
Account replacement and same-account relogin still invalidate stale refresh
work; neither identity persistence nor a successful refresh can resurrect a
retired credential generation.

Flutter now presents native QR as the primary NetEase action. Official Web
remains available as a compatibility fallback with explicit copy that it may
require another login after expiry.

## Evidence sources

No third-party source was copied into Fura. These pinned sources were consulted
for protocol behavior and independently reimplemented behind Fura's existing
transport, credential and lifecycle boundaries:

| Source | Pin / license | Relevant evidence |
| --- | --- | --- |
| `HyPlayer/HyPlayer.NeteaseProvider` | `c11cd1278ed0b3a232242eded7e6d14d1c9f8683`, MIT | EAPI request/profile construction and stable installation context |
| `chaunsin/netease-cloud-music` | `77f510b48f9f7956f83fcf7fe8bdb348ae6ab92b`, MIT | direct EAPI login/refresh shapes and response-cookie rotation |
| `Dustella/NSNC` | `f4bbcf3a945ee018ab278323b7e1dafa5718872d`, WTFPL-2.0 | type-3 QR host distinction and login `Set-Cookie` behavior |
| `AcceleratorPan/TinyCloudMusicDesktop` | `51ca3abcae9eb0f534467df9a3fbd54ebf4f5d5f`, root license not established | corroborating behavior only; no implementation copied |
| `Tsukimi-Mizuki/A-Multi-functional-Playlist-Syncer` | `8876509ff790f0aa659cfbf00e45a5b926254b84`, AGPL-3.0 | corroborating refresh response/cookie behavior only; no implementation copied |

## Root-cause classification

- **CONFIRMED ROOT CAUSE:** Fura's production login was an Official-Web family
  whose bounded capture did not provide the refresh material required by the
  old WEAPI candidate. Production therefore had no proven continuation and a
  definitive authenticated rejection eventually became reauthentication.
- **HIGH-CONFIDENCE CONTRIBUTOR:** the previous production QR presentation did
  not create the independently evidenced Desktop/EAPI type-3 family and Fura
  had no separately persisted stable installation identity for that family.
- **NOT SUPPORTED:** missing `MUSIC_R_U` by itself is the sole cause. The selected
  EAPI refresh passed without sending R and rotated an independent R in the
  response.
- **UNPROVEN:** months-long session durability, every supported OS's native
  secure-storage behavior, and all account/risk-control variants.

## Verification boundary

Offline tests cover exact family routing, EAPI encryption/decryption, route and
signing separation, QR state handling, cookie allowlisting/conflict/deletion,
partial rotation, no-R refresh input, installation persistence, staged recovery,
generation races, safe-read retry-once, mutation no-replay, Bridge redaction and
Flutter login presentation. The bounded live PASS proves one current disposable
session. It is not a substitute for long-duration production soak.
