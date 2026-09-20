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
  require_command patchelf
  require_command readelf
  validate_bundle_shape "$source_bundle"
  require_empty_directory "$destination_bundle"
  cp -a -- "$source_bundle/." "$destination_bundle/"

  optional_jni="$destination_bundle/lib/libdartjni.so"
  if test -f "$optional_jni"; then
    native_manifest="$destination_bundle/data/flutter_assets/NativeAssetsManifest.json"
    library_manifest="$destination_bundle/lib/native_assets.json"
    require_file "$native_manifest"
    require_file "$library_manifest"
    grep -Eq '"native-assets"[[:space:]]*:[[:space:]]*\{\}' "$native_manifest" || \
      die 'refusing to omit libdartjni.so because Flutter declares native assets'
    grep -Eq '"native-assets"[[:space:]]*:[[:space:]]*\{\}' "$library_manifest" || \
      die 'refusing to omit libdartjni.so because the library manifest is non-empty'
    if find "$destination_bundle" -type f ! -path "$optional_jni" -print0 | \
      xargs -0 -r readelf -d 2>/dev/null | grep -q 'Shared library: \[libdartjni.so\]'; then
      die 'refusing to omit libdartjni.so because another bundled ELF needs it'
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
  read_project_version
  mkdir -p -- "$(dirname -- "$destination")"
  {
    printf 'application=%s\n' "$app_name"
    printf 'application_id=%s\n' "$app_id"
    printf 'version=%s+%s\n' "$project_version" "$project_build"
    printf 'source_commit=%s\n' "$(git -C "$repo_root" rev-parse HEAD)"
    printf 'build_baseline=%s\n' "$baseline"
    printf 'architecture=x86_64\n'
    printf 'flutter=%s\n' "$(flutter --version | sed -n '1p')"
    printf 'rustc=%s\n' "$(rustc --version)"
    printf 'cargo=%s\n' "$(cargo --version)"
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
