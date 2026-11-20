# QQ Music user-library evidence

- **Status:** Active research for M1 user library
- **Last checked:** 2026-08-25
- **Scope:** Authenticated account-owned and favorited playlist summaries.

This note records protocol behavior and boundaries, not reusable source code. No real account credential or user-derived response was used in this checkout.

## Sources inspected

1. [L-1124/QQMusicApi at `108617f`](https://github.com/L-1124/QQMusicApi/tree/108617ffe80abefec6358717b9f4d3677550db10), especially `qqmusic_api/modules/user.py`, `qqmusic_api/models/user.py`, and the shared song-list model.
2. [ylw1997/qqmusic-api at `5f87b07`](https://github.com/ylw1997/qqmusic-api/tree/5f87b07b85923f8862d7b57f9d558ce0314ba1a7), especially `docs/apis/get-my-playlists.md` and its executable `my_playlists` request.
3. [yakult-green-tea/qq-music-api at `2c27d6b`](https://github.com/yakult-green-tea/qq-music-api/tree/2c27d6b90dd56bcf0796883e27216f69189d8f68), especially `src/services/auth/qrLogin.ts`, the native QR probe, and authenticated service tests.
4. [feeluown-qqmusic at `241a967`](https://github.com/feeluown/feeluown-qqmusic/tree/241a9678bcd26e88d19e08e5da8048018f06e330), especially its separate legacy favorite-playlist request and `dissid`/`title` mapping. This corroborates collection/identity semantics, not the musicu RPC envelope.

## Account-owned playlist request

All three implementations agree on:

- `POST https://u.y.qq.com/cgi-bin/musicu.fcg`;
- module `music.musicasset.PlaylistBaseRead`;
- method `GetPlaylistByUin`;
- parameter `{uin: String(credential.musicid)}`;
- authenticated musicu comm plus the QQ Music credential Cookie;
- the created/owned list at `data.v_playlist`.

The implementations use different envelope labels and client identities. Ylw's current executable request uses the named `music.musicasset.PlaylistBaseRead` key with the lightweight `ct=11` comm already validated by this project's authentication work. L-1124 and yakult confirm the same module, method, parameter, credential semantics, and response path. The project therefore keeps the smaller named envelope rather than introducing Android device/QIMEI state for this request.

The client requires zero global and named-result codes, bounds the response to 1 MiB with a 30-second request timeout, and retains transport, HTTP, malformed response, non-rejection upstream errors, and the observed credential-rejection codes as distinct failures.

## Minimum response mapping

The account-owned list consistently identifies rows with:

- `tid` — the playlist ID used for ordinary playlist identity;
- `dirId` — the account directory ID used by built-in and mutation paths;
- `dirName` — display name;
- `songNum` — track count when present;
- `picUrl` — cover URL when present.

The client preserves both numeric IDs and rejects a row missing `tid`, `dirId`, or a nonblank name. Cover and track count are optional because current authenticated test fixtures do not always include them. Diagnostics redact playlist IDs and names, and offline fixtures use synthetic values only.

The `dirId: 201` built-in “liked songs” directory is not a generic `disstid`. Current implementations fetch its contents through `CgiGetDiss` with `disstid: 0`, `dirid: 201`, and an encrypted host UIN. Preserving `tid` and `dirId` separately now avoids making the later detail slice guess between incompatible identifiers.

## Deliberate boundary: favorited playlists

`GetPlaylistByUin` is the owned/created collection. L-1124 and yakult independently retrieve favorited playlists through `music.musicasset.PlaylistFavRead/CgiGetPlaylistFavInfo`, using the credential's encrypted UIN plus explicit `offset`/`size` pagination. Both read rows from `data.v_list`, total count from `data.total`, and continuation from `data.hasmore`; L-1124's authenticated test expects `hasmore` as `0` or `1`, while yakult defensively accepts either that representation or a boolean.

Favorite rows use a generic playlist ID (`id`, with current model aliases for `tid`/`dissid`), title, optional cover, and optional song count. They do not carry the account-owned `dirId` identity needed by the built-in liked-songs path.

The project now implements one bounded favorite page in `QQMusicClient`: page size is restricted to `1..=100`, response bodies remain capped at 1 MiB/30 seconds, missing encrypted UIN fails before transport, `hasmore` accepts only boolean or numeric `0`/`1`, and raw response models do not escape the protocol crate. Default tests use synthetic pages and cover exact request shape, pagination, aliases, missing identity, credential rejection, unrelated upstream failure, and redacted diagnostics.

Provider aggregation now loads owned rows first and follows favorite pages in order. It advances by raw page length before deduplication, rejects an empty page that still claims `hasmore`, caps the current operation at ten 100-item pages, deduplicates against owned and earlier favorite rows by QQ playlist ID, and rechecks the exact credential after every await. Explicit rejection clears only the still-current credential; transient and structural failures retain it. Owned and favorite routes use distinct provider-owned opaque IDs.

The single-use cancellable Bridge handle now calls the complete Provider contract, and Flutter presents the result as “Your playlists”. The generated boundary still carries only provider/opaque ID, title, optional artwork/count, and coarse failures. A favorite opaque ID regression proves it is forwarded without parsing; structural or safety-limit errors return no partial list.

## Evidence still required

1. Human visual acceptance of the rebuilt Heart state. No real like/unlike
   mutation was sent by this read-only investigation.
2. Later-page live evidence for the other User Library collections before
   generalizing their bounded first-page compatibility to every account size.

## 2026-11-20 production Retry investigation

A maintainer reported Retry on an authenticated QQ library. The affected
session's login family, encrypted identity presence, concrete Flutter failure,
and request phase are unobserved. This report alone does not establish an
upstream failure or prove that reauthentication would change the outcome.

### Current Fura path and failure behavior

`main.dart` supplies `RustUserLibraryGateway` with the provider's session
continuation. `UserLibraryPage` owns `UserLibraryController`, which calls the
gateway. Its cancellable Bridge handle calls `UserPlaylistsProvider` and maps
each typed error to an empty failure envelope. The Flutter gateway maps the
envelope, with its existing refresh-once/retry-once path limited to explicit
credential rejection. The controller selects the stage and Retry policy.
Liked Songs shares this controller to discover directory 201. Favorite albums
and artists have their own page gateways and state.

| Initial Flutter failure | Stage | Retry | Sign in again |
| --- | --- | --- | --- |
| `network`, `serviceUnavailable`, `invalidResponse`, `coreUnavailable` | `error` | Yes | No |
| `alreadyRunning` | `error` | No | No |
| `credentialRejected`, `credentialRejectedStorageCleanupFailed` | `credentialRejected` | No | Yes |
| `authenticationRequired`, `replaced`, `cancelled` | `authenticationRequired` | No | Yes |

These are controller states for a delivered initial failure. A superseded
operation can be ignored by generation. Refresh with a prior content or empty
stage can keep the last complete snapshot for the retryable failures or
`alreadyRunning`. A credential rejection whose continuation encounters a
temporary problem can be surfaced by the gateway as `serviceUnavailable`.

The QQ aggregate requires an authenticated snapshot, then checks
`encryptUin` before any request. If absent, it returns `InvalidResponse`.
The standalone owned read requires the same authenticated snapshot but has no
encrypted-identity precondition. Synthetic tests demonstrate that it can
discover directory 201 even when the aggregate sends zero requests. In
production the aggregate's failed stage prevents that discovery in the Likes
page. Opening the directory via its typed route is a distinct request and
does require encrypted identity in the current client.

After preflight, the aggregate reads owned rows, checks generation, maps
rows, then reads favorite pages in order. The first owned error prevents
favorite requests. A favorite error after owned success discards this
operation's uncommitted rows. Explicit authorization rejection is typed and
the current Provider marks the exact credential for continuation. Network,
HTTP/upstream and shape failures keep the credential. A replaced generation
discards the result before mapping or publication. Continuation advances by
raw row count, deduplicates by playlist ID, rejects an empty nonterminal page
and stops at ten pages with `InvalidResponse`. A duplicated nonempty
nonterminal page advances the raw offset and can run to the cap. The synthetic
repeated-page test proves the bound, not live pagination incompatibility.

Missing encrypted material is deterministic for a fixed credential, so Retry
alone is insufficient for this branch. The same error currently represents
malformed replies and pagination failures. `omitted_playlist_count` counts
individual unusable rows from successfully decoded collections. It cannot
honestly express an unread source whose row count is unknown. A missing
credential field, temporary outage, structural response failure and pagination
safety stop would need distinct evidence and truthful incomplete semantics.
Explicit credential rejection must remain separate. No aggregate or
presentation policy was changed in this investigation.

### Current wire paths and evidence levels

Each current request uses the credential's canonical music ID and music key
through its numeric/opaque account parameters, authenticated comm and/or
Cookie, with login type carried by the request profile. `str_musicid` is
preferred during decode when usable. Neither endpoint builds a request out of
`openid`, `unionid`, `refresh_token`, `refresh_key`, or expiry as parameter
prerequisites. Expiry and renewal fields belong to session lifecycle.

| Capability | Current endpoint and envelope | Extra material and cursor |
| --- | --- | --- |
| Owned playlists | `music.musicasset.PlaylistBaseRead/GetPlaylistByUin`, named module key, `data.v_playlist` | String music ID in `uin`, no encrypted identity, one response |
| Favorite playlists | `music.musicasset.PlaylistFavRead/CgiGetPlaylistFavInfo`, named key, `v_list/total/hasmore` | Encrypted `uin`, `offset/size`, Boolean or numeric 0/1, generic numeric playlist ID with aliases |
| Liked songs | `music.srfDissInfo.DissInfo/CgiGetDiss`, named key, `songlist/total_song_num/hasmore` | `disstid=0`, `dirid=201`, `enc_host_uin`, `song_begin/song_num` |
| Favorite albums | Legacy `c.y.qq.com` profile-asset CGI, `ct=20`, `reqtype=2`, `data.albumlist/totalalbum` | No encrypted identity, `userid` and inclusive `sin/ein` |
| Favorite artists | `music.concern.RelationList/GetFollowSingerList`, `req_0`, `List/Total/HasMore` | Encrypted `HostUin`, `From/Size`, singer `MID/Name` |

Owned, favorite playlists and liked detail use the Fura Web profile
(`ct=11`, `cv=13020508`, `tmeAppID=qqmusic`, QQ Music Cookie, JSON POST
with Web Origin and Referer). Artists use the library Web profile
(`ct=24`, `cv=4747474`), with QQ Music Cookie and Web headers. Album CGI uses
a Web Referer and the credential Cookie. These are current-code and fixture
facts. The bounded disposable Type 2 and WeChat evidence below now proves
first-page acceptance by the current client for both login families; it does
not prove later pages or the original application's stored session.

Current independent source checks:

- [L-1124/QQMusicApi at c046788](https://github.com/L-1124/QQMusicApi/blob/c046788dd1f11daacc74da487cbbf1bcd8ac6f33/qqmusic_api/modules/user.py)
  corroborates the module, collection identity, directory 201 route and
  parameter distinctions for playlists, liked songs and artists. It also
  exposes a different album RPC with encrypted `euin`; that does not establish
  that the RPC is reliable on Fura's profile.
- [yakult-green-tea/qq-music-api at 2b7c4d4](https://github.com/yakult-green-tea/qq-music-api/blob/2b7c4d4f0d3e9bc97ac55ec28b1a3e874e0be0ca/src/services/auth/authenticatedReads.ts)
  corroborates owned and favorite identity and paging. Its authenticated
  Android comm and `req_0` envelope differ from Fura's named Web RPCs.
  It reports historical successful reads of the legacy album CGI and
  nonzero `80000` for the alternative album RPC. Its owned-first policy and
  repeated-page handling are comparative evidence, not Fura semantics.
- [simple-music at d1adb95](https://github.com/Yyyangshenghao/simple-music/blob/d1adb95b75df1d6089c3f183ffb1aa350c908cad/docs/qq-music-api.md)
  documents a historical Web `CgiGetDiss` read of the liked directory using a
  separate envelope with no explicit `enc_host_uin` in its documented shape.
  This is a counterexample to a universal requirement across profiles and does
  not establish permission to remove the parameter from Fura's current route.

The earlier repository record establishes external protocol evidence,
synthetic fixtures and aggregate acceptance offline. Account-free probes and
historical external account observations are separate. The disposable gates
below additionally establish real-account acceptance by the current client,
but not Flutter UI publication, original stored-session behavior or full
pagination.

### Credential continuity and what the renewal gates covered

QQ Type 2 and WeChat login exchanges decode optional `encryptUin` into
session secrets. Blank material becomes absent. Current and staged secure
storage round-trip that optional field and restoration preserves the stored
value. Type 2 refresh decodes a complete response as its own credential; an
omitted optional field is absent there. WeChat's delta overlay inherits an
omitted `encryptUin`, replaces it on a supplied value and respects an explicit
null/empty value. The verification RPC validates the usable refreshed account
session. It does not check encrypted UIN or enrich the candidate. Successful
publication installs the staged candidate bound to the exact generation.
The retained Type 2 and WeChat renewal gates report only secret-safe field
presence and can run the shared bounded library matrix. They never print field
values or content. Their disposable evidence does not identify the login
family, credential generation or failure phase of the originally reported
stored application session.

### Diagnostics and one disposable read pass

Set `FURA_PROVIDER_DIAGNOSTIC=1` for the application if the maintainer
chooses to reproduce the same failing page. The `library phase=` entries show
the numeric login type, encrypted-identity presence before transport, the
owned/favorite classification, and successful mapping counts or the aggregate
pagination stop. Share just those fixed-field lines. Core takes no independent
action on the application's stored login.

The ignored Debug-only read gate reuses the repo's fresh QQ Type 2 QR helper.
It prints presence flags, then attempts at most one account verification, one
owned read, and the first page of each independently addressable favorite /
liked capability. Material-dependent reads report `NOT_RUN` when required
material is absent. The gate terminates on rejected credentials, HTTP/risk
failures, transport failure and nonzero or unclassified wire envelopes. A
known zero-code envelope with a parse failure can still permit the next
distinct read. The gate has no redirects or retries for the library calls.
No vault is involved. The HTTP submission flag records handoff to transport,
not proof of upstream receipt when HTTP status is absent. No response bytes,
request bytes or account content enter diagnostics. The QR image inherits the
existing private create-new/removal behavior.

```bash
qr_dir=$(mktemp -d)
FURA_QQ_USER_LIBRARY_GATE=1 FURA_QQ_USER_LIBRARY_QR_PATH="$qr_dir/login" \
  cargo +1.97.1 test --locked -p qqmusic-client \
  --test live_qq_type2_refresh_gate \
  bounded_disposable_qq_user_library_gate \
  -- --ignored --exact --nocapture
```

Scan and confirm the one fresh QR when READY appears. The output file uses
the transport-provided .png or .jpg extension. The gate was validated against
synthetic responses and the disabled path before its bounded live runs below.
Even accepted first pages do not prove later pages, UI acceptance, or the
login family of the reported session. Choose a production change only from an
observed failing phase and revalidate the same behavior after it.

### 2026-11-20 disposable Type 2 live evidence

`NEW_DISPOSABLE_SESSION_EVIDENCE`: one fresh, process-only Type 2 QR session
was completed with explicit Human authorization. It did not read or write the
application Vault. The credential carried the core key, encrypted library
identity and all Type 2 rotation fields. Account verification, owned
playlists, favorite playlists, liked-directory discovery, one liked-song
detail page, favorite albums and favorite artists all returned HTTP 200 with
zero global/subrequest codes and were accepted by the current production
client parsers. The bounded first pages mapped 4 owned rows, 5 favorite
playlist rows, 20 liked-song rows, 1 favorite album row and 2 favorite artist
rows with zero omitted rows. No account content or opaque identity was
recorded. This proves the current Type 2 login and request profiles for that
fresh session. It does **not** reproduce the maintainer's older stored session,
identify its login family or prove that later pages accept every account.

The live result rules out a general current outage of these routes for fresh
Type 2 credentials. Because the Type 2 decoder treats refresh as a complete
credential, an omitted `encryptUin` would make the aggregate library fail
locally even while rotating token material remained usable. That synthetic
hypothesis was tested live before retaining a production change.

A second disposable Type 2 session performed exactly one refresh, one
same-account verification and the bounded library reads against the refreshed
candidate. The source contained encrypted identity, the current LoginServer
refresh response explicitly contained it, and the decoded candidate retained
it. Account verification and every bounded library read again returned HTTP
200, zero global/subrequest codes and accepted shapes with the same mapped
counts and zero omissions. The run did not use Vault, retry, fallback or
account mutation.

That result does not support omitted Type 2 refresh identity as the cause of
the reported older session. The experimental merge and partial-aggregate
production candidates were therefore removed rather than promoted. The
aggregate continues to fail closed when the evidenced encrypted identity is
missing; the independent owned-read test remains evidence that this local
preflight is the exact failure point if such a session is ever observed. The
secret-safe source/response/candidate presence diagnostic and disposable gate
remain so a future observed omission can be distinguished without exposing the
value.

The Type 2 evidence does not identify the login family or failure phase of the
maintainer's older stored session. The WeChat run below closes the current
login-family compatibility gap, but likewise cannot substitute for observing
that stored session's failure.

The post-refresh command is retained for future bounded compatibility checks:

```bash
qr_dir=$(mktemp -d)
FURA_QQ_USER_LIBRARY_GATE=1 FURA_QQ_USER_LIBRARY_QR_PATH="$qr_dir/login" \
  cargo +1.97.1 test --locked -p qqmusic-client \
  --test live_qq_type2_refresh_gate \
  bounded_disposable_qq_user_library_post_refresh_gate \
  -- --ignored --exact --nocapture
```

### 2026-11-20 disposable WeChat live evidence

`NEW_DISPOSABLE_SESSION_EVIDENCE`: one fresh, process-only WeChat QR session
was completed with explicit Human authorization. It did not read or write the
application Vault. The initial credential contained the core key, encrypted
library identity, open ID, refresh token, union ID, refresh key and expiry.
Exactly one LoginServer refresh was sent. Its raw response explicitly carried
all of those observed rotating fields, including `encryptUin`; the decoded
candidate retained the encrypted identity and remained refreshable.

The refreshed candidate passed same-account verification. The shared bounded
matrix then sent one request per capability. Owned playlists, favorite
playlists, liked-directory discovery, one liked-song detail page, favorite
albums and favorite artists all returned HTTP 200 with zero global/subrequest
codes and were accepted by the current client parsers. The first pages mapped
20 owned rows, 1 favorite playlist row, 20 liked-song rows, 13 favorite album
rows and 19 favorite artist rows with zero omissions. No pagination, retry,
fallback, mutation, stored credential, response content or opaque identity was
used or retained.

This rules out a general current incompatibility of the Fura User Library
request profiles for both fresh Type 2 and fresh WeChat credentials, including
their first post-refresh candidate. It also rules out the specific hypothesis
that the current observed WeChat refresh response omits encrypted library
identity for this session. It does **not** confirm the cause of the original UI
Retry: that older stored session's generation, login family, encrypted-identity
presence, concrete Flutter failure and failing Provider phase remain
unobserved. Consequently no speculative aggregate fallback or credential
merge was promoted.

The WeChat post-refresh command is retained for a future explicitly authorized
bounded compatibility check:

```bash
qr_dir=$(mktemp -d)
FURA_QQ_USER_LIBRARY_GATE=1 FURA_QQ_USER_LIBRARY_QR_PATH="$qr_dir/login" \
  cargo +1.97.1 test --locked -p qqmusic-client \
  --test live_wechat_refresh_gate \
  bounded_disposable_wechat_user_library_post_refresh_gate \
  -- --ignored --exact --nocapture
```

### 2026-11-20 stored-application Heart Retry root cause

`ORIGINAL_SESSION_EVIDENCE`: Fura Debug restored the maintainer's existing
QQ session through the normal application path. No credential was exported or
printed. The aggregate User Library accepted its credential snapshot and
encrypted identity, accepted the owned and favorite requests, and mapped 20
owned plus 1 favorite playlist with zero omissions. The page-level library
Retry was therefore not reproduced.

The expanded Now Playing Heart did reproduce its independent failure. Its
Liked Songs membership preload sent 12 bounded pages and finished `paused`.
The controller had reached the terminal page, but one raw row had made the
whole membership snapshot inexact. At that point the Heart exposed Retry;
however `resolve()` called `preload()`, whose terminal guard returned without
sending a request. Retry could therefore remain a permanent no-op.

The QQ membership key used by both displayed tracks and raw collection rows is
exactly numeric song ID plus primary song type. The client incorrectly also
required the playback/display `song_mid` before retaining that membership key.
A historical row with ID and type but without a usable playback mid was
omitted from presentation, then unnecessarily poisoned every negative
membership result in the account snapshot.

The client now retains membership identity whenever the exact membership key
is present, independently of whether the row can become a playable/displayable
track. Presentation omission remains fail-closed and counted. A terminal
inexact snapshot still never fabricates `notLiked`; explicit Retry now starts
an offset-zero refresh, exposes loading, and commits only a complete exact
replacement. After rebuilding the application against this change, the same
stored session again read the aggregate library successfully, scanned the same
12 Liked Songs pages, and finished `success` rather than `paused`.

Deterministic regressions cover a row lacking playback mid that still maps the
provider's exact membership key, a terminal inexact snapshot that performs a
real offset-zero retry, unknown state never issuing a blind mutation, the
expanded Heart becoming actionable after reconciliation, and the Compact
outer player continuing to hide Heart. No real like/unlike mutation was sent
during this investigation.
