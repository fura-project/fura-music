#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packaging/linux/lib.sh
source "$script_dir/lib.sh"

test "$#" -eq 2 || die 'usage: prepare_bundle.sh SOURCE_BUNDLE DESTINATION_BUNDLE'
normalize_bundle "$1" "$2"
