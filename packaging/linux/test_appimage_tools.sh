#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packaging/linux/fetch_appimage_tools.sh
source "$script_dir/fetch_appimage_tools.sh"
test_root=$(mktemp -d /tmp/fura-appimage-tools-test-XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT
mkdir "$test_root/bin"
# Test the production curl/sha256 path, not a replacement checksum tool.
cat > "$test_root/bin/curl" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  if [[ $1 == --output ]]; then output=$2; shift 2; else shift; fi
done
printf '%s' "${TEST_DOWNLOAD_BODY:?}" > "$output"
exit "${TEST_DOWNLOAD_EXIT:-0}"
SCRIPT
chmod 0755 "$test_root/bin/curl"
export PATH="$test_root/bin:$PATH"
export TEST_DOWNLOAD_BODY='a complete deterministic tool fixture'
fixture_sha=$(printf '%s' "$TEST_DOWNLOAD_BODY" | sha256sum | cut -d ' ' -f 1)
download_and_verify https://example.invalid/tool "$fixture_sha" "$test_root/good"
test "$(cat "$test_root/good")" = "$TEST_DOWNLOAD_BODY"
for failure in wrong-hash truncated failed-transport; do
  case $failure in
    wrong-hash) digest=$(printf x | sha256sum | cut -d ' ' -f 1) ;;
    truncated) digest=$fixture_sha; export TEST_DOWNLOAD_BODY='a complete' ;;
    failed-transport) digest=$fixture_sha; export TEST_DOWNLOAD_EXIT=22 ;;
  esac
  if (set -e; download_and_verify https://example.invalid/tool "$digest" "$test_root/$failure") > "$test_root/$failure.log" 2>&1; then
    die "accepted $failure"
  fi
done
test "$runtime_version" = 20251108
test "$runtime_url" = "https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64"
test "$runtime_sha256" = 2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d
# These deliberately check variable references in the production provenance
# record, not expanded values in this test shell.
# shellcheck disable=SC2016
grep -Fq 'type2_runtime=$runtime_version' "$script_dir/fetch_appimage_tools.sh"
# shellcheck disable=SC2016
grep -Fq 'type2_runtime_url=$runtime_url' "$script_dir/fetch_appimage_tools.sh"
# shellcheck disable=SC2016
grep -Fq 'type2_runtime_sha256=$runtime_sha256' "$script_dir/fetch_appimage_tools.sh"
printf 'AppImage transport, digest, truncation and pin regressions passed\n'
