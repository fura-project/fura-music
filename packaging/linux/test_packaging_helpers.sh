#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packaging/linux/lib.sh
source "$script_dir/lib.sh"

test_root=$(mktemp -d /tmp/flutterustmusic-packaging-helper-test-XXXXXX)
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

mkdir "$test_root/working directory"
(
  cd "$test_root/working directory"
  absolute_output=$(prepare_empty_output_directory 'relative output with spaces')
  test "$absolute_output" = "$test_root/working directory/relative output with spaces"
  package_file="$absolute_output/fixture.AppImage"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" fixture-ran' > "$package_file"
  chmod 0755 "$package_file"
  mkdir changed-directory
  cd changed-directory
  test "$("$package_file")" = fixture-ran
)

fake_bin="$test_root/fake-bin"
mkdir "$fake_bin"
fake_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
cat > "$fake_bin/git" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
case "${FAKE_GIT_MODE:-success}" in
  success) printf '%s\n' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ;;
  empty) exit 0 ;;
  failure) exit 42 ;;
  *) exit 64 ;;
esac
SCRIPT
cat > "$fake_bin/flutter" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
case "${FAKE_FLUTTER_MODE:-success}" in
  success) printf '%s\n' 'Flutter 3.47.1 • channel stable' ;;
  empty) exit 0 ;;
  failure) exit 43 ;;
  *) exit 64 ;;
esac
SCRIPT
cat > "$fake_bin/rustc" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
case "${FAKE_RUSTC_MODE:-success}" in
  success) printf '%s\n' 'rustc 1.97.1 (fixture)' ;;
  empty) exit 0 ;;
  failure) exit 44 ;;
  *) exit 64 ;;
esac
SCRIPT
cat > "$fake_bin/cargo" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
case "${FAKE_CARGO_MODE:-success}" in
  success) printf '%s\n' 'cargo 1.97.1 (fixture)' ;;
  empty) exit 0 ;;
  failure) exit 45 ;;
  *) exit 64 ;;
