#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packaging/linux/lib.sh
source "$script_dir/lib.sh"

test "$#" -eq 1 || die 'usage: test_arch_workspace.sh NON_ROOT_USER'
test "$EUID" -eq 0 || die 'Arch workspace permission test must run as root'
test_user=$1
test_user_id=$(id -u "$test_user")
test "$test_user_id" -ne 0 || die 'Arch workspace test user must not be root'

test_root=$(mktemp -d /tmp/flutterustmusic-arch-workspace-test-XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT
package_directory="$test_root/package"
mkdir "$package_directory"
printf '%s\n' fixture > "$package_directory/PKGBUILD"

test "$(stat -c %a "$test_root")" = 700
prepare_private_workspace_for_user "$test_root" "$package_directory" "$test_user"
test "$(stat -c %u "$test_root")" -eq "$test_user_id"
test "$(stat -c %a "$test_root")" = 700

# $1 belongs to the non-root child shell.
# shellcheck disable=SC2016
runuser -u "$test_user" -- bash -eu -o pipefail -c '
  test "$(id -u)" -ne 0
  test -x "$1/.."
  cd "$1"
  test -r PKGBUILD
  test -w .
  printf "%s\n" writable > workspace-write-check
' bash "$package_directory"
test -f "$package_directory/workspace-write-check"

printf '%s\n' 'Arch private workspace permission test passed'
