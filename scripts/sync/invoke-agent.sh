#!/usr/bin/env bash
set -euo pipefail

# invoke-agent.sh — Invoke AI agents for reference doc generation and review.
#
# Roles:
#   generator  Load reference file + source files, build prompt, call Claude,
#              validate and write output.
#   reviewer   Load generator output + source files, embed review criteria,
#              call OpenAI, parse VERDICT/FINDINGS, write output file.
#   splice     Splice generator output into a named section of a reference file
#              and update traceability frontmatter.
#
# Usage (generator):
#   invoke-agent.sh --role generator \
#     --reference-file <path>         existing reference file (created if absent)
#     [--section <name>]              limit update to this section only
#     --source-dir <dir>              fetched source files directory
#     --repo-id <id>                  for traceability frontmatter
#     --ref <ref>                     for traceability frontmatter
#     --commit <sha>                  for traceability frontmatter
#     --output-file <path>            write generated content here
#
# Usage (reviewer):
#   invoke-agent.sh --role reviewer \
#     --input-file <path>             generator output to review
#     --source-dir <dir>              fetched source files directory
#     --output-file <path>            write VERDICT and FINDINGS here
#
# Usage (splice):
#   invoke-agent.sh --role splice \
#     --reference-file <path>         file to splice into
#     --section <name>                section heading (without ##)
#     --input-file <path>             generator output (section content)
#     --repo-id <id>                  for frontmatter update
#     --ref <ref>                     for frontmatter update
#     --commit <sha>                  for frontmatter update
#
# Output files:
#   generator:  raw Markdown content (full file or section body)
#   reviewer:   line 1 "VERDICT=ACCEPT|REJECT", blank line, then findings text
#   splice:     modifies --reference-file in place; no separate output file
#
# Exit codes:
#   0  success
#   1  invocation error (bad args, API failure, empty response, section not found)
#   2  reviewer response format mismatch (VERDICT/FINDINGS not parseable)
#
# Sourcing: when sourced as a library (BASH_SOURCE != $0), only functions are
# defined — main execution does not run. Used by test scripts for unit tests.

# ── Shared helpers ────────────────────────────────────────────────────────────

# load_source_files <dir>
# Concatenates every file in <dir> to stdout, each preceded by a filename header.
load_source_files() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "ERROR: source-dir does not exist: $dir" >&2
    return 1
  fi
  local found=0
  while IFS= read -r -d '' fpath; do
    local fname
    fname=$(basename "$fpath")
    echo "### FILE: ${fpath#"$dir"/}"
    echo ""
    cat "$fpath"
    echo ""
    echo ""
    found=1
  done < <(find "$dir" -type f -print0 | sort -z)
  if [[ "$found" -eq 0 ]]; then
    echo "(no source files found in $dir)"
  fi
}

# extract_section <section-name> <file>
# Prints the content of the named ## section (excluding the heading line itself).
extract_section() {
  local section="$1"
  local file="$2"
  awk -v sec="## ${section}" '
    $0 == sec { found=1; next }
    found && /^## / { exit }
    found { print }
  ' "$file"
}

# update_repo_frontmatter <file> <repo-id> <new-ref> <new-commit> <new-date>
# Updates (or inserts) a source entry in the traceability frontmatter block
# at the top of <file>. Preserves all other repos verbatim.
update_repo_frontmatter() {
  local file="$1"
  local repo_id="$2"
  local new_ref="$3"
  local new_commit="$4"
  local new_date="$5"

  if grep -q "    - id: ${repo_id}" "$file" 2>/dev/null; then
    # Update existing entry
    awk -v repo="${repo_id}" \
        -v new_ref="${new_ref}" \
        -v new_commit="${new_commit}" \
        -v new_date="${new_date}" '
      BEGIN { in_target = 0 }
      /^    - id: / {
        in_target = ($0 == "    - id: " repo) ? 1 : 0
      }
      in_target && /^      ref: / {
        print "      ref: " new_ref
        next
      }
      in_target && /^      commit: / {
        print "      commit: " new_commit
        next
      }
      in_target && /^      updated: / {
        print "      updated: " new_date
        in_target = 0
        next
      }
      { print }
    ' "$file" > "${file}.fm.tmp" && mv "${file}.fm.tmp" "$file"
  else
    # Insert new entry after the "  sources:" line inside the frontmatter block
    awk -v repo="${repo_id}" \
        -v new_ref="${new_ref}" \
        -v new_commit="${new_commit}" \
        -v new_date="${new_date}" '
      /^  sources:/ {
        print
        print "    - id: " repo
        print "      ref: " new_ref
        print "      commit: " new_commit
        print "      updated: " new_date
        next
      }
      { print }
    ' "$file" > "${file}.fm.tmp" && mv "${file}.fm.tmp" "$file"
  fi
}

