#!/usr/bin/env bash
# test-section-splice.sh — comprehensive tests for splice_section() (T008a)
#
# Coverage:
#   (1) section found mid-file → only that section replaced, surrounding sections byte-identical
#   (2) section is last in file (EOF boundary) → replaced correctly, no trailing garbage
#   (3) section not found → exit 1 with message naming the missing heading
#   (4) multiple ## sections in file → only target section changed
#   (5) frontmatter has two repos → only contributing repo's entry updated, other preserved
#   (6) generator output is empty → exit 1
#
# Usage: bash scripts/sync/tests/test-section-splice.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVOKE_AGENT="$SCRIPT_DIR/../invoke-agent.sh"
FIXTURES="$SCRIPT_DIR/fixtures/section-splice"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [[ -n "${2:-}" ]] && echo "       $2"; FAIL=$((FAIL + 1)); }

# Source invoke-agent.sh to get splice_section() and helpers
# shellcheck source=../invoke-agent.sh
source "$INVOKE_AGENT"
set +e  # invoke-agent.sh sets -euo pipefail; restore non-exit mode

# ── Temp dir for working copies ───────────────────────────────────────────────
TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

copy_fixture() {
  local name="$1"
  local dest="$TMPDIR_WORK/${name}"
  cp "$FIXTURES/${name}" "$dest"
  echo "$dest"
}

echo ""
echo "T008a — splice_section(): comprehensive section-splice tests"
echo "============================================================="

# ── (1) section found mid-file ────────────────────────────────────────────────
f1=$(copy_fixture "mid-file.md")

# Capture surrounding sections before splice
intro_before=$(awk '/^## Introduction/,/^## [^I]/' "$f1" | head -n -1)
trailing_before=$(awk '/^## Trailing Section/,0' "$f1")

splice_section "Target Section" "$f1" \
  "New content for target section.
Second line of new content." \
  "sdk-js" "v2.0.0" "newshaxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" 2>/dev/null
rc1=$?

if [[ "$rc1" -ne 0 ]]; then
  fail "(1) section mid-file: splice_section exited $rc1"
else
  # Verify new content is present
  if ! grep -q "New content for target section." "$f1"; then
    fail "(1) section mid-file: new content not found in result"
  else
    # Verify surrounding sections are byte-identical
    intro_after=$(awk '/^## Introduction/,/^## [^I]/' "$f1" | head -n -1)
    trailing_after=$(awk '/^## Trailing Section/,0' "$f1")
    if [[ "$intro_before" == "$intro_after" ]] && [[ "$trailing_before" == "$trailing_after" ]]; then
      pass "(1) section mid-file: target replaced, surrounding sections preserved"
    else
      fail "(1) section mid-file: surrounding sections were modified" \
        "intro_before=${intro_before:0:40}... intro_after=${intro_after:0:40}..."
    fi
  fi
fi

# ── (2) section at EOF boundary ───────────────────────────────────────────────
f2=$(copy_fixture "eof.md")

before_before=$(awk '/^## Before Section/,/^## [^B]/' "$f2" | head -n -1)

splice_section "Target Section" "$f2" \
  "New EOF content. Concise replacement." \
  "sdk-js" "v2.0.0" "newshaxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" 2>/dev/null
rc2=$?

if [[ "$rc2" -ne 0 ]]; then
  fail "(2) section at EOF: splice_section exited $rc2"
else
  if ! grep -q "New EOF content." "$f2"; then
    fail "(2) section at EOF: new content not found"
  else
    # Verify old content is gone
    if grep -q "Old EOF content" "$f2"; then
      fail "(2) section at EOF: old content still present"
    else
      # Verify Before Section preserved
      before_after=$(awk '/^## Before Section/,/^## [^B]/' "$f2" | head -n -1)
      # No trailing ## heading should appear after the new content
      trailing_junk=$(awk '/^New EOF content/,0' "$f2" | grep "^## " | wc -l | tr -d ' ')
      if [[ "$before_before" == "$before_after" ]] && [[ "$trailing_junk" -eq 0 ]]; then
        pass "(2) section at EOF: replaced correctly, no trailing garbage"
      else
        fail "(2) section at EOF: before section changed or trailing garbage found" \
          "trailing_## count: $trailing_junk"
      fi
    fi
  fi
