# Tasks: Automated Reference Material Update System

**Input**: Design documents from `specs/001-auto-ref-update/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.
**Tests**: TDD required for T004–T009. See testing mandate in Phase 3.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the file structure and initial configuration. No logic yet.

- [x] T001 Create directory structure: `scripts/sync/` and `.github/workflows/` at repo root
- [x] T002 Create `sources.json` at repo root with initial 3 entries (fastedge-sdk-js, fastedge-sdk-rust, fastedge-test; FastEdge-examples omitted — repo deprecated)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: `validate-sources.sh` must exist and pass before any fetch runs. Every pipeline invocation calls this first.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T003 Implement `scripts/sync/validate-sources.sh`: enforce all 6 rules from `context/sources-json-schema.md` (unique IDs, reachable URLs, `reference_file` starts with `plugins/`, `generator_agent !== reviewer_agent`, section declared when multiple entries target the same file, no build artifact paths in `sparse_paths`); exit 1 with a specific error message on any failure; accept path to `sources.json` as first argument

**Checkpoint**: Run `scripts/sync/validate-sources.sh sources.json` against the file from T002 and confirm it exits 0.

---

## Phase 3: User Story 1 — Full Pipeline Run Produces PRs (Priority: P1) 🎯 MVP

**Goal**: A triggered run fetches source repos, generates updated reference docs, runs a reviewer, and opens one PR per changed repo. This phase delivers the entire working pipeline.

**Independent Test**: Run `gh workflow run sync-reference-docs.yml -f dry_run=true`. Inspect `$GITHUB_STEP_SUMMARY` output — it must show one row per source repo with outcome (changed / skipped), and no PRs or file writes when dry_run is true. Then run without dry_run against a repo known to have new content and confirm exactly one PR is opened containing updated reference content and review findings.

### Testing Mandate (TDD)

**No implementation task in this phase may be marked `[x]` complete until its companion test task also passes.**

**Test structure**:
```
scripts/sync/tests/
├── mocks/                    ← PATH-shimmable fakes for gh and git subcommands
│   ├── gh                    ← fake gh: returns canned JSON per subcommand
│   └── git                   ← fake git ls-remote / cat-file (baseline tests only)
├── test-fetch-repo.sh        ← tests for T004 + T005 parse logic
├── test-section-splice.sh    ← tests for T008 (most thorough)
└── test-verdict-parse.sh     ← tests for T007 VERDICT/FINDINGS parse logic
```

**Per-script testing policy** (apply when implementing each task):
- **T004** `fetch-repo.sh`: test arg validation, path-anchoring logic (no network — use local bare git repo), CHANGED true/false detection
- **T005** baseline helpers: test pipe-delimited message parse (empty tag, malformed message, valid message); tag write command is integration-only — no unit test needed
- **T006** generator: **no unit tests required** — agent prompt assembly is not meaningfully testable without live credentials; dry_run workflow run is the validation gate
- **T007** reviewer: test VERDICT/FINDINGS parse logic only (regex against canned response strings); skip API call testing
- **T008** section-splice: **comprehensive tests required** — test: section found mid-file, section at EOF, section not found (must exit 1), multiple sections preserved, frontmatter updated for one repo while preserving other repos' entries
- **T009** `manage-pr.sh`: **no unit tests required** — mostly `gh` CLI orchestration; dry_run workflow run is the validation gate

**Mock pattern**: place thin shell scripts in `scripts/sync/tests/mocks/` and prepend that directory to `PATH` at the top of each test file. Mocks inspect `$1`/`$2` to return canned output and exit codes.

### Implementation for User Story 1

- [x] T004 [P] [US1] Implement `scripts/sync/fetch-repo.sh`: resolve `"latest-release"` ref via `gh api repos/:owner/:repo/releases/latest`, clone with `gh repo clone -- --filter=blob:none --no-checkout --depth 1`, run `git sparse-checkout init --no-cone` then `git sparse-checkout set` with root-anchored paths (prefix each path with `/` if not already anchored — unanchored patterns match at any depth), complete checkout, capture HEAD commit SHA, emit `CHANGED=true/false` by comparing HEAD SHA against the baseline tag (see T005); accept arguments: `--repo-url`, `--sparse-paths` (space-separated), `--repo-id`, `--ref`, `--checkout-dir`. **Tests required**: see T004a.
- [x] T004a [US1] Write `scripts/sync/tests/test-fetch-repo.sh`: (1) missing args → exit 1 listing all missing flags; (2) unknown arg → exit 1; (3) path-anchoring: given `sparse-paths "src/ docs/README.md"`, assert anchored array is `["/src/" "/docs/README.md"]` — test without network using a local bare git repo as the remote; (4) CHANGED=true when no baseline exists; (5) CHANGED=false when HEAD SHA matches mocked baseline; (6) CHANGED=true when HEAD SHA differs from mocked baseline. **Must pass before T004 is marked complete.**
- [x] T005 [P] [US1] Implement baseline tag read/write helpers in `scripts/sync/fetch-repo.sh`: read annotated tag `refs/tags/ref-update/<repo-id>` via `git ls-remote origin` + `git fetch` + `git cat-file tag FETCH_HEAD`, parse the pipe-delimited message (`<ref> | <commit-sha> | <timestamp>`) to extract last-processed commit SHA; after successful pipeline run, write updated tag with `git tag -f -a "ref-update/$REPO_ID" -m "$REF | $COMMIT | $NOW"` and force-push to origin. Extract `read_baseline_commit()` into a clearly named standalone function (inlined in T004 as scaffolding). **Tests required**: see T005a.
- [x] T005a [US1] Add baseline parse tests to `scripts/sync/tests/test-fetch-repo.sh`: (1) valid message `"v2.0.0 | abc123 | 2026-03-09T00:00:00Z"` → extracted SHA is `abc123`; (2) message with extra whitespace around pipes → SHA still extracted correctly; (3) empty tag message → function returns empty string (not error); (4) no remote tag (ls-remote returns empty) → function returns empty string. Use `mocks/git` to stub `ls-remote` and `cat-file` responses. **Must pass before T005 is marked complete.**
- [x] T006 [P] [US1] Implement `scripts/sync/invoke-agent.sh` generator role (`--role generator`): load existing reference file content (full file or named section per `--section`), load all fetched source files from `--source-dir` with filename headers, build structured prompt instructing the agent to produce precise agent-consumable Markdown with traceability frontmatter (format from `context/sources-json-schema.md`), call `claude -p "$(cat prompt.md)" --output-format json`, extract `.result`, validate non-empty and frontmatter block parseable; write output to `--output-file`; exit 1 on agent error. **Note**: T008 also writes to `invoke-agent.sh` — implement as separate named functions within the same script. **No unit tests required** — validation gate is `dry_run=true` workflow run.
- [x] T007 [US1] Implement `scripts/sync/invoke-agent.sh` reviewer role (`--role reviewer`): load generator output from `--input-file` and source files from `--source-dir`, embed review criteria verbatim from `specs/001-auto-ref-update/contracts/agent-prompts.md`, call OpenAI API via `curl` with `OPENAI_API_KEY` (model: gpt-4o — OpenAI is not a GitHub API; `gh` CLI does not apply here), parse `VERDICT: ACCEPT|REJECT` and `FINDINGS:` block from response; write parsed verdict and findings to `--output-file`; exit 1 on API error, exit 2 if response format does not match expected pattern. **Depends on T006**. **Tests required**: see T007a.
- [x] T007a [US1] Write `scripts/sync/tests/test-verdict-parse.sh`: test the `parse_verdict()` function in isolation by sourcing `invoke-agent.sh` and passing canned response strings: (1) well-formed `VERDICT: ACCEPT\nFINDINGS: ...` → verdict=ACCEPT, findings extracted; (2) well-formed `VERDICT: REJECT\nFINDINGS: ...` → verdict=REJECT; (3) response missing VERDICT line → exit 2; (4) response with VERDICT but no FINDINGS block → exit 2; (5) multi-line FINDINGS block preserved verbatim. **Must pass before T007 is marked complete.**
- [x] T008 [P] [US1] Implement section-splicing logic in `scripts/sync/invoke-agent.sh`: when `--section` is provided, locate the `## <section>` heading boundary in the existing reference file, identify end of section as next `##`-level heading or EOF, splice generator output into that region only, preserve all other sections verbatim, update only the contributing repo's entry in the traceability frontmatter block while preserving other repos' entries; exit 1 loudly if section heading is not found. **Note**: implement `splice_section()` as a standalone named function to avoid conflicts with T006 work. **Tests required**: see T008a.
- [x] T008a [US1] Write `scripts/sync/tests/test-section-splice.sh` — **most thorough test file**: (1) section found mid-file → only that section replaced, surrounding sections byte-identical; (2) section is last in file (EOF boundary) → replaced correctly, no trailing garbage; (3) section not found → exit 1 with message naming the missing heading; (4) multiple `##` sections in file → only target section changed; (5) frontmatter has two repos → after splice, only the contributing repo's entry is updated, the other is preserved verbatim; (6) generator output is empty → exit 1 (guard against writing blank section). Use fixture markdown files in `scripts/sync/tests/fixtures/section-splice/`. **Must pass before T008 is marked complete.**
- [x] T009 [P] [US1] Implement `scripts/sync/manage-pr.sh`: use branch name `auto-ref-update/<repo-id>` (stable, reused across runs); check for existing PR with `gh pr list --head <branch> --json number -q '.[0].number'`; if no PR: `gh pr create --title "auto: update reference docs from <repo-id> (<ref>)" --label "auto-ref-update" --body <body>`; if PR exists: `gh pr edit <num> --body <body>`; body must include source repo, ref, commit, list of changed files, and review agent verdict + findings per the PR shape in `specs/001-auto-ref-update/data-model.md`; accept `--repo-id`, `--ref`, `--commit`, `--changed-files`, `--verdict`, `--findings` arguments. **No unit tests required** — validation gate is `dry_run=true` workflow run.
- [x] T010 [US1] Implement `.github/workflows/sync-reference-docs.yml`: add `workflow_dispatch` trigger with `source_repo_id` (string, optional) and `dry_run` (boolean, default false) inputs; add install step (`npm install -g @anthropic-ai/claude-code@2.1.71` — **pin the version** to avoid silent breakage from CLI output format changes; see plan risk table); loop over all repos in `sources.json` (or only `source_repo_id` if set); for each repo call T003→T004→T006→T007→T008→T009 in sequence; use staging directory pattern (all writes to `$TMPDIR/<repo-id>/`; atomic `cp` to `plugins/` only after all steps for that repo succeed); update baseline tag (T005) after successful file write; write outcome row per repo to `$GITHUB_STEP_SUMMARY`; declare `ANTHROPIC_API_KEY` and `OPENAI_API_KEY` as required env secrets
- [x] T011 [US1] Wire `dry_run` guard in `.github/workflows/sync-reference-docs.yml`: when `dry_run=true`, skip all writes to `plugins/`, skip `gh pr create/edit` calls, and skip baseline tag updates; all preceding steps (fetch, generate, review) still run so the summary accurately reflects what would happen

