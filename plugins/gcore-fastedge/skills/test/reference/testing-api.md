# FastEdge Test Framework API

Reference for `@gcoredev/fastedge-test` — the local WASM test runner and visual debugger
for FastEdge apps. Published from the `fastedge-test` repository.

---

## What This Package Is

`@gcoredev/fastedge-test` has two modes in one binary (`fastedge-debug`):

| Mode | How to invoke | What happens |
|------|--------------|-------------|
| **Test runner** | `npx @gcoredev/fastedge-test ./tests/app.test.ts` | Runs test suite, prints pass/fail, exits |
| **Visual debugger** | `npx @gcoredev/fastedge-test` (no args) | Starts Express server + React UI at port 5179 |

The visual debugger server is the same server bundled inside the FastEdge VSCode extension.
Both modes use the same underlying WASM execution engine.

**Exports:**

| Import path | Contents |
|-------------|----------|
| `@gcoredev/fastedge-test/test` | Test framework: `defineTestSuite`, `runAndExit`, `runFlow`, assertions |
| `@gcoredev/fastedge-test/server` | The debugger server entry point |

---

## The TDD Cycle for FastEdge Apps

**Tests must pass locally before any code is deployed.** The workflow is:

```
1. Write (or generate) tests  →  /gcore-fastedge:test
2. Build the WASM             →  npm run build
3. Run tests                  →  npm test
4. Fix failures               →  edit code → npm run build → npm test
5. All tests pass             →  /gcore-fastedge:deploy
```

Never deploy unless `npm test` exits with code 0. If tests don't exist yet, write them first.
Use the visual debugger (`npm run debug`) to inspect specific requests interactively while
fixing failures — it shows logs, hook results, and property accesses in real time.

---

## Installation

```bash
npm install --save-dev @gcoredev/fastedge-test
```

---

## Imports

All test framework exports come from the `test` sub-path:

```typescript
import {
  defineTestSuite,
  runTestSuite,
  runAndExit,
  runFlow,
  loadConfigFile,
} from '@gcoredev/fastedge-test/test';

import {
  assertRequestHeader,
  assertNoRequestHeader,
  assertResponseHeader,
  assertNoResponseHeader,
  assertFinalStatus,
  assertFinalHeader,
  assertReturnCode,
  assertLog,
  assertNoLog,
  logsContain,
  hasPropertyAccessViolation,
  assertPropertyAllowed,
  assertPropertyDenied,
} from '@gcoredev/fastedge-test/test';
```

---

## defineTestSuite

Validates and returns a typed test suite definition. Throws if `wasmPath`/`wasmBuffer` and `tests` are missing.

```typescript
defineTestSuite({
  wasmPath: './build/app.wasm',    // path to compiled WASM (relative to project root)
  // OR: wasmBuffer: Buffer        // pre-loaded WASM buffer (exactly one required)
  runnerConfig?: {
    dotenvEnabled?: boolean;              // load .env file — see dotenv section below
    enforceProductionPropertyRules?: boolean;  // default true — mirrors CDN property rules
  },
  tests: [
    {
      name: 'descriptive test name',
      run: async (runner) => {
        // throw to fail; use assertion helpers
      },
    },
  ],
})
```

**Note**: `wasmPath` and `wasmBuffer` are mutually exclusive — providing both is a TypeScript type error.

#### dotenvEnabled — How it works

When `dotenvEnabled: true`, the test runner looks for `.env` file(s) in the project root and
loads them into the WASM app before each test. This is how you provide secrets and env vars
without hardcoding them in test files or `test-config.json`.

`.env` file format — prefix values to declare their type:

```bash
# Environment variables  (app reads as IDP_ENTITY_ID, etc.)
FASTEDGE_VAR_ENV_IDP_ENTITY_ID=https://idp.example.com
FASTEDGE_VAR_ENV_BASE_URL=https://app.example.com

# Secrets (app reads via getSecret())
FASTEDGE_VAR_SECRET_SESSION_SECRET=local-dev-secret
FASTEDGE_VAR_SECRET_IDP_CERT=-----BEGIN CERTIFICATE-----...

# Request headers injected into every test request
FASTEDGE_VAR_REQ_HEADER_authorization=Bearer test-token

# Response headers
FASTEDGE_VAR_RSP_HEADER_x-powered-by=FastEdge
```

