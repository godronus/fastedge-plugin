#!/usr/bin/env bash
# test-fetch-repo.sh — tests for fetch-repo.sh (covers T004a and T005a)
#
# T004a: arg validation, path-anchoring logic, CHANGED true/false detection
# T005a: pipe-delimited baseline tag message parse (read_baseline_commit)
#
# Usage: bash scripts/sync/tests/test-fetch-repo.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FETCH_REPO="$SCRIPT_DIR/../fetch-repo.sh"
MOCKS_DIR="$SCRIPT_DIR/mocks"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [[ -n "${2:-}" ]] && echo "       $2"; FAIL=$((FAIL + 1)); }

assert_exit() {
  local label="$1" expect_exit="$2"
  shift 2
  local output actual_exit
  output=$("$@" 2>&1) && actual_exit=0 || actual_exit=$?
  if [[ "$actual_exit" -ne "$expect_exit" ]]; then
    fail "$label" "expected exit $expect_exit, got $actual_exit. Output: $output"
    return 1
  fi
  echo "$output"
  return 0
}

# ── Setup: temporary work dir ─────────────────────────────────────────────────

TMPWORK="$(mktemp -d)"
trap 'rm -rf "$TMPWORK"' EXIT

# ── Setup: local bare git repo fixture (used by path-anchoring + CHANGED tests) ─

BARE_REPO="$TMPWORK/bare-remote.git"

# Build a local bare repo with files at multiple depths to verify path anchoring.
# Use the real git binary directly (before PATH is modified for mocks).
REAL_GIT="$(which git)"
setup_bare_repo() {
  local work="$TMPWORK/work-init"
  mkdir -p "$work"
  "$REAL_GIT" -C "$work" init -q
  "$REAL_GIT" -C "$work" config user.email "test@test.com"
  "$REAL_GIT" -C "$work" config user.name "Test"

  # Files at declared sparse paths
  mkdir -p "$work/src" "$work/docs"
  echo "top-level src" > "$work/src/foo.txt"
  echo "top-level docs readme" > "$work/docs/README.md"

  # File at a nested path that should NOT be checked out when src/ is root-anchored
  mkdir -p "$work/nested/src"
  echo "nested src — should be excluded" > "$work/nested/src/bar.txt"

  "$REAL_GIT" -C "$work" add .
  "$REAL_GIT" -C "$work" commit -qm "initial"
  "$REAL_GIT" -C "$work" tag v1.0.0
  "$REAL_GIT" -C "$work" clone --bare -q "$work" "$BARE_REPO"
  # Push the tag into the bare repo
  "$REAL_GIT" -C "$work" push --quiet "$BARE_REPO" --tags
}

setup_bare_repo

# Get the HEAD SHA from the bare repo (used for CHANGED tests)
HEAD_SHA=$("$REAL_GIT" -C "$BARE_REPO" rev-parse HEAD)

# ── Prepend mocks to PATH ─────────────────────────────────────────────────────
export PATH="$MOCKS_DIR:$PATH"

# ── Source fetch-repo.sh as a library (defines functions, runs nothing) ────────
# shellcheck source=../fetch-repo.sh
source "$FETCH_REPO"
# Restore non-exit-on-error mode: fetch-repo.sh sets -euo pipefail which propagates
# into this shell when sourced; the test script must not exit on failing commands.
set +e

# =============================================================================
# T004a — arg validation + path anchoring + CHANGED detection
# =============================================================================

echo ""
echo "T004a — fetch-repo.sh: argument validation, path anchoring, CHANGED detection"
echo "=============================================================================="

