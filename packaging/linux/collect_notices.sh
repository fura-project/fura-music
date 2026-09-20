#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packaging/linux/lib.sh
source "$script_dir/lib.sh"

test "$#" -eq 2 || die 'usage: collect_notices.sh BUNDLE DESTINATION'
bundle=$1
destination=$2
validate_bundle_shape "$bundle"
require_command cargo
require_command jq
require_empty_directory "$destination"

install -m 0644 "$project_license" "$destination/LICENSE"
if test -f "$bundle/data/flutter_assets/NOTICES.Z"; then
  install -m 0644 "$bundle/data/flutter_assets/NOTICES.Z" \
    "$destination/FLUTTER_AND_DART_NOTICES.Z"
fi

rust_destination="$destination/third-party/rust"
mkdir -p -- "$rust_destination"
metadata_file=$(mktemp /tmp/flutterustmusic-cargo-metadata-XXXXXX.json)
trap 'rm -f -- "$metadata_file"' EXIT
cargo metadata --locked --format-version 1 \
  --manifest-path "$repo_root/Cargo.toml" > "$metadata_file"

jq -r '.packages[] | [.name, .version, .manifest_path, (.license // "NOASSERTION")] | @tsv' \
  "$metadata_file" | while IFS=$'\t' read -r name version manifest_path license_expression; do
    package_directory=$(dirname -- "$manifest_path")
    package_destination="$rust_destination/${name}-${version}"
    mkdir -p -- "$package_destination"
    printf '%s\n' "$license_expression" > "$package_destination/LICENSE-EXPRESSION.txt"
    copied=false
    while IFS= read -r -d '' license_file; do
      install -m 0644 "$license_file" \
        "$package_destination/$(basename -- "$license_file")"
      copied=true
    done < <(find "$package_directory" -maxdepth 1 -type f \
      \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'NOTICE*' -o -iname 'COPYRIGHT*' \) \
      -print0)
    if ! $copied; then
      printf 'No standalone license text was present in the resolved package directory.\n' \
        > "$package_destination/NO-STANDALONE-LICENSE-FILE.txt"
    fi
  done

{
  printf 'Generated from Cargo.lock with cargo metadata.\n'
  printf 'Flutter and Dart notices remain in FLUTTER_AND_DART_NOTICES.Z.\n'
  printf 'This inventory supports development-artifact review; it is not a completed formal redistribution audit.\n'
} > "$destination/NOTICE-BOUNDARY.txt"
