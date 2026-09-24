#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packaging/linux/lib.sh
source "$script_dir/lib.sh"

test "$#" -eq 3 || die 'usage: build_appimage.sh BUNDLE OUTPUT_DIRECTORY CI_RUN_NUMBER'
source_bundle=$1
output_directory=$2
ci_run_number=$3
[[ "$ci_run_number" =~ ^[0-9]+$ ]] || die 'CI run number must be numeric'
output_directory=$(prepare_empty_output_directory "$output_directory")
for command in curl dpkg-query file patchelf readelf jq mksquashfs; do
  require_command "$command"
done
validate_distribution_assets

work_directory=$(mktemp -d /tmp/flutterustmusic-appimage-XXXXXX)
trap 'rm -rf -- "$work_directory"' EXIT
normalized_bundle="$work_directory/normalized-bundle"
notices_directory="$work_directory/notices"
appdir="$work_directory/AppDir"
tools_directory="$work_directory/tools"
mkdir -p \
  "$appdir/usr/lib/flutterustmusic" \
  "$appdir/usr/bin" \
  "$appdir/usr/share/applications" \
  "$appdir/usr/share/icons/hicolor/512x512/apps" \
  "$appdir/usr/share/doc/flutterustmusic"

normalize_bundle "$source_bundle" "$normalized_bundle"
"$script_dir/collect_notices.sh" "$normalized_bundle" "$notices_directory"
write_build_info "$notices_directory/BUILD-INFO.txt" 'Ubuntu 24.04 AppImage build (x86_64)'
cp -a "$normalized_bundle/." "$appdir/usr/lib/flutterustmusic/"
install -m 0644 "$desktop_file" "$appdir/usr/share/applications/${app_id}.desktop"
install -m 0644 "$icon_file" \
  "$appdir/usr/share/icons/hicolor/512x512/apps/${app_id}.png"
cp -a "$notices_directory/." "$appdir/usr/share/doc/flutterustmusic/"

copy_package_runtime_paths() {
  local package=$1
  local path_pattern=$2
  dpkg-query -L "$package" | grep -E "$path_pattern" | while IFS= read -r path; do
    if test -f "$path" || test -L "$path"; then
      cp -a --parents "$path" "$appdir"
    fi
  done
}

copy_package_runtime_paths libgstreamer1.0-0 \
  '/gstreamer-1\.0/.*\.so(\.|$)|/gstreamer1\.0/.*/gst-plugin-scanner$'
copy_package_runtime_paths gstreamer1.0-plugins-base '/gstreamer-1\.0/.*\.so$'
copy_package_runtime_paths gstreamer1.0-plugins-good '/gstreamer-1\.0/.*\.so$'
# linuxdeploy's system-library exclusion list omits HarfBuzz even though the
# bundled Ubuntu libpangoft2 has a direct DT_NEEDED edge to libharfbuzz.so.0.
# Carry that exact runtime edge so clean-room targets do not need a desktop
# Pango installation merely to load the bundled library.
copy_package_runtime_paths libharfbuzz0b '/libharfbuzz\.so\.0(\.|$)'
# FriBidi is another ordinary Pango runtime edge that linuxdeploy's
# system-library exclusion list omits. Keep it private to the AppImage rather
# than treating bidirectional text shaping as a target-system capability.
copy_package_runtime_paths libfribidi0 '/libfribidi\.so\.0(\.|$)'
# libmpv's selected FFmpeg closure includes libavdevice -> libdc1394, whose
# ordinary userspace USB backend is not part of the declared target graphics
# or audio base. Keep the exact libusb SONAME private to the AppImage.
copy_package_runtime_paths libusb-1.0-0 '/libusb-1\.0\.so\.0(\.|$)'
webkit_package=$(dpkg-query -W -f='${binary:Package}\n' 'libwebkit2gtk-4.1-0*' 2>/dev/null | head -n 1)
test -n "$webkit_package" || die 'unable to resolve the Ubuntu WebKitGTK runtime package'
copy_package_runtime_paths "$webkit_package" '/webkit(2)?gtk-4\.1/|/webkit2gtk-4\.1/'

