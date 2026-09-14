# NetEase Tauri/Wry WebKitGTK Comparison

Date: 2026-09-14. Decision: HD-028. Execution:
`AUTONOMOUS_DEVELOPMENT / MIXED`. Diagnostic gate: `COMPLETE`.

## Question and boundary

This bounded probe asks whether Fura's fatal Linux official-login failure needs
Flutter plus `webview_all` native-view integration, or whether an isolated
Tauri/Wry host can reproduce it while sharing only WebKitGTK and the machine's
GPU/EGL stack.

The probe lived at `/tmp/fura-tauri-webkit-probe`; it was never added to the
Fura Cargo workspace. It did not link Fura Core, playback, Queue, Bridge,
Provider or vault code. It used no frontend framework, plugin, sidecar, custom
WebKit fork, TLS bypass, account credential or automated provider interaction.
No QR was scanned and no real NetEase login was attempted. Logs retained only
cycle state and scheme/host/path; screenshots contain short-lived anonymous QR
challenges and remain untracked local evidence.

## Versions and host

The experiment checked the current stable Tauri 2 line before building. The
probe exactly pinned `tauri 2.11.5` and the compatible `tauri-build 2.6.3`;
`Cargo.lock` resolved `tauri-runtime-wry 2.11.4` and `wry 0.55.1`. Tauri's
official WebView reference confirms that Linux uses `webkit2gtk`, so this is an
embedding-path comparison rather than a browser-engine replacement.

| Property | Measured value |
|---|---|
| Session | Wayland (`XDG_SESSION_TYPE=wayland`, `WAYLAND_DISPLAY=wayland-0`, `DISPLAY=:0`) |
| Inherited shell backend | `GDK_BACKEND=wayland`; explicitly unset in both test arms |
| WebKitGTK runtime | 2.52.5, API 4.1 |
| GTK | 3.24.52 |
| GStreamer | 1.28.6 |
| Integrated GPU | AMD Radeon Graphics, Renoir, Mesa 26.1.7 |
| Discrete GPU | NVIDIA GeForce RTX 2060 Max-Q |
| NVIDIA driver | 610.57.04 |
| Rust toolchain | rustc 1.97.1, cargo 1.97.1 |
| Release binary | 10,902,608 bytes |
| Dynamic dependencies | `libwebkit2gtk-4.1.so.0` resolved; zero `not found` entries |

