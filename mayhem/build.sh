#!/usr/bin/env bash
#
# mayhem/build.sh — build the pod5 fuzz harnesses (fuzz/fuzz_compress.cpp, fuzz/fuzz_file.cpp) and
# the upstream unit tests. Runs offline inside the commit image: Arrow/zstd/flatbuffers come from
# /opt/arrow and apt packages installed by mayhem/Dockerfile.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

SRC="${SRC:-/mayhem}"
cd "$SRC"
ARROW=/opt/arrow

# pod5 normally generates cmake/POD5Version.cmake from setuptools_scm; derive it from CHANGELOG.md.
V=$(grep -m1 -oE '^## \[?[0-9]+\.[0-9]+\.[0-9]+' CHANGELOG.md | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
IFS=. read -r V_MAJOR V_MINOR V_REV <<<"$V"
cat > cmake/POD5Version.cmake <<EOT
set(POD5_VERSION_MAJOR $V_MAJOR )
set(POD5_VERSION_MINOR $V_MINOR )
set(POD5_VERSION_REV $V_REV )
set(POD5_NUMERIC_VERSION $V_MAJOR.$V_MINOR.$V_REV )
set(POD5_FULL_VERSION $V )
EOT

# 1) Sanitized pod5_format static library, built with upstream's fuzz-build define (POD5_ENABLE_FUZZERS=1,
#    its own "skip huge sizes when fuzzing" limits; see mayhem/lib-build). fuzzer-no-link adds libFuzzer
#    coverage instrumentation to the library itself; -UNDEBUG keeps its asserts (the harnesses require them).
FLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS -O1 -UNDEBUG"
rm -rf build-fuzz
cmake -S mayhem/lib-build -B build-fuzz -G Ninja -Wno-dev \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$ARROW" \
    -DCMAKE_ARCHIVE_OUTPUT_DIRECTORY="$SRC/build-fuzz/Release/lib" \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_C_FLAGS="$FLAGS" -DCMAKE_CXX_FLAGS="$FLAGS" \
    -DDISABLE_CCACHE=ON
cmake --build build-fuzz --target pod5_format -j"$MAYHEM_JOBS"

# 2) Harnesses: libFuzzer binary + standalone run-once reproducer for each.
INC=(-I"$SRC/c++" -I"$SRC/build-fuzz/c++" -I"$SRC/third_party/include" -I"$ARROW/include")
LIBS=("$SRC/build-fuzz/Release/lib/libpod5_format.a" -L"$ARROW/lib" -Wl,-rpath,"$ARROW/lib" -larrow -lzstd -lz -lpthread)
HFLAGS=($SANITIZER_FLAGS $DEBUG_FLAGS -O1 -UNDEBUG -std=c++20 -DBUILD_SHARED_LIB=0)

$CXX "${HFLAGS[@]}" -c mayhem/lsan_off.cc -o /tmp/lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o

for t in fuzz_compress fuzz_file; do
    $CXX "${HFLAGS[@]}" $LIB_FUZZING_ENGINE "${INC[@]}" "fuzz/$t.cpp" /tmp/lsan_off.o "${LIBS[@]}" -o "/mayhem/$t"
    $CXX "${HFLAGS[@]}" "${INC[@]}" "fuzz/$t.cpp" /tmp/standalone_main.o /tmp/lsan_off.o "${LIBS[@]}" -o "/mayhem/$t-standalone"
done

# 3) Upstream unit tests, normal flags, independent build tree (c++/test/c_api_build_test.c etc.).
rm -rf build-tests
cmake -S mayhem/test-build -B build-tests -G Ninja -Wno-dev \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$ARROW" \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath,$ARROW/lib $COVERAGE_FLAGS" \
    -DDISABLE_CCACHE=ON
cmake --build build-tests --target pod5_unit_tests -j"$MAYHEM_JOBS"
