# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)
cmake_policy(SET CMP0079 NEW)

# Project-level configuration.
set(PROJECT_NAME "rust_lib_flutterustmusic")
project(${PROJECT_NAME} LANGUAGES CXX)

# TD-001: Cargokit 2.13.0 requires rustup even when a supported system Cargo
# toolchain is already installed. Linux is a first-class platform and the
# project is developed on Arch with the system Rust packages, so build this
# library directly until the generated backend supports that toolchain.
find_program(CARGO_EXECUTABLE cargo REQUIRED)
get_filename_component(
  RUST_BUILDER_LINUX_DIR
  "${CMAKE_CURRENT_LIST_DIR}"
  REALPATH
)
get_filename_component(
  RUST_BRIDGE_DIR
  "${RUST_BUILDER_LINUX_DIR}/../../../../bridges/flutter"
  REALPATH
)

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  set(CARGO_PROFILE_ARGUMENTS)
  set(CARGO_PROFILE_DIR "debug")
else()
  set(CARGO_PROFILE_ARGUMENTS "--release")
  set(CARGO_PROFILE_DIR "release")
endif()

set(CARGO_TARGET_DIR "${CMAKE_CURRENT_BINARY_DIR}/cargo_target")
set(RUST_LIBRARY_SOURCE
  "${CARGO_TARGET_DIR}/${CARGO_PROFILE_DIR}/lib${PROJECT_NAME}.so"
)
set(RUST_LIBRARY_OUTPUT
  "${CMAKE_CURRENT_BINARY_DIR}/lib${PROJECT_NAME}.so"
)

add_custom_target(${PROJECT_NAME}_cargo ALL
  COMMAND
    "${CARGO_EXECUTABLE}" build
    --manifest-path "${RUST_BRIDGE_DIR}/Cargo.toml"
    --package "${PROJECT_NAME}"
    ${CARGO_PROFILE_ARGUMENTS}
    --target-dir "${CARGO_TARGET_DIR}"
  COMMAND
    "${CMAKE_COMMAND}" -E copy_if_different
    "${RUST_LIBRARY_SOURCE}"
    "${RUST_LIBRARY_OUTPUT}"
  BYPRODUCTS "${RUST_LIBRARY_OUTPUT}"
  WORKING_DIRECTORY "${RUST_BRIDGE_DIR}"
  COMMENT "Building ${PROJECT_NAME} with the system Cargo toolchain"
  VERBATIM
)

add_dependencies(${BINARY_NAME} ${PROJECT_NAME}_cargo)
target_link_libraries(${BINARY_NAME} PRIVATE "${RUST_LIBRARY_OUTPUT}")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(rust_lib_flutterustmusic_bundled_libraries
  "${RUST_LIBRARY_OUTPUT}"
  PARENT_SCOPE
)
