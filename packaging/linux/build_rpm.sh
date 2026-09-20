#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packaging/linux/lib.sh
source "$script_dir/lib.sh"

test "$#" -eq 3 || die 'usage: build_rpm.sh BUNDLE OUTPUT_DIRECTORY CI_RUN_NUMBER'
source_bundle=$1
output_directory=$2
ci_run_number=$3
[[ "$ci_run_number" =~ ^[0-9]+$ ]] || die 'CI run number must be numeric'
require_empty_directory "$output_directory"
for command in rpmbuild rpm file patchelf readelf jq; do
  require_command "$command"
done
validate_distribution_assets

work_directory=$(mktemp -d /tmp/flutterustmusic-rpm-XXXXXX)
trap 'rm -rf -- "$work_directory"' EXIT
normalized_bundle="$work_directory/normalized-bundle"
notices_directory="$work_directory/notices"
top_directory="$work_directory/rpmbuild"
mkdir -p "$top_directory"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

normalize_bundle "$source_bundle" "$normalized_bundle"
"$script_dir/collect_notices.sh" "$normalized_bundle" "$notices_directory"
write_build_info "$notices_directory/BUILD-INFO.txt" 'Fedora 43 (x86_64)'

tar -C "$normalized_bundle" -czf "$top_directory/SOURCES/flutterustmusic-bundle.tar.gz" .
tar -C "$notices_directory" -czf "$top_directory/SOURCES/flutterustmusic-notices.tar.gz" .
install -m 0755 "$launcher_file" "$top_directory/SOURCES/flutterustmusic"
install -m 0644 "$desktop_file" "$top_directory/SOURCES/${app_id}.desktop"
install -m 0644 "$icon_file" "$top_directory/SOURCES/${app_id}.png"
install -m 0644 "$project_license" "$top_directory/SOURCES/LICENSE"
install -m 0644 "$notices_directory/BUILD-INFO.txt" "$top_directory/SOURCES/BUILD-INFO.txt"

read_project_version
rpm_release="${project_build}.dev${ci_run_number}"
sed \
  -e "s/@VERSION@/$project_version/g" \
  -e "s/@RELEASE@/$rpm_release/g" \
  "$script_dir/flutterustmusic.spec.in" > "$top_directory/SPECS/flutterustmusic.spec"

rpmbuild --define "_topdir $top_directory" -bb "$top_directory/SPECS/flutterustmusic.spec"
package_file=$(find "$top_directory/RPMS" -type f -name '*.rpm' -print -quit)
test -n "$package_file" || die 'rpmbuild did not produce an RPM'
output_package="$output_directory/flutterustmusic-${project_version}-${rpm_release}.fc43-x86_64.rpm"
cp "$package_file" "$output_package"
rpm -qip "$output_package" > "$output_directory/RPM_METADATA.txt"
rpm -qlp "$output_package" > "$output_directory/RPM_CONTENTS.txt"
rpm -qpR "$output_package" > "$output_directory/RPM_REQUIRES.txt"
cp "$top_directory/SPECS/flutterustmusic.spec" "$output_directory/flutterustmusic.spec"
cp "$notices_directory/BUILD-INFO.txt" "$output_directory/BUILD-INFO.txt"
"$script_dir/audit_bundle.sh" "$normalized_bundle" "$output_directory/audit"
write_sha256sums "$output_directory"
