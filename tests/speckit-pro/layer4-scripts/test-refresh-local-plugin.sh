#!/usr/bin/env bash
# test-refresh-local-plugin.sh -- Unit tests for the local plugin refresh helper
set -euo pipefail

source "$(dirname "$0")/../lib/assertions.sh"

PLUGIN_ROOT="$(cd "$(dirname "$0")/../../../speckit-pro" && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/refresh-local-plugin.sh"

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

section "Script shape"

set_test "refresh helper exists"
assert_file_exists "$SCRIPT"

set_test "refresh helper is executable"
assert_file_executable "$SCRIPT"

set_test "help mentions Codex refresh"
result=0
output=$(bash "$SCRIPT" --help 2>&1) || result=$?
assert_eq "0" "$result" "exit code"
assert_contains "$output" "--codex" "help should document --codex"

section "Dry-run default"

set_test "dry-run default rebuilds, validates, and prints Claude dev command"
result=0
output=$(bash "$SCRIPT" --dry-run 2>&1) || result=$?
assert_eq "0" "$result" "exit code"
assert_contains "$output" "build-plugin-payloads.sh" "dry-run should include payload build"
assert_contains "$output" "claude plugin validate" "dry-run should include Claude validation"
assert_contains "$output" "claude --plugin-dir" "dry-run should print local dev command"

set_test "dry-run default refreshes both installed plugin caches"
assert_contains "$output" "plugin uninstall" "default should uninstall Claude plugin"
assert_contains "$output" "codex plugin remove" "default should remove Codex plugin"

set_test "dry-run opt-outs skip installed plugin cache refresh"
result=0
output=$(bash "$SCRIPT" --dry-run --no-codex --no-claude-install 2>&1) || result=$?
assert_eq "0" "$result" "exit code"
assert_not_contains "$output" "plugin uninstall" "--no-claude-install should skip Claude uninstall"
assert_not_contains "$output" "codex plugin remove" "--no-codex should skip Codex remove"

set_test "dry-run does not require generated payloads to exist"
result=0
output=$(SPECKIT_PLUGIN_NAME="plugin-without-payloads" bash "$SCRIPT" --dry-run 2>&1) || result=$?
assert_eq "0" "$result" "exit code"
assert_not_contains "$output" "payload not found" "dry-run should not abort on missing payloads"

set_test "dry-run all prints refresh commands without requiring real CLI state"
FAIL_BIN="$TMP_ROOT/fail-bin"
mkdir -p "$FAIL_BIN"
printf '#!/usr/bin/env bash\nexit 99\n' > "$FAIL_BIN/claude"
printf '#!/usr/bin/env bash\nexit 99\n' > "$FAIL_BIN/codex"
chmod +x "$FAIL_BIN/claude" "$FAIL_BIN/codex"
result=0
output=$(PATH="$FAIL_BIN:$PATH" bash "$SCRIPT" --dry-run --all 2>&1) || result=$?
assert_eq "0" "$result" "exit code"
assert_contains "$output" "claude plugin marketplace list # verify" "should print Claude marketplace verification"
assert_contains "$output" "codex plugin marketplace list # verify" "should print Codex marketplace verification"
assert_contains "$output" "claude plugin install" "should print Claude install command"
assert_contains "$output" "codex plugin add" "should print Codex add command"

section "Stubbed CLI execution"

STUB_BIN="$TMP_ROOT/bin"
CALL_LOG="$TMP_ROOT/calls.log"
mkdir -p "$STUB_BIN"
: > "$CALL_LOG"

cat > "$STUB_BIN/claude" <<EOF
#!/usr/bin/env bash
printf 'claude %s\n' "\$*" >> "$CALL_LOG"
if [ "\$1 \$2 \$3" = "plugin marketplace list" ]; then
  cat <<'LIST'
Configured marketplaces:

  ❯ racecraft-plugins-public
    Source: Directory ($REPO_ROOT)
LIST
fi
exit 0
EOF
chmod +x "$STUB_BIN/claude"

cat > "$STUB_BIN/codex" <<EOF
#!/usr/bin/env bash
printf 'codex %s\n' "\$*" >> "$CALL_LOG"
if [ "\$1 \$2 \$3" = "plugin marketplace list" ]; then
  cat <<'LIST'
MARKETPLACE               ROOT
racecraft-plugins-public  $REPO_ROOT
LIST
fi
exit 0
EOF
chmod +x "$STUB_BIN/codex"

set_test "Codex refresh removes and adds installed plugin"
: > "$CALL_LOG"
result=0
output=$(PATH="$STUB_BIN:$PATH" bash "$SCRIPT" --no-build --no-validate --codex 2>&1) || result=$?
assert_eq "0" "$result" "exit code"
calls=$(cat "$CALL_LOG")
assert_contains "$calls" "codex plugin marketplace list" "should inspect Codex marketplace"
assert_contains "$calls" "codex plugin remove speckit-pro@racecraft-plugins-public" "should remove stale Codex plugin"
assert_contains "$calls" "codex plugin add speckit-pro@racecraft-plugins-public" "should reinstall Codex plugin"
assert_contains "$output" "Start a new Codex thread" "should report restart guidance"

set_test "Claude install refresh honors requested scope"
: > "$CALL_LOG"
result=0
output=$(PATH="$STUB_BIN:$PATH" bash "$SCRIPT" --no-build --no-validate --claude-install --scope local 2>&1) || result=$?
assert_eq "0" "$result" "exit code"
calls=$(cat "$CALL_LOG")
assert_contains "$calls" "claude plugin marketplace list" "should inspect Claude marketplace"
assert_contains "$calls" "claude plugin uninstall speckit-pro@racecraft-plugins-public --scope local -y" "should remove stale Claude plugin"
assert_contains "$calls" "claude plugin install speckit-pro@racecraft-plugins-public --scope local" "should install at requested scope"
assert_contains "$output" "/reload-plugins" "should report Claude reload guidance"

set_test "Claude launch uses generated Claude payload"
: > "$CALL_LOG"
result=0
output=$(PATH="$STUB_BIN:$PATH" bash "$SCRIPT" --no-build --no-validate --launch-claude 2>&1) || result=$?
assert_eq "0" "$result" "exit code"
calls=$(cat "$CALL_LOG")
assert_contains "$calls" "claude --plugin-dir $REPO_ROOT/dist/claude/speckit-pro" "should launch with dist Claude payload"

section "Argument validation"

set_test "invalid scope exits with usage error"
result=0
output=$(bash "$SCRIPT" --scope managed 2>&1) || result=$?
assert_eq "2" "$result" "exit code"
assert_contains "$output" "--scope must be one of" "should explain valid scopes"

set_test "unknown option exits with usage error"
result=0
output=$(bash "$SCRIPT" --wat 2>&1) || result=$?
assert_eq "2" "$result" "exit code"
assert_contains "$output" "unknown option" "should explain unknown option"

test_summary
