#!/usr/bin/env bash
# test-process-repos.sh — unit tests for process-repos.sh orchestration logic
#
# Coverage (things testable without GitHub, Claude, or OpenAI):
#   (1) trigger=release → skipped when no FILTER_REPO_ID set
#   (2) FILTER_REPO_ID overrides trigger check, repo is processed
#   (3) CHANGED=false from fetch → no-changes skip, run_agents not called
#   (4) dry_run=true gate → fetch+generate+review run, writes/PR/baseline skipped
#   (5) REJECT verdict propagates → summary icon is ⚠️, not ✅
#   (6) fetch failure → OVERALL_FAILED set, exits 1, summary row shows ❌ failed
#
# Not covered here (integration-only — validated via dry_run=true workflow run):
#   - git branch/commit/push flow (write_and_push)
#   - PR creation/update (open_or_update_pr / manage-pr.sh)
#   - Baseline tag write (write_baseline_tag)
#
# Usage: bash scripts/sync/tests/test-process-repos.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROCESS_REPOS="$SCRIPT_DIR/../process-repos.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [[ -n "${2:-}" ]] && echo "       $2"; FAIL=$((FAIL + 1)); }

# Source process-repos.sh as a library (sourcing guard skips _process_repos_main)
# shellcheck source=../process-repos.sh
source "$PROCESS_REPOS"
set +e  # process-repos.sh sets -euo pipefail; restore for test assertions

# ── Shared fixtures ───────────────────────────────────────────────────────────

TMPWORK="$(mktemp -d)"
trap 'rm -rf "$TMPWORK"' EXIT

# Redirect step summary to a temp file so tests can ignore it cleanly
export GITHUB_STEP_SUMMARY="${TMPWORK}/step-summary.md"
STEP_SUMMARY="$GITHUB_STEP_SUMMARY"

# Helper: write a one-repo sources.json fixture
# Usage: make_fixture <trigger> [<id>]
make_fixture() {
  local trigger="${1:-release}" id="${2:-test-repo}"
  cat > "${TMPWORK}/sources.json" <<EOF
{
  "version": "1.0",
  "repos": [
    {
      "id": "${id}",
      "github_url": "https://github.com/test/${id}",
      "sparse_paths": ["src/"],
      "ref": "latest-release",
      "trigger": "${trigger}",
      "updates": [
        {
          "reference_file": "plugins/test/ref.md",
          "generator_agent": "claude",
          "reviewer_agent": "codex"
        }
      ]
    }
  ]
}
EOF
  export SOURCES_FILE="${TMPWORK}/sources.json"
}

# Helper: write a two-repo sources.json fixture (both trigger=schedule)
make_fixture_two_repos() {
  cat > "${TMPWORK}/sources.json" <<'EOF'
{
  "version": "1.0",
  "repos": [
    {
      "id": "repo-a",
      "github_url": "https://github.com/test/repo-a",
      "sparse_paths": ["src/"],
      "ref": "latest-release",
      "trigger": "schedule",
      "updates": [{"reference_file": "plugins/test/a.md", "generator_agent": "claude", "reviewer_agent": "codex"}]
    },
    {
      "id": "repo-b",
      "github_url": "https://github.com/test/repo-b",
      "sparse_paths": ["src/"],
      "ref": "latest-release",
      "trigger": "schedule",
      "updates": [{"reference_file": "plugins/test/b.md", "generator_agent": "claude", "reviewer_agent": "codex"}]
    }
  ]
}
EOF
  export SOURCES_FILE="${TMPWORK}/sources.json"
}

# ── Default stub implementations ─────────────────────────────────────────────
# Tests override these per-scenario.

fetch_repo()        { CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }
run_agents()        { OVERALL_VERDICT="ACCEPT"; CHANGED_FILES="plugins/test/ref.md"; }
write_and_push()    { return 0; }
open_or_update_pr() { PR_URL="https://github.com/test/pr/1"; }
write_baseline_tag(){ :; }

echo ""
echo "process-repos.sh: orchestration logic tests"
echo "============================================"

# ── (1) trigger=release repo skipped when no FILTER_REPO_ID ──────────────────

make_fixture "release"
export FILTER_REPO_ID=""
export DRY_RUN="false"

FETCH_CALLED=0
fetch_repo() { FETCH_CALLED=1; CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }

_process_repos_main
rc1=$?

if [[ "$rc1" -eq 0 ]] \
   && echo "$SUMMARY_ROWS" | grep -qF "trigger=release" \
   && [[ "$FETCH_CALLED" -eq 0 ]]; then
  pass "(1) trigger=release → skipped, fetch not called"
else
  fail "(1) trigger=release → skipped, fetch not called" \
    "exit=${rc1}, FETCH_CALLED=${FETCH_CALLED}, SUMMARY_ROWS='${SUMMARY_ROWS}'"
fi

# Restore default stubs
fetch_repo() { CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }

# ── (2) FILTER_REPO_ID overrides trigger — repo is processed ─────────────────

make_fixture "release" "my-repo"
export FILTER_REPO_ID="my-repo"
export DRY_RUN="false"

FETCH_CALLED=0
fetch_repo() { FETCH_CALLED=1; CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }

_process_repos_main
rc2=$?

if [[ "$rc2" -eq 0 ]] \
   && [[ "$FETCH_CALLED" -eq 1 ]] \
   && echo "$SUMMARY_ROWS" | grep -qF "no changes"; then
  pass "(2) FILTER_REPO_ID overrides trigger → fetch called, no-changes skip"
