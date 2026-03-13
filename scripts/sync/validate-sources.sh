#!/usr/bin/env bash
# validate-sources.sh — validate sources.json against all 6 schema rules
# Usage: validate-sources.sh <path-to-sources.json>
set -euo pipefail

SOURCES_FILE="${1:-}"

if [[ -z "$SOURCES_FILE" ]]; then
  echo "ERROR: No sources.json path provided." >&2
  echo "Usage: $0 <path-to-sources.json>" >&2
  exit 1
fi

if [[ ! -f "$SOURCES_FILE" ]]; then
  echo "ERROR: File not found: $SOURCES_FILE" >&2
  exit 1
fi

ERRORS=0

fail() {
  echo "VALIDATION ERROR: $*" >&2
  ERRORS=$((ERRORS + 1))
}

# Rule 1: All repo `id` values must be unique
mapfile -t IDS < <(jq -r '.repos[].id' "$SOURCES_FILE")
UNIQUE_IDS=$(printf '%s\n' "${IDS[@]}" | sort -u | wc -l)
if [[ "${#IDS[@]}" -ne "$UNIQUE_IDS" ]]; then
  DUPES=$(printf '%s\n' "${IDS[@]}" | sort | uniq -d | tr '\n' ' ')
  fail "Rule 1: Duplicate repo id(s) found: $DUPES"
fi

# Rule 2: All github_url values must be reachable via GitHub API
while IFS= read -r URL; do
  # Extract owner/repo from https://github.com/owner/repo
  REPO_PATH="${URL#https://github.com/}"
  if ! gh api "repos/$REPO_PATH" --silent 2>/dev/null; then
    fail "Rule 2: github_url not reachable (repo not found or no access): $URL"
  fi
done < <(jq -r '.repos[].github_url' "$SOURCES_FILE")

# Rule 3: All reference_file paths must start with 'plugins/'
while IFS= read -r REF_FILE; do
  if [[ "$REF_FILE" != plugins/* ]]; then
    fail "Rule 3: reference_file must start with 'plugins/': $REF_FILE"
  fi
done < <(jq -r '.repos[].updates[].reference_file' "$SOURCES_FILE")

# Rule 4: generator_agent must not equal reviewer_agent within the same UpdateEntry
while IFS=$'\t' read -r REPO_ID GEN REV; do
  if [[ "$GEN" == "$REV" ]]; then
    fail "Rule 4: generator_agent equals reviewer_agent ('$GEN') in repo '$REPO_ID'"
  fi
done < <(jq -r '.repos[] | .id as $id | .updates[] | [$id, .generator_agent, .reviewer_agent] | @tsv' "$SOURCES_FILE")

# Rule 5: Any reference_file appearing in multiple UpdateEntry records must have `section` defined in all of them
# Collect all (reference_file, section_or_null) pairs
declare -A REF_HAS_SECTION
declare -A REF_MISSING_SECTION
while IFS=$'\t' read -r REF_FILE SECTION; do
  if [[ "$SECTION" == "null" ]]; then
    REF_MISSING_SECTION["$REF_FILE"]=1
  else
    REF_HAS_SECTION["$REF_FILE"]=1
  fi
done < <(jq -r '.repos[].updates[] | [.reference_file, (.section // "null")] | @tsv' "$SOURCES_FILE")

# A file is problematic if it appears with a section in some entries and without in others,
# OR if it appears more than once total and any entry is missing section.
# Count occurrences per reference_file
declare -A REF_COUNT
while IFS= read -r REF_FILE; do
  REF_COUNT["$REF_FILE"]=$(( ${REF_COUNT["$REF_FILE"]:-0} + 1 ))
done < <(jq -r '.repos[].updates[].reference_file' "$SOURCES_FILE")

for REF_FILE in "${!REF_COUNT[@]}"; do
  COUNT="${REF_COUNT[$REF_FILE]}"
  if [[ "$COUNT" -gt 1 ]] && [[ -n "${REF_MISSING_SECTION[$REF_FILE]+x}" ]]; then
    fail "Rule 5: reference_file '$REF_FILE' appears in multiple UpdateEntry records but is missing 'section' in at least one"
  fi
done

# Rule 6: No sparse_paths entry may reference build artifact or metadata directories
BANNED_PATTERNS=("node_modules/" "dist/" "target/" ".git/")
while IFS=$'\t' read -r REPO_ID SPARSE_PATH; do
  for BANNED in "${BANNED_PATTERNS[@]}"; do
    if [[ "$SPARSE_PATH" == *"$BANNED"* ]]; then
      fail "Rule 6: sparse_path '$SPARSE_PATH' in repo '$REPO_ID' contains banned pattern '$BANNED'"
    fi
  done
done < <(jq -r '.repos[] | .id as $id | .sparse_paths[] | [$id, .] | @tsv' "$SOURCES_FILE")

# Rule 7: If intent_file is specified in an UpdateEntry, the file must exist relative to repo root
while IFS=$'\t' read -r REPO_ID INTENT_FILE; do
  if [[ -n "$INTENT_FILE" && "$INTENT_FILE" != "null" ]]; then
    if [[ ! -f "$INTENT_FILE" ]]; then
      fail "Rule 7: intent_file '$INTENT_FILE' in repo '$REPO_ID' does not exist relative to repo root"
    fi
  fi
done < <(jq -r '.repos[] | .id as $id | .updates[] | [$id, (.intent_file // "")] | @tsv' "$SOURCES_FILE")

# Summary
if [[ "$ERRORS" -gt 0 ]]; then
  echo "sources.json validation FAILED with $ERRORS error(s)." >&2
  exit 1
fi

echo "sources.json validation passed."
