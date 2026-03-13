# TDD Integration Roadmap

Tracks testing/TDD integration across the fastedge-plugin skills.

Start here when working on anything testing-related. Check "Planned" items before starting new
testing work — pick up where a previous agent left off.

---

## Status: Completed

- [x] `/gcore-fastedge:test` skill — `plugins/gcore-fastedge/skills/test/SKILL.md`
  - Mode detection (generate / scaffold / run)
  - Steps: detect app type, check setup, verify install, generate/scaffold tests, create test-config.json, add npm scripts, run tests, summarise
  - Covers both CDN (proxy-wasm) and HTTP-WASM app types

- [x] `skills/test/reference/testing-api.md` — full `@gcoredev/fastedge-test` API reference
  - All assertion helpers from `assertions.ts`
  - `defineTestSuite`, `runAndExit`, `runFlow`, `loadConfigFile` from `suite-runner.ts`
  - `FlowOptions`, `FullFlowResult`, `HookResult` type reference
  - CDN vs HTTP-WASM comparison table
  - Complete examples

- [x] `skills/test/reference/test-config.md` — `test-config.json` schema reference
  - All fields documented
  - CDN property list
  - Visual debugger usage
  - Programmatic loading with `loadConfigFile`
  - Best practices

- [x] `skills/fastedge-docs/reference/best-practices.md` — testing checklist updated
  - Replaced stub checklist with CDN + HTTP-WASM specific checks
  - References `/gcore-fastedge:test` for setup

---

## Status: Planned

### Deploy skill — pre-deploy test step

**File**: `plugins/gcore-fastedge/skills/deploy/SKILL.md`

Before uploading the binary, run `npm test` if test files exist.

Insert as **Step 2.5** (after build, before upload):

```
Step 2.5 — Run tests (if available)

Check for test files: `tests/*.test.ts` or `src/*.test.ts`.
If found:
  - Run `npm test`
  - If tests pass: continue to upload
  - If tests fail: abort and show results
    - Offer override: "Run `/gcore-fastedge:deploy --skip-tests` to deploy anyway"
If no test files found: skip silently
```

**Why**: Prevents deploying a broken binary to production.

---

### Scaffold skill — optional test setup after scaffolding

**File**: `plugins/gcore-fastedge/skills/scaffold/SKILL.md`

After `npx create-fastedge-app` completes successfully, offer to set up tests.

Add at the end of the scaffold flow:

```
Step N — Offer test setup (optional)

Ask the user: "Would you like to set up tests for your new app? (recommended)"
If yes: invoke `/gcore-fastedge:test` in scaffold mode for the new project directory.
If no: mention they can run `/gcore-fastedge:test` later.
```

**Why**: TDD from the start — users get a working test stub immediately after scaffolding.

---

### fastedge-docs — add testing FAQ entry

**File**: `plugins/gcore-fastedge/skills/fastedge-docs/reference/best-practices.md`
(or a new `testing.md` reference file)

Add FAQ entry: "How do I test my FastEdge app?" pointing to `/gcore-fastedge:test`.

---

## Key Dependencies

| Dependency | Notes |
|------------|-------|
| `@gcoredev/fastedge-test` npm package | Published from the `fastedge-test` repo |
| `plugins/gcore-fastedge/skills/test/SKILL.md` | The test skill itself |
| `plugins/gcore-fastedge/skills/test/reference/testing-api.md` | API reference |
| `plugins/gcore-fastedge/skills/test/reference/test-config.md` | Config schema |
