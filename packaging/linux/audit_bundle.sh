#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packaging/linux/lib.sh
source "$script_dir/lib.sh"

test "$#" -ge 2 && test "$#" -le 3 || \
  die 'usage: audit_bundle.sh BUNDLE REPORT_DIRECTORY [RUNTIME_LIBRARY_PATH]'
bundle=$1
report_directory=$2
external_runtime_search_path=${3:-}
use_elf_resolver=false
if test "$#" -eq 3; then
  use_elf_resolver=true
fi
validate_bundle_shape "$bundle"
require_command file
require_command readelf
if ! $use_elf_resolver; then
  require_command ldd
fi
mkdir -p -- "$report_directory"

manifest="$report_directory/BUNDLE_CONTENTS.txt"
elf_report="$report_directory/ELF_DEPENDENCIES.txt"
version_report="$report_directory/ELF_VERSION_REQUIREMENTS.txt"
: > "$elf_report"
: > "$version_report"
find "$bundle" -printf '%y %P %s bytes\n' | sort > "$manifest"

elf_count=0
runtime_search_path="$bundle/lib${external_runtime_search_path:+:$external_runtime_search_path}"
while IFS= read -r -d '' candidate; do
  if ! readelf -h "$candidate" >/dev/null 2>&1; then
    continue
  fi
  elf_count=$((elf_count + 1))
  relative=${candidate#"$bundle"/}
  {
    printf '\n===== %s =====\n' "$relative"
  } >> "$elf_report"

  if $use_elf_resolver; then
    candidate_report="$report_directory/.elf-$elf_count.txt"
    if audit_elf_dependencies \
      "$candidate" "$bundle" "$runtime_search_path" "$candidate_report"; then
      cat "$candidate_report" >> "$elf_report"
      unlink -- "$candidate_report"
    else
      cat "$candidate_report" >> "$elf_report"
      cat "$candidate_report" >&2
      unlink -- "$candidate_report"
      die "unresolved shared library in $relative"
    fi
  else
    {
      file "$candidate"
      readelf -d "$candidate" | grep -E 'NEEDED|RPATH|RUNPATH' || true
      ldd "$candidate" || true
    } >> "$elf_report"
    if ldd "$candidate" 2>&1 | grep -q 'not found'; then
      die "unresolved shared library in $relative"
    fi
  fi

  dynamic_paths=$(readelf -d "$candidate" | grep -E 'RPATH|RUNPATH' || true)
  if printf '%s\n' "$dynamic_paths" | grep -Eq '/home/|/Users/|/__w/|/github/workspace|/runner/work/'; then
    die "build-machine path leaked into RUNPATH/RPATH for $relative"
  fi

  {
    printf '\n===== %s =====\n' "$relative"
    readelf --version-info "$candidate" 2>/dev/null | \
      grep -E 'Name: (GLIBC|GLIBCXX)_' || true
  } >> "$version_report"
done < <(find "$bundle" -type f -print0)

test "$elf_count" -gt 0 || die 'bundle contains no ELF files'

readelf -d "$bundle/lib/libaudioplayers_linux_plugin.so" | grep -q 'libgstreamer-1.0.so.0' || \
  die 'audioplayers plugin is not linked to GStreamer'
readelf -d "$bundle/lib/libflutter_secure_storage_linux_plugin.so" | grep -q 'libsecret-1.so.0' || \
  die 'secure-storage plugin is not linked to libsecret'
readelf -d "$bundle/lib/libmedia_kit_video_plugin.so" | grep -q 'libmpv.so.2' || \
  die 'media_kit video plugin is not linked to libmpv.so.2'
readelf -d "$bundle/lib/libwebview_all_linux_plugin.so" | grep -q 'libwebkit2gtk-4.1.so.0' || \
  die 'WebView plugin is not linked to WebKitGTK 4.1'

{
  printf 'elf_count=%s\n' "$elf_count"
  printf 'bundle_bytes=%s\n' "$(du -sb "$bundle" | awk '{print $1}')"
  printf 'glibc_max='
  grep -Eo 'GLIBC_[0-9.]+' "$version_report" | sort -Vu | tail -n 1 || true
  printf 'glibcxx_max='
  grep -Eo 'GLIBCXX_[0-9.]+' "$version_report" | sort -Vu | tail -n 1 || true
} > "$report_directory/BUNDLE_AUDIT_SUMMARY.txt"
