#!/usr/bin/env bash
set -euo pipefail

# fetch-repo.sh — Sparse-clone a source repo and detect changes vs. baseline
#
# Usage:
#   fetch-repo.sh --repo-url <url> --sparse-paths "<paths>" --repo-id <id> \
#                 --ref <ref> --checkout-dir <dir>
#
# Arguments:
#   --repo-url      Full HTTPS URL to the GitHub repo (no trailing slash)
#   --sparse-paths  Space-separated list of paths for sparse checkout
#   --repo-id       Unique kebab-case repo identifier (matches sources.json id)
#   --ref           "latest-release", "main", or a tag like "vX.Y.Z"
#   --checkout-dir  Directory to clone into (created if absent, re-created if exists)
#
# Outputs (written to stdout, one per line, KEY=VALUE format):
#   CHANGED=true|false   whether HEAD SHA differs from baseline
#   RESOLVED_REF=<tag>   actual tag used (same as --ref unless latest-release)
#   COMMIT=<sha>         full HEAD commit SHA of the cloned source repo
#
# Baseline tags are read/written in the *plugin* repo (current working dir).
#
# Exit codes:
#   0  success
#   1  any error (bad argument, clone failure, API error, etc.)
#
# Sourcing: when sourced as a library (BASH_SOURCE != $0), only functions are
# defined — no execution occurs. Used by test-fetch-repo.sh for unit tests.

# ── Functions ─────────────────────────────────────────────────────────────────

# resolve_latest_release <repo-url>
# Resolves "latest-release" to the actual tag name via the GitHub API.
resolve_latest_release() {
  local repo_url="$1"
  local owner_repo
  owner_repo=$(echo "$repo_url" | sed 's|https://github.com/||')

  local tag_name
  tag_name=$(gh api "repos/${owner_repo}/releases/latest" --jq '.tag_name' 2>/dev/null) || {
    echo "ERROR: gh api request failed for repos/${owner_repo}/releases/latest" >&2
    exit 1
  }

  if [[ -z "$tag_name" || "$tag_name" == "null" ]]; then
    echo "ERROR: Could not resolve latest release for $repo_url — no tag_name in response" >&2
    exit 1
  fi

  echo "$tag_name"
}

# read_baseline_commit <repo-id>
# Reads the last-processed commit SHA from annotated tag refs/tags/ref-update/<repo-id>
# on the plugin repo origin. Message format: "<ref> | <commit-sha> | <timestamp>"
# Returns empty string when no baseline exists (first run).
read_baseline_commit() {
  local repo_id="$1"
  local tag_refspec="refs/tags/ref-update/${repo_id}"

  # Check whether the tag exists on the remote before attempting a fetch
  local remote_sha
  remote_sha=$(git ls-remote origin "$tag_refspec" 2>/dev/null | awk '{print $1}')

  if [[ -z "$remote_sha" ]]; then
    # No baseline — first run for this repo
    echo ""
    return 0
  fi

  # Fetch the annotated tag object so git cat-file can read it locally.
  # FETCH_HEAD points to the tag object after this fetch.
  if ! git fetch --quiet origin "$tag_refspec" 2>/dev/null; then
    echo "WARN: Baseline tag found on remote but fetch failed ($tag_refspec) — treating as new" >&2
    echo ""
    return 0
  fi

  # Read the tag message body (first non-empty line after the blank separator)
  local tag_msg
  tag_msg=$(git cat-file tag FETCH_HEAD 2>/dev/null \
    | awk '/^$/{found=1; next} found{print; exit}')

  if [[ -z "$tag_msg" ]]; then
    echo "WARN: Baseline tag exists but message is empty ($tag_refspec) — treating as new" >&2
    echo ""
    return 0
  fi

  # Extract commit SHA (field 2, pipe-delimited, strip spaces)
  echo "$tag_msg" | cut -d'|' -f2 | tr -d ' '
}

# write_baseline_tag <repo-id> <ref> <commit>
# Writes an annotated tag recording the last-processed state for <repo-id>.
# Tag message format: "<ref> | <commit> | <ISO8601-timestamp>"
# Force-pushes the tag to origin so the next run can read it back.
#
# IMPORTANT — working directory requirement:
#   This function must be called from the PLUGIN REPO ROOT, not from inside a
#   source repo checkout directory. The `git tag` and `git push origin` commands
#   operate on whatever repo is in the current working directory. The workflow
#   (T010) must ensure it returns to the plugin repo root before calling this,
#   as _fetch_repo_main() changes into $CHECKOUT_DIR during its execution.
write_baseline_tag() {
  local repo_id="$1"
  local ref="$2"
  local commit="$3"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local tag_name="ref-update/${repo_id}"

  git tag -f -a "$tag_name" -m "${ref} | ${commit} | ${now}" >&2
  git push --force origin "refs/tags/${tag_name}" >&2
}

# assert_sparse_paths_only <repo-id> <anchored-path>...
# T013: after git checkout, enumerate every tracked file with git ls-files and
# assert that each one falls under at least one of the declared sparse paths.
# Exits 1 with a clear list of offending files if any are found outside the
# declared paths. This prevents a silent full-checkout from contaminating the
# source dir with undeclared content (enforces Principle XI).
#
# Called with the anchored_paths array (leading / already added) because that
# is what was passed to git sparse-checkout set. Matching logic:
#   /src/         → file must start with  src/
#   /README.md    → file must equal       README.md
assert_sparse_paths_only() {
  local repo_id="$1"
  shift
  local anchored_paths=("$@")

  local -a unexpected=()
  local file
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    # In sparse checkout, files outside declared paths have the skip-worktree bit
    # set and are NOT present in the working tree. Only assert on files that are
    # physically present — skip index entries that git did not check out.
    [[ -f "$file" ]] || continue
    local matched=false
    local pat
    for pat in "${anchored_paths[@]}"; do
      local p="${pat#/}"          # strip leading /
      if [[ "$p" == */ ]]; then
        # Directory pattern: file must live under this directory
        [[ "$file" == "$p"* || "$file" == "${p%/}" ]] && matched=true && break
      else
        # File pattern: exact match
        [[ "$file" == "$p" ]] && matched=true && break
      fi
    done
    [[ "$matched" != true ]] && unexpected+=("$file")
  done < <(git ls-files)

  if [[ "${#unexpected[@]}" -gt 0 ]]; then
    echo "ERROR: Post-checkout assertion failed for ${repo_id}" >&2
    echo "ERROR: Files below are outside the declared sparse_paths — aborting:" >&2
    printf '  %s\n' "${unexpected[@]}" >&2
    exit 1
  fi
}

