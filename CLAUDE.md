# fastedge-plugin — Developer Instructions

## What This Repo Is

A **Claude Code plugin** for Gcore FastEdge. It gives Claude Code users skills to scaffold, deploy, and manage FastEdge apps via natural language.

This is NOT a traditional app — there is no build step, no compiled output, no server. Everything is Markdown files that Claude Code reads as context and skills.

---

## Two Separate Concerns

| Location | Audience | Purpose |
|----------|----------|---------|
| `plugins/gcore-fastedge/` | Plugin **users** | Loaded when plugin is installed — CLAUDE.md knowledge base + skill prompts |
| `context/` (this level) | Plugin **developers** | Architecture decisions, maintenance guides, design rationale |

A root-level `CLAUDE.md` (this file) is only read when someone works on the plugin itself, not by plugin users.

---

## Quick Reference

**Install for testing (session only):**
```bash
claude --plugin-dir /path/to/fastedge-plugin
```

**Install persistently:**
```bash
/plugin marketplace add /path/to/fastedge-plugin
/plugin install gcore-fastedge@gcore-fastedge-marketplace
```

**Plugin skills:**
- `/gcore-fastedge:scaffold` — delegates to `create-fastedge-app`
- `/gcore-fastedge:deploy` — build + upload binary + create/update app
- `/gcore-fastedge:manage` — list, get, update, delete, secrets, sync-env
- `/gcore-fastedge:fastedge-docs` — auto-invoked docs skill
- `/gcore-fastedge:test` — write & run tests using `@gcoredev/fastedge-test`
  (generate complete test suites or scaffold stub files; creates test-config.json for debugger)

---

## Repository Structure

```
fastedge-plugin/
├── CLAUDE.md                          # This file (developer instructions)
├── README.md                          # User-facing installation guide
├── context/                           # Developer context (read for maintenance tasks)
│   ├── CONTEXT_INDEX.md               # Start here
│   └── TEMPLATE_STRATEGY.md           # Template hardcoding rationale + audit process
│
├── .claude-plugin/
│   ├── marketplace.json               # Marketplace container descriptor
│   └── plugin.json                    # Root plugin manifest
│
└── plugins/gcore-fastedge/            # The actual plugin (what users get)
    ├── .claude-plugin/
    │   └── plugin.json                # Plugin descriptor (name, version, keywords)
    ├── CLAUDE.md                      # Shared knowledge base (API, SDK, auth, builds)
    └── skills/
        ├── scaffold/SKILL.md          # Delegates to create-fastedge-app CLI
        ├── deploy/SKILL.md            # Build → upload binary → create/update app
        ├── manage/SKILL.md            # App and secret management subcommands
        └── fastedge-docs/
            ├── SKILL.md               # Docs entry point
            └── reference/             # Reference files (stubs — need content)
                ├── platform-overview.md
                ├── sdk-reference.md
                ├── best-practices.md
                └── error-codes.md
```

---

## Discovery Guide

**Read when working on:**

| Task | Read |
|------|------|
| Understanding the plugin structure | This file |
| Scaffold skill / template management | `context/TEMPLATE_STRATEGY.md` |
| Deploy or manage skill logic | `plugins/gcore-fastedge/skills/deploy/SKILL.md` or `manage/SKILL.md` |
| Shared API / SDK knowledge | `plugins/gcore-fastedge/CLAUDE.md` |
| Updating docs reference content | `plugins/gcore-fastedge/skills/fastedge-docs/reference/` |

---

## Key Relationships

- **`create-fastedge-app`** — source of truth for scaffold templates. The scaffold skill delegates to this CLI via `npx create-fastedge-app`. Never duplicate template content in the plugin.
- **`fastedge-test`** — local WASM test runner. The `/gcore-fastedge:test` skill wraps this. Future work: integrate into deploy skill as a pre-deploy test step (see `context/TDD_ROADMAP.md`).
- **`FastEdge-mcp-server`** — parallel tool (MCP for Claude Desktop/API vs plugin for Claude Code). API knowledge in `plugins/gcore-fastedge/CLAUDE.md` should stay aligned with it.

---

## TDD Integration

Testing skill is live. Scaffold and deploy integration is planned. See `context/TDD_ROADMAP.md`.