**Checkpoint**: US1 is complete when `gh workflow run sync-reference-docs.yml` triggers successfully, the summary shows per-repo outcomes, and at least one PR is opened with reference doc changes and review findings in the body.

---

## Phase 4: User Story 2 — Sparse Checkout Fetches Only Required Paths (Priority: P2)

**Goal**: `fetch-repo.sh` hard-fails rather than falling back to a full clone when sparse checkout cannot be satisfied. Verifies post-checkout that only declared paths are present.

**Independent Test**: Configure a `sparse_paths` entry that includes one valid path and one nonexistent path. Run `fetch-repo.sh` for that repo — it must exit 1 with a clear error, and no full checkout of the repo must exist in the checkout dir.

### Implementation for User Story 2

- [x] T012 [US2] Add hard-failure guard in `scripts/sync/fetch-repo.sh`: after `git sparse-checkout set`, verify the command exited 0; if not, exit 1 with message identifying the repo ID and failing path; do not retry with a full clone under any circumstance (enforces Constitution Principle XI)
- [x] T013 [P] [US2] Add post-checkout path assertion in `scripts/sync/fetch-repo.sh`: after `git checkout`, enumerate all tracked files in the working tree with `git ls-files`; assert that every file path matches at least one pattern in `sparse_paths`; if any file outside declared paths is present, exit 1 with the unexpected paths listed

