#!/usr/bin/env bash
# test-validate-sources.sh — test suite for validate-sources.sh
# Usage: bash scripts/sync/tests/test-validate-sources.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="$SCRIPT_DIR/../validate-sources.sh"
FIXTURES="$SCRIPT_DIR/fixtures/validate-sources"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Prepend mocks dir so our gh mock takes precedence over the real gh
export PATH="$SCRIPT_DIR/mocks:$PATH"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; echo "       $2"; FAIL=$((FAIL + 1)); }

run() {
  local label="$1" fixture="$2" expect_exit="$3" expect_pattern="$4"
  local output
  output=$(bash "$VALIDATE" "$fixture" 2>&1)
  local actual_exit=$?
  if [[ "$actual_exit" -ne "$expect_exit" ]]; then
    fail "$label" "expected exit $expect_exit, got $actual_exit. Output: $output"
    return
  fi
  if [[ -n "$expect_pattern" ]] && ! echo "$output" | grep -q "$expect_pattern"; then
    fail "$label" "output did not match '$expect_pattern'. Got: $output"
    return
  fi
  pass "$label"
}

echo "validate-sources.sh tests"
echo "========================="

# Happy path
run "valid sources.json passes all rules" \
  "$FIXTURES/valid.json" 0 "validation passed"

# Rule 1
run "Rule 1: duplicate repo IDs fail" \
  "$FIXTURES/rule1-duplicate-ids.json" 1 "Rule 1"

# Rule 2
run "Rule 2: unreachable github_url fails" \
  "$FIXTURES/rule2-bad-url.json" 1 "Rule 2"

# Rule 3
run "Rule 3: reference_file outside plugins/ fails" \
  "$FIXTURES/rule3-bad-ref-path.json" 1 "Rule 3"

# Rule 4
run "Rule 4: generator_agent equals reviewer_agent fails" \
  "$FIXTURES/rule4-same-agent.json" 1 "Rule 4"

# Rule 5
run "Rule 5: shared reference_file missing section in one entry fails" \
  "$FIXTURES/rule5-missing-section.json" 1 "Rule 5"

# Rule 6
run "Rule 6: banned sparse_path (node_modules/) fails" \
  "$FIXTURES/rule6-banned-sparse-path.json" 1 "Rule 6"

# Rule 7
run "Rule 7: intent_file pointing to missing file fails" \
  "$FIXTURES/rule7-missing-intent-file.json" 1 "Rule 7"

# Rule 7 valid: intent_file must resolve relative to repo root
label="Rule 7: intent_file pointing to existing file passes"
output=$(cd "$REPO_ROOT" && bash "$VALIDATE" "$FIXTURES/rule7-valid-intent-file.json" 2>&1)
actual_exit=$?
if [[ "$actual_exit" -eq 0 ]] && echo "$output" | grep -q "validation passed"; then
  pass "$label"
else
  fail "$label" "exit=$actual_exit. Output: $output"
fi

# Missing argument
run "no argument: exits with usage error" \
  "" 1 "Usage" 2>/dev/null || {
    output=$(bash "$VALIDATE" 2>&1); actual=$?
    if [[ "$actual" -eq 1 ]] && echo "$output" | grep -q "Usage"; then
      pass "no argument: exits with usage error"
      FAIL=$((FAIL - 1))
    fi
  }

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
