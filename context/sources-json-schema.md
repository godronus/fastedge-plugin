# sources.json Schema Reference

> Supports Constitution Principle IX: `sources.json` is Law.
> This document is the authoritative specification for the `sources.json` manifest.

---

## Purpose

`sources.json` lives at the root of the `fastedge-plugin` repo. It is the **single source of
truth** for:

- Which source repos are fetched during automated runs
- Which paths within each repo are sparse-checked out
- Which reference files get updated as a result
- Which AI agents generate and review each update

No repo is ever fetched and no reference file is ever written unless it appears in this manifest.

---

## File Location

```
fastedge-plugin/
└── sources.json          ← this file governs all automation
```

---

## Top-Level Structure

```json
{
  "version": "1.0",
  "repos": [ ...RepoEntry ]
}
```

| Field     | Type   | Required | Description                                          |
| --------- | ------ | -------- | ---------------------------------------------------- |
| `version` | string | yes      | Schema version. Bump when breaking changes are made. |
| `repos`   | array  | yes      | List of source repos to monitor and fetch from.      |

---

## RepoEntry

```json
{
  "id": "fastedge-sdk-js",
  "github_url": "https://github.com/G-Core/FastEdge-sdk-js",
  "sparse_paths": ["src/", "examples/", "README.md", "CHANGELOG.md"],
  "ref": "latest-release",
  "trigger": "release",
  "updates": [ ...UpdateEntry ]
}
```

| Field          | Type            | Required | Description                                                                                                                                                 |
| -------------- | --------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`           | string          | yes      | Unique identifier for this repo. Used in traceability frontmatter written to reference files. Must be kebab-case.                                           |
| `github_url`   | string          | yes      | Full HTTPS URL of the GitHub repo. No trailing slash.                                                                                                       |
| `sparse_paths` | array\<string\> | yes      | Paths to include in the sparse checkout. Directories must end with `/`. Files are exact paths. Never includes build artifacts, lockfiles, or binary assets. |
| `ref`          | string          | yes      | What to check out. See **Ref Strategy** below.                                                                                                              |
| `trigger`      | string          | yes      | What causes this repo to be fetched. See **Trigger Types** below.                                                                                           |
| `updates`      | array           | yes      | One or more reference file updates this repo drives. Must be non-empty.                                                                                     |

### Ref Strategy

| Value              | Behavior                                                                               |
| ------------------ | -------------------------------------------------------------------------------------- |
| `"latest-release"` | Resolves to the most recent GitHub release tag at run time. Preferred for stable SDKs. |
| `"main"`           | Always fetches the HEAD of the default branch. Use for repos with no release cadence.  |
| `"vX.Y.Z"`         | Pins to a specific release tag. Only use this when a manual pin is intentional.        |

### Trigger Types

| Value        | Behavior                                                                                                                                   |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `"release"`  | Workflow runs when the source repo publishes a new GitHub release (via `repository_dispatch`). Requires the source repo to send the event. |
| `"schedule"` | Workflow runs on the configured cron schedule regardless of releases.                                                                      |
| `"both"`     | Workflow runs on either trigger.                                                                                                           |

---

## UpdateEntry

Each `UpdateEntry` maps a source repo fetch to a specific reference file inside the plugin.

```json
{
  "reference_file": "plugins/gcore-fastedge/skills/fastedge-docs/reference/sdk-reference.md",
  "section": "JavaScript SDK",
  "generator_agent": "claude",
  "reviewer_agent": "codex"
}
```

| Field             | Type   | Required | Description                                                                                                                                                                                                    |
| ----------------- | ------ | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `reference_file`  | string | yes      | Path to the reference file to update, relative to repo root. Must start with `plugins/`. Enforces Constitution Principle X (Write Scope).                                                                      |
| `section`         | string | no       | The named section within the reference file that this repo is responsible for. Required when multiple repos update the same reference file. The generator agent updates only this section, not the full file.  |
| `intent_file`     | string | no       | Path to a Markdown file containing synthesis instructions for the generator agent, relative to repo root. Convention: `agent-intent-skills/<repo-id>/<reference-filename>.md`.                                 |
|                   |        |          | When present, the file content is injected verbatim into the generator prompt as a `## Synthesis Instructions` block. Use this to specify output structure, audience, what to include/exclude, and quality bar |
|                   |        |          | for the target reference file.                                                                                                                                                                                 |
| `generator_agent` | string | yes      | AI agent that generates the updated content. See **Agent Values** below.                                                                                                                                       |
| `reviewer_agent`  | string | yes      | AI agent that reviews the generated content. **Must differ from `generator_agent`.** Enforces Constitution Principle VIII.                                                                                     |

### Agent Values

| Value       | Agent                                     |
| ----------- | ----------------------------------------- |
| `"claude"`  | Anthropic Claude (via Claude Code or API) |
| `"codex"`   | OpenAI Codex / ChatGPT                    |
| `"gemini"`  | Google Gemini                             |
| `"copilot"` | GitHub Copilot                            |

> The CI workflow uses these values to select which agent CLI to invoke. Adding a new agent
> requires a corresponding implementation in the workflow before it can be used here.

---

## Section Ownership Rules

When two or more `UpdateEntry` records point to the same `reference_file`, each **must** declare
a unique `section`. The generator agent receives:

1. The current content of only its owned section
2. The newly fetched source content for its repo
3. An instruction to update only its section, preserving all other sections verbatim

This prevents a JS SDK update from accidentally overwriting Rust SDK content in the same file.

---

