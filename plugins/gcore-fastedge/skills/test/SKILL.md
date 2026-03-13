---
disable-model-invocation: false
argument-hint: "[project-dir]"
description: Write and run tests for a FastEdge WASM app using @gcoredev/fastedge-test
---

# /gcore-fastedge:test

Write and run automated tests for a FastEdge WASM app.

## TDD Principle — Tests Before Deploy

**FastEdge development follows a test-driven cycle.** Tests must pass locally before any
code is deployed to the edge. This is not optional — it prevents deploying broken WASM binaries
that fail silently at the edge with 53x error codes.

The cycle:
```
Write tests → Build WASM → Run tests → Fix failures → All pass → Deploy
```

If a user asks to deploy without mentioning tests:
- Check whether tests exist (`tests/` directory, `*.test.ts` files)
- If no tests exist, prompt: "Before deploying, let's write tests for this app.
  Run `/gcore-fastedge:test` to generate a test suite, then we'll verify it passes locally."
- If tests exist but haven't been run, run them first

The visual debugger (`npm run debug`) is the interactive complement to automated tests —
use it to inspect specific requests while fixing failures. Reference: `./reference/vscode-debugger.md`

---

## Mode Detection

Detect the user's intent from phrasing before starting:

| User says | Mode |
|-----------|------|
| "write tests", "generate tests", "create tests" | **Generate** — read source, produce complete test file |
| "set up testing", "help me test", "add testing" | **Scaffold** — create stub file with TODOs |
| "run my tests", "test my app", "run tests" | **Run** — verify setup and execute |

If ambiguous, ask: "Would you like me to generate tests from your source code, or just scaffold a starter file?"

---

## Step 1 — Detect App Type

Check for `componentize.config.js` or `package.json` build scripts:

- **CDN / proxy-wasm**: Uses `componentize` or `proxy-wasm` in build config, or imports from `fastedge::proxy-wasm`. Hooks-based model (onRequestHeaders, onResponseHeaders, etc.).
- **HTTP-WASM**: Standard Hono/fetch handler. Responds to HTTP requests directly.

This determines which test patterns to use (see `./reference/testing-api.md`).

---

## Step 2 — Check Existing Test Setup

Look for:
- `tests/*.test.ts` or `src/*.test.ts` — existing test files
- `test-config.json` in project root — existing debugger config

If both exist: **work with them**, don't overwrite. Add new test cases to the existing suite.
If only test-config.json exists: use it for WASM path and request config.
If nothing exists: proceed to create from scratch.

---

## Step 3 — Install Check

Check `package.json` devDependencies for `@gcoredev/fastedge-test`.

If missing, tell the user:
```
@gcoredev/fastedge-test is not installed. Run:
  npm install --save-dev @gcoredev/fastedge-test
Then re-run this command.
```
Do not proceed until the package is available.

---

## Step 4 — Generate or Scaffold Tests

Reference: `./reference/testing-api.md`

### Generate Mode

1. Read the app entry file (`src/index.ts` or equivalent).
2. Identify all routes/handlers/hooks.
3. Create `tests/app.test.ts` with one test case per route.

**CDN app template:**
```typescript
import { defineTestSuite, runAndExit, runFlow } from '@gcoredev/fastedge-test/test';
import { assertFinalStatus, assertFinalHeader } from '@gcoredev/fastedge-test/test';

await runAndExit(defineTestSuite({
  wasmPath: './build/app.wasm',
  tests: [
    {
      name: 'GET / returns 200',
      run: async (runner) => {
        const result = await runFlow(runner, {
          url: 'https://example.com/',
          method: 'GET',
        });
        assertFinalStatus(result, 200);
      },
    },
    // ... one test per route/hook
  ],
}));
```

**HTTP-WASM app template:**
```typescript
import { defineTestSuite, runAndExit } from '@gcoredev/fastedge-test/test';

await runAndExit(defineTestSuite({
  wasmPath: './build/app.wasm',
  tests: [
    {
      name: 'GET / returns 200',
      run: async (runner) => {
        const response = await runner.execute({
          path: '/',
          method: 'GET',
          headers: {},
        });
        if (response.status !== 200) {
          throw new Error(`Expected 200, got ${response.status}`);
        }
      },
    },
  ],
}));
```

### Scaffold Mode

Create `tests/app.test.ts` with a skeleton and TODO comments:
```typescript
import { defineTestSuite, runAndExit, runFlow } from '@gcoredev/fastedge-test/test';
import { assertFinalStatus } from '@gcoredev/fastedge-test/test';

await runAndExit(defineTestSuite({
  wasmPath: './build/app.wasm',
  tests: [
    {
      name: 'TODO: describe what this test checks',
      run: async (runner) => {
        // TODO: implement test
        // const result = await runFlow(runner, { url: 'https://example.com/', method: 'GET' });
        // assertFinalStatus(result, 200);
        throw new Error('Not implemented');
      },
    },
  ],
}));
```

