#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

test "$#" -eq 1 || die 'usage: find_single_local_deb.sh ARTIFACT_DIRECTORY'
artifact_directory=$1
test -d "$artifact_directory" || \
  die "DEB artifact directory is missing: $artifact_directory"
artifact_directory=$(readlink -f -- "$artifact_directory")

mapfile -d '' -t debs < <(
  find "$artifact_directory" -maxdepth 1 -type f -name '*.deb' -print0
)
test "${#debs[@]}" -eq 1 || \
  die "expected exactly one local DEB in $artifact_directory; found ${#debs[@]}"
test -s "${debs[0]}" || die "DEB file is empty: ${debs[0]}"
readlink -f -- "${debs[0]}"