# (1) Missing args → exit 1 listing all missing flags
output=$(bash "$FETCH_REPO" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && echo "$output" | grep -q "Missing"; then
  pass "(1) missing args → exit 1 with 'Missing'"
else
  fail "(1) missing args → exit 1 with 'Missing'" "exit=$rc, output=$output"
fi

# (2) Unknown arg → exit 1
output=$(bash "$FETCH_REPO" --unknown-flag value 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && echo "$output" | grep -q "Unknown"; then
  pass "(2) unknown arg → exit 1 with 'Unknown'"
else
  fail "(2) unknown arg → exit 1 with 'Unknown'" "exit=$rc, output=$output"
fi

# (3) Path-anchoring: given sparse-paths "src/ docs/README.md",
#     only root-anchored paths are checked out (nested/src/bar.txt must be absent)
CHECKOUT_DIR_3="$TMPWORK/checkout-3"
export MOCK_GIT_REMOTE="$BARE_REPO"
export MOCK_GH_LATEST_TAG="v1.0.0"
export MOCK_GIT_LS_REMOTE=""   # no baseline → CHANGED=true

output3=$(bash "$FETCH_REPO" \
  --repo-url "https://github.com/example/test-repo" \
  --sparse-paths "src/ docs/README.md" \
  --repo-id "test-repo" \
  --ref "v1.0.0" \
  --checkout-dir "$CHECKOUT_DIR_3" 2>&1) && rc3=0 || rc3=$?

if [[ "$rc3" -ne 0 ]]; then
  fail "(3) path-anchoring: script exited $rc3. Output: $output3"
else
  # src/foo.txt and docs/README.md should be present
  if [[ -f "$CHECKOUT_DIR_3/src/foo.txt" ]] && [[ -f "$CHECKOUT_DIR_3/docs/README.md" ]]; then
    # nested/src/bar.txt must NOT be present (only anchored /src/ should match)
    if [[ ! -f "$CHECKOUT_DIR_3/nested/src/bar.txt" ]]; then
      pass "(3) path-anchoring: declared paths checked out, nested/src excluded"
    else
      fail "(3) path-anchoring: nested/src/bar.txt was incorrectly checked out (paths not root-anchored)"
    fi
  else
    fail "(3) path-anchoring: expected files missing in checkout" \
      "src/foo.txt exists: $([[ -f "$CHECKOUT_DIR_3/src/foo.txt" ]] && echo yes || echo no), docs/README.md exists: $([[ -f "$CHECKOUT_DIR_3/docs/README.md" ]] && echo yes || echo no)"
  fi
fi

unset MOCK_GIT_REMOTE MOCK_GH_LATEST_TAG MOCK_GIT_LS_REMOTE

# (4) CHANGED=true when no baseline exists (ls-remote returns empty)
CHECKOUT_DIR_4="$TMPWORK/checkout-4"
export MOCK_GIT_REMOTE="$BARE_REPO"
export MOCK_GH_LATEST_TAG="v1.0.0"
export MOCK_GIT_LS_REMOTE=""  # no tag on remote → first run

output4=$(bash "$FETCH_REPO" \
  --repo-url "https://github.com/example/test-repo" \
  --sparse-paths "src/" \
  --repo-id "test-repo" \
  --ref "v1.0.0" \
  --checkout-dir "$CHECKOUT_DIR_4" 2>&1) && rc4=0 || rc4=$?

# stdout contains KEY=VALUE lines, stderr contains INFO lines
stdout4=$(bash "$FETCH_REPO" \
  --repo-url "https://github.com/example/test-repo" \
  --sparse-paths "src/" \
  --repo-id "test-repo" \
  --ref "v1.0.0" \
  --checkout-dir "$TMPWORK/checkout-4b" 2>/dev/null) && rc4b=0 || rc4b=$?

if [[ "$rc4b" -eq 0 ]] && echo "$stdout4" | grep -q "CHANGED=true"; then
  pass "(4) CHANGED=true when no baseline (first run)"
else
  fail "(4) CHANGED=true when no baseline" "exit=$rc4b, stdout=$stdout4"
fi

unset MOCK_GIT_REMOTE MOCK_GH_LATEST_TAG MOCK_GIT_LS_REMOTE

# (5) CHANGED=false when HEAD SHA matches baseline
CHECKOUT_DIR_5="$TMPWORK/checkout-5"
export MOCK_GIT_REMOTE="$BARE_REPO"
export MOCK_GH_LATEST_TAG="v1.0.0"
# ls-remote returns a line with a SHA (the remote tag object SHA, not commit SHA — but
# read_baseline_commit extracts the commit SHA from cat-file message, not from ls-remote)
export MOCK_GIT_LS_REMOTE="abc000def111 refs/tags/ref-update/test-repo"
# cat-file returns a message whose field 2 is the current HEAD SHA
export MOCK_GIT_CAT_FILE_OUTPUT="v1.0.0 | ${HEAD_SHA} | 2026-03-01T00:00:00Z"

stdout5=$(bash "$FETCH_REPO" \
  --repo-url "https://github.com/example/test-repo" \
  --sparse-paths "src/" \
  --repo-id "test-repo" \
  --ref "v1.0.0" \
  --checkout-dir "$CHECKOUT_DIR_5" 2>/dev/null) && rc5=0 || rc5=$?

if [[ "$rc5" -eq 0 ]] && echo "$stdout5" | grep -q "CHANGED=false"; then
  pass "(5) CHANGED=false when HEAD SHA matches baseline"
else
  fail "(5) CHANGED=false when HEAD SHA matches baseline" "exit=$rc5, stdout=$stdout5"
fi

unset MOCK_GIT_REMOTE MOCK_GH_LATEST_TAG MOCK_GIT_LS_REMOTE MOCK_GIT_CAT_FILE_OUTPUT

# (6) CHANGED=true when HEAD SHA differs from baseline
CHECKOUT_DIR_6="$TMPWORK/checkout-6"
export MOCK_GIT_REMOTE="$BARE_REPO"
export MOCK_GH_LATEST_TAG="v1.0.0"
export MOCK_GIT_LS_REMOTE="abc000def111 refs/tags/ref-update/test-repo"
export MOCK_GIT_CAT_FILE_OUTPUT="v0.9.0 | oldsha000000000000000000000000000000000000 | 2026-02-01T00:00:00Z"

stdout6=$(bash "$FETCH_REPO" \
  --repo-url "https://github.com/example/test-repo" \
  --sparse-paths "src/" \
  --repo-id "test-repo" \
  --ref "v1.0.0" \
  --checkout-dir "$CHECKOUT_DIR_6" 2>/dev/null) && rc6=0 || rc6=$?

if [[ "$rc6" -eq 0 ]] && echo "$stdout6" | grep -q "CHANGED=true"; then
  pass "(6) CHANGED=true when HEAD SHA differs from baseline"
else
  fail "(6) CHANGED=true when HEAD SHA differs from baseline" "exit=$rc6, stdout=$stdout6"
fi

unset MOCK_GIT_REMOTE MOCK_GH_LATEST_TAG MOCK_GIT_LS_REMOTE MOCK_GIT_CAT_FILE_OUTPUT

# =============================================================================
# T005a — read_baseline_commit: pipe-delimited message parse
# (uses the sourced read_baseline_commit function + mocks/git via PATH)
# =============================================================================

echo ""
echo "T005a — read_baseline_commit: baseline tag message parse"
echo "========================================================="

# (1) Valid message "v2.0.0 | abc123 | 2026-03-09T00:00:00Z" → extracted SHA is "abc123"
export MOCK_GIT_LS_REMOTE="tagsha000 refs/tags/ref-update/repo-a"
export MOCK_GIT_CAT_FILE_OUTPUT="v2.0.0 | abc123 | 2026-03-09T00:00:00Z"

result1=$(read_baseline_commit "repo-a")
if [[ "$result1" == "abc123" ]]; then
  pass "(1) valid message → extracted SHA is 'abc123'"
else
  fail "(1) valid message → extracted SHA is 'abc123'" "got: '$result1'"
fi

unset MOCK_GIT_LS_REMOTE MOCK_GIT_CAT_FILE_OUTPUT

# (2) Message with extra whitespace around pipes → SHA still extracted correctly
export MOCK_GIT_LS_REMOTE="tagsha000 refs/tags/ref-update/repo-b"
export MOCK_GIT_CAT_FILE_OUTPUT="v2.0.0  |  abc123  |  2026-03-09T00:00:00Z"

result2=$(read_baseline_commit "repo-b")
if [[ "$result2" == "abc123" ]]; then
  pass "(2) extra whitespace around pipes → SHA still extracted correctly"
else
  fail "(2) extra whitespace around pipes → SHA still extracted correctly" "got: '$result2'"
fi

unset MOCK_GIT_LS_REMOTE MOCK_GIT_CAT_FILE_OUTPUT

# (3) Empty tag message → function returns empty string (not error)
export MOCK_GIT_LS_REMOTE="tagsha000 refs/tags/ref-update/repo-c"
export MOCK_GIT_CAT_FILE_OUTPUT=""

result3=$(read_baseline_commit "repo-c" 2>/dev/null)
if [[ -z "$result3" ]]; then
  pass "(3) empty tag message → returns empty string"
else
  fail "(3) empty tag message → returns empty string" "got: '$result3'"
fi

unset MOCK_GIT_LS_REMOTE MOCK_GIT_CAT_FILE_OUTPUT

# (4) No remote tag (ls-remote returns empty) → function returns empty string
export MOCK_GIT_LS_REMOTE=""

result4=$(read_baseline_commit "repo-d")
if [[ -z "$result4" ]]; then
  pass "(4) no remote tag → returns empty string"
else
  fail "(4) no remote tag → returns empty string" "got: '$result4'"
fi

unset MOCK_GIT_LS_REMOTE

# =============================================================================
# T013 — assert_sparse_paths_only(): post-checkout path assertion
#
# assert_sparse_paths_only() calls exit 1 on failure, so each case runs in a
# subshell ( ) to isolate the exit from the test script.
# MOCK_GIT_LS_FILES_OUTPUT controls what the mocked git ls-files returns.
# Actual files are created in per-test temp dirs so [[ -f "$file" ]] works.
# =============================================================================

echo ""
echo "T013 — assert_sparse_paths_only(): post-checkout path assertion"
echo "================================================================"

# (1) All files match a directory pattern → exit 0
ASSERT_DIR_1="$TMPWORK/assert-1"
mkdir -p "$ASSERT_DIR_1/src"
echo "content" > "$ASSERT_DIR_1/src/foo.txt"
echo "content" > "$ASSERT_DIR_1/src/bar.txt"
export MOCK_GIT_LS_FILES_OUTPUT="src/foo.txt
src/bar.txt"

output_a1=$( ( cd "$ASSERT_DIR_1" && assert_sparse_paths_only "test-repo" "/src/" ) 2>&1 ) \
  && rc_a1=0 || rc_a1=$?
if [[ "$rc_a1" -eq 0 ]]; then
  pass "(1) all files under /src/ → exit 0"
else
  fail "(1) all files under /src/ → exit 0" "exit=${rc_a1}, output=${output_a1}"
fi
unset MOCK_GIT_LS_FILES_OUTPUT

# (2) Exact file pattern → exit 0
ASSERT_DIR_2="$TMPWORK/assert-2"
mkdir -p "$ASSERT_DIR_2"
echo "content" > "$ASSERT_DIR_2/README.md"
export MOCK_GIT_LS_FILES_OUTPUT="README.md"

output_a2=$( ( cd "$ASSERT_DIR_2" && assert_sparse_paths_only "test-repo" "/README.md" ) 2>&1 ) \
  && rc_a2=0 || rc_a2=$?
if [[ "$rc_a2" -eq 0 ]]; then
  pass "(2) exact file pattern /README.md → exit 0"
else
  fail "(2) exact file pattern /README.md → exit 0" "exit=${rc_a2}, output=${output_a2}"
fi
unset MOCK_GIT_LS_FILES_OUTPUT

# (3) File outside declared paths → exit 1, names the offending file
ASSERT_DIR_3="$TMPWORK/assert-3"
mkdir -p "$ASSERT_DIR_3/src" "$ASSERT_DIR_3/docs"
echo "content" > "$ASSERT_DIR_3/src/foo.txt"
echo "content" > "$ASSERT_DIR_3/docs/guide.md"
export MOCK_GIT_LS_FILES_OUTPUT="src/foo.txt
docs/guide.md"

output_a3=$( ( cd "$ASSERT_DIR_3" && assert_sparse_paths_only "test-repo" "/src/" ) 2>&1 ) \
  && rc_a3=0 || rc_a3=$?
if [[ "$rc_a3" -eq 1 ]] && echo "$output_a3" | grep -qF "docs/guide.md"; then
  pass "(3) file outside /src/ → exit 1, offending path named"
else
  fail "(3) file outside /src/ → exit 1, offending path named" \
    "exit=${rc_a3}, output=${output_a3}"
fi
unset MOCK_GIT_LS_FILES_OUTPUT

# (4) Skip-worktree entry (in ls-files but not on disk) → not flagged
ASSERT_DIR_4="$TMPWORK/assert-4"
mkdir -p "$ASSERT_DIR_4/src"
echo "content" > "$ASSERT_DIR_4/src/foo.txt"
# docs/guide.md is returned by ls-files (index entry) but NOT created on disk
export MOCK_GIT_LS_FILES_OUTPUT="src/foo.txt
docs/guide.md"

output_a4=$( ( cd "$ASSERT_DIR_4" && assert_sparse_paths_only "test-repo" "/src/" ) 2>&1 ) \
  && rc_a4=0 || rc_a4=$?
if [[ "$rc_a4" -eq 0 ]]; then
  pass "(4) skip-worktree entry absent from disk → not flagged, exit 0"
else
  fail "(4) skip-worktree entry absent from disk → not flagged, exit 0" \
    "exit=${rc_a4}, output=${output_a4}"
fi
unset MOCK_GIT_LS_FILES_OUTPUT

# (5) Nested path does not match root-anchored directory pattern
ASSERT_DIR_5="$TMPWORK/assert-5"
mkdir -p "$ASSERT_DIR_5/src" "$ASSERT_DIR_5/nested/src"
echo "content" > "$ASSERT_DIR_5/src/foo.txt"
echo "content" > "$ASSERT_DIR_5/nested/src/bar.txt"
export MOCK_GIT_LS_FILES_OUTPUT="src/foo.txt
nested/src/bar.txt"

output_a5=$( ( cd "$ASSERT_DIR_5" && assert_sparse_paths_only "test-repo" "/src/" ) 2>&1 ) \
  && rc_a5=0 || rc_a5=$?
if [[ "$rc_a5" -eq 1 ]] && echo "$output_a5" | grep -qF "nested/src/bar.txt"; then
  pass "(5) nested/src/bar.txt does not match root-anchored /src/ → exit 1"
else
  fail "(5) nested/src/bar.txt does not match root-anchored /src/ → exit 1" \
    "exit=${rc_a5}, output=${output_a5}"
fi
unset MOCK_GIT_LS_FILES_OUTPUT

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
