# Quickstart: Automated Reference Material Update System

**Branch**: `001-auto-ref-update` | **Date**: 2026-03-09

---

## What This System Does

When a source repo (like `FastEdge-sdk-js`) publishes a new release, or when a maintainer triggers it manually, this system:

1. Fetches only the declared paths from the source repo (sparse checkout)
2. Runs a generator AI agent to update the relevant reference docs in `plugins/`
3. Runs a reviewer AI agent to evaluate the output
4. Opens one pull request per changed source repo for human review and merge

---

## Running a Manual Update

```bash
# Trigger an update for all source repos
gh workflow run sync-reference-docs.yml

# Trigger an update for one specific repo
gh workflow run sync-reference-docs.yml -f source_repo_id=fastedge-sdk-js

# Dry run (no files written, no PRs opened)
gh workflow run sync-reference-docs.yml -f dry_run=true
```

---

## Adding a New Source Repo

1. Edit `sources.json` and add a new `RepoEntry`:

```json
{
  "id": "my-new-repo",
  "github_url": "https://github.com/G-Core/my-new-repo",
  "sparse_paths": ["src/", "README.md"],
  "ref": "latest-release",
  "trigger": "release",
  "updates": [
    {
      "reference_file": "plugins/gcore-fastedge/skills/fastedge-docs/reference/my-doc.md",
      "generator_agent": "claude",
      "reviewer_agent": "codex"
    }
  ]
}
```

2. Create the target reference file (empty or with placeholder) at the declared path under `plugins/`.
3. Commit `sources.json` and the new file to `main`.
4. The next pipeline run will process it.

**Rules enforced automatically**:
- `reference_file` must start with `plugins/` (Principle X)
- `generator_agent` must differ from `reviewer_agent` (Principle VIII)
- `sparse_paths` must not include build artifacts (Principle XI)

---

## Adding Webhook Support to a Source Repo

To have a source repo automatically trigger the pipeline on new releases, add this workflow step to the source repo's release workflow:

```yaml
- name: Trigger fastedge-plugin reference update
  run: |
    curl -X POST \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${{ secrets.FASTEDGE_PLUGIN_DISPATCH_TOKEN }}" \
      https://api.github.com/repos/G-Core/fastedge-plugin/dispatches \
      -d '{
        "event_type": "fastedge-ref-update",
        "client_payload": {
          "source_repo_id": "my-new-repo",
          "ref": "${{ github.ref_name }}",
          "commit": "${{ github.sha }}"
        }
      }'
```

The `FASTEDGE_PLUGIN_DISPATCH_TOKEN` secret must be a PAT with `repo` scope stored in the source repo's secrets.

---

## Required Repository Secrets

| Secret | Used by | Description |
|--------|---------|-------------|
| `ANTHROPIC_API_KEY` | Generator/reviewer (when `agent: claude`) | Anthropic API key for Claude invocations |
| `OPENAI_API_KEY` | Reviewer (when `agent: codex`) | OpenAI API key for GPT-4o invocations |
| `GITHUB_TOKEN` | Built-in | Used for `gh` CLI PR operations and baseline tag pushes — needs PR write + tag write permissions |

**Baseline tracking**: The pipeline records the last-processed commit per source repo as an annotated git tag in this repo (`refs/tags/ref-update/<repo-id>`). No file commits are needed. To inspect baselines:
```bash
git ls-remote origin 'refs/tags/ref-update/*'
```

---

## Reviewing an Auto-Generated PR

Every auto-generated PR:
- Is labelled `auto-ref-update`
- Contains the source repo, ref, and commit in the PR body
- Contains the reviewer agent's verdict and findings
- If labelled `needs-review`: the reviewer raised concerns; check the findings before merging

Human reviewers should:
1. Check the reviewer agent's findings in the PR body
2. Verify the traceability frontmatter at the top of changed files
3. Optionally: diff against the source repo content directly
4. Merge if satisfied; close if the update is incorrect

---

## Checking Pipeline Run Results

After any run, the GitHub Actions summary for that workflow run shows a table:

```
| Source Repo       | Outcome   | Ref    | PR                    |
|-------------------|-----------|--------|-----------------------|
| fastedge-sdk-js   | ✅ PR #42 | v2.1.0 | https://github.com/.. |
| fastedge-sdk-rust | ⏭ skipped | v0.4.1 | no changes            |
```

Failed repos are listed with the specific failing step.
