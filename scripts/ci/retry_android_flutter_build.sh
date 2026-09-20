#!/usr/bin/env bash
set -euo pipefail

if test "$#" -lt 3 || test "$2" != --; then
  printf '%s\n' \
    'usage: retry_android_flutter_build.sh LOG_DIRECTORY -- COMMAND [ARG...]' >&2
  exit 64
fi

log_directory=$1
shift 2
attempt_limit=${ANDROID_BUILD_MAX_ATTEMPTS:-3}
base_delay=${ANDROID_BUILD_RETRY_DELAY_SECONDS:-15}
[[ "$attempt_limit" =~ ^[1-9][0-9]*$ ]] || {
  printf 'invalid ANDROID_BUILD_MAX_ATTEMPTS: %s\n' "$attempt_limit" >&2
  exit 64
}
[[ "$base_delay" =~ ^[0-9]+$ ]] || {
  printf 'invalid ANDROID_BUILD_RETRY_DELAY_SECONDS: %s\n' "$base_delay" >&2
  exit 64
}
mkdir -p "$log_directory"

for ((attempt = 1; attempt <= attempt_limit; attempt += 1)); do
  log_file="$log_directory/attempt-$attempt.log"
  printf 'Android build attempt %d/%d: %q' "$attempt" "$attempt_limit" "$1"
  if test "$#" -gt 1; then
    printf ' %q' "${@:2}"
  fi
  printf '\n'

  set +e
  "$@" 2>&1 | tee "$log_file"
  status=${PIPESTATUS[0]}
  set -e
  if test "$status" -eq 0; then
    exit 0
  fi

  if ! grep -Eqi \
    'Received status code (429|502|503|504)|HTTP (response )?(status )?(code )?(429|502|503|504)|Too Many Requests|Connection reset by peer|Read timed out' \
    "$log_file"; then
    printf 'Android build failed with non-transient status %d; not retrying.\n' \
      "$status" >&2
    exit "$status"
  fi
  if test "$attempt" -eq "$attempt_limit"; then
    printf 'Android dependency download retry budget exhausted; preserving status %d.\n' \
      "$status" >&2
    exit "$status"
  fi

  delay=$((base_delay * (1 << (attempt - 1))))
  printf 'Transient Android dependency download failure; retrying in %d seconds.\n' \
    "$delay" >&2
  sleep "$delay"
done