## Traceability Frontmatter

Every automated reference file update prepends or updates a frontmatter block at the top of
the file (Constitution Principle XV). The format is:

```markdown
<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-js
      ref: v2.1.0
      commit: abc1234
      updated: 2026-03-10
    - id: fastedge-sdk-rust
      ref: v0.4.1
      commit: def5678
      updated: 2026-03-08
-->
```

The reviewing agent validates this block is present and accurate before approving. A missing or
malformed traceability block is a review blocker.

---

## Validation Rules

The CI workflow validates `sources.json` against these rules before any fetch runs:

1. All `id` values are unique across `repos`
2. All `github_url` values are reachable (HTTP 200)
3. All `reference_file` paths start with `plugins/` (enforces Principle X)
4. No `generator_agent` equals `reviewer_agent` within the same `UpdateEntry` (enforces Principle VIII)
5. Any `reference_file` appearing in multiple `UpdateEntry` records has a `section` defined in all of them
6. No `sparse_paths` entry references a path that would include `node_modules/`, `dist/`, `target/`, or `.git/`
7. If `intent_file` is specified in an `UpdateEntry`, the file must exist relative to repo root at the time of validation

A validation failure aborts the workflow before any sparse checkout begins.

---

## Example: Current Reference File Mapping

Based on the existing reference files in `plugins/gcore-fastedge/skills/`:

| Reference File                      | Source Repo(s)                         | Section(s)                       |
| ----------------------------------- | -------------------------------------- | -------------------------------- |
| `sdk-reference.md`                  | `FastEdge-sdk-js`, `FastEdge-sdk-rust` | `"JavaScript SDK"`, `"Rust SDK"` |
| `js-runtime.md`                     | `FastEdge-sdk-js`                      | _(full file, no section needed)_ |
| `platform-overview.md`              | _(TBD — no clear single source repo)_  | —                                |
| `best-practices.md`                 | `FastEdge-examples`                    | _(full file, no section needed)_ |
| `error-codes.md`                    | `FastEdge-sdk-js`, `FastEdge-sdk-rust` | `"JavaScript"`, `"Rust"`         |
| `test/reference/testing-api.md`     | `fastedge-test`                        | _(full file, no section needed)_ |
| `test/reference/test-config.md`     | `fastedge-test`                        | _(full file, no section needed)_ |
| `test/reference/vscode-debugger.md` | `fastedge-test`                        | _(full file, no section needed)_ |

> `platform-overview.md` needs a source decision before it can be included in `sources.json`.
> It may need to be manually maintained or sourced from Gcore's public documentation.

---

## Complete Example

```json
{
  "version": "1.0",
  "repos": [
    {
      "id": "fastedge-sdk-js",
      "github_url": "https://github.com/G-Core/FastEdge-sdk-js",
      "sparse_paths": ["src/", "examples/", "README.md", "CHANGELOG.md"],
      "ref": "latest-release",
      "trigger": "release",
      "updates": [
        {
          "reference_file": "plugins/gcore-fastedge/skills/fastedge-docs/reference/sdk-reference.md",
          "section": "JavaScript SDK",
          "generator_agent": "claude",
          "reviewer_agent": "codex"
        },
        {
          "reference_file": "plugins/gcore-fastedge/skills/fastedge-docs/reference/js-runtime.md",
          "generator_agent": "claude",
          "reviewer_agent": "codex"
        },
        {
          "reference_file": "plugins/gcore-fastedge/skills/fastedge-docs/reference/error-codes.md",
          "section": "JavaScript",
          "generator_agent": "claude",
          "reviewer_agent": "codex"
        }
      ]
    },
    {
      "id": "fastedge-sdk-rust",
      "github_url": "https://github.com/G-Core/FastEdge-sdk-rust",
      "sparse_paths": ["src/", "examples/", "README.md", "CHANGELOG.md"],
      "ref": "latest-release",
      "trigger": "release",
      "updates": [
        {
          "reference_file": "plugins/gcore-fastedge/skills/fastedge-docs/reference/sdk-reference.md",
          "section": "Rust SDK",
          "generator_agent": "claude",
          "reviewer_agent": "codex"
        },
        {
          "reference_file": "plugins/gcore-fastedge/skills/fastedge-docs/reference/error-codes.md",
          "section": "Rust",
          "generator_agent": "claude",
          "reviewer_agent": "codex"
        }
      ]
    },
    {
      "id": "fastedge-test",
      "github_url": "https://github.com/G-Core/fastedge-test",
      "sparse_paths": [
        "src/",
        "test/",
        "context/",
        "README.md",
        "CHANGELOG.md"
      ],
      "ref": "latest-release",
      "trigger": "release",
      "updates": [
        {
          "reference_file": "plugins/gcore-fastedge/skills/test/reference/testing-api.md",
          "generator_agent": "claude",
          "reviewer_agent": "codex"
        },
        {
          "reference_file": "plugins/gcore-fastedge/skills/test/reference/test-config.md",
          "generator_agent": "claude",
          "reviewer_agent": "codex"
        }
      ]
    },
    {
      "id": "FastEdge-examples",
      "github_url": "https://github.com/G-Core/FastEdge-examples",
      "sparse_paths": ["*/", "README.md"],
      "ref": "main",
      "trigger": "schedule",
      "updates": [
        {
          "reference_file": "plugins/gcore-fastedge/skills/fastedge-docs/reference/best-practices.md",
          "generator_agent": "claude",
          "reviewer_agent": "codex"
        }
      ]
    }
  ]
}
```
