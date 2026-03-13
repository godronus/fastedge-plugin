#!/usr/bin/env bash
# run-all-tests.sh — run all sync test suites and report a combined result
# Usage: bash scripts/sync/tests/run-all-tests.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SUITES=(
  test-validate-sources.sh
  test-fetch-repo.sh
  test-section-splice.sh
  test-verdict-parse.sh
  test-process-repos.sh
)

FAILED_SUITES=()

for suite in "${SUITES[@]}"; do
  echo "========================================"
  if bash "$SCRIPT_DIR/$suite"; then
    echo "  => $suite: OK"
  else
    echo "  => $suite: FAILED"
    FAILED_SUITES+=("$suite")
  fi
  echo ""
done

echo "========================================"
if [[ ${#FAILED_SUITES[@]} -eq 0 ]]; then
  echo "All suites passed."
  exit 0
else
  echo "Failed suites: ${FAILED_SUITES[*]}"
  exit 1
fi
