# Builds only the upstream unit tests (c++/test) against the pod5 sources, with normal flags.
# The top-level CMakeLists would also pull in fuzz/, whose corpus archives are git-lfs objects.
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
set(POD5_DISABLE_TESTS OFF)

add_compile_definitions(POD5_ENABLE_FUZZERS=0)
include_directories("${POD5_SRC}/third_party/include")
enable_testing()
include(GenerateExportHeader)
add_subdirectory(${POD5_SRC}/c++ c++)
