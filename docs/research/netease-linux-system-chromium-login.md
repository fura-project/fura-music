# NetEase Linux isolated system-Chromium login

Date: 2026-09-14
Decision: HD-029
Implementation status: Human-accepted Linux login; broader account and media evidence remain scoped

## Outcome

The bounded native-browser experiment passed every prerequisite and the same
architecture is now integrated behind the existing NetEase
`OfficialWebAuthenticationGateway` on Linux. Fura launches an already-installed
Chromium-family browser with a new attempt-scoped profile, reads the official
session through a localhost-only Chrome DevTools Protocol endpoint, and sends
only a coarse authenticated/failure result back to Dart. `MUSIC_U` and optional
`__csrf` never cross the Rust-to-Dart Bridge.

On 2026-09-14 the Human confirmed that the external browser completed a real
login and Fura returned to a signed-in NetEase Library. The Agent still did not
type, scan, confirm, automate CAPTCHA, or inspect account credentials. This is
Human acceptance of the Linux login handoff, not evidence for every platform,
restart/sign-out behavior, personalized endpoint, or media entitlement. The
web-only product decision and subsequent media repair are recorded in
[HD-030](netease-web-only-login-and-media.md).

## Why this route

HD-027 and HD-028 rejected Linux WebKitGTK after the official page reproduced
blank DMA-BUF behavior and a native NVIDIA EGL/WebKit Web-process crash class
through both Flutter embedding and isolated Tauri/Wry. A third WebKit wrapper
would not address that renderer boundary. The system-Chromium route instead:

- uses the user's installed, independently sandboxed browser executable;
- never opens, copies, queries, or locks the user's default browser profile;
- avoids a bundled CEF/Chromium runtime, browser extension, sidecar service,
  Selenium, Puppeteer, ChromeDriver, or JavaScript Cookie extraction;
- leaves the direct QR/SMS protocol implementation below the product boundary,
  while HD-030 removes those risk-controlled routes from the NetEase UI.

Chrome's official security change requires Chrome 136 and later to ignore
remote-debugging switches for the default profile unless a non-standard
`--user-data-dir` is supplied. Fura's fresh profile is therefore both the
privacy boundary and the supported CDP bootstrap mechanism. CDP uses
`Storage.getCookies`; the older `Network.getAllCookies` method is deprecated.

Primary references:

- <https://developer.chrome.com/blog/remote-debugging-port>
- <https://chromedevtools.github.io/devtools-protocol/tot/Storage/#method-getCookies>
- <https://chromedevtools.github.io/devtools-protocol/tot/Network/#method-getAllCookies>

## Host and browser discovery evidence

Discovery order is fixed to `google-chrome-stable`, `google-chrome`, `chromium`,
then `chromium-browser`. The selected executable must canonicalize to a
root-owned, executable regular file under `/usr` or `/opt`. Snap/Flatpak launch
indirection and arbitrary PATH binaries are not accepted by this candidate.

| Field | Observation |
| --- | --- |
| command/canonical executable | `/usr/bin/google-chrome-stable` |
| browser version | `Google Chrome 152.0.7977.82` |
| native package | `google-chrome 152.0.7977.82-1` via pacman ownership |
| executable ownership/mode | `root:root`, `0755`, regular file |
| runtime directory | `/run/user/1000`, Human-owned, `0700` |

No browser Cookie database or existing profile path was opened during the
experiment.

## Standalone probe

Before production changes, the repository-external Rust probe was created at
`/tmp/fura-chromium-login-probe`. It is not a workspace member and is not part
of the product dependency graph. It uses direct process management, loopback
HTTP/WebSocket I/O, and raw CDP messages only.

Every browser launch used separate command arguments:

```text
--app=https://music.163.com/#/login
--user-data-dir=<fresh-attempt-profile>
--remote-debugging-address=127.0.0.1
--remote-debugging-port=0
--no-first-run
--no-default-browser-check
```

No `--no-sandbox`, TLS-disabling, certificate-bypass, GPU/compositor override,
proxy interception, risk-control bypass, or default-profile switch was used.
Browser stdout/stderr was not captured, preventing the CDP token-bearing URL
from entering Fura logs.

### CDP bootstrap boundary

The probe and production code both:

