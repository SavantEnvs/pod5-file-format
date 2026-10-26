#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
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

# RUN the upstream Catch2 unit tests that mayhem/build.sh built (normal flags, build-tests/).
# They write/read pod5 files and assert known values (round-trips, svb16 encode/decode, migration,
# recovery, C API), so a no-op'd program fails them.
RUNNER="$SRC/build-tests/c++/test/pod5_unit_tests"
[ -x "$RUNNER" ] || { echo "missing $RUNNER — mayhem/build.sh must build it" >&2; emit_ctrf "catch2" 0 1 0; exit $?; }

# test_data/*.pod5 are git-lfs objects; when a checkout carries only the LFS pointers, skip the
# three test cases that open them instead of reporting pointer-file noise as failures.
FILTER=()
if head -c 40 "$SRC/test_data/multi_fast5_zip_v0.pod5" 2>/dev/null | grep -q 'git-lfs'; then
  echo "test_data is LFS pointers — skipping the cases that read it" >&2
  FILTER=("~Scenario: Opening older files" "~update_file() updates the file" "~Repacker smoke test")
fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
OUT="$WORK/out.txt"
"$RUNNER" "${FILTER[@]}" >"$OUT" 2>&1
tail -n 5 "$OUT"

passed=0; failed=0
if line=$(grep -E '^All tests passed \(' "$OUT" | tail -1) && [ -n "$line" ]; then
  passed=$(sed -E 's/.* in ([0-9]+) test cases?\)/\1/' <<<"$line")
elif line=$(grep -E '^test cases: ' "$OUT" | tail -1) && [ -n "$line" ]; then
  passed=$(grep -oE '[0-9]+ passed' <<<"$line" | grep -oE '[0-9]+' || echo 0)
  failed=$(grep -oE '[0-9]+ failed' <<<"$line" | head -1 | grep -oE '[0-9]+' || echo 0)
else
  echo "no Catch2 summary in the runner output" >&2
  failed=1
fi
[ "$passed" -gt 0 ] || failed=$(( failed + 1 ))
emit_ctrf "catch2" "$passed" "$failed" 0
