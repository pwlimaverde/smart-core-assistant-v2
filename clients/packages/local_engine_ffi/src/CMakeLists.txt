# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(local_engine_ffi_library VERSION 0.0.1 LANGUAGES C)

add_library(local_engine_ffi SHARED
  "local_engine_ffi.c"
)

set_target_properties(local_engine_ffi PROPERTIES
  PUBLIC_HEADER local_engine_ffi.h
  OUTPUT_NAME "local_engine_ffi"
)

target_compile_definitions(local_engine_ffi PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(local_engine_ffi PRIVATE "-Wl,-z,max-page-size=16384")
endif()