# parse_verdict <response-string>
# Extracts VERDICT and FINDINGS from a reviewer agent response.
# Sets globals: PARSED_VERDICT, PARSED_FINDINGS
# Returns 2 if the response format does not match the expected pattern.
parse_verdict() {
  local response="$1"

  # Extract VERDICT line (case-insensitive)
  local verdict
  verdict=$(printf '%s' "$response" | grep -i "^VERDICT:" | head -1 | \
    sed 's/^VERDICT:[[:space:]]*//' | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')

  if [[ -z "$verdict" ]]; then
    echo "ERROR: Response missing VERDICT line" >&2
    return 2
  fi

  if [[ "$verdict" != "ACCEPT" && "$verdict" != "REJECT" ]]; then
    echo "ERROR: VERDICT must be ACCEPT or REJECT, got: '$verdict'" >&2
    return 2
  fi

  # Extract FINDINGS block: everything from the FINDINGS: line onwards
  local findings
  findings=$(printf '%s' "$response" | awk '
    /^FINDINGS:/ {
      found = 1
      sub(/^FINDINGS:[[:space:]]*/, "")
      if (length($0) > 0) print
      next
    }
    found { print }
  ')

  if [[ -z "$findings" ]]; then
    echo "ERROR: Response has VERDICT but no FINDINGS block (or FINDINGS is empty)" >&2
    return 2
  fi

  PARSED_VERDICT="$verdict"
  PARSED_FINDINGS="$findings"
}

# splice_section <section> <reference-file> <new-content> <repo-id> <ref> <commit>
# Replaces the body of "## <section>" in <reference-file> with <new-content>.
# Updates the traceability frontmatter entry for <repo-id>.
# Exits 1 if section heading is not found or generator output is empty.
splice_section() {
  local section="$1"
  local reference_file="$2"
  local new_content="$3"
  local repo_id="$4"
  local ref="$5"
  local commit="$6"

  # Guard: empty generator output
  if [[ -z "${new_content// /}" ]]; then
    echo "ERROR: Generator output is empty — refusing to write blank section in ${reference_file}" >&2
    exit 1
  fi

  # Find section heading line number
  local start_line
  start_line=$(grep -n "^## ${section}$" "$reference_file" | head -1 | cut -d: -f1)

  if [[ -z "$start_line" ]]; then
    echo "ERROR: Section '## ${section}' not found in ${reference_file}" >&2
    exit 1
  fi

  # Find next ## heading after start_line
  local next_section_line
  next_section_line=$(awk -v start="$start_line" \
    'NR > start && /^## /{print NR; exit}' "$reference_file")

  # Build the new file
  {
    # Lines up to and including the section heading
    head -n "$start_line" "$reference_file"
    echo ""
    # New section content
    printf '%s\n' "$new_content"
    # Content after this section (if any)
    if [[ -n "$next_section_line" ]]; then
      echo ""
      tail -n "+${next_section_line}" "$reference_file"
    fi
  } > "${reference_file}.splice.tmp"

  mv "${reference_file}.splice.tmp" "$reference_file"

  # Update traceability frontmatter for this repo
  local today
  today=$(date -u +"%Y-%m-%d")
  update_repo_frontmatter "$reference_file" "$repo_id" "$ref" "$commit" "$today"
}

# ── Generator role (T006) ─────────────────────────────────────────────────────

_build_generator_prompt() {
  local existing_content="$1"
  local source_content="$2"
  local section="$3"
  local repo_id="$4"
  local ref="$5"
  local commit="$6"
  local today="$7"
  local intent_content="${8:-}"

  local section_instruction=""
  local frontmatter_instruction=""

  if [[ -n "$section" ]]; then
    section_instruction="**Section scope**: Update ONLY the content for the section named \"${section}\". Do NOT output the section heading (## ...) itself — output only the body content that goes beneath the heading. Do not include any other sections."
  else
    frontmatter_instruction="**Traceability frontmatter**: The very first content in the output file MUST be this exact frontmatter block (fill in the values):
<!--
  auto-updated: true
  sources:
    - id: ${repo_id}
      ref: ${ref}
      commit: ${commit}
      updated: ${today}
-->"
  fi

  local synthesis_block=""
  if [[ -n "$intent_content" ]]; then
    synthesis_block="## Synthesis Instructions

${intent_content}"
  fi

  cat <<PROMPT
You are updating a Gcore FastEdge reference document for AI agent consumption.

## Existing Reference Content

${existing_content:-*(no existing content — generate from scratch)*}

## Source Material

${source_content}

## Instructions

Produce an updated reference document following ALL of these requirements:

1. **Accuracy**: Content must precisely reflect the source material. No invented or assumed details.
2. **Completeness**: Include ALL public API signatures, parameters, return types, constraints, and error conditions.
3. **Agent-consumability**: Write for AI consumption — structured, precise, no vague prose, no marketing language.
4. **Preservation**: Do not remove information present in the existing content unless the source material contradicts it.
${section_instruction}
${frontmatter_instruction}
${synthesis_block}
**Output**: Return ONLY the document content. No preamble, no explanation, no commentary.
PROMPT
}

_run_generator() {
  local REFERENCE_FILE="" SECTION="" SOURCE_DIR="" REPO_ID="" REF="" COMMIT="" OUTPUT_FILE="" INTENT_FILE=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reference-file) REFERENCE_FILE="$2"; shift 2 ;;
      --section)        SECTION="$2";        shift 2 ;;
      --source-dir)     SOURCE_DIR="$2";     shift 2 ;;
      --repo-id)        REPO_ID="$2";        shift 2 ;;
      --ref)            REF="$2";            shift 2 ;;
      --commit)         COMMIT="$2";         shift 2 ;;
      --output-file)    OUTPUT_FILE="$2";    shift 2 ;;
      --intent-file)    INTENT_FILE="$2";    shift 2 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
  done

  local missing=()
  [[ -z "$SOURCE_DIR" ]]  && missing+=(--source-dir)
  [[ -z "$REPO_ID" ]]     && missing+=(--repo-id)
  [[ -z "$REF" ]]         && missing+=(--ref)
  [[ -z "$COMMIT" ]]      && missing+=(--commit)
  [[ -z "$OUTPUT_FILE" ]] && missing+=(--output-file)
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required arguments: ${missing[*]}" >&2; exit 1
  fi

  # Load existing reference content (full file or named section)
  local existing_content=""
  if [[ -n "$REFERENCE_FILE" && -f "$REFERENCE_FILE" ]]; then
    if [[ -n "$SECTION" ]]; then
      existing_content=$(extract_section "$SECTION" "$REFERENCE_FILE")
    else
      existing_content=$(cat "$REFERENCE_FILE")
    fi
  fi

  # Load source files
  local source_content
  source_content=$(load_source_files "$SOURCE_DIR")

  local today
  today=$(date -u +"%Y-%m-%d")

  # Load intent file content if provided
  local intent_content=""
  if [[ -n "$INTENT_FILE" ]]; then
    if [[ ! -f "$INTENT_FILE" ]]; then
      echo "ERROR: intent-file does not exist: $INTENT_FILE" >&2
      exit 1
    fi
    intent_content=$(cat "$INTENT_FILE")
  fi

  # Build prompt
  local prompt
  prompt=$(_build_generator_prompt "$existing_content" "$source_content" \
    "$SECTION" "$REPO_ID" "$REF" "$COMMIT" "$today" "$intent_content")

  # Write prompt to temp file (avoids shell quoting issues)
  local prompt_file
  prompt_file=$(mktemp /tmp/invoke-agent-prompt.XXXXXX.md)
  # shellcheck disable=SC2064
  trap "rm -f '${prompt_file}'" RETURN
  printf '%s\n' "$prompt" > "$prompt_file"

  echo "INFO: Invoking Claude generator for ${REPO_ID}${SECTION:+ / ${SECTION}}" >&2

  # Invoke Claude and extract .result from JSON output
  local result
  result=$(claude -p "$(cat "$prompt_file")" --output-format json 2>/dev/null \
    | jq -r '.result // empty') || {
    echo "ERROR: Claude invocation failed" >&2
    exit 1
  }

  if [[ -z "$result" ]]; then
    echo "ERROR: Claude returned empty result" >&2
    exit 1
  fi

  # Validate frontmatter present for full-file updates
  if [[ -z "$SECTION" ]]; then
    if ! printf '%s' "$result" | grep -q "auto-updated: true"; then
      echo "ERROR: Generator output missing traceability frontmatter (auto-updated: true)" >&2
      exit 1
    fi
  fi

  printf '%s\n' "$result" > "$OUTPUT_FILE"
  echo "INFO: Generator output written to ${OUTPUT_FILE}" >&2
}

