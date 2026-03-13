# Feature Specification: Automated Reference Material Update System

**Feature Branch**: `001-auto-ref-update`
**Created**: 2026-03-09
**Status**: Draft
**Input**: User description: "Define the feature specification for the automated reference material update system. The system fetches source repos using sparse checkout, runs an AI agent to update reference docs, runs a different AI agent to review the output, and opens one pull request per changed source repo."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Full Pipeline Run Produces PRs (Priority: P1)

A maintainer triggers the reference update system. The system fetches each configured source repo using sparse checkout, runs the update agent to rewrite the affected reference docs, runs the review agent to validate the output, and opens one pull request per source repo whose content changed.

**Why this priority**: This is the core value proposition — without the end-to-end pipeline working correctly, no other capability is useful.

**Independent Test**: Can be fully tested by triggering the pipeline with two source repos where at least one has new content, and verifying that exactly one PR per changed repo is opened with updated reference docs.

**Acceptance Scenarios**:

1. **Given** source repos are configured and at least one has new content, **When** the update pipeline runs, **Then** one pull request is opened per source repo that produced doc changes, and no PR is opened for repos with no changes.
2. **Given** the pipeline runs successfully, **When** reviewing the opened PRs, **Then** each PR contains only changes derived from its corresponding source repo.
3. **Given** the update agent produces output, **When** the review agent runs, **Then** the review agent's findings are incorporated into the PR before it is opened.

---

### User Story 2 - Sparse Checkout Fetches Only Required Paths (Priority: P2)

The system fetches source repos using sparse checkout — only the paths relevant to reference doc generation are downloaded, not the full repository contents.

**Why this priority**: Sparse checkout is an explicit requirement that directly affects performance and bandwidth when source repos are large. Without it the pipeline is functional but impractical at scale.

**Independent Test**: Can be fully tested by observing that only the declared sparse paths are present locally after fetch; full repo trees must not be checked out.

**Acceptance Scenarios**:

1. **Given** a source repo with many files, **When** the system fetches it, **Then** only the files matching the configured sparse paths are present in the local working copy.
2. **Given** sparse paths are updated in configuration, **When** the next pipeline run fetches that repo, **Then** only the new sparse paths are fetched.

---

### User Story 3 - Individual Source Repo Failure Does Not Block Others (Priority: P3)

If fetching or processing one source repo fails (network error, agent error, no reviewable output), the pipeline continues processing the remaining source repos and opens PRs for those that succeeded.

**Why this priority**: Resilience is important for an automated system that may run unattended, but the core pipeline (P1) must work first.

**Independent Test**: Can be fully tested by configuring one invalid source repo alongside valid ones and verifying PRs are still opened for valid repos while the failure is reported.

**Acceptance Scenarios**:

1. **Given** one source repo is unreachable, **When** the pipeline runs, **Then** that repo is skipped with an error recorded and the remaining repos are processed normally.
2. **Given** the update agent produces no meaningful changes for one repo, **When** the pipeline runs, **Then** no PR is opened for that repo and the outcome is logged.

---

### User Story 4 - Review Agent Blocks Low-Quality Output (Priority: P3)

The review agent evaluates the update agent's output before a PR is opened. If the review agent determines the output does not meet quality criteria, the PR is not opened and the issue is reported.

**Why this priority**: Quality gating via a second agent is a stated architectural requirement. When the review agent rejects the update agent's output, the PR is still opened but labelled "needs-review" with the review agent's findings attached, so human reviewers always see the output and can make the final call.

**Independent Test**: Can be tested by providing the update agent with intentionally bad source material and verifying the review agent's rejection prevents a PR from being opened (or triggers the agreed fallback).

**Acceptance Scenarios**:

1. **Given** the update agent produces output, **When** the review agent runs and determines the content is acceptable, **Then** the PR is opened.
2. **Given** the review agent determines the content does not meet quality criteria, **When** evaluating the update agent's output, **Then** the PR is still opened but labelled "needs-review" and the review agent's findings are attached so human reviewers can assess and decide.

