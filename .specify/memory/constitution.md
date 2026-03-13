<!--
SYNC IMPACT REPORT
==================
Version change: 1.0.0 → 1.1.0 → 1.2.0

Modified principles: None (1.1.0); XIV renumbered to XV (1.2.0)

Added sections:
  - Reference Material Automation (Principles VI–XIV) in 1.1.0
  - Principle XIV: GitHub CLI for All GitHub API Calls added in 1.2.0

Removed sections: None

Templates reviewed:
  ✅ .specify/templates/plan-template.md — Constitution Check gate present; covers Principles I–V;
     new principles VI–XIV are automation-scoped and do not require plan-template changes.
  ✅ .specify/templates/spec-template.md — Scope and requirements sections align; no updates required.
  ✅ .specify/templates/tasks-template.md — Phases and categories align; no updates required.
  ⚠  .specify/templates/commands/ — Directory does not exist; no command templates to review.

Follow-up TODOs:
  - TODO(RATIFICATION_DATE): Date retained from initial fill (2026-03-09); update if a prior adoption
    date exists in git history or team records.
  - Consider adding a sources.json schema reference doc under context/ to support Principle IX.
  - Consider adding command template files under .specify/templates/commands/ as skills grow.
-->

# Gcore FastEdge Plugin Constitution

## Core Principles

### I. Skill-First Design

All plugin capabilities MUST be expressed as Markdown skill prompts loaded by Claude Code.
There is no build step, no compiled output, and no server process. A skill file IS the
deliverable. Adding TypeScript, Python, or shell scripts to implement plugin logic is a
violation of this principle unless the script is invoked by a skill as an external tool
(e.g., `create-fastedge-app`, `fastedge-build`).

**Rationale**: The plugin's portability and zero-dependency installation model depends entirely
on skills being pure Markdown. Any compiled component breaks the "clone and load" guarantee.

### II. Delegate, Don't Duplicate

The scaffold skill MUST delegate project creation to the `create-fastedge-app` CLI. Template
content (package.json, tsconfig.json, Cargo.toml, etc.) MUST NOT be duplicated or regenerated
inside this plugin. The upstream CLI is the single source of truth for all project templates.

Similarly, API endpoint definitions, SDK usage patterns, and build commands MUST live in
`plugins/gcore-fastedge/CLAUDE.md` — not scattered across individual skill files or copied
into new locations.

**Rationale**: Duplication creates drift. When `create-fastedge-app` or the FastEdge API
changes, a single file update MUST be sufficient to keep the plugin correct.

### III. Scope Boundary (NON-NEGOTIABLE)

Claude MUST operate exclusively within the user's active project directory. The following are
never acceptable under any circumstance:

- Any path containing `../` (even one level up)
- Listing or reading the parent directory of the project
- Reading or grepping sibling folders or other projects on disk
- Using workspace root as a search base unless it IS the project root

If information is not present in the current project or in this plugin's knowledge base, Claude
MUST ask the user rather than searching the filesystem.

**Rationale**: Users grant Claude access to their active project, not their entire filesystem.
Violating this boundary is a security and privacy issue, not a convenience trade-off.

### IV. Clarify Before Acting

Before scaffolding or deploying, Claude MUST confirm all three of the following:

1. **App type** — CDN app or HTTP app (use-case descriptions are NOT explicit; always ask)
2. **Language** — determined by type constraints (ask if multiple options exist)
3. **Project name** — required before any scaffold or deploy command runs

Use-case descriptions such as "gateway for CDN resources", "auth for CDN traffic", or
"edge middleware" are ambiguous and MUST trigger a clarifying question, not an assumption.

**Rationale**: Scaffolding the wrong app type (HTTP vs. CDN) or language produces a project
that cannot be corrected without starting over. One clarifying question prevents that failure.

### V. Knowledge Base Integrity

The shared knowledge base in `plugins/gcore-fastedge/CLAUDE.md` is the authoritative source
for API endpoints, SDK imports, build commands, error codes, and authentication patterns.
Content in this file MUST stay aligned with the FastEdge MCP server knowledge base. When the
FastEdge API or SDK changes, this file MUST be updated before any skill is used or released.