# ── Reviewer role (T007) ──────────────────────────────────────────────────────

# Review criteria embedded verbatim from specs/001-auto-ref-update/contracts/agent-prompts.md
_REVIEW_CRITERIA='Evaluate the proposed reference document update against these criteria:
1. Accuracy: Does the content correctly reflect the source material?
2. Completeness: Are all public API signatures, parameters, return types, and constraints present?
3. Agent-consumability: Is the content precise and structured for AI consumption (no vague prose, no marketing language)?
4. Traceability: Is the frontmatter block present, correctly formatted, and does the commit SHA match the source?
5. Scope compliance: If a section was specified, does the update touch ONLY that section?

Respond in this exact format:
VERDICT: ACCEPT
FINDINGS: <one paragraph, or "None." if no issues>

OR:

VERDICT: REJECT
FINDINGS: <specific issues found, referenced by section or line>'

_build_reviewer_prompt() {
  local generated_content="$1"
  local source_content="$2"

  cat <<PROMPT
## Proposed Reference Document Update

${generated_content}

## Source Material Used to Generate It

${source_content}

## Review Instructions

${_REVIEW_CRITERIA}
PROMPT
}

_run_reviewer() {
  local INPUT_FILE="" SOURCE_DIR="" OUTPUT_FILE=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --input-file)  INPUT_FILE="$2";  shift 2 ;;
      --source-dir)  SOURCE_DIR="$2";  shift 2 ;;
      --output-file) OUTPUT_FILE="$2"; shift 2 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
  done

  local missing=()
  [[ -z "$INPUT_FILE" ]]  && missing+=(--input-file)
  [[ -z "$SOURCE_DIR" ]]  && missing+=(--source-dir)
  [[ -z "$OUTPUT_FILE" ]] && missing+=(--output-file)
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required arguments: ${missing[*]}" >&2; exit 1
  fi

  if [[ ! -f "$INPUT_FILE" ]]; then
    echo "ERROR: input-file does not exist: $INPUT_FILE" >&2; exit 1
  fi

  local generated_content
  generated_content=$(cat "$INPUT_FILE")

  local source_content
  source_content=$(load_source_files "$SOURCE_DIR")

  local prompt
  prompt=$(_build_reviewer_prompt "$generated_content" "$source_content")

  echo "INFO: Invoking OpenAI reviewer (gpt-4o)" >&2

  # Call OpenAI chat completions API
  local request_body
  request_body=$(jq -n --arg content "$prompt" '{
    model: "gpt-4o",
    messages: [{"role": "user", "content": $content}],
    temperature: 0
  }')

  local api_response
  api_response=$(curl -s -f -X POST \
    "https://api.openai.com/v1/chat/completions" \
    -H "Authorization: Bearer ${OPENAI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$request_body") || {
    echo "ERROR: OpenAI API call failed (curl exit $?)" >&2
    exit 1
  }

  local response_text
  response_text=$(printf '%s' "$api_response" | jq -r '.choices[0].message.content // empty')

  if [[ -z "$response_text" ]]; then
    echo "ERROR: Empty response from OpenAI API. Raw: ${api_response}" >&2
    exit 1
  fi

  # Parse VERDICT and FINDINGS
  PARSED_VERDICT="" PARSED_FINDINGS=""
  parse_verdict "$response_text" && pv_exit=0 || pv_exit=$?
  if [[ "$pv_exit" -ne 0 ]]; then
    exit "$pv_exit"
  fi

  # Write output file: VERDICT on line 1, blank line, then findings
  {
    echo "VERDICT=${PARSED_VERDICT}"
    echo ""
    printf '%s\n' "$PARSED_FINDINGS"
  } > "$OUTPUT_FILE"

  echo "INFO: Reviewer output written to ${OUTPUT_FILE} (verdict: ${PARSED_VERDICT})" >&2
}