---

### Edge Cases

- What happens when a source repo has no configured sparse paths? (System should reject the configuration, not fetch the entire repo.)
- How does the system detect that a source repo has changed since the last run? (Assumption: git commit hash comparison against a stored baseline.)
- What happens when a PR for the same source repo is already open? (Assumption: system updates the existing PR rather than opening a duplicate.)
- What happens when the review agent is unavailable or times out? (System should fail that repo's pipeline step and report it, not silently skip the review.)
- What if two source repos produce changes to the same reference doc file? (Should be treated as a conflict and reported rather than silently overwriting.)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST fetch each configured source repo using sparse checkout, downloading only the declared paths.
- **FR-002**: System MUST run an update agent against the fetched source content to produce updated reference documentation.
- **FR-003**: System MUST run a review agent against the update agent's output before any pull request is opened.
- **FR-004**: System MUST open exactly one pull request per source repo that produced accepted doc changes; repos with no changes MUST NOT result in a PR.
- **FR-005**: System MUST process each source repo independently so that a failure in one repo does not prevent processing of others.
- **FR-006**: System MUST record and surface the outcome (success, skipped, failed) for each source repo after a pipeline run.
- **FR-007**: System MUST store a baseline reference per source repo (e.g., last-processed commit hash) to determine whether new content exists since the previous run.
- **FR-008**: System MUST detect when a PR for the same source repo is already open and update it rather than opening a duplicate.
- **FR-009**: System MUST support two trigger mechanisms: manual CLI invocation (for on-demand runs) and webhook from a source repo (for automatic runs on source repo push or release events).
- **FR-010**: System MUST make the list of source repos and their sparse paths configurable without code changes.
- **FR-011**: System MUST attach review agent findings to the pull request (as a PR description section or comment) so reviewers can assess quality.

### Key Entities

- **Source Repo**: An external git repository from which reference material is derived. Has a URL, one or more sparse checkout paths, and a last-processed commit baseline.
- **Sparse Path**: A file path or glob pattern within a source repo that limits what is fetched. Belongs to exactly one source repo.
- **Reference Doc**: A documentation file in the plugin repo that is generated or updated from source repo content. May be affected by one or more source repos.
- **Update Agent**: An AI agent instance invoked once per source repo. Receives fetched source content and produces updated reference doc content.
- **Review Agent**: An AI agent instance invoked once per update agent output. Evaluates quality and produces a review verdict and findings.
- **Pipeline Run**: A single execution of the full update workflow across all configured source repos. Has a start time, end time, and per-repo outcomes.
- **Pull Request**: One opened per source repo with accepted changes. Contains updated reference docs and review agent findings.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A complete pipeline run across all configured source repos completes without manual intervention.
- **SC-002**: Each opened pull request contains changes from exactly one source repo and no changes from others.
- **SC-003**: No pull request is opened for a source repo that has no new content since the last run.
- **SC-004**: A failure in any single source repo's processing does not prevent pull requests from being opened for other repos in the same run.
- **SC-005**: Every pipeline run produces a complete audit trail showing the outcome (success/skipped/failed) for each source repo.
- **SC-006**: The review agent's findings are visible on every opened pull request before any human reviewer acts on it.
- **SC-007**: Adding or removing a source repo requires only a configuration change with no modifications to pipeline code.

## Assumptions

- Source repos are hosted on a Git hosting service that supports the PR API used by the pipeline.
- The update agent and review agent are separate AI agent invocations with distinct system prompts; they are not the same agent run twice.
- "Changed" is determined by comparing the HEAD commit hash of the relevant sparse paths against the stored baseline from the previous run.
- If no baseline exists for a source repo (first run), the system treats all content as new and proceeds with the full update pipeline.
- The plugin repo where reference docs live is the same repo that pull requests are opened against.
- Sparse checkout paths are defined per source repo and validated at configuration load time, not at fetch time.
- The review agent produces a verdict (accept / reject) plus optional findings text; the update agent does not read the review agent's output and self-correct (no loopback by default).