fi

# ── (3) section not found → exit 1 with message naming the missing heading ────
f3=$(copy_fixture "mid-file.md")

error_output=$(splice_section "Nonexistent Section" "$f3" "content" \
  "sdk-js" "v1.0.0" "sha" 2>&1) && rc3=0 || rc3=$?

if [[ "$rc3" -eq 1 ]] && echo "$error_output" | grep -q "Nonexistent Section"; then
  pass "(3) section not found → exit 1 naming missing heading"
else
  fail "(3) section not found → exit 1 naming missing heading" \
    "exit=$rc3, output=$error_output"
fi

# ── (4) multiple ## sections → only target section changed ────────────────────
f4=$(copy_fixture "mid-file.md")

# Capture all sections before splice
intro_4_before=$(awk '/^## Introduction/,/^## Target/' "$f4" | grep -v "^## Target")
trailing_4_before=$(awk '/^## Trailing Section/,0' "$f4")

splice_section "Target Section" "$f4" "Replacement for test 4." \
  "sdk-js" "v2.0.0" "sha4xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" 2>/dev/null
rc4=$?

if [[ "$rc4" -ne 0 ]]; then
  fail "(4) multiple sections: splice_section exited $rc4"
else
  intro_4_after=$(awk '/^## Introduction/,/^## Target/' "$f4" | grep -v "^## Target")
  trailing_4_after=$(awk '/^## Trailing Section/,0' "$f4")
  if grep -q "Replacement for test 4." "$f4" && \
     [[ "$intro_4_before" == "$intro_4_after" ]] && \
     [[ "$trailing_4_before" == "$trailing_4_after" ]]; then
    pass "(4) multiple sections → only target section changed"
  else
    fail "(4) multiple sections → only target section changed" \
      "intro match: $([[ "$intro_4_before" == "$intro_4_after" ]] && echo yes || echo no), trailing match: $([[ "$trailing_4_before" == "$trailing_4_after" ]] && echo yes || echo no)"
  fi
fi

# ── (5) frontmatter: two repos → only contributing repo's entry updated ────────
f5=$(copy_fixture "two-repos.md")

# Capture the rust entry verbatim before splice
rust_entry_before=$(awk '/- id: sdk-rust/,/^    - id: |^-->/' "$f5" | grep -v "^    - id: [^s]" | grep -v "^-->")

splice_section "JavaScript SDK" "$f5" "Updated JavaScript SDK content." \
  "sdk-js" "v2.0.0" "newjssha000000000000000000000000000000000000000" 2>/dev/null
rc5=$?

if [[ "$rc5" -ne 0 ]]; then
  fail "(5) two-repos frontmatter: splice_section exited $rc5"
else
  # sdk-js ref must be updated
  js_ref_after=$(awk '/- id: sdk-js/{f=1} f && /ref:/{print; f=0}' "$f5" | sed 's/.*ref: //')
  # sdk-rust entry must be byte-identical
  rust_entry_after=$(awk '/- id: sdk-rust/,/^    - id: |^-->/' "$f5" | grep -v "^    - id: [^s]" | grep -v "^-->")
  # sdk-rust commit must still be the old value
  rust_commit_after=$(awk '/- id: sdk-rust/{f=1} f && /commit:/{print; f=0}' "$f5" | sed 's/.*commit: //')

  if [[ "$js_ref_after" == "v2.0.0" ]] && \
     [[ "$rust_commit_after" == "oldrustsha000000000000000000000000000000000000" ]]; then
    pass "(5) two-repos frontmatter: sdk-js updated, sdk-rust preserved verbatim"
  else
    fail "(5) two-repos frontmatter: unexpected values" \
      "js_ref=$js_ref_after, rust_commit=$rust_commit_after"
  fi
fi

# ── (6) generator output is empty → exit 1 ────────────────────────────────────
f6=$(copy_fixture "mid-file.md")

error_output6=$(splice_section "Target Section" "$f6" "" \
  "sdk-js" "v1.0.0" "sha" 2>&1) && rc6=0 || rc6=$?

if [[ "$rc6" -eq 1 ]]; then
  pass "(6) empty generator output → exit 1"
else
  fail "(6) empty generator output → exit 1" "exit=$rc6, output=$error_output6"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