---

## Step 5 — Create/Update test-config.json

Always create or update `test-config.json` in the project root.
Reference: `./reference/test-config.md`

Use the WASM build output path from the build config. For CDN apps, include representative `properties`. Example:

```json
{
  "$schema": "./node_modules/@gcoredev/fastedge-test/schemas/test-config.schema.json",
  "description": "Test config for <app-name>",
  "wasm": {
    "path": "build/app.wasm",
    "description": "<app description>"
  },
  "request": {
    "method": "GET",
    "url": "https://example.com/",
    "headers": {},
    "body": ""
  },
  "properties": {
    "request.country": "US",
    "request.city": "New York",
    "request.continent": "NA"
  },
  "logLevel": 0,
  "envVars": {},
  "secrets": {}
}
```

Omit `properties` for HTTP-WASM apps (not applicable).

---

## Step 5.5 — Secrets and Environment Variables Setup

If the app uses `getSecret()` or `getEnv()`, set up the secrets/env vars for local testing.
Reference: `./reference/vscode-debugger.md` — "Providing Secrets, Variables, and Headers"

**Detect whether secrets are needed:** check the source code for `getSecret(` or `getEnv(` calls.
If found, determine which keys are required and set them up using one of two methods:

### If the values are non-sensitive (safe to commit with placeholders):

Add them to `test-config.json`:
```json
{
  "envVars": { "IDP_ENTITY_ID": "https://idp.example.com" },
  "secrets": { "SESSION_SECRET": "local-placeholder" }
}
```

### If the values are sensitive (real secrets, certificates, tokens):

1. Enable dotenv in the test suite by adding `runnerConfig: { dotenvEnabled: true }`:
```typescript
await runAndExit(defineTestSuite({
  wasmPath: './build/app.wasm',
  runnerConfig: { dotenvEnabled: true },
  tests: [ ... ],
}));
```

2. Create `.env.example` (committed) showing the required variables:
```bash
# Copy to .env and fill in real values
FASTEDGE_VAR_SECRET_SESSION_SECRET=your-local-secret
FASTEDGE_VAR_SECRET_IDP_CERT=-----BEGIN CERTIFICATE-----...
FASTEDGE_VAR_ENV_IDP_ENTITY_ID=https://your-idp.example.com
```

3. Add `.env` and `.env.secrets` to `.gitignore` — tell the user to do this if not already present.

**For SAML apps specifically:** the IdP certificate and any signing keys must go in `.env`
via `FASTEDGE_VAR_SECRET_` prefix — never commit real certs to `test-config.json`.

---

## Step 6 — Add npm Scripts

Check `package.json` for existing `test`, `test:watch`, and `debug` scripts. If not present, add:

```json
{
  "scripts": {
    "test": "npx @gcoredev/fastedge-test ./tests/app.test.ts",
    "test:watch": "npx @gcoredev/fastedge-test --watch ./tests/app.test.ts",
    "debug": "npx @gcoredev/fastedge-test"
  }
}
```

Do not overwrite existing scripts with different values — only add missing ones.

---

## Step 7 — Run Tests (Generate Mode or Run Mode)

After generating tests, or in Run mode:

1. Run `npm test`.
2. Report results: how many passed, how many failed.
3. If failures: analyse the error message and suggest a fix.
   - `WASM not found` → build the app first (`npm run build`)
   - `assertFinalStatus` mismatch → inspect the route logic
   - `Expected request header ... to be set` → check hook implementation

---

## Step 8 — Summary

Print what was created or run:

```
Done:
  ✓ Created tests/app.test.ts (3 test cases)
  ✓ Created test-config.json
  ✓ Added npm scripts: test, test:watch, debug

Next steps:
  npm run build          # compile app to WASM
  npm test               # run tests
  npm run debug          # open visual debugger at http://localhost:5179
  (or) FastEdge: Debug Application  # VSCode command (uses bundled debugger)
```

---

## Advising on Local Debugging

Reference: `./reference/vscode-debugger.md`

When a user asks how to debug their app, test a specific request, or investigate unexpected
behaviour locally — read `./reference/vscode-debugger.md` before advising. It covers:
- Starting the visual debugger (VSCode extension commands vs. `npm run debug`)
- `test-config.json` integration (auto-loaded on startup)
- What the debugger UI shows (logs, hook results, property accesses)
- Port conflict resolution
- Debugging specific request shapes (e.g. SAML ACS POSTs)
