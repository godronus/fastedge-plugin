# Implementation Plan: Automated Reference Material Update System

**Branch**: `001-auto-ref-update` | **Date**: 2026-03-09 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/001-auto-ref-update/spec.md`

---

## Summary

Build a GitHub Actions–based pipeline that reads `sources.json`, sparse-checks out each configured source repo, invokes a generator AI agent (Claude) to update reference docs, invokes a separate reviewer AI agent (OpenAI GPT-4o) to quality-gate the output, and opens one pull request per source repo with accepted or flagged changes. Manual `workflow_dispatch` and cross-repo `repository_dispatch` webhooks both trigger the pipeline.

---

## Technical Context

**Language/Version**: Bash (scripts), YAML (GitHub Actions workflow)
**Primary Dependencies**: `gh` CLI (pre-installed on ubuntu-latest), `jq` (pre-installed), `claude` CLI (installed at workflow start), OpenAI REST API via `curl`
**Storage**: `sources.json` (pipeline config), git annotated tags `refs/tags/ref-update/<repo-id>` (commit baselines, branchless)
**Testing**: `workflow_dispatch` with `dry_run: true` input for local/CI validation; `act` for local workflow testing
**Target Platform**: GitHub Actions (ubuntu-latest)
**Project Type**: CI/CD automation pipeline (developer infrastructure — not user-facing plugin logic)
**Performance Goals**: Full pipeline run completes within GitHub Actions 6-hour timeout; per-repo processing finishes within 10 minutes
**Constraints**: Writes only to `plugins/` (Principle X); sparse checkout only, never full clone (Principle XI); no partial writes (Principle XII)
**Scale/Scope**: Designed for ~10 source repos; scales linearly with repo count

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

### Principles I–V (Core Plugin Principles)

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Skill-First Design | ✅ Pass | Automation scripts are CI/CD developer infrastructure, not plugin skill logic. Analogous to `create-fastedge-app` being an external tool. No skill files are modified. |
| II. Delegate, Don't Duplicate | ✅ Pass | Pipeline reads source repos and writes reference files; does not duplicate template content. |
| III. Scope Boundary | ✅ Pass | External repo fetches are the pipeline's designed purpose; the boundary restriction applies to Claude operating within a user's project, not to this automation. Write scope is restricted to `plugins/` (Principle X). |
| IV. Clarify Before Acting | ✅ Pass | Not applicable — this is automated infrastructure, not a user-interactive skill. |
| V. Knowledge Base Integrity | ✅ Pass | This feature IS the mechanism to keep the knowledge base current. The PR-gated human review step ensures no incorrect content lands in `CLAUDE.md` or reference files. |

### Principles VI–XV (Reference Material Automation)

| Principle | Status | Notes |
|-----------|--------|-------|
| VI. PR-Gated | ✅ Pass | All changes go through a PR. Workflow never merges. |
| VII. One PR Per Source Repo | ✅ Pass | Branch naming `auto-ref-update/<repo-id>` enforces one-PR-per-repo. |
| VIII. Cross-Agent Review | ✅ Pass | `generator_agent !== reviewer_agent` enforced by sources.json validation. |
| IX. sources.json is Law | ✅ Pass | Only repos and paths listed in `sources.json` are fetched. Only `reference_file` paths listed there are written. |
| X. Write Scope — plugins/ Only | ✅ Pass | Validation rule 3 in sources.json schema enforces `reference_file` starts with `plugins/`. Script additionally enforces this at write time. |
| XI. Sparse Checkout | ✅ Pass | Workflow uses `--sparse --filter=blob:none --depth 1`. Full clone fallback is not implemented — failure instead. |
| XII. Fail Visibly | ✅ Pass | Staging directory pattern: no `plugins/` writes until all steps succeed. `exit 1` on any failure. |
| XIII. Reference Docs Are for Agents | ✅ Pass | Generator agent prompt explicitly instructs: precise API signatures, parameter types, concrete examples, no vague summaries. |
| XIV. GitHub CLI for All GitHub API Calls | ✅ Pass | All scripts use `gh api` and `gh repo clone`. No `curl` calls to api.github.com. Private repo support inherent. |
| XV. Version Traceability | ✅ Pass | Generator agent writes traceability frontmatter. Reviewer agent validates it. Missing block = review blocker. |

**Constitution Check: ALL PRINCIPLES PASS. No violations.**

---

## Project Structure

### Documentation (this feature)

```text
specs/001-auto-ref-update/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── workflow-triggers.md    # Trigger interface contract
│   └── agent-prompts.md        # Generator/reviewer prompt contracts
└── tasks.md             # Phase 2 output (/speckit.tasks — not created here)
```

### Source Code (repository root)

```text
sources.json                              # Pipeline configuration (Principle IX)

.github/
└── workflows/
    └── sync-reference-docs.yml           # Main pipeline workflow
# Baselines stored as annotated git tags: refs/tags/ref-update/<repo-id>

scripts/
└── sync/
    ├── validate-sources.sh               # Validate sources.json before any fetch
    ├── fetch-repo.sh                     # Sparse checkout a single source repo
    ├── invoke-agent.sh                   # Call generator or reviewer agent
    └── manage-pr.sh                      # Create or update PR via gh CLI