# _fetch_repo_main [args...]
# Main execution: arg parsing → ref resolution → baseline read → sparse clone
# → change detection → emit KEY=VALUE results to stdout.
_fetch_repo_main() {
  # ── Argument parsing ────────────────────────────────────────────────────────

  local REPO_URL="" SPARSE_PATHS="" REPO_ID="" REF="" CHECKOUT_DIR=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo-url)     REPO_URL="$2";     shift 2 ;;
      --sparse-paths) SPARSE_PATHS="$2"; shift 2 ;;
      --repo-id)      REPO_ID="$2";      shift 2 ;;
      --ref)          REF="$2";          shift 2 ;;
      --checkout-dir) CHECKOUT_DIR="$2"; shift 2 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
  done

  # ── Validation ──────────────────────────────────────────────────────────────

  local missing=()
  [[ -z "$REPO_URL" ]]     && missing+=(--repo-url)
  [[ -z "$SPARSE_PATHS" ]] && missing+=(--sparse-paths)
  [[ -z "$REPO_ID" ]]      && missing+=(--repo-id)
  [[ -z "$REF" ]]          && missing+=(--ref)
  [[ -z "$CHECKOUT_DIR" ]] && missing+=(--checkout-dir)

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required arguments: ${missing[*]}" >&2
    exit 1
  fi

  # ── Resolve ref ─────────────────────────────────────────────────────────────

  local RESOLVED_REF="$REF"
  if [[ "$REF" == "latest-release" ]]; then
    RESOLVED_REF=$(resolve_latest_release "$REPO_URL")
    echo "INFO: Resolved latest-release → $RESOLVED_REF for $REPO_ID" >&2
  fi

  # ── Read baseline commit SHA ─────────────────────────────────────────────────

  local LAST_COMMIT
  LAST_COMMIT=$(read_baseline_commit "$REPO_ID")

  # ── Sparse clone ─────────────────────────────────────────────────────────────

  # Remove stale checkout dir if present — always start clean
  if [[ -e "$CHECKOUT_DIR" ]]; then
    echo "INFO: Removing existing checkout dir for fresh clone: $CHECKOUT_DIR" >&2
    rm -rf "$CHECKOUT_DIR"
  fi
  mkdir -p "$CHECKOUT_DIR"

  echo "INFO: Cloning $REPO_URL at $RESOLVED_REF into $CHECKOUT_DIR" >&2

  gh repo clone "$REPO_URL" "$CHECKOUT_DIR" -- \
    --filter=blob:none \
    --no-checkout \
    --depth 1 \
    --branch "$RESOLVED_REF" >&2

  # ── Sparse checkout paths ────────────────────────────────────────────────────

  cd "$CHECKOUT_DIR"

  # In no-cone mode, patterns without a leading / match at any depth (gitignore semantics).
  # Prefix each path with / to root-anchor it so src/ matches only the top-level src/,
  # not docs/src/, compiler/src/, etc.
  local anchored_paths=()
  for p in $SPARSE_PATHS; do
    [[ "$p" == /* ]] && anchored_paths+=("$p") || anchored_paths+=("/$p")
  done

  git sparse-checkout init --no-cone >&2

  # T012: hard-failure guard — no full-clone fallback under any circumstance
  git sparse-checkout set "${anchored_paths[@]}" >&2 || {
    echo "ERROR: git sparse-checkout set failed for ${REPO_ID} — aborting (no full-clone fallback)" >&2
    echo "ERROR: Paths attempted: ${anchored_paths[*]}" >&2
    exit 1
  }

  git checkout >&2

  # T013: post-checkout path assertion — every tracked file must match a declared path
  assert_sparse_paths_only "$REPO_ID" "${anchored_paths[@]}"

  # ── Capture HEAD commit SHA ───────────────────────────────────────────────────

  local COMMIT
  COMMIT=$(git rev-parse HEAD)

  # ── Detect changes ────────────────────────────────────────────────────────────

  local CHANGED
  if [[ -z "$LAST_COMMIT" ]]; then
    CHANGED=true
    echo "INFO: No baseline found for $REPO_ID — treating as changed (first run)" >&2
  elif [[ "$COMMIT" == "$LAST_COMMIT" ]]; then
    CHANGED=false
    echo "INFO: No changes for $REPO_ID (commit unchanged: $COMMIT)" >&2
  else
    CHANGED=true
    echo "INFO: Changes detected for $REPO_ID ($LAST_COMMIT → $COMMIT)" >&2
  fi

  # ── Emit results ──────────────────────────────────────────────────────────────

  echo "CHANGED=$CHANGED"
  echo "RESOLVED_REF=$RESOLVED_REF"
  echo "COMMIT=$COMMIT"
}

# ── Entry point ───────────────────────────────────────────────────────────────
# Guard: when sourced as a library, only function definitions above are loaded.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _fetch_repo_main "$@"
fi
