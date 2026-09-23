#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packaging/linux/lib.sh
source "$script_dir/lib.sh"

test_root=$(mktemp -d /tmp/flutterustmusic-elf-verifier-test-XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

expect_failure() {
  local expected=$1
  shift
  local log="$test_root/failure.log"
  if ("$@") >"$log" 2>&1; then
    die "command unexpectedly succeeded: $*"
  fi
  grep -Fq "$expected" "$log" || {
    cat "$log" >&2
    die "expected failure was not reported: $expected"
  }
}

require_command cc
cat > "$test_root/dependency.c" <<'SOURCE'
int fura_fixture_dependency(void) { return 42; }
SOURCE
cat > "$test_root/plugin.c" <<'SOURCE'
extern int fura_fixture_dependency(void);
int fura_fixture_plugin(void) { return fura_fixture_dependency(); }
SOURCE

cc -shared -fPIC "$test_root/dependency.c" \
  -Wl,-soname,libfura_fixture_dependency.so.1 \
  -o "$test_root/libfura_fixture_dependency.so.1"
cc -shared -fPIC "$test_root/plugin.c" \
  -L"$test_root" -Wl,--no-as-needed -l:libfura_fixture_dependency.so.1 \
  -o "$test_root/libfura_fixture_plugin.so"
chmod 0644 "$test_root/libfura_fixture_dependency.so.1" \
  "$test_root/libfura_fixture_plugin.so"

test ! -x "$test_root/libfura_fixture_plugin.so"
verify_elf_needed_dependency \
  "$test_root/libfura_fixture_plugin.so" libfura_fixture_dependency.so.1
LD_LIBRARY_PATH="$test_root" require_runtime_library \
  libfura_fixture_dependency.so.1

expect_failure 'ELF does not declare required dependency' \
  verify_elf_needed_dependency \
    "$test_root/libfura_fixture_plugin.so" libnot_present.so.1
# $1 belongs to the isolated child shell.
# shellcheck disable=SC2016
expect_failure 'runtime linker cannot resolve required library' \
  env -u LD_LIBRARY_PATH bash -c \
    'source "$1"; require_runtime_library libfura_fixture_missing.so.1' \
    bash "$script_dir/lib.sh"

printf '%s\n' 'non-executable shared-object dependency tests passed'
