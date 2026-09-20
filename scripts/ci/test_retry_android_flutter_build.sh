#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
retry_script="$script_dir/retry_android_flutter_build.sh"
test_root=$(mktemp -d /tmp/flutterustmusic-android-retry-test-XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fake_build="$test_root/fake-build"
cat > "$fake_build" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
count=0
test ! -f "$COUNT_FILE" || count=$(<"$COUNT_FILE")
count=$((count + 1))
printf '%d\n' "$count" > "$COUNT_FILE"
case "$MODE" in
  recover)
    if test "$count" -eq 1; then
      printf '%s\n' 'Received status code 429 from server: Too Many Requests' >&2
      exit 75
    fi
    ;;
  compile)
    printf '%s\n' 'Compilation failed: unresolved symbol' >&2
    exit 42
    ;;
  exhaust)
    printf '%s\n' 'HTTP response code 503' >&2
    exit 86
    ;;
  *) exit 64 ;;
esac
SCRIPT
chmod 0755 "$fake_build"

export ANDROID_BUILD_RETRY_DELAY_SECONDS=0

COUNT_FILE="$test_root/recover.count" MODE=recover \
  "$retry_script" "$test_root/recover-logs" -- "$fake_build"
test "$(<"$test_root/recover.count")" -eq 2

set +e
COUNT_FILE="$test_root/compile.count" MODE=compile \
  "$retry_script" "$test_root/compile-logs" -- "$fake_build"
status=$?
set -e
test "$status" -eq 42
test "$(<"$test_root/compile.count")" -eq 1

set +e
COUNT_FILE="$test_root/exhaust.count" MODE=exhaust \
  "$retry_script" "$test_root/exhaust-logs" -- "$fake_build"
status=$?
set -e
test "$status" -eq 86
test "$(<"$test_root/exhaust.count")" -eq 3

printf '%s\n' 'Android transient retry tests passed'
