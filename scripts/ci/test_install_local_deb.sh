#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
install_script="$script_dir/install_local_deb.sh"
test_root=$(mktemp -d /tmp/flutterustmusic-deb-path-test-XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fake_bin="$test_root/fake-bin"
mkdir "$fake_bin" "$test_root/artifacts with spaces" "$test_root/changed directory"
cat > "$fake_bin/apt-get" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$APT_ARGUMENTS"
SCRIPT
chmod 0755 "$fake_bin/apt-get"
printf '%s\n' fixture > "$test_root/artifacts with spaces/package.deb"

(
  cd "$test_root/changed directory"
  PATH="$fake_bin:$PATH" APT_ARGUMENTS="$test_root/install.args" \
    "$install_script" install '../artifacts with spaces/package.deb'
  PATH="$fake_bin:$PATH" APT_ARGUMENTS="$test_root/reinstall.args" \
    "$install_script" reinstall '../artifacts with spaces/package.deb'
)

absolute_deb="$test_root/artifacts with spaces/package.deb"
mapfile -t install_args < "$test_root/install.args"
test "${#install_args[@]}" -eq 3
test "${install_args[0]}" = install
test "${install_args[1]}" = --yes
test "${install_args[2]}" = "$absolute_deb"

mapfile -t reinstall_args < "$test_root/reinstall.args"
test "${#reinstall_args[@]}" -eq 4
test "${reinstall_args[0]}" = install
test "${reinstall_args[1]}" = --yes
test "${reinstall_args[2]}" = --reinstall
test "${reinstall_args[3]}" = "$absolute_deb"

printf '%s\n' 'local DEB install path tests passed'