"$script_dir/fetch_appimage_tools.sh" "$tools_directory"
linuxdeploy_extract="$work_directory/linuxdeploy-extracted"
appimagetool_extract="$work_directory/appimagetool-extracted"
mkdir "$linuxdeploy_extract" "$appimagetool_extract"
(
  cd "$linuxdeploy_extract"
  "$tools_directory/linuxdeploy-x86_64.AppImage" --appimage-extract >/dev/null
)
(
  cd "$appimagetool_extract"
  "$tools_directory/appimagetool-x86_64.AppImage" --appimage-extract >/dev/null
)

export PATH="$tools_directory:$PATH"
"$linuxdeploy_extract/squashfs-root/AppRun" \
  --appdir "$appdir" \
  --executable "$appdir/usr/lib/flutterustmusic/flutterustmusic" \
  --deploy-deps-only "$appdir/usr" \
  --desktop-file "$desktop_file" \
  --icon-file "$icon_file" \
  --icon-filename "$app_id" \
  --custom-apprun "$script_dir/assets/AppRun" \
  --exclude-library 'libEGL.so*' \
  --exclude-library 'libGL.so*' \
  --exclude-library 'libGLX.so*' \
  --exclude-library 'libOpenGL.so*' \
  --exclude-library 'libdrm.so*' \
  --exclude-library 'libgbm.so*' \
  --exclude-library 'libwayland-*.so*' \
  --plugin gtk

# The GTK plugin invokes linuxdeploy again without the outer exclusion list.
# Enforce the same host-graphics boundary after the plugin has completed; the
# existing audit below verifies that every remaining ELF still resolves.
while IFS= read -r -d '' bundled_graphics_library; do
  printf 'Removing target-provided graphics library: %s\n' \
    "${bundled_graphics_library#"$appdir"/}"
  unlink -- "$bundled_graphics_library"
done < <(find "$appdir/usr/lib" \( -type f -o -type l \) \( \
  -name 'libEGL.so*' -o \
  -name 'libGL.so*' -o \
  -name 'libGLX.so*' -o \
  -name 'libOpenGL.so*' -o \
  -name 'libdrm.so*' -o \
  -name 'libgbm.so*' -o \
  -name 'libwayland-*.so*' \
\) -print0)

# linuxdeploy deploys the application ELF to usr/bin using its basename while
# collecting dependencies. Install the shell launcher only afterwards so the
# two files cannot collide in linuxdeploy's deferred strip queue.
install -m 0755 "$launcher_file" "$appdir/usr/bin/flutterustmusic"

system_notices="$appdir/usr/share/doc/flutterustmusic/third-party/system"
"$script_dir/collect_appimage_system_notices.sh" "$appdir" "$system_notices"

read_project_version
portable_version="${project_version}+${project_build}-dev${ci_run_number}"
package_file="$output_directory/flutterustmusic-${portable_version}-ubuntu24.04-x86_64.AppImage"
ARCH=x86_64 VERSION="$portable_version" \
  "$appimagetool_extract/squashfs-root/AppRun" \
  --runtime-file "$tools_directory/runtime-x86_64" \
  "$appdir" "$package_file"
chmod 0755 "$package_file"

extract_directory="$work_directory/final-extract"
mkdir "$extract_directory"
(
  cd "$extract_directory"
  "$package_file" --appimage-extract >/dev/null
)
"$script_dir/audit_appimage.sh" "$extract_directory/squashfs-root" \
  "$output_directory/audit"
cp "$notices_directory/BUILD-INFO.txt" "$output_directory/BUILD-INFO.txt"
cp "$tools_directory/TOOLS.txt" "$output_directory/APPIMAGE_TOOLS.txt"
write_sha256sums "$output_directory"
