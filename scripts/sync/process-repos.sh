#!/usr/bin/env bash
set -uo pipefail

# process-repos.sh — Main pipeline loop for sync-reference-docs.yml.
#
# Reads sources.json, fetches each eligible source repo, runs the generator
# and reviewer agents, writes updated reference files, opens/updates PRs,
# and records baseline tags.
#
# Environment variables (all required when called from GitHub Actions):
#   DRY_RUN          "true" to skip file writes, PRs, and baseline updates
#   FILTER_REPO_ID   if set, process only this repo ID (ignores trigger field)
#   SOURCES_FILE     path to sources.json (default: sources.json); overridable
#                    for testing without modifying the real config file
#   GITHUB_STEP_SUMMARY  path to Actions step summary file (set by runner)
#   ANTHROPIC_API_KEY    passed through to invoke-agent.sh (generator)
#   OPENAI_API_KEY       passed through to invoke-agent.sh (reviewer)
#
# Usage:
#   bash scripts/sync/process-repos.sh
#
# Sourcing: when sourced as a library (BASH_SOURCE != $0), only functions are
# defined — no execution occurs. Used by test-process-repos.sh for unit tests.
#
# Exit codes:
#   0  all processed repos succeeded (or were legitimately skipped)
#   1  one or more repos failed; see output for details

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source fetch-repo.sh as a library to get write_baseline_tag() and friends.
# The BASH_SOURCE guard inside fetch-repo.sh prevents its main() from running.
# fetch-repo.sh applies set -euo pipefail when sourced; restore +e immediately
# because this script uses manual error handling (if ! ...) to isolate per-repo
# failures without exiting the entire loop.
# shellcheck source=./fetch-repo.sh
source "${SCRIPT_DIR}/fetch-repo.sh"
set +e

# ── Environment defaults ──────────────────────────────────────────────────────

DRY_RUN="${DRY_RUN:-false}"
FILTER_REPO_ID="${FILTER_REPO_ID:-}"
SOURCES_FILE="${SOURCES_FILE:-sources.json}"
# GITHUB_STEP_SUMMARY may be unset outside Actions (write to /dev/null safely)
STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

# T015: repository_dispatch payload fields (empty outside dispatch context)
DISPATCH_REF="${DISPATCH_REF:-}"
DISPATCH_TRIGGER="${DISPATCH_TRIGGER:-}"

# Staging and checkout dirs live in RUNNER_TEMP when in Actions; /tmp locally
_TMPBASE="${RUNNER_TEMP:-/tmp}"
STAGING_BASE="${_TMPBASE}/sync-staging"
CHECKOUT_BASE="${_TMPBASE}/sync-checkout"

# ── Helpers ───────────────────────────────────────────────────────────────────

# verdict_icon ACCEPT|REJECT → emoji
verdict_icon() {
  [[ "$1" == "ACCEPT" ]] && echo "✅" || echo "⚠️"
}

# ── Per-repo processing functions ────────────────────────────────────────────

# fetch_repo <index> → sets RESOLVED_REF, COMMIT, CHANGED
fetch_repo() {
  local idx="$1"
  local repo_url sparse_paths repo_id ref checkout_dir

  repo_url=$(jq -r ".repos[$idx].github_url" "$SOURCES_FILE")
  sparse_paths=$(jq -r ".repos[$idx].sparse_paths | join(\" \")" "$SOURCES_FILE")
  repo_id=$(jq -r ".repos[$idx].id" "$SOURCES_FILE")
  # T015: use DISPATCH_REF when set (repository_dispatch override)
  ref="${DISPATCH_REF:-$(jq -r ".repos[$idx].ref" "$SOURCES_FILE")}"
  checkout_dir="${CHECKOUT_BASE}/${repo_id}"

  local fetch_output
  fetch_output=$(bash "${SCRIPT_DIR}/fetch-repo.sh" \
    --repo-url     "$repo_url" \
    --sparse-paths "$sparse_paths" \
    --repo-id      "$repo_id" \
    --ref          "$ref" \
    --checkout-dir "$checkout_dir") || return 1

  # Parse KEY=VALUE pairs from fetch-repo.sh stdout
  RESOLVED_REF="" COMMIT="" CHANGED=""
  while IFS='=' read -r key value; do
    case "$key" in
      CHANGED)      CHANGED="$value" ;;
      RESOLVED_REF) RESOLVED_REF="$value" ;;
      COMMIT)       COMMIT="$value" ;;
    esac
  done <<< "$fetch_output"
}