Stub reference files under `skills/fastedge-docs/reference/` MUST be filled with accurate
content before being surfaced to users. Empty or placeholder reference files MUST NOT be
presented as authoritative documentation.

**Rationale**: A plugin that gives wrong API information causes silent failures in user
deployments. The knowledge base is the one place where correctness is non-negotiable.

## Reference Material Automation

This section governs the automated system that keeps plugin reference docs current by fetching
from source repositories and opening pull requests for human review.

### VI. PR-Gated — Humans Always Merge

All automated reference material updates MUST go through a pull request. No automated change
merges without explicit human approval. This rule has no exceptions — not for trivial wording
changes, not for patch-level SDK updates, not under time pressure.

**Rationale**: Automation can misinterpret source changes. Human sign-off is the final
correctness gate before users receive updated documentation.

### VII. One PR Per Source Repo

Each source repository that has changes MUST produce exactly one pull request. Changes from
multiple source repos MUST NOT be bundled into a single PR. If three repos have changes,
three separate PRs are opened.

**Rationale**: Bundled PRs obscure provenance and make targeted rollback impossible. One PR
per source means one scope of review and one revert unit.

### VIII. Cross-Agent Review — Never Self-Review

The agent that generates a reference doc update MUST NOT review its own output. A different AI
agent MUST perform the review and post its findings as a PR comment before a human evaluates
the change. A PR with no cross-agent review comment MUST NOT be merged.

**Rationale**: Self-review cannot catch systematic errors in how the generating agent
interpreted the source. An independent reviewer catches class-level mistakes the author
cannot see.

### IX. sources.json is Law

`sources.json` is the single source of truth for what gets fetched, from where, and which
reference files get updated. The automation MUST NOT fetch from any URL or path not listed in
`sources.json`. The automation MUST NOT write to any file not mapped in `sources.json`.
Adding a new source or target file requires a `sources.json` change committed by a human first.

**Rationale**: An unbounded fetch-and-write surface is a security and correctness risk.
`sources.json` makes the automation's scope auditable and version-controlled.

### X. Write Scope — plugins/ Only

Automation MAY ONLY write files within the `plugins/gcore-fastedge/` directory tree. All
other paths in the repository are read-only to automation. Any attempt to write outside this
boundary MUST cause the workflow to fail immediately with no files written.

**Rationale**: Confining writes to the plugin directory prevents automation from accidentally
modifying developer tooling, CI configuration, or other repository infrastructure.

### XI. Sparse Checkout — Never Full Clones

Source repositories MUST be fetched using sparse checkout scoped to the paths declared in
`sources.json`. Full clones of source repositories are never performed. If a required path
cannot be sparse-checked out, the workflow MUST fail rather than fall back to a full clone.

**Rationale**: Full clones of large repositories are slow, wasteful, and expand the blast
radius of any checkout-time error. Sparse checkout enforces that the automation only touches
what `sources.json` declares.

### XII. Fail Visibly — No Silent Degradation

If any step in the automation workflow fails, the entire workflow MUST fail loudly with zero
file changes written. Partial updates — where some reference files are updated and others are
not — are never acceptable. The failure message MUST identify the specific step and source
that caused the failure.

**Rationale**: A partial update produces a plugin with inconsistent reference material, which
is worse than no update. Loud failure with a clear error is always preferable to silent
partial success.

### XIII. Reference Docs Are for Agents

Reference material under `skills/fastedge-docs/reference/` MUST be written for AI agent
consumption. This means: precise API signatures with parameter types and return types, concrete
runnable examples, explicit constraints and error conditions, and version context. Vague
summaries, marketing language, and prose descriptions without specifics are not reference
material and MUST NOT appear in these files.

**Rationale**: The primary consumer of reference files is an AI agent resolving a user query
in real time. Agents need precision, not narrative. Vague content produces vague answers.

### XIV. GitHub CLI for All GitHub API Calls