- read at most 4 KiB from the fresh profile's `DevToolsActivePort`;
- require exactly a non-zero port and one bounded
  `/devtools/browser/<alphanumeric-or-hyphen-token>` path;
- request `/json/version` from `127.0.0.1:<same-port>`;
- accept only `ws://127.0.0.1:<same-port>/<same-path>` or the exact
  `localhost` equivalent;
- reject user-info, query strings, fragments, path changes, non-loopback
  addresses, and port changes;
- connect at browser scope and invoke `Storage.getCookies`.

Neither the full WebSocket URL, its token, the ephemeral port, the temporary
profile path, Cookie values, nor official account content is logged.

### Synthetic HttpOnly/isolation gate

A loopback-only HTTP server set
`fura_chromium_probe=synthetic; HttpOnly; SameSite=Lax`. Browser-level
`Storage.getCookies` observed the Cookie and `httpOnly=true`; a second fresh
profile did not contain it:

```text
synthetic_cookie_found=true
synthetic_cookie_http_only=true
fresh_profile_cookie_absent=true
profile_isolation=PASS
document_cookie_dependency=false
cookie_db_opened=false
```

### Official-page no-login gate

The probe opened the exact HTTPS official login target, observed it through
`Target.getTargets`, performed no account action, then closed the browser and
deleted the profile:

```text
official_page_no_login_smoke=PASS
```

### Twenty-cycle lifecycle gate

Twenty sequential runs each created a new profile and endpoint. The browser was
closed through `Browser.close`; no forced termination or crash occurred:

```text
lifecycle_attempted=20
lifecycle_browser_started=20
lifecycle_cdp_connected=20
lifecycle_official_target_seen=20
lifecycle_closed_cleanly=20
lifecycle_forced_termination=0
lifecycle_forced_kill=0
lifecycle_profile_deleted=20
lifecycle_leftover_processes=0
lifecycle_crash_count=0
lifecycle_result=PASS
```

After the qualified runs, `/run/user/1000` and `/tmp` contained no
`fura-netease-login-*` profile and `/proc` contained no process whose argument
referenced one. The probe passed Rust format/check/strict Clippy and Release
build. Its Release executable was 2,468,200 bytes with no missing dynamic
dependency.

## Production architecture

### Ownership and data flow

```text
Flutter LoginController
  -> OfficialWebAuthenticationGateway (non-secret state only)
    -> typed Rust system-browser operation
      -> validated native browser + fresh 0700 TempDir profile
      -> exact official page + loopback ephemeral CDP
      -> Storage.getCookies
      -> exact-domain MUSIC_U + optional __csrf only
      -> provider.import_browser_credential (pending candidate)
      -> provider.verify_pending_credential (normal account endpoint)
    <- authenticated or typed coarse failure
  -> existing secure-storage export after verified success
```

The raw Cookie candidate remains inside Rust and its temporary byte buffer is
overwritten after staging. Dart receives only the outcome enum. The existing
provider export returns its opaque credential document only after account
verification, so the secure vault remains unchanged.

Linux selects this path categorically. If no validated browser exists, official
Web login is unavailable; it does not silently fall back to rejected WebKitGTK.
Other platforms retain the existing broker pending separate evidence.

### Cookie selection

The CDP result is bounded to 2 MiB. Only names `MUSIC_U` and `__csrf` on
`music.163.com` or `.music.163.com` are considered. Missing `MUSIC_U` keeps
polling. Conflicting duplicates, non-ASCII/control/separator values, a
`MUSIC_U` above 4096 bytes, or CSRF above 256 bytes fail as invalid. All other
Cookies are ignored and never enter the Provider.

### Cancellation, retry, and cleanup

- One async Rust gate serializes browser ownership. A newer generation replaces
  the previous one and waits for its cleanup before launching.
- Cancel, navigation, replacement, sign-out, and disposal invalidate the
  attempt. Sign-out also waits for the browser/profile owner to finish.
- User-closing the private browser window maps to cancellation at the Flutter
  presentation edge.
- After capture, the browser closes and the profile is deleted before staging.
  Cleanup failure overwrites/discards the candidate and saves nothing.
- Rejection clears the pending candidate through the existing Provider rule.
  Network, service, and invalid-response verification failures retain it for
  the existing explicit verification retry; they do not reopen a browser.
