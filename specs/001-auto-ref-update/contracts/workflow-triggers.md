# Contract: Workflow Trigger Interfaces

**Feature**: `001-auto-ref-update` | **Date**: 2026-03-09

The `sync-reference-docs` workflow exposes two trigger interfaces.

---

## Trigger 1: Manual Dispatch (`workflow_dispatch`)

**Invoked by**: Any user with write access to the repo, via GitHub Actions UI or CLI.

**CLI invocation**:
```bash
gh workflow run sync-reference-docs.yml
# optionally with a specific repo filter:
gh workflow run sync-reference-docs.yml -f source_repo_id=fastedge-sdk-js
```

**Inputs**:

| Input | Type | Required | Description |
|-------|------|----------|-------------|
| `source_repo_id` | string | No | If set, process only this repo ID. If omitted, process all repos in `sources.json`. |
| `dry_run` | boolean | No | If `true`, run all steps but do not open or update PRs and do not commit baselines. |

**Behaviour**: Processes repos whose `trigger` is `"schedule"` or `"both"`, plus any repo matching `source_repo_id` regardless of its trigger setting.

---

## Trigger 2: Repository Dispatch (`repository_dispatch`)

**Invoked by**: A source repository sending a `repository_dispatch` event to the `fastedge-plugin` repo.

**Required event type**: `fastedge-ref-update`

**Payload contract**:
```json
{
  "event_type": "fastedge-ref-update",
  "client_payload": {
    "source_repo_id": "fastedge-sdk-js",
    "ref": "v2.2.0",
    "commit": "abc1234def5678abc1234def5678abc1234def56"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `source_repo_id` | string | Yes | Must match an `id` in `sources.json`. Unknown IDs cause a validation failure. |
| `ref` | string | Yes | The release tag or branch ref that triggered the dispatch. |
| `commit` | string | Yes | Full 40-character commit SHA at that ref. |

**Behaviour**: Processes only the repo identified by `source_repo_id`. Repos with `trigger: "schedule"` are not processed even if listed in `sources.json`.

**How source repos send the event**:
```bash
curl -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $FASTEDGE_PLUGIN_DISPATCH_TOKEN" \
  https://api.github.com/repos/G-Core/fastedge-plugin/dispatches \
  -d '{
    "event_type": "fastedge-ref-update",
    "client_payload": {
      "source_repo_id": "fastedge-sdk-js",
      "ref": "v2.2.0",
      "commit": "abc1234..."
    }
  }'
```

The dispatch token (`FASTEDGE_PLUGIN_DISPATCH_TOKEN`) must be a PAT with `repo` scope stored as a secret in the source repo.

---

## Workflow Exit Codes

| Exit Code | Meaning |
|-----------|---------|
| `0` | All processed repos succeeded (or were legitimately skipped) |
| `1` | One or more repos failed; see step summary for details |

A non-zero exit makes the workflow run appear as "failed" in GitHub Actions, which is intentional (Principle XII: fail visibly).
