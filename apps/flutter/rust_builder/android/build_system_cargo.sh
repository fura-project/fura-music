#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 8 ]]; then
  echo "usage: build_system_cargo.sh MODE MANIFEST NDK_VERSION OUTPUT SDK MIN_SDK TARGETS TARGET_DIR" >&2
  exit 64
fi

build_mode=$1
manifest_dir=$2
ndk_version=$3
output_dir=$4
sdk_directory=$5
min_sdk=$6
target_platforms=$7
target_dir=$8

case $target_platforms in
  android-arm64)
    rust_target=aarch64-linux-android
    cargo_target_env=AARCH64_LINUX_ANDROID
    android_abi=arm64-v8a
    ;;
  android-x64)
    rust_target=x86_64-linux-android
    cargo_target_env=X86_64_LINUX_ANDROID
    android_abi=x86_64
    ;;
  *)
    echo "The Linux system-Cargo path requires one explicit android-arm64 or android-x64 target." >&2
    echo "Invoke Flutter with --target-platform, or use rustup/Cargokit for other ABI sets." >&2
    exit 65
    ;;
esac

case $build_mode in
  debug)
    cargo_profile_args=()
    cargo_profile_dir=debug
    ;;
  profile|release)
    cargo_profile_args=(--release)
    cargo_profile_dir=release
    ;;
  *)
    echo "Unsupported Android build mode: $build_mode" >&2
    exit 65
    ;;
esac

cargo_executable=$(command -v cargo || true)
rustc_executable=$(command -v rustc || true)
if [[ -z $cargo_executable || -z $rustc_executable ]]; then
  echo "The Android system-Cargo path requires cargo and rustc in PATH." >&2
  exit 69
fi

rust_sysroot=$($rustc_executable --print sysroot)
rust_library="$rust_sysroot/lib/rustlib/src/rust/library"
if [[ ! -f $rust_library/Cargo.lock ]]; then
  echo "Missing Rust standard-library sources for $($rustc_executable --version)." >&2
  echo "Install the matching rust-src package (on Arch/Manjaro: sudo pacman -S rust-src)." >&2
  exit 69
fi

host_arch=$(uname -m)
if [[ $host_arch != x86_64 ]]; then
  echo "The Linux system-Cargo Android path is validated only on an x86_64 host, not $host_arch." >&2
  exit 65
fi

ndk_bin="$sdk_directory/ndk/$ndk_version/toolchains/llvm/prebuilt/linux-x86_64/bin"
target_clang="$ndk_bin/${rust_target}${min_sdk}-clang"
for tool in clang clang++ llvm-ar llvm-nm llvm-ranlib "${rust_target}${min_sdk}-clang"; do
  if [[ ! -x $ndk_bin/$tool ]]; then
    echo "Missing Android NDK tool: $ndk_bin/$tool" >&2
    exit 69
  fi
done

ndk_major=${ndk_version%%.*}
if (( ndk_major < 23 )); then
  echo "The Android system-Cargo path requires NDK 23 or newer, not $ndk_version." >&2
  exit 65
fi
libgcc_workaround="$target_dir/cargokit/libgcc_workaround/$ndk_major"
rm -rf -- "$output_dir"
mkdir -p "$output_dir/$android_abi" "$libgcc_workaround"
printf 'INPUT(-lunwind)\n' > "$libgcc_workaround/libgcc.a"

unit_separator=$'\x1f'
rust_flags="-L${unit_separator}$libgcc_workaround"
rust_flags+="${unit_separator}-C${unit_separator}link-arg=-Wl,--hash-style=both"
rust_flags+="${unit_separator}-C${unit_separator}link-arg=-Wl,-z,max-page-size=16384"
if [[ $rust_target == aarch64-linux-android ]]; then
  clang_resource_dir=$($ndk_bin/clang --print-resource-dir)
  compiler_rt_builtins="$clang_resource_dir/lib/linux/libclang_rt.builtins-aarch64-android.a"
  if [[ ! -f $compiler_rt_builtins ]]; then
    echo "Missing Android AArch64 compiler runtime: $compiler_rt_builtins" >&2
    exit 69
  fi
  rust_flags+="${unit_separator}-C${unit_separator}link-arg=$compiler_rt_builtins"
fi
if [[ -n ${CARGO_ENCODED_RUSTFLAGS:-} ]]; then
  rust_flags="${CARGO_ENCODED_RUSTFLAGS}${unit_separator}${rust_flags}"
fi

env \
  RUSTC_BOOTSTRAP=1 \
  "AR_${rust_target}=$ndk_bin/llvm-ar" \
  "CC_${rust_target}=$ndk_bin/clang" \
  "CFLAGS_${rust_target}=--target=${rust_target}${min_sdk}" \
  "CXX_${rust_target}=$ndk_bin/clang++" \
  "CXXFLAGS_${rust_target}=--target=${rust_target}${min_sdk}" \
  "RANLIB_${rust_target}=$ndk_bin/llvm-ranlib" \
  "CARGO_TARGET_${cargo_target_env}_LINKER=$target_clang" \
  "CARGO_ENCODED_RUSTFLAGS=$rust_flags" \
  "$cargo_executable" build \
    --manifest-path "$manifest_dir/Cargo.toml" \
    --package rust_lib_flutterustmusic \
    --locked \
    "${cargo_profile_args[@]}" \
    --target "$rust_target" \
    --target-dir "$target_dir" \
    -Z build-std=std,panic_abort

rust_library_path="$target_dir/$rust_target/$cargo_profile_dir/librust_lib_flutterustmusic.so"
if [[ ! -f $rust_library_path ]]; then
  echo "Cargo completed without the expected Rust bridge library: $rust_library_path" >&2
  exit 70
fi
unresolved_aarch64_builtins=$(
  "$ndk_bin/llvm-nm" -u "$rust_library_path" |
    awk '$NF ~ /^__aarch64_/ { print $NF }' |
    sort -u
)
if [[ -n $unresolved_aarch64_builtins ]]; then
  echo "Rust bridge has unresolved AArch64 compiler-runtime symbols:" >&2
  echo "$unresolved_aarch64_builtins" >&2
  exit 70
fi
cp -- "$rust_library_path" "$output_dir/$android_abi/librust_lib_flutterustmusic.so"