**Checkpoint**: US2 is complete when running `fetch-repo.sh` with a repo that has been fully cloned in a prior test shows only declared paths, and a bad sparse path causes immediate exit 1.

---

## Phase 5: User Story 3 — Individual Repo Failure Does Not Block Others (Priority: P3)

**Goal**: A failure in one repo's processing step is isolated; the workflow loop continues and opens PRs for all other repos that succeed. Also adds the webhook trigger for cross-repo automation.

**Independent Test**: Add a deliberately invalid `github_url` as a second entry in `sources.json`, trigger the workflow, and confirm the step summary shows one failed row and one (or more) successful rows, and that PRs are opened for the valid repos.

### Implementation for User Story 3

- [x] T014 [US3] Refactor per-repo processing block in `.github/workflows/sync-reference-docs.yml` into an isolated Bash function `process_repo()`; wrap each call in the loop with `if ! process_repo "$REPO_ID"; then record_failure "$REPO_ID" "$?"; fi` so a non-zero exit from any step inside `process_repo` is caught, recorded, and the loop advances to the next repo without exiting the entire workflow
- [x] T015 [P] [US3] Add `repository_dispatch` trigger to `.github/workflows/sync-reference-docs.yml` with `event_type: fastedge-ref-update`; parse `github.event.client_payload` fields (`source_repo_id`, `ref`, `commit`) per the trigger contract in `specs/001-auto-ref-update/contracts/workflow-triggers.md`; when triggered by dispatch, process only the identified repo; validate `source_repo_id` exists in `sources.json` and exit 1 if not