Optional type-split files (`.env.secrets`, `.env.variables`, `.env.req_headers`, `.env.rsp_headers`)
can be used instead of or alongside the main `.env`. Full details in `./vscode-debugger.md`.

Add to `.gitignore`:
```
.env
.env.secrets
```
Commit a `.env.example` with placeholder values instead.

---

## runAndExit

Run a suite, print results to stdout, and exit the process. Exits with code 0 if all pass, 1 if any fail. Use this for standalone test scripts.

```typescript
await runAndExit(defineTestSuite({ ... }));
```

Output format:
```
  ✓ GET / returns 200 (12ms)
  ✗ POST /api fails with missing body (8ms)
      Expected final response status 400, got 200

  1/2 passed in 20ms
```

---

## runTestSuite

Same as `runAndExit` but returns `SuiteResult` instead of exiting. Use when you want programmatic control.

```typescript
const results: SuiteResult = await runTestSuite(suite);
// { passed, failed, total, durationMs, results: TestResult[] }
```

---

## runFlow (CDN / proxy-wasm only)

Simulate a full CDN request-response lifecycle through all hooks. Returns a `FullFlowResult`.

```typescript
const result = await runFlow(runner, {
  url: 'https://example.com/path',    // required — derives :path, :authority, :scheme pseudo-headers
  method: 'GET',                       // default 'GET'
  requestHeaders: { 'x-custom': 'val' },  // merged with auto-derived pseudo-headers
  requestBody: '',                     // default ''
  responseStatus: 200,                 // simulated upstream response status, default 200
  responseStatusText: 'OK',            // default 'OK'
  responseHeaders: { 'content-type': 'text/html' },
  responseBody: '<html>...</html>',
  properties: {                        // CDN properties to simulate
    'request.country': 'US',
    'request.city': 'New York',
  },
  enforceProductionPropertyRules: true,  // default true
});
```

---

## runner.execute (HTTP-WASM only)

Execute a single HTTP request against the WASM app. Returns `{ status, headers, body, logs }`.

```typescript
const response = await runner.execute({
  path: '/api/hello',
  method: 'GET',
  headers: { 'content-type': 'application/json' },
  body: '',    // optional
});

// response.status: number
// response.headers: Record<string, string>
// response.body: string
// response.logs: LogEntry[]
```

---

## CDN vs HTTP-WASM Comparison

| Aspect | CDN / proxy-wasm | HTTP-WASM |
|--------|-----------------|-----------|
| App type | Header manipulation, geo-routing, edge middleware | HTTP handlers, API servers |
| Entry function | Hooks: `onRequestHeaders`, `onResponseHeaders`, etc. | Single HTTP handler |
| Test function | `runFlow(runner, options)` | `runner.execute(options)` |
| Result type | `FullFlowResult` | `{ status, headers, body, logs }` |
| Assertions on headers | `assertRequestHeader`, `assertResponseHeader` | Check `response.headers` directly |
| Properties | Supported (`properties` field in FlowOptions) | Not applicable |
| Hook return codes | `assertReturnCode(hookResult, 0)` | Not applicable |

---

## FullFlowResult (CDN)

Returned by `runFlow()`. Contains per-hook results and the final simulated response.

```typescript
result.hookResults.onRequestHeaders   // HookResult — after request headers hook
result.hookResults.onRequestBody      // HookResult — after request body hook
result.hookResults.onResponseHeaders  // HookResult — after response headers hook
result.hookResults.onResponseBody     // HookResult — after response body hook

result.finalResponse.status           // number — final HTTP status
result.finalResponse.headers          // Record<string, string> — final response headers
result.finalResponse.body             // string — final response body
```

`HookResult` structure:
```typescript
hookResult.returnCode                 // number: 0 = Ok, 1 = Pause
hookResult.output.request.headers     // Record<string, string>
hookResult.output.response.headers    // Record<string, string>
hookResult.logs                       // LogEntry[] — console output from WASM
```

