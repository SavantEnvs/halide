#!/usr/bin/env bash
#
# mayhem/test.sh — RUN the behavioral oracle built by mayhem/build.sh.
#
# AUTHORED ORACLE (clearly labeled): upstream Halide's own test suite (test/correctness,
# test/internal.cpp, ctest — hundreds of tests) requires a full LLVM-21 libHalide build,
# which this focused commit image deliberately does not perform (see mayhem/build.sh).
# Instead this oracle asserts known-answer/golden behavior of the EXACT code the fuzz
# targets exercise: the Halide::Internal string utilities (src/Util.cpp) and the
# build_halide_h header tool (tools/build_halide_h.cpp). A patch that no-ops these
# programs (exit 0) produces no output and FAILS the golden assertions below.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

PASSED=0
FAILED=0

# --- Part 1: Halide::Internal string-utility known-answer tests (29 checks) ---
EXPECTED_SELFTEST=29
OUT="$(/mayhem/halide_util_selftest 2>&1 || true)"
echo "$OUT"
P1=$(printf '%s\n' "$OUT" | grep -c '^PASS ' || true)
F1=$(printf '%s\n' "$OUT" | grep -c '^FAIL ' || true)
if [ $(( P1 + F1 )) -ne "$EXPECTED_SELFTEST" ]; then
  # Neutered / crashed / truncated run: every unaccounted check counts as failed.
  F1=$(( EXPECTED_SELFTEST - P1 ))
  echo "ERROR: selftest reported $(( P1 + F1 )) of $EXPECTED_SELFTEST checks"
fi
PASSED=$(( PASSED + P1 ))
FAILED=$(( FAILED + F1 ))

# --- Part 2: build_halide_h golden-output checks (5 checks) ---
WORK=$(mktemp -d)
printf 'HALIDE-LICENSE-MARKER-7391\n' > "$WORK/lic.txt"
cat > "$WORK/hdr.h" <<'EOF'
#include "sub.h"
int halide_top_marker_1234;
EOF
cat > "$WORK/sub.h" <<'EOF'
int halide_sub_marker_5678;
EOF
GOLD="$(/mayhem/build_halide_h_oracle "$WORK/lic.txt" "$WORK/hdr.h" "$WORK/sub.h" 2>/dev/null || true)"

bh_check() { # name, condition already evaluated
  if [ "$2" = 0 ]; then echo "PASS bhh_$1"; PASSED=$((PASSED+1));
  else echo "FAIL bhh_$1"; FAILED=$((FAILED+1)); fi
}
printf '%s' "$GOLD" | grep -q 'HALIDE-LICENSE-MARKER-7391'; bh_check license $?
printf '%s' "$GOLD" | grep -q '#ifndef HALIDE_H';           bh_check guard $?
printf '%s' "$GOLD" | grep -q 'halide_top_marker_1234';     bh_check top $?
test "$(printf '%s' "$GOLD" | grep -c 'halide_sub_marker_5678')" = 1; bh_check sub_inlined_once $?
! printf '%s' "$GOLD" | grep -q '#include "';               bh_check includes_resolved $?
rm -rf "$WORK"

emit_ctrf "halide-behavioral-oracle" "$PASSED" "$FAILED"