**Checkpoint**: US3 is complete when the workflow runs with a mix of valid and invalid repos and produces a summary showing both failure rows and PR links for successful repos.

---

## Phase 6: User Story 4 — Review Agent Blocks Low-Quality Output (Priority: P3)

**Goal**: When the reviewer returns `VERDICT: REJECT`, the PR is still opened but labelled `needs-review`. When the reviewer returns `VERDICT: ACCEPT` on a subsequent re-run, the label is removed.

**Independent Test**: Supply the generator with source content known to be poor quality (e.g., an empty source dir). Confirm the opened PR carries the `needs-review` label and the PR body shows `VERDICT: REJECT`. Re-run with good source content; confirm the PR body is updated, `needs-review` is removed, and `auto-ref-update` label remains.

### Implementation for User Story 4

- [x] T016 [US4] Add `needs-review` label logic to `scripts/sync/manage-pr.sh`: when `--verdict REJECT`, add `needs-review` label (`gh pr edit --add-label needs-review`); when `--verdict ACCEPT` on an existing PR that already has `needs-review`, remove it (`gh pr edit --remove-label needs-review`)
- [x] T017 [P] [US4] Add required-label pre-check to `scripts/sync/manage-pr.sh`: before any `gh pr create/edit`, verify `auto-ref-update` and `needs-review` labels exist in the repo via `gh label list --json name`; create any missing labels with `gh label create` (colour `#0075ca` for `auto-ref-update`, `#e4e669` for `needs-review`) so the workflow never fails on a label-not-found error