---

## Assertion Helpers

All assertions throw `Error` on failure. Compatible with any test framework or plain scripts.

### Request Headers (CDN — in HookResult)

```typescript
assertRequestHeader(hookResult, 'x-forwarded-for')          // assert header exists
assertRequestHeader(hookResult, 'x-country', 'US')          // assert header has value
assertNoRequestHeader(hookResult, 'x-internal-secret')      // assert header absent
```

### Response Headers (CDN — in HookResult)

```typescript
assertResponseHeader(hookResult, 'cache-control')
assertResponseHeader(hookResult, 'cache-control', 'max-age=3600')
assertNoResponseHeader(hookResult, 'x-debug-header')
```

### Final Response (CDN — in FullFlowResult)

```typescript
assertFinalStatus(result, 200)                              // assert HTTP status
assertFinalHeader(result, 'content-type')                   // assert header exists
assertFinalHeader(result, 'content-type', 'application/json')  // assert header value
```

### Hook Return Code

```typescript
assertReturnCode(hookResult, 0)   // 0 = Ok (continue)
assertReturnCode(hookResult, 1)   // 1 = Pause (stop processing)
```

### Log Assertions

```typescript
assertLog(hookResult, 'processed request')        // assert log contains substring
assertNoLog(hookResult, 'error')                  // assert no log contains substring
const found = logsContain(hookResult, 'debug')    // boolean — does any log match?
```

### Property Access Control (CDN)

Asserts whether CDN property reads were allowed or denied (based on production rules).

```typescript
assertPropertyAllowed(hookResult, 'request.country')  // assert property was readable
assertPropertyDenied(hookResult, 'internal.secret')   // assert property was blocked
const hasViolation = hasPropertyAccessViolation(hookResult)  // boolean
```

---

## loadConfigFile

Load and validate a `test-config.json` file for use in test suites.

```typescript
import { loadConfigFile } from '@gcoredev/fastedge-test/test';

const config = await loadConfigFile('./test-config.json');

await runAndExit(defineTestSuite({
  wasmPath: config.wasm.path,
  tests: [
    {
      name: 'uses saved config',
      run: async (runner) => {
        const result = await runFlow(runner, {
          url: config.request.url,
          method: config.request.method,
          requestHeaders: config.request.headers,
          properties: config.properties ?? {},
        });
        assertFinalStatus(result, 200);
      },
    },
  ],
}));
```

See `./test-config.md` for the full schema.

---

## npm Scripts

Recommended scripts for `package.json`:

```json
{
  "scripts": {
    "test": "npx @gcoredev/fastedge-test ./tests/app.test.ts",
    "test:watch": "npx @gcoredev/fastedge-test --watch ./tests/app.test.ts",
    "debug": "npx @gcoredev/fastedge-test"
  }
}
```

- `npm test` — run test suite once (for CI)
- `npm run test:watch` — re-run on file changes (during development)
- `npm run debug` — open visual debugger at `http://localhost:5179`

---

## Complete CDN Example

```typescript
import {
  defineTestSuite,
  runAndExit,
  runFlow,
  assertFinalStatus,
  assertFinalHeader,
  assertRequestHeader,
} from '@gcoredev/fastedge-test/test';

await runAndExit(defineTestSuite({
  wasmPath: './build/geo-router.wasm',
  tests: [
    {
      name: 'adds X-Country header from CDN property',
      run: async (runner) => {
        const result = await runFlow(runner, {
          url: 'https://example.com/',
          method: 'GET',
          properties: { 'request.country': 'DE' },
        });
        assertFinalStatus(result, 200);
        assertRequestHeader(result.hookResults.onRequestHeaders, 'x-country', 'DE');
      },
    },
    {
      name: 'blocks request from blocked country',
      run: async (runner) => {
        const result = await runFlow(runner, {
          url: 'https://example.com/',
          method: 'GET',
          properties: { 'request.country': 'XX' },
        });
        assertFinalStatus(result, 403);
      },
    },
  ],
}));
```
