#!/usr/bin/env bash
set -euo pipefail

packaging_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$packaging_dir/../.." && pwd)

app_name=flutterustmusic
app_id=dev.axiaobo.flutterustmusic
native_app_root=/usr/lib/flutterustmusic
desktop_file="$packaging_dir/assets/${app_id}.desktop"
launcher_file="$packaging_dir/assets/flutterustmusic"
icon_file="$repo_root/apps/flutter/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"
project_license="$repo_root/LICENSE"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

require_file() {
  test -f "$1" || die "required file is missing: $1"
}

require_directory() {
  test -d "$1" || die "required directory is missing: $1"
}

require_empty_directory() {
  local directory=$1
  case "$directory" in
    ''|/|/usr|/usr/*|/opt|/opt/*) die "refusing unsafe work directory: $directory" ;;
  esac
  mkdir -p -- "$directory"
  if find "$directory" -mindepth 1 -print -quit | grep -q .; then
    die "work directory must be empty: $directory"
  fi
}

prepare_empty_output_directory() {
  local directory=$1
  require_empty_directory "$directory"
  (
    cd -- "$directory"
    pwd -P
  )
}

prepare_private_workspace_for_user() {
  local workspace=$1
  local writable_tree=$2
  local user=$3
  local workspace_path
  local writable_path
  local user_id
  local group_id

  test "$EUID" -eq 0 || die 'private workspace ownership requires root'
  require_directory "$workspace"
  require_directory "$writable_tree"
  workspace_path=$(readlink -f -- "$workspace")
  writable_path=$(readlink -f -- "$writable_tree")
  case "$writable_path/" in
    "$workspace_path"/*) ;;
    *) die "writable tree is outside the private workspace: $writable_path" ;;
  esac

  id "$user" >/dev/null 2>&1 || die "workspace user does not exist: $user"
  user_id=$(id -u "$user")
  group_id=$(id -g "$user")
  test "$user_id" -ne 0 || die 'workspace user must not be root'

  chown "$user_id:$group_id" "$workspace_path"
  chmod 0700 "$workspace_path"
  chown -R "$user_id:$group_id" "$writable_path"
}

read_project_version() {
  local raw_version
  raw_version=$(sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*/\1/p' \
    "$repo_root/apps/flutter/pubspec.yaml")
  test -n "$raw_version" || die 'unable to read version from apps/flutter/pubspec.yaml'

  project_version=${raw_version%%+*}
  if [[ "$raw_version" == *+* ]]; then
    project_build=${raw_version#*+}
  else
    project_build=1
  fi
  [[ "$project_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.~-][A-Za-z0-9]+)*$ ]] || \
    die "unsupported project version: $project_version"
  [[ "$project_build" =~ ^[0-9]+$ ]] || die "unsupported project build number: $project_build"
}

validate_bundle_shape() {
  local bundle=$1
  require_directory "$bundle"
  require_file "$bundle/$app_name"
  require_file "$bundle/lib/libflutter_linux_gtk.so"
  require_file "$bundle/lib/libapp.so"
  require_file "$bundle/lib/librust_lib_flutterustmusic.so"
  require_file "$bundle/lib/libmedia_kit_video_plugin.so"
  require_file "$bundle/lib/libaudioplayers_linux_plugin.so"
  require_file "$bundle/lib/libflutter_secure_storage_linux_plugin.so"
  require_file "$bundle/lib/libwebview_all_linux_plugin.so"
  require_file "$bundle/data/icudtl.dat"
  require_directory "$bundle/data/flutter_assets"
  require_file "$bundle/data/flutter_assets/NativeAssetsManifest.json"
}

validate_distribution_assets() {
  require_command desktop-file-validate
  require_command file
  desktop-file-validate "$desktop_file"
  file "$icon_file" | grep -q 'PNG image data' || die 'desktop icon is not a PNG image'
  grep -qx 'Exec=flutterustmusic' "$desktop_file" || die 'desktop Exec does not match the launcher'
  grep -qx "Icon=$app_id" "$desktop_file" || die 'desktop Icon does not match the application ID'
}

normalize_bundle() {
  local source_bundle=$1
  local destination_bundle=$2
  local native_manifest
  local library_manifest
  local optional_jni
  local candidate
  require_command patchelf
  require_command readelf
  require_command jq
  validate_bundle_shape "$source_bundle"
  require_empty_directory "$destination_bundle"
  cp -a -- "$source_bundle/." "$destination_bundle/"

  native_manifest="$destination_bundle/data/flutter_assets/NativeAssetsManifest.json"
  if ! jq -e '
    type == "object" and
    (."format-version" | type == "array" and length == 3 and all(type == "number")) and
    (."native-assets" | type == "object")
  ' "$native_manifest" >/dev/null; then
    die "invalid Flutter native-assets manifest: $native_manifest"
  fi

  optional_jni="$destination_bundle/lib/libdartjni.so"
  if test -f "$optional_jni"; then
    library_manifest="$destination_bundle/lib/native_assets.json"
    test "$(jq '."native-assets" | length' "$native_manifest")" -eq 0 || \
      die 'refusing to omit libdartjni.so because Flutter declares native assets'
    # Flutter's runtime consumes NativeAssetsManifest.json from flutter_assets.
    # CMake also installs build/native_assets/linux into lib when that staging
    # directory exists, but a Release bundle may legitimately omit this copy.
    if test -f "$library_manifest"; then
      if ! jq -e '
        type == "object" and
        (."format-version" | type == "array" and length == 3 and all(type == "number")) and
        (."native-assets" | type == "object")
      ' "$library_manifest" >/dev/null; then
        die "invalid optional native-assets staging manifest: $library_manifest"
      fi
      test "$(jq '."native-assets" | length' "$library_manifest")" -eq 0 || \
        die 'refusing to omit libdartjni.so because the staging manifest is non-empty'
    fi
    while IFS= read -r -d '' candidate; do
      if readelf -d "$candidate" 2>/dev/null | \
        grep -q 'Shared library: \[libdartjni.so\]'; then
        die "refusing to omit libdartjni.so because a bundled ELF needs it: $candidate"
      fi
      if grep -aFq 'libdartjni.so' "$candidate"; then
        die "refusing to omit libdartjni.so because bundled runtime data references it: $candidate"
      fi
    done < <(find "$destination_bundle" -type f ! -path "$optional_jni" -print0)
    if readelf -d "$optional_jni" 2>/dev/null | \
      grep -q 'Shared library: \[libjvm.so\]'; then
      printf '%s\n' \
        'Omitting unused libdartjni.so; retaining it would add an undeclared libjvm.so dependency.' \
        >&2
    fi
    # package:jni builds this optional desktop JVM helper whenever the build
    # host happens to have a JDK. Fura's Linux code has no JNI native asset and
    # a clean installed-package launch verifies that no runtime path loads it.
    unlink -- "$optional_jni"
  fi

  while IFS= read -r -d '' candidate; do
    if ! readelf -h "$candidate" >/dev/null 2>&1; then
      continue
    fi
    case "$candidate" in
      "$destination_bundle/$app_name")
        # The loader, not this shell, expands ORIGIN.
        # shellcheck disable=SC2016
        patchelf --set-rpath '$ORIGIN/lib' "$candidate"
        ;;
      "$destination_bundle/lib/"*)
        # The loader, not this shell, expands ORIGIN.
        # shellcheck disable=SC2016
        patchelf --set-rpath '$ORIGIN' "$candidate"
        ;;
    esac
  done < <(find "$destination_bundle" -type f -print0)

  validate_bundle_shape "$destination_bundle"
}

write_build_info() {
  local destination=$1
  local baseline=$2
  local source_commit
  local flutter_version
  local rustc_version
  local cargo_version
  read_project_version

  if ! source_commit=$(git -C "$repo_root" rev-parse --verify HEAD); then
    die 'unable to read source commit from the checkout'
  fi
  [[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || \
    die 'source commit from the checkout is empty or invalid'
  if test -n "${GITHUB_SHA:-}" && test "$source_commit" != "$GITHUB_SHA"; then
    die "source commit does not match GITHUB_SHA: $source_commit != $GITHUB_SHA"
  fi
  if ! flutter_version=$(flutter --version | sed -n '1p'); then
    die 'unable to read Flutter version'
  fi
  test -n "$flutter_version" || die 'Flutter version is empty'
  if ! rustc_version=$(rustc --version); then
    die 'unable to read rustc version'
  fi
  test -n "$rustc_version" || die 'rustc version is empty'
  if ! cargo_version=$(cargo --version); then
    die 'unable to read Cargo version'
  fi
  test -n "$cargo_version" || die 'Cargo version is empty'

  mkdir -p -- "$(dirname -- "$destination")"
  {
    printf 'application=%s\n' "$app_name"
    printf 'application_id=%s\n' "$app_id"
    printf 'version=%s+%s\n' "$project_version" "$project_build"
    printf 'source_commit=%s\n' "$source_commit"
    printf 'build_baseline=%s\n' "$baseline"
    printf 'architecture=x86_64\n'
    printf 'flutter=%s\n' "$flutter_version"
    printf 'rustc=%s\n' "$rustc_version"
    printf 'cargo=%s\n' "$cargo_version"
  } > "$destination"
}

install_native_tree() {
  local bundle=$1
  local package_root=$2
  local doc_source=$3
  validate_bundle_shape "$bundle"

  install -d \
    "$package_root$native_app_root" \
    "$package_root/usr/bin" \
    "$package_root/usr/share/applications" \
    "$package_root/usr/share/icons/hicolor/512x512/apps" \
    "$package_root/usr/share/doc/$app_name"
  cp -a -- "$bundle/." "$package_root$native_app_root/"
  install -m 0755 "$launcher_file" "$package_root/usr/bin/$app_name"
  install -m 0644 "$desktop_file" \
    "$package_root/usr/share/applications/${app_id}.desktop"
  install -m 0644 "$icon_file" \
    "$package_root/usr/share/icons/hicolor/512x512/apps/${app_id}.png"
  install -m 0644 "$project_license" \
    "$package_root/usr/share/doc/$app_name/LICENSE"
  if test -d "$doc_source"; then
    cp -a -- "$doc_source/." "$package_root/usr/share/doc/$app_name/"
  fi
}

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

write_sha256sums() {
  local output_directory=$1
  (
    cd -- "$output_directory"
    find . -maxdepth 1 -type f \
      \( -name '*.deb' -o -name '*.rpm' -o -name '*.pkg.tar.zst' -o -name '*.AppImage' \) \
      -printf '%f\n' | sort | xargs -r sha256sum > SHA256SUMS
  )
}
