# NetEase `webview_all` Official Login Trial

Date: 2026-09-14. Decision: HD-027. Candidate: `webview_all 1.4.1`.
Execution: `AUTONOMOUS_DEVELOPMENT / MIXED`. Promotion gate:
`HUMAN_REVIEW`.

## Decision and dependency audit

This is a bounded candidate, not a claim that embedded WebKit has become
generally safe. The earlier Human Linux evidence remains authoritative: the
previous WebKit candidate produced EGL/DMABuf and GStreamer failures followed
by a Flutter device disconnect. `webview_all` is still WebKitGTK-backed on
Linux, so a successful machine soak only permits a Human real-account and
stability trial.

The selected package is pinned exactly to `1.4.1`, is MIT licensed, requires
Dart `^3.9.0` and Flutter `>=3.35.0`, and documents Android API 24+, iOS 13+,
macOS 10.15+, Windows 10 1809+, and Linux WebKitGTK 4.1. Fura currently uses
Flutter 3.47.1 / Dart 3.13.1, resolves Android `flutter.minSdkVersion` to API
24, targets iOS 15 and macOS 12, and therefore did not raise an application
platform floor for this candidate.

Linux packaging now installs `libwebkit2gtk-4.1-dev` in the existing
cross-platform development workflow. Generated Linux, macOS and Windows plugin
registrants are dependency output, not hand-written platform implementations.

## Linux host and renderer evidence

| Property | Observed value |
|---|---|
| Session | Wayland (`XDG_SESSION_TYPE=wayland`, `WAYLAND_DISPLAY=wayland-0`) |
| Flutter backend environment | inherited `GDK_BACKEND=wayland`; the trial did not inject it |
| WebKitGTK | 2.52.5, API 4.1 |
| GTK | 3.24.52 |
| GStreamer | 1.28.6 |
| Discrete GPU | NVIDIA GeForce RTX 2060 Max-Q, `nvidia` driver |
| Integrated GPU | AMD Renoir, `amdgpu` driver |
| Renderer overrides | none |

No DMA-BUF disable, software-rendering switch, X11 override, sandbox disable,
TLS bypass or other process-global renderer workaround was set. Because the
default environment passed the bounded probe, there is no diagnostic override
A/B result to promote. Any future need for a global renderer override returns
to `HUMAN_DECISION`.

## Linux-first probe

`apps/flutter/integration_test/webview_all_linux_stability_test.dart` owns a
disposable loopback HTTP server and a synthetic HttpOnly cookie. The probe does
not use a real account, retain browser data, or log page contents or cookies.

Results on the host above:

- 50 visible create/load/input/JavaScript/scroll/resize/unmount/close cycles
  completed in the default runtime;
- native crash count: 0;
- Flutter device disconnect count: 0;
- the local server's `fura_webview_probe=synthetic; HttpOnly; SameSite=Lax`
  value was absent from `document.cookie` but present through
  `WebViewCookieManager.getCookies(...)`;
- `WebViewDataManager.clearAllWebsiteData()` completed and the native cookie
  query no longer returned the synthetic cookie;
- an opt-in render-only request to `https://music.163.com/#/login` reached an
  interactive/complete document at the exact allowed HTTPS origin;
- the first render probe waited only for `onPageFinished` and timed out without
  a native crash. The probe was corrected to accept the browser document's
  `interactive` or `complete` readiness because the current site can retain
  network activity. The corrected probe passed in approximately six seconds
  during development and in approximately three seconds in the final
  current-tree run;
- the WebKit child process seen immediately after exit disappeared by the next
  one-second observation; no persistent probe process was observed.

The official-page probe performed no login. Rendering evidence is not account
acceptance, CAPTCHA compatibility, restart persistence or long-duration Linux
stability evidence.

## Final machine verification

The final current-tree checkpoint produced the following bounded evidence:

- `cargo fmt --all -- --check` passed;
- `cargo test --locked --workspace` and
  `cargo test --locked --workspace --all-targets` each passed 550 tests with 23
  explicit live/Human tests ignored;
- `cargo clippy --locked --workspace --all-targets -- -D warnings` passed;
- `flutter gen-l10n` completed, and Dart formatting checked 253 files with zero
  changes;
- the first full Flutter run exposed one missing ARB placeholder description;
  after correcting that metadata, its focused seven tests and the complete 588-
  test Flutter suite passed;
- `dart analyze .` reported no issues. `flutter analyze` did not reach code
  diagnostics because this SDK's analysis-server LSP initialization payload was
  truncated and exited 255; that pre-existing tool-process failure is retained
  as a limitation rather than reported as a code diagnostic;
- the deterministic Linux integration run passed the HttpOnly/cleanup and 50-
  cycle tests, with the account-free official-page case intentionally skipped;
  the separate opt-in official-page-only run passed;
- Linux Release built successfully. `ldd` resolves the candidate plugin,
  WebKitGTK 4.1, JavaScriptCoreGTK, the Rust library and all other dependencies
  with no `not found` entry;
- the Android ARM64 Debug APK built successfully and contains only the requested
  ARM64 Flutter and Rust native libraries among those inspected;
- no public Rust Bridge API changed, so pinned FRB generation was not needed.

An older Human-started `flutter run -d linux --debug` process remained active
during the final process audit and was deliberately not terminated. It started
before these final probes and had no WebKit child process. No
`WebKitWebProcess`, `WebKitNetworkProcess`, or integration-test process remained
after the final probes.

## Product candidate architecture

The candidate adds one small visible browser/session owner; it does not add a
second Provider, credential owner, vault, OAuth framework, service locator or
sidecar.