esac
SCRIPT
chmod 0755 "$fake_bin"/*

build_info="$test_root/output/BUILD-INFO.txt"
PATH="$fake_bin:$PATH" \
  GITHUB_SHA="$fake_sha" \
  write_build_info "$build_info" 'fixture baseline'
grep -Fxq "source_commit=$fake_sha" "$build_info"
grep -Fxq 'flutter=Flutter 3.47.1 • channel stable' "$build_info"

failure_output="$test_root/git-failure/BUILD-INFO.txt"
# $1 and $2 belong to the isolated child shell.
# shellcheck disable=SC2016
expect_failure 'unable to read source commit' \
  env PATH="$fake_bin:$PATH" GITHUB_SHA="$fake_sha" FAKE_GIT_MODE=failure \
    bash -c 'source "$1"; write_build_info "$2" fixture' \
    bash "$script_dir/lib.sh" "$failure_output"
test ! -e "$failure_output"

empty_output="$test_root/git-empty/BUILD-INFO.txt"
# $1 and $2 belong to the isolated child shell.
# shellcheck disable=SC2016
expect_failure 'source commit from the checkout is empty or invalid' \
  env PATH="$fake_bin:$PATH" GITHUB_SHA="$fake_sha" FAKE_GIT_MODE=empty \
    bash -c 'source "$1"; write_build_info "$2" fixture' \
    bash "$script_dir/lib.sh" "$empty_output"
test ! -e "$empty_output"

mismatch_output="$test_root/git-mismatch/BUILD-INFO.txt"
# $1 and $2 belong to the isolated child shell.
# shellcheck disable=SC2016
expect_failure 'source commit does not match GITHUB_SHA' \
  env PATH="$fake_bin:$PATH" \
    GITHUB_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
    bash -c 'source "$1"; write_build_info "$2" fixture' \
    bash "$script_dir/lib.sh" "$mismatch_output"
test ! -e "$mismatch_output"

version_output="$test_root/flutter-failure/BUILD-INFO.txt"
# $1 and $2 belong to the isolated child shell.
# shellcheck disable=SC2016
expect_failure 'unable to read Flutter version' \
  env PATH="$fake_bin:$PATH" GITHUB_SHA="$fake_sha" FAKE_FLUTTER_MODE=failure \
    bash -c 'source "$1"; write_build_info "$2" fixture' \
    bash "$script_dir/lib.sh" "$version_output"
test ! -e "$version_output"

empty_version_output="$test_root/flutter-empty/BUILD-INFO.txt"
# $1 and $2 belong to the isolated child shell.
# shellcheck disable=SC2016
expect_failure 'Flutter version is empty' \
  env PATH="$fake_bin:$PATH" GITHUB_SHA="$fake_sha" FAKE_FLUTTER_MODE=empty \
    bash -c 'source "$1"; write_build_info "$2" fixture' \
    bash "$script_dir/lib.sh" "$empty_version_output"
test ! -e "$empty_version_output"

rustc_failure_output="$test_root/rustc-failure/BUILD-INFO.txt"
# $1 and $2 belong to the isolated child shell.
# shellcheck disable=SC2016
expect_failure 'unable to read rustc version' \
  env PATH="$fake_bin:$PATH" GITHUB_SHA="$fake_sha" FAKE_RUSTC_MODE=failure \
    bash -c 'source "$1"; write_build_info "$2" fixture' \
    bash "$script_dir/lib.sh" "$rustc_failure_output"
test ! -e "$rustc_failure_output"

rustc_empty_output="$test_root/rustc-empty/BUILD-INFO.txt"
# $1 and $2 belong to the isolated child shell.
# shellcheck disable=SC2016
expect_failure 'rustc version is empty' \
  env PATH="$fake_bin:$PATH" GITHUB_SHA="$fake_sha" FAKE_RUSTC_MODE=empty \
    bash -c 'source "$1"; write_build_info "$2" fixture' \
    bash "$script_dir/lib.sh" "$rustc_empty_output"
test ! -e "$rustc_empty_output"

cargo_failure_output="$test_root/cargo-failure/BUILD-INFO.txt"
# $1 and $2 belong to the isolated child shell.
# shellcheck disable=SC2016
expect_failure 'unable to read Cargo version' \
  env PATH="$fake_bin:$PATH" GITHUB_SHA="$fake_sha" FAKE_CARGO_MODE=failure \
    bash -c 'source "$1"; write_build_info "$2" fixture' \
    bash "$script_dir/lib.sh" "$cargo_failure_output"
test ! -e "$cargo_failure_output"

cargo_empty_output="$test_root/cargo-empty/BUILD-INFO.txt"
# $1 and $2 belong to the isolated child shell.
# shellcheck disable=SC2016
expect_failure 'Cargo version is empty' \
  env PATH="$fake_bin:$PATH" GITHUB_SHA="$fake_sha" FAKE_CARGO_MODE=empty \
    bash -c 'source "$1"; write_build_info "$2" fixture' \
    bash "$script_dir/lib.sh" "$cargo_empty_output"
test ! -e "$cargo_empty_output"

mime_definitions="$test_root/freedesktop.org.xml"
printf '%s\n' \
  '<?xml version="1.0" encoding="UTF-8"?>' \
  '<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">' \
  '<mime-type type="application/x-fura-mime-regression"><glob pattern="*.fura-mime-regression"/></mime-type>' \
  '</mime-info>' > "$mime_definitions"
mime_appdir="$test_root/mime-appdir"
mkdir "$mime_appdir"
stage_appimage_mime_database "$mime_appdir" "$mime_definitions"
test -s "$mime_appdir/usr/share/mime/mime.cache"
grep -aq 'application/x-fura-mime-regression' "$mime_appdir/usr/share/mime/mime.cache"

printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/update-mime-database"
chmod 0755 "$fake_bin/update-mime-database"
# A successful tool exit without the actual cache must not pass packaging.
# shellcheck disable=SC2016
expect_failure 'AppImage MIME cache missing or empty' \
  env PATH="$fake_bin:$PATH" bash -c \
    'source "$1"; stage_appimage_mime_database "$2" "$3"' \
    bash "$script_dir/lib.sh" "$test_root/empty-mime-appdir" "$mime_definitions"

printf '%s\n' 'packaging path, build-info and MIME-cache targeted tests passed'
