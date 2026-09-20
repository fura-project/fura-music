#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packaging/linux/lib.sh
source "$script_dir/lib.sh"

test "$#" -eq 3 || die 'usage: build_arch.sh BUNDLE OUTPUT_DIRECTORY CI_RUN_NUMBER'
source_bundle=$1
output_directory=$2
ci_run_number=$3
[[ "$ci_run_number" =~ ^[0-9]+$ ]] || die 'CI run number must be numeric'
require_empty_directory "$output_directory"
for command in makepkg pacman file patchelf readelf jq; do
  require_command "$command"
done
validate_distribution_assets

work_directory=$(mktemp -d /tmp/flutterustmusic-arch-XXXXXX)
trap 'rm -rf -- "$work_directory"' EXIT
normalized_bundle="$work_directory/normalized-bundle"
notices_directory="$work_directory/notices"
package_directory="$work_directory/package"
mkdir -p "$package_directory"

normalize_bundle "$source_bundle" "$normalized_bundle"
"$script_dir/collect_notices.sh" "$normalized_bundle" "$notices_directory"
write_build_info "$notices_directory/BUILD-INFO.txt" 'Arch Linux rolling (x86_64)'

mkdir "$package_directory/bundle" "$package_directory/notices"
cp -a "$normalized_bundle/." "$package_directory/bundle/"
cp -a "$notices_directory/." "$package_directory/notices/"
tar -C "$package_directory" -czf "$package_directory/flutterustmusic-bundle.tar.gz" bundle
tar -C "$package_directory" -czf "$package_directory/flutterustmusic-notices.tar.gz" notices
rm -rf -- "$package_directory/bundle" "$package_directory/notices"
install -m 0755 "$launcher_file" "$package_directory/flutterustmusic"
install -m 0644 "$desktop_file" "$package_directory/${app_id}.desktop"
install -m 0644 "$icon_file" "$package_directory/${app_id}.png"
install -m 0644 "$project_license" "$package_directory/LICENSE"
install -m 0644 "$notices_directory/BUILD-INFO.txt" "$package_directory/BUILD-INFO.txt"

read_project_version
pkgrel="${project_build}.${ci_run_number}"
sed \
  -e "s/@PKGVER@/$project_version/g" \
  -e "s/@PKGREL@/$pkgrel/g" \
  -e "s/@BUNDLE_SHA256@/$(sha256_file "$package_directory/flutterustmusic-bundle.tar.gz")/g" \
  -e "s/@NOTICES_SHA256@/$(sha256_file "$package_directory/flutterustmusic-notices.tar.gz")/g" \
  -e "s/@LAUNCHER_SHA256@/$(sha256_file "$package_directory/flutterustmusic")/g" \
  -e "s/@DESKTOP_SHA256@/$(sha256_file "$package_directory/${app_id}.desktop")/g" \
  -e "s/@ICON_SHA256@/$(sha256_file "$package_directory/${app_id}.png")/g" \
  -e "s/@LICENSE_SHA256@/$(sha256_file "$package_directory/LICENSE")/g" \
  -e "s/@BUILD_INFO_SHA256@/$(sha256_file "$package_directory/BUILD-INFO.txt")/g" \
  "$script_dir/PKGBUILD.in" > "$package_directory/PKGBUILD"

if test "$EUID" -eq 0; then
  makepkg_user=${MAKEPKG_USER:-}
  test -n "$makepkg_user" || die 'set MAKEPKG_USER when invoking this script as root'
  id "$makepkg_user" >/dev/null 2>&1 || die "makepkg user does not exist: $makepkg_user"
  chown -R "$makepkg_user" "$package_directory"
  # $1 belongs to the non-root child shell.
  # shellcheck disable=SC2016
  runuser -u "$makepkg_user" -- bash -eu -o pipefail -c '
    cd "$1"
    makepkg --clean --cleanbuild --force --noconfirm
  ' bash "$package_directory"
else
  (
    cd "$package_directory"
    makepkg --clean --cleanbuild --force --noconfirm
  )
fi
package_file=$(find "$package_directory" -maxdepth 1 -type f -name '*.pkg.tar.zst' -print -quit)
test -n "$package_file" || die 'makepkg did not produce a package'
output_package="$output_directory/flutterustmusic-${project_version}-${pkgrel}-arch-x86_64.pkg.tar.zst"
cp "$package_file" "$output_package"
pacman -Qip "$output_package" > "$output_directory/ARCH_METADATA.txt"
pacman -Qlp "$output_package" > "$output_directory/ARCH_CONTENTS.txt"
cp "$package_directory/PKGBUILD" "$output_directory/PKGBUILD"
cp "$notices_directory/BUILD-INFO.txt" "$output_directory/BUILD-INFO.txt"
"$script_dir/audit_bundle.sh" "$normalized_bundle" "$output_directory/audit"
write_sha256sums "$output_directory"