# run_agents <repo-index> <staging-dir> <checkout-dir>
# For each UpdateEntry: invokes generator then reviewer.
# Writes gen-N.md, rev-N.txt, combined-findings.txt to staging-dir.
# Sets CHANGED_FILES and OVERALL_VERDICT on success; returns 1 on failure.
run_agents() {
  local idx="$1" staging_dir="$2" checkout_dir="$3"
  local repo_id update_count

  repo_id=$(jq -r ".repos[$idx].id" "$SOURCES_FILE")
  update_count=$(jq ".repos[$idx].updates | length" "$SOURCES_FILE")

  CHANGED_FILES=""
  OVERALL_VERDICT="ACCEPT"
  local findings_file="${staging_dir}/combined-findings.txt"
  > "$findings_file"

  local j
  for ((j = 0; j < update_count; j++)); do
    local reference_file section intent_file gen_output rev_output section_args intent_args

    reference_file=$(jq -r ".repos[$idx].updates[$j].reference_file" "$SOURCES_FILE")
    section=$(jq -r ".repos[$idx].updates[$j].section // empty" "$SOURCES_FILE")
    intent_file=$(jq -r ".repos[$idx].updates[$j].intent_file // empty" "$SOURCES_FILE")
    gen_output="${staging_dir}/gen-${j}.md"
    rev_output="${staging_dir}/rev-${j}.txt"

    section_args=()
    [[ -n "$section" ]] && section_args=(--section "$section")

    intent_args=()
    [[ -n "$intent_file" ]] && intent_args=(--intent-file "$intent_file")

    bash "${SCRIPT_DIR}/invoke-agent.sh" \
      --role generator \
      "${section_args[@]}" \
      "${intent_args[@]}" \
      --reference-file "$reference_file" \
      --source-dir     "$checkout_dir" \
      --repo-id        "$repo_id" \
      --ref            "$RESOLVED_REF" \
      --commit         "$COMMIT" \
      --output-file    "$gen_output" || return 1

    bash "${SCRIPT_DIR}/invoke-agent.sh" \
      --role reviewer \
      --input-file  "$gen_output" \
      --source-dir  "$checkout_dir" \
      --output-file "$rev_output" || return 1

    local entry_verdict entry_findings
    entry_verdict=$(head -1 "$rev_output" | sed 's/^VERDICT=//')
    entry_findings=$(tail -n +3 "$rev_output")

    [[ "$entry_verdict" == "REJECT" ]] && OVERALL_VERDICT="REJECT"

    {
      echo "**${reference_file}${section:+ / ${section}}**: ${entry_verdict}"
      echo ""
      echo "$entry_findings"
      echo ""
    } >> "$findings_file"

    CHANGED_FILES="${CHANGED_FILES:+${CHANGED_FILES} }${reference_file}"
  done
}

# write_and_push <repo-index> <staging-dir>
# Creates/resets the PR branch, splices or copies each staged file,
# commits, and force-pushes. Returns 1 on any failure; restores
# the default branch before returning. Returns 2 when git diff
# shows no net changes (content already current — not an error).
write_and_push() {
  local idx="$1" staging_dir="$2"
  local update_count pr_branch

  update_count=$(jq ".repos[$idx].updates | length" "$SOURCES_FILE")
  pr_branch="auto-ref-update/${REPO_ID}"

  git checkout -B "$pr_branch"

  local j failed=0
  for ((j = 0; j < update_count; j++)); do
    local reference_file section gen_output

    reference_file=$(jq -r ".repos[$idx].updates[$j].reference_file" "$SOURCES_FILE")
    section=$(jq -r ".repos[$idx].updates[$j].section // empty" "$SOURCES_FILE")
    gen_output="${staging_dir}/gen-${j}.md"

    if [[ -n "$section" ]]; then
      bash "${SCRIPT_DIR}/invoke-agent.sh" \
        --role           splice \
        --reference-file "$reference_file" \
        --section        "$section" \
        --input-file     "$gen_output" \
        --repo-id        "$REPO_ID" \
        --ref            "$RESOLVED_REF" \
        --commit         "$COMMIT" || { failed=1; break; }
    else
      mkdir -p "$(dirname "$reference_file")"
      cp "$gen_output" "$reference_file"
    fi
  done

  if [[ "$failed" -eq 1 ]]; then
    git checkout "$DEFAULT_BRANCH"
    return 1
  fi

  # shellcheck disable=SC2086
  git add -- $CHANGED_FILES

  if git diff --cached --quiet; then
    echo "INFO: No net changes to commit for ${REPO_ID} (content already current)"
    git checkout "$DEFAULT_BRANCH"
    return 2  # signal: skipped — not an error
  fi

  git commit -m "auto: update reference docs from ${REPO_ID} (${RESOLVED_REF})"
  git push --force origin "$pr_branch"
  git checkout "$DEFAULT_BRANCH"
}