**Checkpoint**: US4 is complete when a reject verdict produces a `needs-review`-labelled PR, and a subsequent accept verdict removes the label.

---

## Phase 7a: Synthesis Quality

**Purpose**: Give the generator agent per-reference-file synthesis instructions so output is shaped correctly for each target document, not just generically accurate.

**Design**: A new optional `intent_file` field in each `UpdateEntry` points to a Markdown file under `agent-intent-skills/<repo-id>/<filename>.md`. The generator prompt injects this content verbatim as a `## Synthesis Instructions` section. Intent files live in the repo as plain Markdown — no build step, no inline JSON strings.

```
agent-intent-skills/
└── fastedge-test/
    ├── testing-api.md       ← intent for skills/test/reference/testing-api.md
    ├── test-config.md       ← intent for skills/test/reference/test-config.md
    └── vscode-debugger.md   ← intent for skills/test/reference/vscode-debugger.md
```

**Prerequisites**: Phase 3 complete (invoke-agent.sh and process-repos.sh exist).

- [x] T_7a1 Add validation rule 7 to `scripts/sync/validate-sources.sh`: if `intent_file` is specified in an `UpdateEntry`, assert the file exists relative to repo root; exit 1 naming the missing file if not found. **No new test file needed** — extend the existing validate-sources test or add an inline check.
- [x] T_7a2 [P] Update `scripts/sync/invoke-agent.sh` `_build_generator_prompt()`: accept optional `--intent-file` argument; when provided, load the file content and append as a `## Synthesis Instructions` block after the existing instructions in the prompt. When not provided, prompt is unchanged.
- [x] T_7a3 [P] Update `scripts/sync/process-repos.sh` `run_agents()`: read `intent_file` from each `UpdateEntry` via `jq -r ".repos[$idx].updates[$j].intent_file // empty"`; when non-empty, pass `--intent-file "$intent_file"` to the generator invocation.

**Checkpoint**: Run `validate-sources.sh sources.json` — must pass (all intent_file paths exist). Run the workflow with `dry_run=true` against `fastedge-test` and confirm the generator prompt in the logs contains the synthesis instructions block.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation updates, hardening, and observability improvements that span all stories.

- [x] T018 Update `context/REFERENCE_MATERIAL.md`: replace the entire "Future Enhancement: GitHub Actions Sync Pipeline" section with a description of the implemented pipeline; reference `sources.json`, `.github/workflows/sync-reference-docs.yml`, and `context/sources-json-schema.md` as the three documents a maintainer needs
- [x] T019 [P] Add sources.json validation as the very first step in `.github/workflows/sync-reference-docs.yml` (before `npm install` or any fetch): run `scripts/sync/validate-sources.sh sources.json`; any failure exits the entire workflow run with a descriptive error before any external call is made. **Implemented early (Phase 3).**
- [x] T020 [P] Verify that `GITHUB_TOKEN` permissions in `.github/workflows/sync-reference-docs.yml` cover PR creation and tag push: add explicit `permissions:` block with `contents: write` (for tag push), `pull-requests: write`; document required PAT scopes in `specs/001-auto-ref-update/quickstart.md` for users who run the workflow with a custom token. **Implemented early (Phase 3).**

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2 — implementation tasks can begin once validate-sources.sh is done; each task is complete only when its companion test task (T004a, T005a, T007a, T008a) also passes
- **US2 (Phase 4)**: Depends on T004 (fetch-repo.sh base implementation) — hardening additions to an existing script
- **US3 (Phase 5)**: Depends on T010 (workflow exists) — restructures existing loop
- **US4 (Phase 6)**: Depends on T007 (reviewer verdict available) and T009 (manage-pr.sh exists)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2 — no dependency on US2/US3/US4
- **US2 (P2)**: Can start after T004 within Phase 3 — only modifies `fetch-repo.sh`
- **US3 (P3)**: Can start after T010 within Phase 3 — only modifies the workflow loop
- **US4 (P3)**: Can start after T007 and T009 within Phase 3 — only modifies `manage-pr.sh`

