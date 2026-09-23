#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

test "$#" -eq 2 || die 'usage: install_local_deb.sh install|reinstall DEB_FILE'
operation=$1
deb_file=$2
test -s "$deb_file" || die "DEB file is missing or empty: $deb_file"
deb_file=$(readlink -f -- "$deb_file")
test -f "$deb_file" || die "unable to resolve DEB file: $deb_file"
case "$operation" in
  install)
    exec apt-get install --yes "$deb_file"
    ;;
  reinstall)
    exec apt-get install --yes --reinstall "$deb_file"
    ;;
  *) die "unsupported DEB install operation: $operation" ;;
esac
