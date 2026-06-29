#!/usr/bin/env bash
# Tests for the speckit-pro toolchain preflight.
set -euo pipefail

source "$(dirname "$0")/../lib/assertions.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CHECKER="$REPO_ROOT/tests/speckit-pro/check-toolchain.sh"
LAST_OUTPUT=""
LAST_EXIT=0

run_checker() {
  LAST_EXIT=0
  LAST_OUTPUT="$(bash "$CHECKER" "$@" 2>&1)" || LAST_EXIT=$?
}

section "check-toolchain.sh"

set_test "toolchain checker exists"
assert_file_exists "$CHECKER"

set_test "toolchain checker is executable"
assert_file_executable "$CHECKER"

set_test "help exits 0"
run_checker --help
assert_eq "0" "$LAST_EXIT"

set_test "help lists supported modes"
assert_contains "$LAST_OUTPUT" "--mode all"

set_test "missing --mode value exits 2"
run_checker --mode
assert_eq "2" "$LAST_EXIT"

set_test "missing --mode value prints a diagnostic"
assert_contains "$LAST_OUTPUT" "Missing value for --mode"

set_test "invalid --mode value exits 2"
run_checker --mode invalid
assert_eq "2" "$LAST_EXIT"

set_test "invalid --mode value prints a diagnostic"
assert_contains "$LAST_OUTPUT" "Invalid --mode: invalid"

test_summary
