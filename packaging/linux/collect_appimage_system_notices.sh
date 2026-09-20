#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packaging/linux/lib.sh
source "$script_dir/lib.sh"

test "$#" -eq 2 || die 'usage: collect_appimage_system_notices.sh APPDIR DESTINATION'
appdir=$1
destination=$2
require_directory "$appdir"
require_command dpkg-query
mkdir -p "$destination"

package_list=$(mktemp /tmp/flutterustmusic-appimage-packages-XXXXXX.txt)
trap 'rm -f -- "$package_list"' EXIT
: > "$package_list"

while IFS= read -r -d '' bundled_file; do
  relative_path=${bundled_file#"$appdir"}
  owner=''
  if test -e "$relative_path" || test -L "$relative_path"; then
    owner=$(dpkg-query -S "$relative_path" 2>/dev/null | sed -n '1s/: .*//p' || true)
  fi
  if test -z "$owner"; then
    base_name=$(basename -- "$bundled_file")
    owner=$(dpkg-query -S "*/$base_name" 2>/dev/null | sed -n '1s/: .*//p' || true)
  fi
  if test -n "$owner"; then
    printf '%s\n' "${owner%%:*}" >> "$package_list"
  fi
done < <(find "$appdir/usr/lib" "$appdir/usr/libexec" -type f -print0 2>/dev/null || true)

sort -u "$package_list" -o "$package_list"
while IFS= read -r package; do
  test -n "$package" || continue
  copyright_file="/usr/share/doc/$package/copyright"
  package_destination="$destination/$package"
  mkdir -p "$package_destination"
  if test -f "$copyright_file"; then
    install -m 0644 "$copyright_file" "$package_destination/copyright"
  else
    printf 'No Debian copyright file was installed for this package.\n' \
      > "$package_destination/NO-COPYRIGHT-FILE.txt"
  fi
done < "$package_list"
cp "$package_list" "$destination/PACKAGES.txt"
