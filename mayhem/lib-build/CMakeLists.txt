# Builds only pod5_format, the way upstream's ENABLE_FUZZERS=ON does (POD5_ENABLE_FUZZERS=1 turns on its
# "skip huge sizes when fuzzing" limits). The top-level CMakeLists cannot be used with ENABLE_FUZZERS=ON
# here: it would also configure fuzz/, whose corpus archives are git-lfs objects.
cmake_minimum_required(VERSION 3.18.0)
project(POD5)

set(POD5_SRC ${CMAKE_CURRENT_SOURCE_DIR}/../.. CACHE PATH "pod5 source tree")
include(${POD5_SRC}/cmake/POD5Version.cmake)
set(CMAKE_PROJECT_VERSION ${POD5_NUMERIC_VERSION})
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${POD5_SRC}/cmake")

option(ENABLE_CONAN "" OFF)
option(CONAN2 "" OFF)
option(BUILD_SHARED_LIB "" OFF)
option(BUILD_PYTHON_WHEEL "" OFF)
option(POD5_BUILD_EXAMPLES "" OFF)
set(POD5_DISABLE_TESTS ON)

add_compile_definitions(POD5_ENABLE_FUZZERS=1)
include_directories("${POD5_SRC}/third_party/include")
include(GenerateExportHeader)
add_subdirectory(${POD5_SRC}/c++ c++)