plugins/gcore-fastedge/                   # WRITE TARGET ONLY (Principle X)
    skills/fastedge-docs/reference/       # Reference files updated by pipeline
    skills/test/reference/                # Test reference files
```

**Structure Decision**: Single-project layout with workflow + scripts. No separate backend/frontend split. Scripts are pure Bash to avoid introducing a Node.js or Python runtime dependency in CI beyond what `claude` CLI requires. The `scripts/sync/` directory is developer infrastructure — it lives at repo root alongside `sources.json`, separate from `plugins/` which is user-facing.

---

## Complexity Tracking

> No Constitution Check violations were found. This table is empty by design.

---

## Implementation Phases

### Phase A: Foundation (prerequisites for everything else)

1. **`sources.json`** — create the initial configuration file with the four repos from the schema example (fastedge-sdk-js, fastedge-sdk-rust, fastedge-test, FastEdge-examples). This is the gating deliverable; nothing else runs without it.

2. **`scripts/sync/validate-sources.sh`** — implement all 6 validation rules from the schema doc. Exit 1 on any violation. Called first in the workflow before any fetch.

### Phase B: Fetch Layer

4. **`scripts/sync/fetch-repo.sh`** — implement sparse checkout using the research-confirmed sequence:
   - Resolve `latest-release` ref via GitHub releases API
   - Clone with `--filter=blob:none --no-checkout --depth 1 --sparse`
   - `git sparse-checkout set --no-cone` with paths from `sources.json`
   - Compare HEAD commit to baseline; output `CHANGED=true/false`
   - Exit 1 (not fallback to full clone) if sparse checkout fails

### Phase C: Agent Layer

5. **`scripts/sync/invoke-agent.sh`** — implement the two-role invocation:
   - Generator role: builds structured prompt with existing file content + source material → calls `claude -p` → validates output non-empty and frontmatter present
   - Reviewer role: builds evaluation prompt with generator output + source → calls OpenAI API via curl → parses `VERDICT:` and `FINDINGS:` → exits 2 if format invalid
   - Dispatches to correct API based on `--agent` argument
   - Writes output to `--output-file`

### Phase D: PR Layer

6. **`scripts/sync/manage-pr.sh`** — implement create-or-update:
   - Branch: `auto-ref-update/<repo-id>` (stable, reused across runs)
   - Check existence: `gh pr list --head <branch> --json number -q '.[0].number'`
   - Create or update PR body with source metadata + review findings
   - Add `needs-review` label if verdict is REJECT; add only `auto-ref-update` if ACCEPT
   - Pre-checks that required labels exist in repo; creates them if missing

### Phase E: Main Workflow

7. **`.github/workflows/sync-reference-docs.yml`** — wire everything together:
   - Triggers: `workflow_dispatch` (with `source_repo_id` and `dry_run` inputs) + `repository_dispatch` (event_type: `fastedge-ref-update`)
   - Install step: `npm install -g @anthropic-ai/claude-code`
   - Per-repo loop: validate → fetch → for each UpdateEntry → generate → review → stage writes → if all succeed → write to plugins/ → open/update PR → update baseline
   - Staging pattern: all writes go to temp dir; atomic move to plugins/ only on full success
   - Step summary: write outcome table to `$GITHUB_STEP_SUMMARY`
   - Secrets required: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` (GITHUB_TOKEN is built-in)

### Phase F: Observability

8. **Update `context/REFERENCE_MATERIAL.md`** — replace the "Future Enhancement" section with a description of the implemented pipeline, pointing to `sources.json` and the workflow.

9. **Create required GitHub labels** — `auto-ref-update` and `needs-review` must exist in the repo. Document in quickstart (already done) and add a one-time setup step to the workflow that ensures they exist.

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Bash scripts, not Node.js | Zero additional runtime deps beyond `claude` CLI and pre-installed tools; readable and auditable without toolchain setup |
| Stable branch name `auto-ref-update/<repo-id>` | Allows PR update-in-place across re-runs without accumulating stale PR branches |
| Staging directory before plugins/ write | Implements Principle XII atomically; no partial writes possible |
| Baseline tracked via annotated git tags `ref-update/<repo-id>` | Branchless and atomic — no commit needed; avoids polluting PR diffs or requiring write access to protected `main`; tag message stores ref name and timestamp alongside commit SHA |
| Non-cone sparse checkout mode | Supports file-level paths like `README.md` which cone mode cannot express |
| Reviewer response format is strict (`VERDICT: X\nFINDINGS: Y`) | Deterministic parsing; format violation fails loudly rather than guessing |

---

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Claude CLI API changes break `--output-format json` | Pin `@anthropic-ai/claude-code` to a specific version in the install step; update deliberately |
| Source repo changes `sparse_paths` layout between runs | `validate-sources.sh` runs before every fetch; add a check that declared paths are reachable after sparse checkout |
| Two repos targeting the same reference file create a race in the workflow | Process repos sequentially by default; section ownership rules in sources.json prevent content collision |
| `GITHUB_TOKEN` lacks permission to create PRs or push tags | Document in quickstart that the token needs PR write and tag write permissions; workflow fails visibly if insufficient |
| Annotated tag message is corrupted or unreadable on next run | Treat missing/unreadable tag as a first-run (process everything); tag is recreated on success |
| Reviewer returns malformed output (hallucinated format) | `invoke-agent.sh` exits 2 on parse failure; that repo's pipeline step fails loudly |