else
  fail "(2) FILTER_REPO_ID overrides trigger → fetch called, no-changes skip" \
    "exit=${rc2}, FETCH_CALLED=${FETCH_CALLED}, SUMMARY_ROWS='${SUMMARY_ROWS}'"
fi

# Restore default stubs
fetch_repo() { CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }

# ── (3) CHANGED=false → no-changes skip, run_agents not called ───────────────

make_fixture "schedule"
export FILTER_REPO_ID=""
export DRY_RUN="false"

fetch_repo() { CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }
RUN_AGENTS_CALLED=0
run_agents() { RUN_AGENTS_CALLED=1; OVERALL_VERDICT="ACCEPT"; CHANGED_FILES="plugins/test/ref.md"; }

_process_repos_main
rc3=$?

if [[ "$rc3" -eq 0 ]] \
   && echo "$SUMMARY_ROWS" | grep -qF "no changes" \
   && [[ "$RUN_AGENTS_CALLED" -eq 0 ]]; then
  pass "(3) CHANGED=false → no-changes skip, run_agents not called"
else
  fail "(3) CHANGED=false → no-changes skip, run_agents not called" \
    "exit=${rc3}, RUN_AGENTS_CALLED=${RUN_AGENTS_CALLED}, SUMMARY_ROWS='${SUMMARY_ROWS}'"
fi

# Restore default stubs
fetch_repo()  { CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }
run_agents()  { OVERALL_VERDICT="ACCEPT"; CHANGED_FILES="plugins/test/ref.md"; }

# ── (4) dry_run=true → fetch+agents run, write_and_push not called ───────────

make_fixture "schedule"
export FILTER_REPO_ID=""
export DRY_RUN="true"

fetch_repo()  { CHANGED=true; RESOLVED_REF="v2.0.0"; COMMIT="def456"; }
run_agents()  { OVERALL_VERDICT="ACCEPT"; CHANGED_FILES="plugins/test/ref.md"; }
WRITE_CALLED=0
write_and_push() { WRITE_CALLED=1; return 0; }

_process_repos_main
rc4=$?

if [[ "$rc4" -eq 0 ]] \
   && echo "$SUMMARY_ROWS" | grep -qF "dry-run" \
   && [[ "$WRITE_CALLED" -eq 0 ]]; then
  pass "(4) dry_run=true → summary shows dry-run, write_and_push not called"
else
  fail "(4) dry_run=true → summary shows dry-run, write_and_push not called" \
    "exit=${rc4}, WRITE_CALLED=${WRITE_CALLED}, SUMMARY_ROWS='${SUMMARY_ROWS}'"
fi

# Restore default stubs
fetch_repo()     { CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }
run_agents()     { OVERALL_VERDICT="ACCEPT"; CHANGED_FILES="plugins/test/ref.md"; }
write_and_push() { return 0; }

# ── (5) REJECT verdict propagates to summary icon ────────────────────────────

make_fixture "schedule"
export FILTER_REPO_ID=""
export DRY_RUN="false"

fetch_repo()     { CHANGED=true; RESOLVED_REF="v2.0.0"; COMMIT="def456"; }
run_agents()     { OVERALL_VERDICT="REJECT"; CHANGED_FILES="plugins/test/ref.md"; }
write_and_push() { return 0; }
open_or_update_pr() { PR_URL="https://github.com/test/pr/42"; }

_process_repos_main
rc5=$?

if [[ "$rc5" -eq 0 ]] \
   && echo "$SUMMARY_ROWS" | grep -qF "⚠️" \
   && ! echo "$SUMMARY_ROWS" | grep -qF "✅"; then
  pass "(5) REJECT verdict → summary icon is ⚠️, not ✅"
else
  fail "(5) REJECT verdict → summary icon is ⚠️, not ✅" \
    "exit=${rc5}, SUMMARY_ROWS='${SUMMARY_ROWS}'"
fi

# Restore default stubs
fetch_repo()      { CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }
run_agents()      { OVERALL_VERDICT="ACCEPT"; CHANGED_FILES="plugins/test/ref.md"; }
write_and_push()  { return 0; }
open_or_update_pr(){ PR_URL="https://github.com/test/pr/1"; }

# ── (6) fetch failure → exits 1, failed row + skipped row in summary ─────────

make_fixture_two_repos
export FILTER_REPO_ID=""
export DRY_RUN="false"

fetch_repo() {
  local idx="$1"
  if [[ "$idx" -eq 0 ]]; then
    return 1  # repo-a fails
  else
    CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"  # repo-b: no changes
  fi
}

_process_repos_main 2>/dev/null
rc6=$?

if [[ "$rc6" -eq 1 ]] \
   && echo "$SUMMARY_ROWS" | grep -qF "repo-a" \
   && echo "$SUMMARY_ROWS" | grep -qF "failed" \
   && echo "$SUMMARY_ROWS" | grep -qF "repo-b" \
   && echo "$SUMMARY_ROWS" | grep -qF "no changes"; then
  pass "(6) fetch failure → exits 1, repo-a 'failed' row + repo-b 'skipped' row in summary"
else
  fail "(6) fetch failure → exits 1, repo-a 'failed' row + repo-b 'skipped' row in summary" \
    "exit=${rc6}, SUMMARY_ROWS='${SUMMARY_ROWS}'"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