### Within Phase 3 (US1)

```
T004 (fetch-repo.sh base) ──> T004a (tests) ─┐
T005 (baseline tags)       ──> T005a (tests) ─┤
T006 (invoke generator)    ─────────────────  ─┤  ← no test task
T008 (section splicing)    ──> T008a (tests) ─┤
T009 (manage-pr.sh base)   ─────────────────  ─┘  ← no test task
     │
T006 ──> T007 (invoke reviewer) ──> T007a (tests) ──┐
                                                     ├──> T010 (workflow) ──> T011 (dry_run)
T004+T004a, T005+T005a, T008+T008a, T009 ───────────┘
```

T007 depends on T006. T010 depends on all implementation tasks AND their passing test tasks. T011 is a simple guard added to T010.

### Parallel Opportunities

- T004, T005, T006, T008, T009 can all be worked in parallel within Phase 3 (different files)
- T004a, T005a can be worked in parallel (both in `test-fetch-repo.sh` but cover distinct functions)
- T007a and T008a can begin once their implementation tasks are written (before T010)
- T012 and T013 are parallel within Phase 4 (both in fetch-repo.sh but independent additions)
- T014 and T015 are parallel within Phase 5 (different trigger paths in the workflow)
- T016 and T017 are parallel within Phase 6 (different sections of manage-pr.sh)
- T018, T019, T020 are parallel within Phase 7

---

## Parallel Example: User Story 1

```
# These can all be started at the same time:
Task T004:  "Implement fetch-repo.sh"
Task T004a: "Write tests for fetch-repo.sh — arg validation, path anchoring, CHANGED logic"
Task T005:  "Implement baseline tag helpers in fetch-repo.sh"
Task T005a: "Write parse tests for baseline tag message extraction"
Task T006:  "Implement invoke-agent.sh generator role"
Task T008:  "Implement section-splicing logic in invoke-agent.sh"
Task T008a: "Write comprehensive tests for splice_section() — all edge cases"
Task T009:  "Implement manage-pr.sh"

# Then, once T006 is done:
Task T007:  "Implement invoke-agent.sh reviewer role"
Task T007a: "Write verdict/findings parse tests"

# Finally, once all scripts + tests pass:
Task T010: "Implement sync-reference-docs.yml wiring all scripts together"
Task T011: "Wire dry_run guard in sync-reference-docs.yml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001–T002)
2. Complete Phase 2: Foundational (T003) — CRITICAL BLOCKER
3. Complete Phase 3: User Story 1 (T004–T011, including test tasks T004a, T005a, T007a, T008a)
4. **STOP and VALIDATE**: trigger `workflow_dispatch` with `dry_run=true`, inspect summary, then without dry_run against a real repo
5. The pipeline is now live and delivering value — PRs will be opened automatically

### Incremental Delivery

1. Setup + Foundational → `sources.json` valid, validate script working
2. US1 complete → full pipeline live, PRs opening, human reviewers can start using it
3. US2 complete → sparse checkout hard-enforced, no risk of full-clone accidents
4. US3 + US4 complete → resilience and quality gate fully operational
5. Polish → docs updated, permissions hardened

### Notes

- Scripts in `scripts/sync/` are standalone — test each independently before wiring into the workflow
- The `dry_run=true` flag is the primary safety mechanism during development; use it for all testing until confident
- The annotated baseline tag is the only persistent state — inspectable at any time with `git ls-remote origin 'refs/tags/ref-update/*'`
- Constitution Principles IX and X are enforced mechanically: `validate-sources.sh` checks `plugins/` prefix (Principle X), and `fetch-repo.sh` only fetches paths in `sources.json` (Principle IX)