- Shutdown first sends CDP `Browser.close` and waits up to 10 seconds. Only
  processes whose arguments contain the unique owned profile may then receive
  bounded SIGTERM/SIGKILL cleanup. Profile deletion is required for success.

### Presentation and preserved routes

The existing full-screen presentation boundary remains, but Linux displays a
clear system-browser waiting state rather than a WebView. Direct QR, external
QR handoff, SMS, credential restoration, and all QQ authentication code remain
unchanged.

## Dependency and packaging review

Linux-only Bridge dependencies are `tokio-tungstenite`, `futures-util`, `url`,
`tempfile`, `nix`, `serde`, `serde_json`, and `zeroize`. They provide direct
WebSocket/CDP, URL validation, private temporary directories, safe signals,
bounded JSON, and buffer clearing. They are target-scoped and do not link into
Android. No Web runtime, bundled browser, driver, automation framework,
extension, or service was added. Observed licenses remain within the current
MIT/Apache-2.0/BSD/Unicode/Unlicense family.

The resolved Linux-specific direct versions and licenses at the machine gate
were:

| Package | Resolved version | License |
| --- | --- | --- |
| `futures-util` | 0.3.34 | MIT OR Apache-2.0 |
| `nix` | 0.31.3 | MIT |
| `serde` | 1.0.229 | MIT OR Apache-2.0 |
| `serde_json` | 1.0.151 | MIT OR Apache-2.0 |
| `tempfile` | 3.27.0 | MIT OR Apache-2.0 |
| `tokio-tungstenite` | 0.28.0 | MIT |
| `url` | 2.5.8 | MIT OR Apache-2.0 |
| `zeroize` | 1.9.0 | Apache-2.0 OR MIT |

The same-machine pre-integration Linux Release artifact was preserved before
the candidate build, so the comparison does not require a second worktree or
duplicate build cache:

| Linux Release bundle | Bytes |
| --- | ---: |
| before integration | 45,492,666 |
| after integration | 46,381,663 |
| delta | +888,997 (+1.9542%) |

The launcher remained 24,464 bytes; the added code is in the Rust Bridge shared
library. An `ldd` scan of every executable/shared object in the final bundle
reported no missing dependency. The Rust Bridge itself resolves only the
normal system `libgcc_s`, `libm`, `libc`, and ELF loader. No `libcef`, Chromium
runtime, Qt WebEngine, ChromeDriver, or browser binary is present in the
bundle. The pre-existing `webview_all` Linux plugin artifact remains because
the retained non-Linux broker is still declared by the cross-platform Flutter
package; HD-029 did not add it and the Linux product route never selects it.

The Android ARM64 root dependency graph was also inspected. None of `nix`,
`tempfile`, `tokio-tungstenite`, `serde_json`, `url`, or `zeroize` is a direct
Bridge dependency there, so the task's conditional Android rebuild gate was
not triggered.

## Integration machine gates

- pinned FRB 2.13.0 regeneration: passed; generated Rust/Dart output audited;
- `cargo fmt --all -- --check`: passed;
- `cargo test --locked --workspace`: passed;
- `cargo test --locked --workspace --all-targets`: 554 passed, 23 explicit
  live/Human-only tests ignored, zero failed;
- `cargo clippy --locked --workspace --all-targets -- -D warnings`: passed;
- `flutter gen-l10n`: passed;
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  253 files checked, zero changed;
- `dart analyze .`: passed;
- targeted Flutter authentication tests: 58 passed;
- full `flutter test`: 589 passed;
- `flutter build linux --release`: passed;
- final Release ELF dependency closure: no missing dependency.

The separate `flutter analyze` wrapper was also attempted, but this installed
Flutter SDK's analysis-server/LSP process exited while decoding a truncated
capabilities JSON document, before project diagnostics. Direct `dart analyze
.` on the same source graph passed. This toolchain failure is not classified as
a source warning or a successful Flutter-wrapper gate.

## Human acceptance boundary

Machine tests do not prove current real-account acceptance. A Human must run
the Linux candidate, choose official-site login, confirm the isolated window
does not inherit an existing browser session, complete login manually, confirm
the intended account and clean-process restore, then cancel a second attempt
and check cleanup. Do not share Cookies, CDP URL/token, QR, account identifier,
profile, or vault data; report only the coarse result and cleanup observation.
