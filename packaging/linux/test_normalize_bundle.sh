#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packaging/linux/lib.sh
source "$script_dir/lib.sh"

for command in cc jq patchelf readelf; do
  require_command "$command"
done

test_root=$(mktemp -d /tmp/flutterustmusic-normalize-test-XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

make_fixture() {
  local bundle=$1
  mkdir -p "$bundle/lib" "$bundle/data/flutter_assets"
  printf '%s\n' '{"format-version":[1,0,0],"native-assets":{}}' \
    > "$bundle/data/flutter_assets/NativeAssetsManifest.json"
  printf '%s\n' fixture > "$bundle/data/icudtl.dat"

  printf '%s\n' 'int main(void) { return 0; }' | \
    cc -x c - -o "$bundle/$app_name"
  printf '%s\n' 'int plugin_symbol(void) { return 0; }' | \
    cc -shared -fPIC -x c - -o "$bundle/lib/libfixture.so"
  for library in \
    libflutter_linux_gtk.so \
    libapp.so \
    librust_lib_flutterustmusic.so \
    libmedia_kit_video_plugin.so \
    libaudioplayers_linux_plugin.so \
    libflutter_secure_storage_linux_plugin.so \
    libwebview_all_linux_plugin.so; do
    cp "$bundle/lib/libfixture.so" "$bundle/lib/$library"
  done
  printf '%s\n' 'int dartjni_symbol(void) { return 0; }' | \
    cc -shared -fPIC -Wl,-soname,libdartjni.so -x c - \
      -o "$bundle/lib/libdartjni.so"
}

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

source_bundle="$test_root/source-without-staging-manifest"
destination_bundle="$test_root/normalized-without-staging-manifest"
make_fixture "$source_bundle"
normalize_bundle "$source_bundle" "$destination_bundle"
test ! -e "$destination_bundle/lib/libdartjni.so"

source_bundle="$test_root/source-with-staging-manifest"
destination_bundle="$test_root/normalized-with-staging-manifest"
make_fixture "$source_bundle"
cp "$source_bundle/data/flutter_assets/NativeAssetsManifest.json" \
  "$source_bundle/lib/native_assets.json"
normalize_bundle "$source_bundle" "$destination_bundle"
test ! -e "$destination_bundle/lib/libdartjni.so"

source_bundle="$test_root/source-missing-runtime-manifest"
make_fixture "$source_bundle"
unlink "$source_bundle/data/flutter_assets/NativeAssetsManifest.json"
expect_failure 'required file is missing' \
  normalize_bundle "$source_bundle" "$test_root/missing-runtime-output"

source_bundle="$test_root/source-malformed-runtime-manifest"
make_fixture "$source_bundle"
printf '%s\n' '{not-json' \
  > "$source_bundle/data/flutter_assets/NativeAssetsManifest.json"
expect_failure 'invalid Flutter native-assets manifest' \
  normalize_bundle "$source_bundle" "$test_root/malformed-runtime-output"

source_bundle="$test_root/source-declared-native-asset"
make_fixture "$source_bundle"
printf '%s\n' \
  '{"format-version":[1,0,0],"native-assets":{"package:fixture/asset":{"absolute":"libdartjni.so"}}}' \
  > "$source_bundle/data/flutter_assets/NativeAssetsManifest.json"
expect_failure 'Flutter declares native assets' \
  normalize_bundle "$source_bundle" "$test_root/declared-native-output"

source_bundle="$test_root/source-elf-reference"
make_fixture "$source_bundle"
printf '%s\n' 'extern int dartjni_symbol(void); int call_jni(void) { return dartjni_symbol(); }' | \
  cc -shared -fPIC -x c - -L"$source_bundle/lib" \
    -Wl,--no-as-needed -ldartjni \
    -o "$source_bundle/lib/libmedia_kit_video_plugin.so"
expect_failure 'bundled ELF needs it' \
  normalize_bundle "$source_bundle" "$test_root/elf-reference-output"

source_bundle="$test_root/source-runtime-reference"
make_fixture "$source_bundle"
printf '%s\n' 'runtime loader requests libdartjni.so' \
  >> "$source_bundle/data/flutter_assets/runtime-reference.txt"
expect_failure 'bundled runtime data references it' \
  normalize_bundle "$source_bundle" "$test_root/runtime-reference-output"

printf '%s\n' 'normalize_bundle targeted tests passed'
