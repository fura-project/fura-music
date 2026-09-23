#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

test "$#" -le 2 || die 'usage: trust_exact_checkout.sh [WORKSPACE [EXPECTED_COMMIT]]'
workspace=${1:-${GITHUB_WORKSPACE:-}}
expected_commit=${2:-${GITHUB_SHA:-}}
test -n "$workspace" || die 'checkout workspace is required'
workspace=$(readlink -f -- "$workspace")
test -d "$workspace/.git" || die "checkout has no .git directory: $workspace"

top_level=$(git -c safe.directory="$workspace" -C "$workspace" rev-parse --show-toplevel) || \
  die "unable to validate checkout path: $workspace"
top_level=$(readlink -f -- "$top_level")
test "$top_level" = "$workspace" || \
  die "checkout top level does not match workspace: $top_level != $workspace"

if ! git config --global --get-all safe.directory | grep -Fxq "$workspace"; then
  git config --global --add safe.directory "$workspace"
fi
source_commit=$(git -C "$workspace" rev-parse --verify HEAD) || \
  die 'unable to read checkout commit after configuring trust'
[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || die 'checkout commit is empty or invalid'
if test -n "$expected_commit" && test "$source_commit" != "$expected_commit"; then
  die "checkout commit does not match expected commit: $source_commit != $expected_commit"
fi

id
printf 'HOME=%s\nCHECKOUT=%s\nSOURCE_COMMIT=%s\n' \
  "$HOME" "$workspace" "$source_commit"
stat -c 'Checkout owner=%u:%g mode=%a path=%n' "$workspace"