# ── Splice role (T008) ────────────────────────────────────────────────────────

_run_splice() {
  local REFERENCE_FILE="" SECTION="" INPUT_FILE="" REPO_ID="" REF="" COMMIT=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reference-file) REFERENCE_FILE="$2"; shift 2 ;;
      --section)        SECTION="$2";        shift 2 ;;
      --input-file)     INPUT_FILE="$2";     shift 2 ;;
      --repo-id)        REPO_ID="$2";        shift 2 ;;
      --ref)            REF="$2";            shift 2 ;;
      --commit)         COMMIT="$2";         shift 2 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
  done

  local missing=()
  [[ -z "$REFERENCE_FILE" ]] && missing+=(--reference-file)
  [[ -z "$SECTION" ]]        && missing+=(--section)
  [[ -z "$INPUT_FILE" ]]     && missing+=(--input-file)
  [[ -z "$REPO_ID" ]]        && missing+=(--repo-id)
  [[ -z "$REF" ]]            && missing+=(--ref)
  [[ -z "$COMMIT" ]]         && missing+=(--commit)
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required arguments: ${missing[*]}" >&2; exit 1
  fi

  if [[ ! -f "$REFERENCE_FILE" ]]; then
    echo "ERROR: reference-file does not exist: $REFERENCE_FILE" >&2; exit 1
  fi

  local new_content
  new_content=$(cat "$INPUT_FILE")

  splice_section "$SECTION" "$REFERENCE_FILE" "$new_content" "$REPO_ID" "$REF" "$COMMIT"
  echo "INFO: Spliced section '${SECTION}' into ${REFERENCE_FILE}" >&2
}