Sources: [Tauri WebView versions](https://v2.tauri.app/reference/webview-versions/),
[Tauri 2.11.5 Rust API](https://docs.rs/tauri/2.11.5/tauri/), and
[Wry 0.55.1 release](https://github.com/tauri-apps/wry/releases/tag/wry-v0.55.1).

## Strict lifecycle

Each cycle created one `WebviewWindow` directly at
`https://music.163.com/#/login`, observed official-host Started and Finished
events, waited four seconds for SPA paint, resized 1280 x 720 to 900 x 600,
performed one bounded JavaScript scroll, resized back, requested close and
verified the label was absent from Tauri's WebView manager before incrementing
`closed_complete`. A 45-second Finished deadline stopped an unqualified load.
No cycles overlapped.

Both arms explicitly unset `WEBKIT_DISABLE_DMABUF_RENDERER`,
`WEBKIT_DISABLE_COMPOSITING_MODE`, `LIBGL_ALWAYS_SOFTWARE` and `GDK_BACKEND`.
The default arm also unset `WEBKIT_DMABUF_RENDERER_FORCE_SHM`; the comparison
arm set only that variable to `1`. No other renderer/backend experiment ran.
A separate `coredumpctl` monitor stopped the host as soon as a new
`WebKitWebProcess` core appeared.

## Results

| Host / renderer | Attempted | Page Finished | Closed complete | DMA-BUF errors | Native crash | Host outcome |
|---|---:|---:|---:|---:|---:|---|
| Flutter `webview_all` default, prior HD-027 short A/B | not cycle-counted | not qualified | not qualified | 228 in the full run; 12 and 233 in independent runs | 0 in short arm | Fura responsive, official content blank |
| Flutter `webview_all` + SHM, prior strict soak | 17 | 17 | 16 | 0 | 1 | Flutter disconnected after WebProcess SIGSEGV |
| Tauri/Wry default, strict target 100 | 13 | 12 | 12 | 0 | 0 | Host stayed alive; attempt 13 hit the 45-second Finished deadline and probe ended |
| Tauri/Wry + SHM, strict target 100 | 3 | 3 | 2 | 0 | 1 | Host was alive when monitor detected core, then harness terminated it |

Before the strict default run, an independent 10-cycle default smoke completed
10/10 with no failure. The strict cycle-10 screenshot shows the official page,
login card and anonymous QR with no observed blank region, black frame, texture
corruption or fill error. The strict default run did not reach cycle 25. Its
attempt-13 timeout is not classified as a native crash or proof of remote
throttling; it simply prevents a 100/100 stability claim.

The SHM screenshot attempt failed at the desktop PipeWire capture boundary and
is not counted as visual evidence. The page did emit Finished in all three
attempts, but Finished alone is not treated as proof of a correct painted
frame. The native crash occurred before cycle 10, so no later screenshot is
claimed.

## Crash comparison

The previous Flutter SHM core (PID 286762) and isolated Tauri SHM core (PID
357156) match on every decisive crash-class field:

| Field | Flutter / `webview_all` | Tauri / Wry |
|---|---|---|
| Process | `WebKitWebProcess` | `WebKitWebProcess` |
| Signal | SIGSEGV (11) | SIGSEGV (11) |
| Crashing thread | `SkiaGPUWorker` | `SkiaGPUWorker` |
| Top GPU library | `libnvidia-eglcore.so.610.57.04` | `libnvidia-eglcore.so.610.57.04` |
| NVIDIA EGL present | `libEGL_nvidia.so.0` | `libEGL_nvidia.so.0` |
| Trigger point | after official-page Finished 17 | after official-page Finished 3 |

The exact instruction offsets differ, but the process role, signal, thread and
NVIDIA EGL stack family are the same. The Tauri host remained alive long enough
for the external monitor to observe the core and send TERM. A surviving host
does not turn a crashed content process into a WebView pass.

## Interpretation and stopped phases

This is strong common-layer evidence: Flutter, `GtkOverlay` and `webview_all`
are not necessary for the fatal WebKit/GPU crash to occur. The shared
WebKitGTK/Skia/NVIDIA EGL path is sufficient on this host. It does not prove
that Flutter embedding is irrelevant to every symptom: Tauri default visibly
rendered and logged zero DMA-BUF import failures during its completed cycles,
whereas Flutter default was blank with repeated DMA-BUF EGL-import errors.
That default-path difference remains real but is no longer a basis for trying
another WebKitGTK wrapper as a production fix.

The authorized stop condition was met in the SHM arm. Therefore:

- synthetic HttpOnly Cookie: `NOT_RUN`;
- `clear_all_browsing_data`: `NOT_RUN`;
- isolated Tauri login-helper feasibility: `NO` for this measured WebKit path;
- additional renderer variables: `NOT_RUN`;
- Fura production code changed: `NO`;
- external QR baseline preserved: `YES`;
- real NetEase login: `NOT ATTEMPTED BY AGENT`.

The bounded diagnostic question is complete. Linux embedded WebKit remains
rejected. Product work now requires a Human decision between retaining external
QR/no embedded Linux login and authorizing a separate non-WebKit CEF/Chromium
trial; HD-028 does not authorize either implementation.

## Validation and evidence handling

The isolated probe passed `cargo fmt --all -- --check`, `cargo check`, Release
build and `cargo clippy --all-targets -- -D warnings`. `ldd` found no missing
library. Probe source, `target/`, logs, screenshots and core dumps were not
added to Git. Fura source did not change, so Flutter/Rust product builds were
not repeated; documentation formatting and repository diff checks are the only
Fura gates required for this evidence-only commit.

Ephemeral local evidence is under `/tmp/fura-tauri-webkit-evidence`. It must not
be published because screenshots may contain expired anonymous QR challenges.
