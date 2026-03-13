#!/usr/bin/env bash
# test-verdict-parse.sh — unit tests for parse_verdict() in invoke-agent.sh (T007a)
#
# Coverage:
#   (1) well-formed "VERDICT: ACCEPT\nFINDINGS: ..." → verdict=ACCEPT, findings extracted
#   (2) well-formed "VERDICT: REJECT\nFINDINGS: ..." → verdict=REJECT
#   (3) response missing VERDICT line → return 2
#   (4) response with VERDICT but no FINDINGS block → return 2
#   (5) multi-line FINDINGS block preserved verbatim
#
# Usage: bash scripts/sync/tests/test-verdict-parse.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVOKE_AGENT="$SCRIPT_DIR/../invoke-agent.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [[ -n "${2:-}" ]] && echo "       $2"; FAIL=$((FAIL + 1)); }

# Source invoke-agent.sh as a library to get parse_verdict()
# shellcheck source=../invoke-agent.sh
source "$INVOKE_AGENT"
set +e  # invoke-agent.sh sets -euo pipefail; restore non-exit mode for tests

echo ""
echo "T007a — parse_verdict(): VERDICT/FINDINGS parse logic"
echo "======================================================"

# ── (1) well-formed ACCEPT response ──────────────────────────────────────────
PARSED_VERDICT="" PARSED_FINDINGS=""
parse_verdict "VERDICT: ACCEPT
FINDINGS: The content accurately reflects the source material."
rc1=$?

if [[ "$rc1" -eq 0 ]] && [[ "$PARSED_VERDICT" == "ACCEPT" ]] && [[ -n "$PARSED_FINDINGS" ]]; then
  pass "(1) ACCEPT response → verdict=ACCEPT, findings extracted"
else
  fail "(1) ACCEPT response → verdict=ACCEPT, findings extracted" \
    "exit=$rc1, PARSED_VERDICT='${PARSED_VERDICT}', PARSED_FINDINGS='${PARSED_FINDINGS}'"
fi

# ── (2) well-formed REJECT response ──────────────────────────────────────────
PARSED_VERDICT="" PARSED_FINDINGS=""
parse_verdict "VERDICT: REJECT
FINDINGS: The traceability frontmatter is missing the commit SHA."
rc2=$?

if [[ "$rc2" -eq 0 ]] && [[ "$PARSED_VERDICT" == "REJECT" ]]; then
  pass "(2) REJECT response → verdict=REJECT"
else
  fail "(2) REJECT response → verdict=REJECT" \
    "exit=$rc2, PARSED_VERDICT='${PARSED_VERDICT}'"
fi

# ── (3) response missing VERDICT line → return 2 ─────────────────────────────
PARSED_VERDICT="" PARSED_FINDINGS=""
parse_verdict "This is just some text without a verdict line." 2>/dev/null
rc3=$?

if [[ "$rc3" -eq 2 ]]; then
  pass "(3) missing VERDICT line → return 2"
else
  fail "(3) missing VERDICT line → return 2" "exit=$rc3"
fi

# ── (4) VERDICT present but no FINDINGS block → return 2 ─────────────────────
PARSED_VERDICT="" PARSED_FINDINGS=""
parse_verdict "VERDICT: ACCEPT" 2>/dev/null
rc4=$?

if [[ "$rc4" -eq 2 ]]; then
  pass "(4) VERDICT but no FINDINGS block → return 2"
else
  fail "(4) VERDICT but no FINDINGS block → return 2" "exit=$rc4"
fi

# ── (5) multi-line FINDINGS block preserved verbatim ─────────────────────────
PARSED_VERDICT="" PARSED_FINDINGS=""
multi_response="VERDICT: ACCEPT
FINDINGS: Line one of findings.
Line two of findings.
Line three of findings."

parse_verdict "$multi_response"
rc5=$?

expected_line1="Line one of findings."
expected_line2="Line two of findings."
expected_line3="Line three of findings."

if [[ "$rc5" -eq 0 ]] && \
   echo "$PARSED_FINDINGS" | grep -qF "$expected_line1" && \
   echo "$PARSED_FINDINGS" | grep -qF "$expected_line2" && \
   echo "$PARSED_FINDINGS" | grep -qF "$expected_line3"; then
  pass "(5) multi-line FINDINGS block preserved verbatim"
else
  fail "(5) multi-line FINDINGS block preserved verbatim" \
    "exit=$rc5, PARSED_FINDINGS='${PARSED_FINDINGS}'"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
