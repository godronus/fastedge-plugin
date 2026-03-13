# Research: Automated Reference Material Update System

**Branch**: `001-auto-ref-update` | **Date**: 2026-03-09

## 1. Claude Code CLI — Non-Interactive Invocation in CI

**Decision**: Use `claude -p "<prompt>"` with `ANTHROPIC_API_KEY` environment variable.

**Rationale**: The `-p` / `--print` flag puts Claude Code into headless mode — it executes the prompt, returns output, and exits without any interactive session. This is the documented path for CI use.

**Concrete pattern**:
```bash
npm install -g @anthropic-ai/claude-code     # install step in workflow
export ANTHROPIC_API_KEY="${{ secrets.ANTHROPIC_API_KEY }}"
result=$(claude -p "$(cat prompt.md)" --output-format json | jq -r '.result')
```

**Alternatives considered**:
- Direct Anthropic REST API via curl — works but lacks file-reading context that Claude Code provides natively
- Actions-specific Anthropic SDK — no official GitHub Action exists; CLI is the canonical path

---

## 2. Review Agent (OpenAI) — Non-Interactive Invocation in CI

**Decision**: Use direct OpenAI REST API via `curl` with `OPENAI_API_KEY`. There is no official OpenAI CLI.

**Rationale**: OpenAI provides no official CLI tool. The REST API is stable, curl is available on all ubuntu-latest runners, and `jq` handles response parsing. This keeps the workflow dependency-free (no Node.js packages needed for the review step).

**Concrete pattern**:
```bash
review_output=$(curl -s https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d "$(jq -n --arg prompt "$REVIEW_PROMPT" \
    '{"model":"gpt-4o","messages":[{"role":"user","content":$prompt}]}')" \
  | jq -r '.choices[0].message.content')
```

**Alternatives considered**:
- Community CLI wrappers (not official, introduce undeclared deps)
- GitHub Copilot API (not publicly available for programmatic invocation)
- Gemini API (similar curl pattern — viable as future reviewer option, same abstraction)

**Note**: `sources.json` `reviewer_agent` field governs which agent is selected per `UpdateEntry`. The workflow's `invoke-agent.sh` dispatches to the correct API based on this value. Adding a new reviewer requires implementing its invocation branch in that script.

---

## 3. PR Create-or-Update Pattern

**Decision**: Use `gh pr list --head <branch>` to check existence, then `gh pr create` or `gh pr edit` conditionally.

**Rationale**: `gh pr create` fails with an error if a PR already exists on the branch. The check-then-act pattern is the standard workaround documented in gh CLI best practices.

**Concrete pattern**:
```bash
PR_NUM=$(gh pr list --head "$BRANCH_NAME" --json number -q '.[0].number')
if [ -z "$PR_NUM" ]; then
  gh pr create --title "$TITLE" --body "$BODY" --label "auto-ref-update"
else
  gh pr edit "$PR_NUM" --body "$BODY"
  gh pr comment "$PR_NUM" --body "$REVIEW_COMMENT"
fi
```

**Auth**: `GH_TOKEN=${{ secrets.GITHUB_TOKEN }}` — the built-in workflow token is sufficient for PRs within the same repo.

**Labels required**: `auto-ref-update` and `needs-review` must be pre-created in the repo. The workflow validates their existence at startup.

---

## 4. Git Sparse Checkout (Cross-Repo, Mid-Workflow)

**Decision**: Use `gh repo clone <url> <dest> -- --filter=blob:none --no-checkout --depth 1 --branch <ref> --sparse` followed by `git sparse-checkout init --no-cone` + `git sparse-checkout set`.

**Rationale**: This minimizes data transferred (partial clone, no blob objects initially, shallow history) while allowing gitignore-style path patterns as required by `sources.json`. Non-cone mode is chosen over cone mode because `sources.json` sparse paths include individual files (e.g., `README.md`, `CHANGELOG.md`) which cone mode cannot express.

`gh repo clone` is preferred over raw `git clone` with an x-access-token URL for two reasons:
1. **Token safety** — `gh` uses its own credential store; the token never appears in the git remote URL, reflog, process list, or CI logs. Embedding `x-access-token:${GITHUB_TOKEN}` in a URL risks leaking the token in verbose git output.
2. **Consistency** — `gh` CLI is already a declared primary dependency (pre-installed on `ubuntu-latest`); there is no additional cost to using it for cloning.

**Concrete sequence**:
```bash
# Ref resolution: for "latest-release", resolve via gh API first
RESOLVED_REF=$(gh api "repos/${OWNER}/${REPO}/releases/latest" --jq '.tag_name')

# Sparse clone via gh (passes git flags after --)
gh repo clone "$REPO_URL" "$CHECKOUT_DIR" -- \
  --filter=blob:none \
  --no-checkout \
  --depth 1 \
  --branch "$RESOLVED_REF"

cd "$CHECKOUT_DIR"

# Root-anchor each path (prefix / prevents matching nested dirs like docs/src/)
git sparse-checkout init --no-cone
git sparse-checkout set "${ANCHORED_PATHS[@]}"
git checkout
```