# open_or_update_pr <staging-dir>
# Calls manage-pr.sh and captures the PR URL to PR_URL.
open_or_update_pr() {
  local findings_file="${1}/combined-findings.txt"
  local combined_findings
  combined_findings=$(cat "$findings_file")

  PR_URL=$(bash "${SCRIPT_DIR}/manage-pr.sh" \
    --repo-id       "$REPO_ID" \
    --ref           "$RESOLVED_REF" \
    --commit        "$COMMIT" \
    --changed-files "$CHANGED_FILES" \
    --verdict       "$OVERALL_VERDICT" \
    --findings      "$combined_findings") || {
    echo "WARN: manage-pr.sh failed for ${REPO_ID} — PR may need manual attention" >&2
    PR_URL="(pr error)"
  }
}

# ── T014: Per-repo isolation helpers ─────────────────────────────────────────

# _FAILURE_REASON is set by process_repo before returning 1 so that
# record_failure can include the specific reason in the summary row.
_FAILURE_REASON=""

# record_failure REPO_ID EXIT_CODE
# Called by the main loop when process_repo exits non-zero.
# Writes the failure summary row and marks OVERALL_FAILED.
record_failure() {
  local repo_id="$1" exit_code="${2:-1}"
  local reason="${_FAILURE_REASON:-unexpected error (exit ${exit_code})}"
  _FAILURE_REASON=""
  echo "ERROR: Failed processing ${repo_id}: ${reason}" >&2
  SUMMARY_ROWS+="| ${repo_id} | ❌ failed | — | ${reason} |"$'\n'
  OVERALL_FAILED=1
}

