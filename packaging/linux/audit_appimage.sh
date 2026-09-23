#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packaging/linux/lib.sh
source "$script_dir/lib.sh"

test "$#" -eq 2 || die 'usage: audit_appimage.sh EXTRACTED_APPDIR REPORT_DIRECTORY'
appdir=$1
report_directory=$2
require_directory "$appdir"
require_file "$appdir/AppRun"
validate_bundle_shape "$appdir/usr/lib/flutterustmusic"
mkdir -p "$report_directory"

find "$appdir" -printf '%y %P %s bytes\n' | sort \
  > "$report_directory/APPIMAGE_CONTENTS.txt"

for required_pattern in \
  'libmpv.so.2*' \
  'libsecret-1.so.0*' \
  'libwebkit2gtk-4.1.so.0*' \
  'libgstreamer-1.0.so.0*' \
  'libgstapp-1.0.so.0*' \
  'libgstplayback.so' \
  'libgstaudioconvert.so' \
  'libgstautodetect.so' \
  'libgstsoup.so' \
  'gst-plugin-scanner' \
  'WebKitWebProcess' \
  'WebKitNetworkProcess'; do
  find "$appdir" -name "$required_pattern" -print -quit | grep -q . || \
    die "AppImage payload is missing $required_pattern"
done

if find "$appdir" \( -name 'libc.so.6' -o -name 'ld-linux-x86-64.so.2' \) \
  -print -quit | grep -q .; then
  die 'AppImage must not bundle glibc or the ELF dynamic loader'
fi
if find "$appdir" \( \
    -name 'libEGL.so*' -o \
    -name 'libGL.so*' -o \
    -name 'libGLX.so*' -o \
    -name 'libOpenGL.so*' -o \
    -name 'libdrm.so*' -o \
    -name 'libgbm.so*' -o \
    -name 'libwayland-*.so*' \
  \) -print -quit | grep -q .; then
  die 'AppImage must use the target graphics and Wayland stack'
fi

app_lib="$appdir/usr/lib/flutterustmusic/lib"
portable_lib="$appdir/usr/lib"
multiarch_lib="$appdir/usr/lib/x86_64-linux-gnu"
: > "$report_directory/APPIMAGE_ELF_DEPENDENCIES.txt"
: > "$report_directory/APPIMAGE_ELF_VERSION_REQUIREMENTS.txt"
elf_count=0
runtime_search_path="$app_lib:$multiarch_lib:$portable_lib"
while IFS= read -r -d '' candidate; do
  if ! readelf -h "$candidate" >/dev/null 2>&1; then
    continue
  fi
  elf_count=$((elf_count + 1))
  relative=${candidate#"$appdir"/}
  candidate_report="$report_directory/.elf-$elf_count.txt"
  {
    printf '\n===== %s =====\n' "$relative"
  } >> "$report_directory/APPIMAGE_ELF_DEPENDENCIES.txt"
  if ! audit_elf_dependencies \
    "$candidate" "$appdir" "$runtime_search_path" "$candidate_report"; then
    cat "$candidate_report" \
      >> "$report_directory/APPIMAGE_ELF_DEPENDENCIES.txt"
    cat "$candidate_report" >&2
    unlink -- "$candidate_report"
    die "AppImage contains an unresolved shared library in $relative"
  fi
  cat "$candidate_report" >> "$report_directory/APPIMAGE_ELF_DEPENDENCIES.txt"
  unlink -- "$candidate_report"
  dynamic_paths=$(readelf -d "$candidate" | grep -E 'RPATH|RUNPATH' || true)
  if printf '%s\n' "$dynamic_paths" | \
    grep -Eq '/home/|/Users/|/__w/|/github/workspace|/runner/work/'; then
    die "build-machine path leaked into AppImage RUNPATH/RPATH for $relative"
  fi
  {
    printf '\n===== %s =====\n' "$relative"
    readelf --version-info "$candidate" 2>/dev/null | \
      grep -E 'Name: (GLIBC|GLIBCXX)_' || true
  } >> "$report_directory/APPIMAGE_ELF_VERSION_REQUIREMENTS.txt"
done < <(find "$appdir" -type f -print0)
test "$elf_count" -gt 0 || die 'AppImage contains no ELF files'

{
  printf 'elf_count=%s\n' "$elf_count"
  printf 'appdir_bytes=%s\n' "$(du -sb "$appdir" | awk '{print $1}')"
  printf 'glibc_max='
  grep -Eo 'GLIBC_[0-9.]+' \
    "$report_directory/APPIMAGE_ELF_VERSION_REQUIREMENTS.txt" | \
    sort -Vu | tail -n 1 || true
  printf 'glibcxx_max='
  grep -Eo 'GLIBCXX_[0-9.]+' \
    "$report_directory/APPIMAGE_ELF_VERSION_REQUIREMENTS.txt" | \
    sort -Vu | tail -n 1 || true
} > "$report_directory/APPIMAGE_AUDIT_SUMMARY.txt"

"$script_dir/audit_bundle.sh" "$appdir/usr/lib/flutterustmusic" \
  "$report_directory/bundle" \
  "$runtime_search_path${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$appdir"
