#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packaging/linux/lib.sh
source "$script_dir/lib.sh"

test "$#" -eq 3 || die 'usage: build_deb.sh BUNDLE OUTPUT_DIRECTORY CI_RUN_NUMBER'
source_bundle=$1
output_directory=$2
ci_run_number=$3
[[ "$ci_run_number" =~ ^[0-9]+$ ]] || die 'CI run number must be numeric'
require_empty_directory "$output_directory"
for command in dpkg-deb dpkg-shlibdeps file patchelf readelf jq; do
  require_command "$command"
done
validate_distribution_assets

work_directory=$(mktemp -d /tmp/flutterustmusic-deb-XXXXXX)
trap 'rm -rf -- "$work_directory"' EXIT
normalized_bundle="$work_directory/normalized-bundle"
notices_directory="$work_directory/notices"
package_root="$work_directory/package-root"
mkdir -p "$package_root"

normalize_bundle "$source_bundle" "$normalized_bundle"
"$script_dir/collect_notices.sh" "$normalized_bundle" "$notices_directory"
write_build_info "$notices_directory/BUILD-INFO.txt" 'Ubuntu 24.04 (amd64)'
install_native_tree "$normalized_bundle" "$package_root" "$notices_directory"

mkdir -p "$work_directory/debian"
cat > "$work_directory/debian/control" <<'CONTROL'
Source: flutterustmusic
Section: sound
Priority: optional
Maintainer: Fura maintainers <noreply@example.invalid>
Standards-Version: 4.7.0

Package: flutterustmusic
Architecture: amd64
Description: Desktop music client development package
CONTROL

elf_arguments=()
while IFS= read -r -d '' candidate; do
  if readelf -h "$candidate" >/dev/null 2>&1; then
    elf_arguments+=("-e$candidate")
  fi
done < <(find "$package_root$native_app_root" -type f -print0)
test "${#elf_arguments[@]}" -gt 0 || die 'no ELF files found for dpkg-shlibdeps'

(
  cd "$work_directory"
  dpkg-shlibdeps --ignore-missing-info \
    -l"$package_root$native_app_root/lib" \
    -Tdebian/substvars \
    "${elf_arguments[@]}"
)
auto_dependencies=$(sed -n 's/^shlibs:Depends=//p' "$work_directory/debian/substvars")
test -n "$auto_dependencies" || die 'dpkg-shlibdeps produced no runtime dependencies'

read_project_version
deb_version="${project_version}+${project_build}~dev${ci_run_number}"
installed_size=$(du -sk "$package_root" | awk '{print $1}')
control_directory="$package_root/DEBIAN"
mkdir -p "$control_directory"
cat > "$control_directory/control" <<CONTROL
Package: flutterustmusic
Version: $deb_version
Section: sound
Priority: optional
Architecture: amd64
Maintainer: Fura maintainers <noreply@example.invalid>
Installed-Size: $installed_size
Depends: $auto_dependencies, ca-certificates, dbus-user-session, fonts-dejavu-core, gstreamer1.0-plugins-base, gstreamer1.0-plugins-good
Suggests: gnome-keyring
Homepage: https://github.com/fura-project/fura-music
Description: Desktop music client development package
 Manual, short-lived development package for maintainer-operated Linux runtime
 testing. This is not a signed production release.
CONTROL

package_file="$output_directory/flutterustmusic-${deb_version}-ubuntu24.04-amd64.deb"
dpkg-deb --root-owner-group --build "$package_root" "$package_file"
dpkg-deb --info "$package_file" > "$output_directory/DEB_METADATA.txt"
dpkg-deb --contents "$package_file" > "$output_directory/DEB_CONTENTS.txt"
cp "$notices_directory/BUILD-INFO.txt" "$output_directory/BUILD-INFO.txt"
"$script_dir/audit_bundle.sh" "$normalized_bundle" "$output_directory/audit"
write_sha256sums "$output_directory"
