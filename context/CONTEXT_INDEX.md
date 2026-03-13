# Context Index — fastedge-plugin

Start here. Read only what your task requires.

---

## Files in This Directory

| File | Read When |
|------|-----------|
| `TEMPLATE_STRATEGY.md` | Updating scaffold templates, auditing template list, adding new templates |
| `REFERENCE_MATERIAL.md` | Updating `fastedge-docs` reference files, adding new SDK features, building the sync pipeline |
| `TDD_ROADMAP.md` | Testing/TDD integration — what's been built, what's planned for scaffold/deploy integration |

---

## Key Decisions Already Made

| Decision | Summary | Detail |
|----------|---------|--------|
| Scaffold delegates to CLI | The scaffold skill runs `npx create-fastedge-app` instead of generating files itself | `TEMPLATE_STRATEGY.md` |
| Templates are hardcoded | Template names are listed in `scaffold/SKILL.md`, not fetched dynamically at runtime | `TEMPLATE_STRATEGY.md` |
| mcp-server skill removed | Was in the original README, never implemented. Add to `create-fastedge-app` first if needed | — |
| Reference files are embedded | Docs are in `reference/*.md` in the plugin, not fetched from Context7 or live URLs at runtime | `REFERENCE_MATERIAL.md` |
| Reference sync is manual for now | Files were built by reading `FastEdge-sdk-js/types/*.d.ts` + `docs.rs/fastedge`. Future: GitHub Actions pipeline | `REFERENCE_MATERIAL.md` |
| scaffold `disable-model-invocation: false` | Changed so agents can invoke the scaffold skill directly (not just users via slash command) | — |
| Agent must use `create-fastedge-app` | `CLAUDE.md` now hard-constrains agents to never manually scaffold files — always run the CLI | `plugins/gcore-fastedge/CLAUDE.md` |
| File system scope is a hard constraint | Agents are explicitly prohibited from reading `../` paths or sibling folders | `plugins/gcore-fastedge/CLAUDE.md` |
| Intake-first protocol | Agents must collect app type → language → name before any research or file operations | `plugins/gcore-fastedge/CLAUDE.md` |
| JS runtime constraints documented | StarlingMonkey constraints, crypto.subtle matrix, SAML incompatibilities — in `js-runtime.md` | `REFERENCE_MATERIAL.md` |

---

## What to Read For...

| Task | Read |
|------|------|
| Adding/updating scaffold templates | `TEMPLATE_STRATEGY.md` |
| Updating docs reference content | `REFERENCE_MATERIAL.md` |
| Testing integration | `TDD_ROADMAP.md`, `skills/test/SKILL.md` |
| Agent behaviour / interaction protocol | `plugins/gcore-fastedge/CLAUDE.md` — Interaction Protocol section |
| JS runtime limits, SAML, crypto.subtle | `plugins/gcore-fastedge/skills/fastedge-docs/reference/js-runtime.md` |

---

## Known Gaps (Future Work)

- `fastedge-docs/reference/best-practices.md` and `error-codes.md` — may still be stubs, review needed
- `sdk-reference.md` and `platform-overview.md` — have real content (not stubs)
- Deploy skill: pre-deploy test step not yet added — see `TDD_ROADMAP.md`
- Scaffold skill: optional test setup after scaffolding not yet added — see `TDD_ROADMAP.md`
- AssemblyScript CDN app capabilities in `CLAUDE.md` were verified against `proxy-wasm-sdk-as/assembly/fastedge/kvStore.ts` — KvStore is **read-only** (no set/write), `open()` returns `KvStore | null`, `get()` returns `ArrayBuffer | null`
- Template audit against `create-fastedge-app` still pending (scaffold templates may have drifted)
