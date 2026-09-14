# NetEase web-only login and authenticated media compatibility

Date: 2026-09-14
Decision: HD-030
Execution: Human-confirmed login plus machine-verified compatibility repair

## Outcome

The Human confirmed that the isolated Linux system-browser route completes a
real NetEase login and returns to a signed-in Fura Library. That observation
accepts the Linux login handoff itself. It does not by itself prove every
authenticated read, restart restoration, sign-out cleanup, media entitlement,
or another platform.

NetEase authentication is now **official-Web only at the product boundary**.
The Flutter gateway no longer advertises the internal QR or SMS capabilities,
the signed-out dialog contains one official-website action, and the controller
routes the generic start action to that same operation. QQ Quick Login and
QQ/WeChat QR remain unchanged. The older bounded NetEase QR/SMS protocol code
is retained below the product boundary as historical compatibility evidence;
there is no reachable Fura UI path that starts it.

The Human's first successful web-login session exposed a separate playback
defect: authenticated Library reads succeeded, but every selected NetEase Track
ended as `ServiceUnavailable`. The audio engine and provider-aware playback
router were not the failing boundary. The NetEase media client was still using
the older `interface.music.163.com` EAPI base and supplied only `MUSIC_U` and
`__csrf` in the encrypted header.

The authenticated media request now uses:

- `https://interface3.music.163.com/eapi/song/enhance/player/url/v1`;
- the already-verified `MUSIC_U` and CSRF values in both the HTTP Cookie and
  encrypted EAPI header;
- the bounded desktop request context (`os=pc`, app/version/build, resolution,
  channel, and a request-local ID);
- `level=standard` with `encodeType=flac`, while still accepting only the
  actual supported standard MP3/M4A/AAC response and never substituting a
  different Track or Provider.

The request-local context is never added to the persisted credential. Media
URIs, encrypted bodies, Cookies, Track IDs, and account data remain absent from
diagnostics. `FURA_NETEASE_MEDIA_DEBUG=1` reports only the coarse transport or
business outcome when a Human retest still fails.

## Current protocol evidence

Two current independent implementations agree on the EAPI media host. yt-dlp
uses `interface3.music.163.com`, `/song/enhance/player/url/v1`, the desktop
Cookie/header context, and `encodeType=flac`. ncmapi independently routes
`song_url` to `interface3.music.163.com/eapi/song/enhance/player/url`.

- <https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/neteasemusic.py>
- <https://github.com/benmooo/ncmapi/blob/main/routes.go>

No code was copied. Fura's existing bounded RustCrypto EAPI implementation and
typed Provider resolver remain the runtime.

## Verification and remaining gate

Deterministic tests decrypt the outgoing request and assert the exact host,
path, session/CSRF placement, desktop context, standard level, encoding hint,
and redacted response mapping. NetEase client and Provider suites, Dart
analysis, the login controller tests, the signed-out web-only Widget test, and
the full Flutter suite pass.

Real-account media playback remains `HUMAN_REVIEW` until the Human rebuilds the
current tree and successfully starts at least one ordinary entitled Track. A
null source, trial-only source, regional/copyright restriction, or individual
account entitlement remains a valid per-Track stop and must not be described as
an all-catalog playback fix.

## 2026-09-15 Android transport addendum

The authenticated request compatibility above was necessary but did not cover
the transport policy of its returned CDN URL. A separate opt-in, anonymous and
strictly bounded observation found that the current media response used plain
HTTP on the exact host `m701.music.126.net`, format `M4a`, with a 1200-second
TTL. HTTP and HTTPS Range requests to the same path/query both returned status
206, 4096 bytes and an MP4 `ftyp` signature. Neither variant required an extra
header.

The NetEase client now normalizes only strict first-party media hosts matching
`m` plus 1–4 ASCII digits under `.music.126.net` from HTTP to HTTPS. It preserves
the complete path/query, retains existing HTTPS responses and rejects
userinfo, explicit ports, fragments, foreign schemes, other NetEase labels and
lookalike suffixes. This is a Provider-private rule; it does not reuse QQ's CDN
allowlist, enable global Android cleartext traffic, add a proxy, download the
media through Flutter, or substitute another source.

After the change, the same bounded observation reports an HTTPS source while
the HTTP/HTTPS A/B still returns equivalent media bytes. Unit tests retain the
existing authenticated-media, response-code, item-code, trial/null-source,
format, quality and short-TTL compatibility paths. Real-account playback on a
physical Android device remains the independent Human gate described by the
[runtime checklist](android-system-playback-runtime-checklist.md).
