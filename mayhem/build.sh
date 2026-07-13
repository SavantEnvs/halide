#!/usr/bin/env bash
#
# mayhem/build.sh — build the Halide fuzz harnesses, standalone reproducers, and the
# functional test oracle. Runs as `mayhem` in /mayhem inside the commit image.
#
# NOTE (focused build — see repos/halide.yaml / PR notes): upstream Halide requires a full
# LLVM 21 toolchain and a multi-hour libHalide build. Both fuzz targets, however, exercise only
# self-contained code:
#   * strip-namespaces  -> Halide::Internal::strip_namespaces (src/Util.cpp), which calls
#     extract_namespaces/split_string in the same TU; its transitive closure is just
#     Util.cpp + Error.cpp + Debug.cpp (no LLVM — only a -DLLVM_VERSION compile macro).
#   * build-halide-h    -> tools/build_halide_h.cpp, a standalone header-concatenation tool.
# So we compile exactly the real project sources on each fuzzed code path (with $SANITIZER_FLAGS
# + $DEBUG_FLAGS, so the fuzzed code is instrumented and carries DWARF<4), instead of building all
# of Halide+LLVM. The code paths are upstream's, unchanged; only the link scope is narrowed.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

CXXSTD="-std=c++17"
INC="-Isrc"
# LLVM_VERSION is normally injected by the Halide build; get_llvm_version() only static_asserts it
# is defined. The value is irrelevant to the fuzzed string utilities.
DEFS="-DLLVM_VERSION=210"

# Real Halide sources on the strip-namespaces code path.
UTIL_SRCS="src/Util.cpp src/Error.cpp src/Debug.cpp"

echo ">> [1/4] compiling instrumented Halide util objects (fuzzed code path)"
UTIL_OBJS=""
for s in $UTIL_SRCS; do
    o="/tmp/$(basename "$s" .cpp).san.o"
    # shellcheck disable=SC2086
    $CXX $CXXSTD $SANITIZER_FLAGS $DEBUG_FLAGS $DEFS $INC -c "$s" -o "$o"
    UTIL_OBJS="$UTIL_OBJS $o"
done

echo ">> [2/4] linking strip-namespaces fuzzer + standalone reproducer"
# libFuzzer target
# shellcheck disable=SC2086
$CXX $CXXSTD $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE $INC \
    mayhem/fuzz_strip_namespaces.cpp $UTIL_OBJS -o /mayhem/fuzz_strip_namespaces
# standalone (non-fuzzer) reproducer: compile the C driver as C first so its extern "C"
# LLVMFuzzerTestOneInput reference is not mangled by clang++.
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
# shellcheck disable=SC2086
$CXX $CXXSTD $SANITIZER_FLAGS $DEBUG_FLAGS $INC \
    mayhem/fuzz_strip_namespaces.cpp /tmp/standalone_main.o $UTIL_OBJS \
    -o /mayhem/fuzz_strip_namespaces-standalone

echo ">> [3/4] building build-halide-h in-process fuzzer + standalone reproducer"
# In-process libFuzzer harness over tools/build_halide_h.cpp (the raw file-input CLI form
# traced 0 edges under Mayhem; same code path, converted per the harness policy).
# shellcheck disable=SC2086
$CXX $CXXSTD $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
    mayhem/fuzz_build_halide_h.cpp -o /mayhem/fuzz_build_halide_h
# shellcheck disable=SC2086
$CXX $CXXSTD $SANITIZER_FLAGS $DEBUG_FLAGS \
    mayhem/fuzz_build_halide_h.cpp /tmp/standalone_main.o -o /mayhem/fuzz_build_halide_h-standalone

echo ">> [4/4] building functional test oracle (normal flags, no sanitizers)"
# Independent, clean build so test.sh only RUNS it. Includes the SAME real Util/Error/Debug
# sources, so a sabotage patch to strip_namespaces/split_string fails the oracle.
# shellcheck disable=SC2086
$CXX $CXXSTD -O2 $COVERAGE_FLAGS $DEFS $INC \
    mayhem/halide_util_selftest.cpp $UTIL_SRCS -o /mayhem/halide_util_selftest
# A normal-flags build of build_halide_h for the oracle's golden-output check.
# shellcheck disable=SC2086
$CXX $CXXSTD -O2 $COVERAGE_FLAGS tools/build_halide_h.cpp -o /mayhem/build_halide_h_oracle

echo ">> build.sh complete"
ls -l /mayhem/fuzz_strip_namespaces /mayhem/fuzz_strip_namespaces-standalone \
      /mayhem/fuzz_build_halide_h /mayhem/fuzz_build_halide_h-standalone \
      /mayhem/halide_util_selftest /mayhem/build_halide_h_oracle
