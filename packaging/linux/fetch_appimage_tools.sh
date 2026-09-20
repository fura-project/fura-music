#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packaging/linux/lib.sh
source "$script_dir/lib.sh"

test "$#" -eq 1 || die 'usage: fetch_appimage_tools.sh DESTINATION'
destination=$1
require_command curl
require_command sha256sum
require_empty_directory "$destination"

linuxdeploy_url='https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage'
linuxdeploy_sha256='c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d'
appimagetool_url='https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage'
appimagetool_sha256='ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0'
gtk_plugin_commit='7a3fbc31a9e5075073ff8790f26effbac5f84453'
gtk_plugin_url="https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/${gtk_plugin_commit}/linuxdeploy-plugin-gtk.sh"
gtk_plugin_sha256='b0f4cbc684a0103a9651f0955b635eaea0096b3a66c0f5a2c2aa337960375171'
runtime_url='https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-x86_64'
runtime_sha256='1cc49bcf1e2ccd593c379adb17c9f85a36d619088296504de95b1d06215aebbf'

download_and_verify() {
  local url=$1
  local sha256=$2
  local output=$3
  curl --fail --location --retry 4 --retry-all-errors --silent --show-error \
    --output "$output" "$url"
  printf '%s  %s\n' "$sha256" "$output" | sha256sum --check --status || \
    die "checksum mismatch for $url"
}

download_and_verify "$linuxdeploy_url" "$linuxdeploy_sha256" \
  "$destination/linuxdeploy-x86_64.AppImage"
download_and_verify "$appimagetool_url" "$appimagetool_sha256" \
  "$destination/appimagetool-x86_64.AppImage"
download_and_verify "$gtk_plugin_url" "$gtk_plugin_sha256" \
  "$destination/linuxdeploy-plugin-gtk.sh"
download_and_verify "$runtime_url" "$runtime_sha256" \
  "$destination/runtime-x86_64"
chmod 0755 \
  "$destination/linuxdeploy-x86_64.AppImage" \
  "$destination/appimagetool-x86_64.AppImage" \
  "$destination/linuxdeploy-plugin-gtk.sh" \
  "$destination/runtime-x86_64"

cat > "$destination/TOOLS.txt" <<TOOLS
linuxdeploy=1-alpha-20251107-1
linuxdeploy_sha256=$linuxdeploy_sha256
linuxdeploy_gtk_commit=$gtk_plugin_commit
linuxdeploy_gtk_sha256=$gtk_plugin_sha256
appimagetool=1.9.1
appimagetool_sha256=$appimagetool_sha256
type2_runtime_url=$runtime_url
type2_runtime_sha256=$runtime_sha256
TOOLS