```text
LoginController
  -> OfficialWebAuthenticationGateway
  -> PlatformNeteaseOfficialWebLoginBroker
  -> visible full-screen WebViewWidget
  -> native WebViewCookieManager (MUSIC_U, optional __csrf only)
  -> minimal mutable Cookie-header bytes
  -> existing Rust stage_netease_official_web_credential
  -> pending candidate, not authenticated
  -> existing Account Summary verification
  -> existing NetEase-only secure vault after verified success
```

The initial and only currently allowed top-level origin is exact HTTPS
`music.163.com`. `about:blank` is allowed for browser initialization. HTTP,
userinfo, explicit ports, look-alike subdomains and arbitrary third-party
top-level navigation are rejected. Subresources remain browser-owned. Page
JavaScript is enabled because the official login application needs it, but
Fura performs no JavaScript credential extraction. Permission prompts are
denied and every recoverable SSL error is cancelled.

The official page owns QR, phone/SMS, device confirmation, behavior CAPTCHA and
security verification. Fura does not collect a password, submit an SMS request
from this WebView layer, automate a CAPTCHA, simulate a device, inject risk
cookies or bypass TLS.

Cookie inspection is native, single-flight and no faster than approximately
one second, with page/navigation events allowed to wake the next inspection.
Only `MUSIC_U` and an optional `__csrf` are selected. Conflicting duplicates,
empty values, non-printable/non-ASCII values, quotes, commas, semicolons,
backslashes and values beyond the existing Rust bounds are rejected before the
Bridge. The complete cookie jar is never persisted.

The immutable cookie strings necessarily exist briefly in Dart memory; this
trial does not make a false zeroization claim about them. The mutable byte
buffer is zeroed after Rust staging or when cancelled/rejected. Cookie values,
headers and tokenized URLs are not printed, placed in semantics/widget keys,
copied to the clipboard, sent to analytics, written to ARB, or placed in a
persistent Dart model.

## Lifecycle and isolation

Each attempt clears website data before creating the session and after closing
it. Success removes the WebView before staging and verification continue.
Cancel, route close, Provider switch, replacement, disposal and sign-out
invalidate the attempt generation, remove the visible view, close the owned
offscreen session, clear website data and suppress late Cookie results. Runtime
operations and close have bounded timeouts so a stuck native call cannot own
the login UI indefinitely.

Sign-out now reports browser-data cleanup separately from core or vault
cleanup. It cancels the browser attempt and attempts website-data cleanup
before clearing the NetEase native credential and NetEase-only vault. A browser
cleanup failure remains explicit and retryable after the account/vault are
removed.

The existing direct QR session, system-browser/app QR confirmation handoff,
mobile-EAPI SMS candidate and all of their tests remain available. QQ
authentication is unchanged. A widget regression starts a real fake-backed
`playing` session, opens and closes the official login route, and proves the
same Queue/playback controller, current Track and playing state remain while
the audio session receives zero stop calls.

## Sources and implementation boundary

Dependency facts and common APIs were checked against the package's
[pub.dev page](https://pub.dev/packages/webview_all),
[changelog](https://pub.dev/packages/webview_all/changelog),
[repository](https://github.com/abandoft/webview_all),
[platform setup](https://abandoft.github.io/webview_all/getting-started/platform-setup/)
and [controller guide](https://abandoft.github.io/webview_all/guides/controller/).
Fura depends on the documented common controller, Widget, navigation, Cookie,
data-manager and offscreen-session APIs rather than copying a platform binding.

The released
[go-musicfox implementation at the pinned reference commit](https://github.com/go-musicfox/go-musicfox/tree/12169a71098f8b8607bcf655eaddabf57ca14daf)
was used only as behavioral evidence for the sequence “open the official page,
observe `MUSIC_U` through a native Cookie API, verify, then persist and close.”
go-musicfox is GPL-3.0; no Go source, native binding, TLS-fingerprint behavior,
browser-header spoofing or risk-control Cookie injection was copied, ported or
vendored into this MIT-licensed candidate.

## Machine and Human boundaries

Unit/widget coverage includes capability unavailable, bounded navigation,
candidate construction, visible presentation, cancel/close, replacement,
late Cookie suppression, malformed/conflicting Cookie rejection, timeout,
cleanup failure, explicit sign-out cleanup, existing Rust staging/verification
outcomes, vault persistence, QQ regressions, English/Chinese copy and playback
owner isolation. Existing Rust browser-credential staging tests remain the
authoritative proof that observing a browser candidate does not authenticate an
account.

The Agent did not log into a real NetEase account. Human acceptance checklist:

1. Rebuild the exact candidate and select NetEase.
2. Start official Web login and confirm the visible origin is
   `music.163.com`.
3. Complete the provider-owned login manually, including any security page.
4. Confirm Fura detects the candidate and Account Summary verification succeeds.
5. Confirm authenticated Library reads work.
6. Keep music playing while opening, resizing and closing the login route.
7. Reopen/close the route repeatedly and observe Linux stability.
8. Restart Fura and confirm the verified vault session restores.
9. Sign out and confirm only NetEase state is removed.

The Human must not share `MUSIC_U`, a password, an SMS code, a browser cookie
database or DevTools output, and must not install a MITM certificate.

Promotion requires the Human evidence above. A default-runtime WebProcess
crash, Flutter disconnect, exit hang, overlay corruption, pointer interception,
unreadable HttpOnly cookie, incomplete website-data cleanup or need for a
global renderer override immediately stops automatic promotion. The preserved
external QR-confirmation baseline remains the rollback path.
