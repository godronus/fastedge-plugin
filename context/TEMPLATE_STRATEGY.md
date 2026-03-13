# Template Strategy — Scaffold Skill

## Design Decision: Hardcoded Templates

The scaffold skill (`plugins/gcore-fastedge/skills/scaffold/SKILL.md`) lists template names statically rather than fetching them dynamically at runtime.

### Why Hardcoded

`create-fastedge-app` provides a `--list-templates` flag that outputs available templates as JSON. We chose NOT to use this at runtime for the following reasons:

1. **Every invocation pays the cost** — fetching the list requires a subprocess call (npx + package resolution) before any useful work begins. This latency is paid on every scaffold, even when the user already knows what template they want.

2. **`argument-hint` is static** — the SKILL.md frontmatter `argument-hint` (shown in Claude Code autocomplete) cannot be dynamic. Even with a runtime fetch, the hint would still show stale names.

3. **Templates change deliberately and rarely** — a new template in `create-fastedge-app` is a deliberate, planned change. Updating the plugin's one-line table entry is a trivial follow-up step, not an accident risk.

4. **Descriptions add value** — the skill's table includes human-readable descriptions per template. Raw JSON from `--list-templates` doesn't provide this; we'd lose richness.

### When to Update the Hardcoded List

Update `plugins/gcore-fastedge/skills/scaffold/SKILL.md` whenever a new template is added to `create-fastedge-app`. Specifically:
- Add a row to the language support table
- Update the `argument-hint` in the SKILL.md frontmatter
- Add an example invocation if it's a new template type

---

## How to Audit Templates

Before adding a new template to the skill, verify what `create-fastedge-app` actually supports:

```bash
npx create-fastedge-app --list-templates
```

This outputs a JSON array of available templates with their supported languages. Cross-reference this against the table in `scaffold/SKILL.md` to identify any drift.

You can also check the source directly:
```
create-fastedge-app/src/create-app/available-templates.ts
```

---

## Current Template Mapping

The plugin exposes the same template names as the CLI (no translation layer):

| Template | Languages | CLI invocation |
|----------|-----------|----------------|
| `http-base` | TypeScript (default), JavaScript, Rust | `npx create-fastedge-app <name> --template http-base --typescript --no-verify` |
| `http-react` | TypeScript (default), JavaScript | `npx create-fastedge-app <name> --template http-react --typescript --no-verify` |
| `http-react-hono` | TypeScript (default), JavaScript | `npx create-fastedge-app <name> --template http-react-hono --typescript --no-verify` |
| `cdn-base` | Rust, AssemblyScript (ask user) | `npx create-fastedge-app <name> --template cdn-base --rust --no-verify` |

**Language flags:** `--typescript`, `--javascript`, `--rust`, `--as`

**Non-interactive flag:** `--no-verify` — always use this to prevent interactive prompts.

---

## Source of Truth

`create-fastedge-app` is the canonical source of truth for all scaffold templates. The plugin must never contain inline template file content. If a template is not in `create-fastedge-app`, it does not belong in the scaffold skill.

To add a new template type to the plugin:
1. Add it to `create-fastedge-app` first (with its template files, language support, etc.)
2. Verify it works: `npx create-fastedge-app test-project --template <new-template> --no-verify`
3. Then update `scaffold/SKILL.md` — add the row to the table and update `argument-hint`