All scripts in the automation pipeline MUST use the `gh` CLI for GitHub API requests and
repository operations. Direct `curl` calls to `api.github.com` are prohibited. This applies
to: releases API lookups, PR creation and editing, label management, workflow triggers, and
repository cloning.

Use `gh api <endpoint> --jq <filter>` for API queries and `gh repo clone` for clones.
The `gh` CLI handles authentication transparently for both public and private repositories,
eliminating the need to manage `GITHUB_TOKEN` or `Authorization` headers manually.

**Rationale**: Private source repositories are a realistic scenario. `curl`-based API calls
require manual token injection and break on private repos without extra configuration. `gh`
provides uniform auth for all GitHub operations with zero per-script token wiring.

### XV. Version Traceability

Every reference file updated by automation MUST include a frontmatter block at the top of the
file recording:

- `source_repo`: the repository URL the content was drawn from
- `source_ref`: the commit SHA or release tag at the time of fetch
- `updated`: the ISO 8601 date the file was written (YYYY-MM-DD)

A reference file missing this frontmatter block after an automated update is a workflow
defect and MUST NOT be merged.

**Rationale**: Without traceability, there is no way to audit whether a reference file is
current, determine which source version it reflects, or reproduce the fetch that generated it.

## Plugin Architecture Constraints

- Skills MUST be self-contained within their `SKILL.md` file. Cross-skill imports or
  sequential chaining MUST be initiated by the user or by Claude following explicit user
  instructions — not hardcoded into skill prompts.
- The `plugins/gcore-fastedge/` directory is what users receive. The root `CLAUDE.md`,
  `context/`, and `.specify/` directories are developer-only and MUST NOT contain
  user-facing skill logic.
- Version numbers in `.claude-plugin/plugin.json` MUST follow semantic versioning. A skill
  addition is a MINOR bump; a breaking change to skill behavior is a MAJOR bump; wording
  fixes are PATCH.
- Secrets (`GCORE_API_KEY`) MUST never be logged, echoed, or embedded in skill output.
  Skills MUST verify the variable is set and provide a clear error message if it is not.

## Development Workflow

- **To test the plugin**: `claude --plugin-dir /path/to/fastedge-plugin` (session only) or
  `/plugin marketplace add` + `/plugin install` (persistent).
- **Before modifying a skill**: read the existing `SKILL.md` and the shared `CLAUDE.md` to
  understand current behavior and API assumptions.
- **Before adding a new reference file**: verify the content is accurate against the live
  FastEdge API or SDK documentation. Do not create stubs and mark them as complete.
- **To update templates**: read `context/TEMPLATE_STRATEGY.md` before making any changes
  that affect scaffold behavior.
- **Constitution Check (per feature)**: Before beginning implementation on any feature,
  verify the feature does not violate Principles I–XV. Document any justified exceptions in
  the plan's Complexity Tracking table.
- **Before modifying automation**: confirm all changes comply with Principles VI–XV.
  Any automation change that expands fetch scope or write scope MUST update `sources.json`
  first and MUST be reviewed against Principles IX and X explicitly.

## Governance

This constitution supersedes all other development practices and informal conventions for
the `fastedge-plugin` repository. All pull requests MUST be reviewed against these principles
before merge.

**Amendment procedure**: Amendments require (1) a written rationale explaining why the
principle change is necessary, (2) identification of all skills or reference files affected,
and (3) a version bump per semantic versioning rules above. Amendments MUST be committed with
a message of the form: `docs: amend constitution to vX.Y.Z (<summary>)`.

**Compliance review**: Each feature plan (`/speckit.plan` output) MUST include a Constitution
Check gate. Any violation of Principles I–XV that is not documented and justified in the
Complexity Tracking table is a merge blocker.

**Runtime guidance**: For day-to-day development context, refer to `CLAUDE.md` (root,
developer-facing) and `plugins/gcore-fastedge/CLAUDE.md` (user-facing knowledge base).

**Version**: 1.2.0 | **Ratified**: 2026-03-09 | **Last Amended**: 2026-03-10