# process_repo REPO_ID
# Runs the complete pipeline for one source repo in isolation.
# Writes its own SUMMARY_ROWS entry for success/skip outcomes.
# On failure: sets _FAILURE_REASON, returns 1 (record_failure writes the row).
process_repo() {
  REPO_ID="$1"

  # Look up index in sources.json
  local idx
  idx=$(jq -r --arg id "$REPO_ID" '.repos | to_entries[] | select(.value.id == $id) | .key' "$SOURCES_FILE")

  local TRIGGER
  TRIGGER=$(jq -r ".repos[$idx].trigger" "$SOURCES_FILE")

  # ── Filter: which repos are eligible for this trigger ────────────────────
  if [[ -n "$FILTER_REPO_ID" ]]; then
    [[ "$REPO_ID" != "$FILTER_REPO_ID" ]] && return 0
  else
    if [[ "$TRIGGER" != "schedule" && "$TRIGGER" != "both" ]]; then
      echo "INFO: Skipping ${REPO_ID} (trigger=${TRIGGER})"
      SUMMARY_ROWS+="| ${REPO_ID} | ⏭ skipped | — | trigger=${TRIGGER} |"$'\n'
      return 0
    fi
  fi

  echo "========================================"
  echo "Processing: ${REPO_ID}"

  local STAGING_DIR="${STAGING_BASE}/${REPO_ID}"
  local CHECKOUT_DIR="${CHECKOUT_BASE}/${REPO_ID}"
  mkdir -p "$STAGING_DIR"

  RESOLVED_REF="" COMMIT="" CHANGED=""
  CHANGED_FILES="" OVERALL_VERDICT="ACCEPT" PR_URL=""

  # ── Step 1: Fetch ─────────────────────────────────────────────────────────
  if ! fetch_repo "$idx"; then
    _FAILURE_REASON="fetch error"
    return 1
  fi

  if [[ "$CHANGED" != "true" ]]; then
    echo "INFO: No changes for ${REPO_ID} — skipping"
    SUMMARY_ROWS+="| ${REPO_ID} | ⏭ skipped | ${RESOLVED_REF} | no changes |"$'\n'
    return 0
  fi

  # ── Step 2: Generate + review ─────────────────────────────────────────────
  if ! run_agents "$idx" "$STAGING_DIR" "$CHECKOUT_DIR"; then
    _FAILURE_REASON="agent error"
    return 1
  fi

  # ── dry_run gate ──────────────────────────────────────────────────────────
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "INFO: dry_run=true — skipping writes, PR, and baseline for ${REPO_ID}"
    SUMMARY_ROWS+="| ${REPO_ID} | 🔍 dry-run $(verdict_icon "$OVERALL_VERDICT") | ${RESOLVED_REF} | writes skipped |"$'\n'
    return 0
  fi

  # ── Step 3: Write + commit + push ─────────────────────────────────────────
  local write_rc=0
  write_and_push "$idx" "$STAGING_DIR" || write_rc=$?

  if [[ "$write_rc" -eq 1 ]]; then
    _FAILURE_REASON="write error"
    return 1
  fi

  if [[ "$write_rc" -eq 2 ]]; then
    SUMMARY_ROWS+="| ${REPO_ID} | ⏭ skipped | ${RESOLVED_REF} | no net changes |"$'\n'
    return 0
  fi

  # ── Step 4: Open / update PR ──────────────────────────────────────────────
  open_or_update_pr "$STAGING_DIR"

  # ── Step 5: Update baseline tag ───────────────────────────────────────────
  write_baseline_tag "$REPO_ID" "$RESOLVED_REF" "$COMMIT" || {
    echo "WARN: Failed to update baseline tag for ${REPO_ID}" >&2
  }

  SUMMARY_ROWS+="| ${REPO_ID} | $(verdict_icon "$OVERALL_VERDICT") PR | ${RESOLVED_REF} | ${PR_URL:-opened} |"$'\n'
  return 0
}

# ── Main ─────────────────────────────────────────────────────────────────────

_process_repos_main() {
  local PLUGIN_ROOT DEFAULT_BRANCH

  PLUGIN_ROOT="$(pwd)"
  DEFAULT_BRANCH="$(git symbolic-ref --short HEAD)"
  mkdir -p "$STAGING_BASE" "$CHECKOUT_BASE"

  git config user.email "github-actions[bot]@users.noreply.github.com"
  git config user.name  "github-actions[bot]"

  OVERALL_FAILED=0
  SUMMARY_ROWS=""

  # ── T015: Validate repository_dispatch payload ────────────────────────────
  if [[ "${DISPATCH_TRIGGER}" == "repository_dispatch" ]]; then
    if [[ -z "$FILTER_REPO_ID" ]]; then
      echo "ERROR: repository_dispatch missing source_repo_id in client_payload" >&2
      exit 1
    fi
    local _found
    _found=$(jq -r --arg id "$FILTER_REPO_ID" '.repos[] | select(.id == $id) | .id' "$SOURCES_FILE")
    if [[ -z "$_found" ]]; then
      echo "ERROR: repository_dispatch source_repo_id '${FILTER_REPO_ID}' not found in ${SOURCES_FILE}" >&2
      exit 1
    fi
  fi

  local REPO_COUNT
  REPO_COUNT=$(jq '.repos | length' "$SOURCES_FILE")

  local i
  for ((i = 0; i < REPO_COUNT; i++)); do
    REPO_ID=$(jq -r ".repos[$i].id" "$SOURCES_FILE")
    if ! process_repo "$REPO_ID"; then
      record_failure "$REPO_ID" "$?"
    fi
  done

  # ── Write step summary ────────────────────────────────────────────────────
  {
    echo "## Sync Reference Docs — Run Summary"
    echo ""
    echo "| Source Repo | Outcome | Ref | PR |"
    echo "|-------------|---------|-----|----|"
    printf '%s' "$SUMMARY_ROWS"
  } >> "$STEP_SUMMARY"

  if [[ "$OVERALL_FAILED" -eq 1 ]]; then
    echo "ERROR: One or more repos failed processing" >&2
    return 1
  fi
}

# ── Entry point ───────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _process_repos_main "$@"
fi