**Path anchoring**: In no-cone mode, patterns without a leading `/` match at any depth. Each path from `sources.json` is prefixed with `/` before passing to `git sparse-checkout set` so that `src/` matches only the top-level `src/`, not `nested/src/`.

**Alternatives considered**:
- `git clone` with `x-access-token` URL — rejected: token leakage risk in git internals and CI logs
- `actions/checkout` with `sparse-checkout` option — only works for the workflow's own repo, not external repos
- Full clone — rejected per Constitution Principle XI
- Cone mode — rejected because file-level sparse paths (e.g., `README.md`) are not expressible in cone mode

---

## 5. Baseline Tracking Strategy

**Decision**: Use one annotated git tag per source repo, force-updated in the plugin repo after each successful run. Tag naming: `refs/tags/ref-update/<repo-id>`. Tag message encodes the source commit SHA, ref name, and timestamp.

**Rationale**: Baseline tracking needs to persist across workflow runs without requiring a commit to any branch. A committed file (e.g., `ref-baselines.json`) would need to go somewhere — `main` is protected, and the PR branch would pollute the PR diff with unrelated baseline commits. Git tags are branchless and atomic: `git push origin --force refs/tags/ref-update/<repo-id>` records the new baseline without touching any branch. Tag pushes are also safe under concurrent runs (last writer wins, which is acceptable — both runs processed the same commit).

**Tag format**:
```
tag name:    refs/tags/ref-update/fastedge-sdk-js
tag message: v2.1.0 | abc1234def5678 | 2026-03-09T14:30:00Z
             <ref>   | <commit-sha>   | <processed_at>
```

**Check-for-changes sequence**:
```bash
# 1. Get last processed commit from tag message
LAST_MSG=$(git ls-remote origin "refs/tags/ref-update/fastedge-sdk-js")
LAST_SHA=$(echo "$LAST_MSG" | ... parse commit from message ...)

# 2. Resolve current HEAD of source repo sparse paths
CURRENT_SHA=$(git ls-remote https://github.com/G-Core/FastEdge-sdk-js refs/tags/v2.1.0 | awk '{print $1}')

# 3. Skip if identical
[ "$LAST_SHA" = "$CURRENT_SHA" ] && echo "CHANGED=false" || echo "CHANGED=true"
```

**Tag lifecycle**:
- First run (no tag exists): treat as new content, run full pipeline; create tag on success
- Subsequent runs: compare tag message commit SHA to current source HEAD; skip if identical
- On successful PR open: force-push updated tag with new commit SHA, ref, and timestamp

**Alternatives considered and rejected**:
- `ref-baselines.json` committed to a branch — no clean branch to commit to without polluting PR diffs or writing to protected `main`; race condition risk on concurrent runs
- GitHub Actions cache — evictable, not reliable for permanent state
- Repository variables — not designed for frequently-updated per-repo structured data
- One tag per processed commit (append-only) — tags accumulate indefinitely; requires querying and sorting to find "latest" per repo

---

## 6. Workflow Trigger: Manual Dispatch + Repository Dispatch

**Decision**: Support `workflow_dispatch` (manual CLI or GitHub UI) and `repository_dispatch` with `event_type: "fastedge-ref-update"`.

**Rationale**: The spec requires both manual CLI invocation and webhook triggers from source repos. `workflow_dispatch` provides the manual path. `repository_dispatch` is the GitHub-native mechanism for cross-repo webhooks — source repos send the event on release, filtered by `event_type` to avoid unintended triggers.

**Source repo webhook payload**:
```json
{
  "event_type": "fastedge-ref-update",
  "client_payload": {
    "source_repo_id": "fastedge-sdk-js",
    "ref": "v2.2.0",
    "commit": "abc1234"
  }
}
```

When triggered by `repository_dispatch`, the workflow processes only the repo identified in `client_payload.source_repo_id`. When triggered by `workflow_dispatch`, it processes all repos in `sources.json`.

---

## 7. Fail-Visible Strategy (Principle XII)

**Decision**: Use a staging directory pattern — all file writes go to a temp directory first. Only after ALL steps for a repo succeed are files moved to `plugins/`. If any step fails, `exit 1` is called before any write to `plugins/`.

**Rationale**: This implements the "no partial updates" requirement from Principle XII. If the review agent fails or the traceability frontmatter cannot be written, the temp dir is discarded and no `plugins/` file is touched.

**US3 / Principle XII reconciliation**: The `exit 1` is scoped to the per-repo processing function. The top-level workflow loop catches the non-zero exit, records the failure in the run summary (`$GITHUB_STEP_SUMMARY`), and continues to the next repo — satisfying FR-005 (US3: individual repo failure must not block others) without violating Principle XII (no partial writes to `plugins/`). The two principles operate at different scopes: Principle XII governs file atomicity within a single repo's processing; US3 governs pipeline resilience across repos.

**Alternatives considered**:
- Write files then revert on failure — more complex, risks edge cases where revert also fails
- Separate git worktree — more isolation but adds complexity for a single-script flow