# ── Main ──────────────────────────────────────────────────────────────────────

_invoke_agent_main() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: invoke-agent.sh --role generator|reviewer|splice [role-specific args]" >&2
    exit 1
  fi

  local ROLE=""
  # Peek at --role before dispatching
  local args=("$@")
  local i
  for ((i = 0; i < ${#args[@]}; i++)); do
    if [[ "${args[$i]}" == "--role" ]]; then
      ROLE="${args[$((i+1))]:-}"
      break
    fi
  done

  if [[ -z "$ROLE" ]]; then
    echo "ERROR: --role is required (generator|reviewer|splice)" >&2
    exit 1
  fi

  # Remove --role and its value from args, then dispatch
  local remaining=()
  local skip_next=0
  for arg in "${args[@]}"; do
    if [[ "$skip_next" -eq 1 ]]; then
      skip_next=0
      continue
    fi
    if [[ "$arg" == "--role" ]]; then
      skip_next=1
      continue
    fi
    remaining+=("$arg")
  done

  case "$ROLE" in
    generator) _run_generator "${remaining[@]}" ;;
    reviewer)  _run_reviewer  "${remaining[@]}" ;;
    splice)    _run_splice    "${remaining[@]}" ;;
    *)
      echo "ERROR: Unknown role '${ROLE}'. Must be generator, reviewer, or splice." >&2
      exit 1
      ;;
  esac
}

# ── Entry point ───────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _invoke_agent_main "$@"
fi
