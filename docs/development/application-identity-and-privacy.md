# Application identity and privacy

Status: implemented candidate, awaiting cross-platform Human review

Last updated: 2026-09-27

## Canonical public identity

Fura's public application identity is `com.fura.flutterustmusic`. Public
project metadata uses `Fura Project`, the display name remains `fura music`,
and first-party copyright presentation uses `Fura contributors` without
claiming a legal entity.

The following compatibility names intentionally remain unchanged:

- Dart package: `flutterustmusic`
- Rust bridge crate: `rust_lib_flutterustmusic`
- executable and bundle product name: `flutterustmusic`
- Linux package and runtime root: `flutterustmusic` and
  `/usr/lib/flutterustmusic`
- repository: `fura-project/fura-music`

Those names are project identifiers rather than personal identity and remain
part of existing build, runtime and user-data contracts.

## Platform mapping

| Platform surface | Public value |
| --- | --- |
| Android namespace/application ID | `com.fura.flutterustmusic` |
| Android Application class | `com.fura.flutterustmusic.FuraApplication` |
| iOS/macOS Runner bundle ID | `com.fura.flutterustmusic` |
| iOS/macOS RunnerTests bundle ID | `com.fura.flutterustmusic.RunnerTests` |
| Linux GTK application ID | `com.fura.flutterustmusic` |
| Linux desktop/icon/WM class | `com.fura.flutterustmusic` |
| Windows CompanyName | `Fura Project` |
| Copyright presentation | `Fura contributors` |

Android's Rust JNI export is part of the same atomic namespace migration and
must remain synchronized with `FuraApplication`. CI checks the merged
manifest, APK package ID and exported native symbol together.

## Migration semantics

Changing an Android application ID or Apple bundle ID creates a distinct app
identity. Existing development installs, package-scoped storage, secure
storage, Keychain access and sandbox data do not automatically transfer. This
development-stage cutover intentionally does not read the former package
sandbox, copy credentials, share application groups or manufacture a
cross-identity migration path.

The secure-storage service/account namespace now follows the canonical public
identity. Existing data under the former development identity is intentionally
left untouched and inaccessible to the new app identity.

## Privacy hygiene

First-party tracked source and documentation must not contain:

- the former personal reverse-domain application identity;
- maintainer nicknames used as public product attribution;
- absolute maintainer HOME or workspace paths;
- private signing material or production credential files.

Documentation uses `$HOME`, `<workspace>`, `<repo>` or another reproducible
placeholder. Repository links are relative paths rather than host-local file
paths. Third-party author names, license notices, required contact details and
provenance URLs are legal/evidence material and are not removed by this rule.

`scripts/ci/audit_privacy_hygiene.py` enforces the first-party tracked-source
boundary. `scripts/ci/audit_artifact_privacy.py` scans built payloads for the
former identity and the active build roots without printing matched bytes.

Release/development artifacts use
`scripts/ci/build_flutter_with_privacy.py`. The wrapper first lets Flutter
produce the platform configuration, gives the generated Dart plugin registrant
a stable package URI, and then performs the real build without another package
resolution pass. Rust source paths are remapped to stable project/build roots;
Android's system-Cargo path applies the corresponding C/C++ prefix maps as
well. Symbol files produced for a private build are diagnostics and must not be
uploaded as application artifacts.

The generated package-URI mapping is scoped to that build and removed from
the ordinary pub configuration even on build failure. Private builds carry
the compile-only `FURA_PATH_PRIVATE_REGISTRANT=1` define to give them a distinct
incremental kernel namespace. Flutter's kernel cache key includes caller
dart-defines but not the generated registrant URI: switching a cached kernel
between ordinary `file:` and private `package:` registrants can skip root
isolate Dart plugin registration. Do not run the preparation helper alone as
a persistent development configuration, reuse its private kernels for ordinary
Debug runs, or compensate with manual root-isolate plugin registration.

Flutter Debug kernels intentionally contain source URIs so debuggers can
resolve application and dependency code. They are not hex-patched or stripped
after compilation. Android x64 development artifacts are therefore built in
Release mode and receive the same strict root scan as the ARM64 package. The
iOS Simulator supports only Debug mode; its CI artifact is checked for the
former product identity and personal marker, but is not evidence of a
path-private Release payload. Locally built Debug applications must not be
published when their build environment contains a personal HOME or workspace
path.

## Signing and Git history boundaries

No development team, provisioning profile, certificate, signing key or Human
account is generated or changed by this migration. Physical Apple-device
provisioning after the bundle-ID cutover remains a Human signing gate.

Historical Git author metadata is immutable evidence in existing Git objects.
This work does not use history rewriting, filter tools, root rebases, tag
rewrites or force pushes. If historical personal metadata must be removed,
that requires a separate Human decision because every rewritten commit would
receive a new object ID and pinned evidence or external forks could break.
