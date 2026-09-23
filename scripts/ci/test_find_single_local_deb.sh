#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
finder="$script_dir/find_single_local_deb.sh"
test_root=$(mktemp -d /tmp/flutterustmusic-deb-discovery-test-XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

expect_failure() {
  local expected=$1
  shift
  local log="$test_root/failure.log"
  if "$@" >"$log" 2>&1; then
    printf 'command unexpectedly succeeded: %s\n' "$*" >&2
    exit 1
  fi
  grep -Fq "$expected" "$log" || {
    cat "$log" >&2
    printf 'expected failure was not reported: %s\n' "$expected" >&2
    exit 1
  }
}

mkdir "$test_root/no packages" "$test_root/one package" \
  "$test_root/multiple packages" "$test_root/plain"

expect_failure 'found 0' "$finder" "$test_root/no packages"

printf '%s\n' fixture > "$test_root/plain/package.deb"
test "$("$finder" "$test_root/plain")" = "$test_root/plain/package.deb"

printf '%s\n' fixture > "$test_root/one package/package with spaces.deb"
test "$("$finder" "$test_root/one package")" = \
  "$test_root/one package/package with spaces.deb"

printf '%s\n' one > "$test_root/multiple packages/one.deb"
printf '%s\n' two > "$test_root/multiple packages/two.deb"
expect_failure 'found 2' "$finder" "$test_root/multiple packages"

printf '%s\n' 'local DEB discovery tests passed'
