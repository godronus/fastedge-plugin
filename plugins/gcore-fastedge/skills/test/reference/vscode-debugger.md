# FastEdge Visual Debugger

The visual debugger is an **Express + React server** packaged inside `@gcoredev/fastedge-test`.
The same server is bundled into the FastEdge VSCode extension, so both routes give users an
identical experience. Non-VSCode users (e.g. Vim, Cursor, JetBrains, terminal-only workflows)
install the npm package and run the debugger directly with Node.

---

## What It Provides

The debugger is a local HTTP server + React UI that:
- Loads your compiled `.wasm` file
- Lets you fire test HTTP requests at it (with configurable headers, body, and CDN properties)
- Shows all hook results, console logs, and property accesses in real time
- Auto-loads `test-config.json` from the project root if present

The server runs at **`http://localhost:5179`**.

---

## Two Ways to Run the Debugger

### Option A — Via VSCode Extension (zero setup)

Install the FastEdge VSCode extension. The extension bundles the debugger server internally —
no Node.js installation required by the user.

**VSCode Command Palette commands:**

| Command | What it does |
|---------|-------------|
| `FastEdge: Debug Application` | Opens debugger UI, optionally pick a WASM file |
| `Debug: FastEdge App (Current File)` | Builds the current file and opens debugger |
| `Debug: FastEdge App (Workspace)` | Builds the workspace project and opens debugger |
| `FastEdge: Start Debugger Server` | Manually starts the server without opening the UI |
| `FastEdge: Stop Debugger Server` | Stops the running server |

### Option B — Via npm (any editor, Node.js required)

Install `@gcoredev/fastedge-test` as a dev dependency. The package includes the same
debugger server (as `dist/server.js`) and exposes a `fastedge-debug` binary.

```bash
# Install
npm install --save-dev @gcoredev/fastedge-test

# Start the visual debugger (no test file = debugger mode)
npx @gcoredev/fastedge-test
# or equivalently:
fastedge-debug

# Or via npm script (if configured in package.json):
npm run debug
```

Opens the debugger UI at `http://localhost:5179`.

The same binary, when given a test file argument, runs the test suite instead:
```bash
# Test mode — runs the test suite, exits with pass/fail
npx @gcoredev/fastedge-test ./tests/app.test.ts
npm test   # if configured
```

**Dual-mode summary:**

| Invocation | Mode |
|-----------|------|
| `npx @gcoredev/fastedge-test` (no args) | Visual debugger at port 5179 |
| `npx @gcoredev/fastedge-test ./tests/app.test.ts` | Runs test suite, exits |

**Prerequisites for Option B:**
- Node.js installed
- `@gcoredev/fastedge-test` in devDependencies
- A compiled `.wasm` file (build first)
- Optionally: a `test-config.json` in the project root

---

## Providing Secrets, Variables, and Headers

There are two ways to pass runtime values (env vars, secrets, request headers, response headers)
into your WASM app during local debugging/testing. Use whichever fits your workflow.

---

### Method 1 — test-config.json fields

Set values directly in `test-config.json`. These are loaded automatically by both the visual
debugger and the test framework.

```json
{
  "wasm": { "path": "build/app.wasm" },
  "envVars": {
    "IDP_ENTITY_ID": "https://my-idp.example.com"
  },
  "secrets": {
    "SESSION_SECRET": "local-only-placeholder",
    "IDP_CERT": "-----BEGIN CERTIFICATE-----\n..."
  }
}
```

**When to use:** Quick setup, non-sensitive values, configs you want to commit (use placeholder
values for secrets — don't commit real keys).

---

### Method 2 — dotenv files

Keeps secrets out of `test-config.json` and out of source control. The debugger and test
framework both read `.env` files when dotenv is enabled.

#### dotenv file format

In the `.env` file at your project root, prefix values to declare their type:

```bash
# Environment variables
FASTEDGE_VAR_ENV_IDP_ENTITY_ID=https://my-idp.example.com
FASTEDGE_VAR_ENV_BASE_URL=https://my-app.example.com

# Secrets (encrypted env vars in production)
FASTEDGE_VAR_SECRET_SESSION_SECRET=my-local-secret
FASTEDGE_VAR_SECRET_IDP_CERT=-----BEGIN CERTIFICATE-----...

# Request headers injected into every test request
FASTEDGE_VAR_REQ_HEADER_authorization=Bearer test-token
FASTEDGE_VAR_REQ_HEADER_x-custom-header=value

# Response headers added to every response
FASTEDGE_VAR_RSP_HEADER_x-powered-by=FastEdge
```

The prefix is stripped before the value is injected — your app reads `IDP_ENTITY_ID`,
`SESSION_SECRET`, etc., not the prefixed names.

#### Optional type-split files

For large configurations, split by type (all optional):

```
.env                 ← main file; can contain all types or just some
.env.variables       ← env vars only (FASTEDGE_VAR_ENV_ prefix not needed here)
.env.secrets         ← secrets only
.env.req_headers     ← request headers only
.env.rsp_headers     ← response headers only
```

#### Priority / override hierarchy

```
launch.json (VSCode)   ← highest priority — overrides everything
  └─ .env              ← overrides type-split files below
      └─ .env.variables
      └─ .env.secrets
      └─ .env.req_headers
      └─ .env.rsp_headers
```

Values defined higher up override values defined lower down.

#### Enabling dotenv — Option A (VSCode launch.json)

Add to `.vscode/launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "dotenv": true
    }
  ]
}
```

`dotenv: true` → walks up from the build output location until it finds a `.env` file or
reaches the workspace root.

`dotenv: "./some/path"` → loads from a specific path, relative to the **workspace root**
(not the build location).

#### Enabling dotenv — Option B (test framework)

Pass `dotenvEnabled: true` in the `runnerConfig` when defining your test suite:

```typescript
await runAndExit(defineTestSuite({
  wasmPath: './build/app.wasm',
  runnerConfig: {
    dotenvEnabled: true,   // reads .env file from project root
  },
  tests: [ ... ],
}));
```

#### What to put in .gitignore

```
.env
.env.secrets
.env.variables
.env.req_headers
.env.rsp_headers
```

Commit a `.env.example` with placeholder values so teammates know what to set up.

---

## test-config.json Integration

The debugger auto-loads `test-config.json` from the project root on startup.
This means: set up the config once, and every debugger session has the right WASM
path, request, headers, and environment variables pre-filled.

The `/gcore-fastedge:test` skill creates this file automatically. To create or update it
manually, see `./test-config.md` for the full schema.

Key fields for the debugger:

```json
{
  "wasm": { "path": "build/app.wasm" },
  "request": {
    "method": "POST",
    "url": "https://example.com/saml/acs",
    "headers": { "content-type": "application/x-www-form-urlencoded" },
    "body": "SAMLResponse=..."
  },
  "envVars": { "IDP_CERT": "-----BEGIN CERTIFICATE-----..." },
  "secrets": { "SESSION_SECRET": "local-test-value" }
}
```

You can also load multiple named configs from the UI — useful for testing different scenarios
(happy path, error case, different request shapes) without changing the file each time.

---

## Debugging a Specific Request

To test a specific HTTP scenario (e.g. a SAML ACS POST):

1. Build the WASM: `npm run build`
2. Set `test-config.json` with the right method, URL, headers, and body
3. Open the debugger: `npm run debug` or `FastEdge: Debug Application` from VSCode
4. Click **Execute** — the request fires against the local WASM
5. Inspect logs and hook results in the UI

To iterate: edit `test-config.json` or adjust the request directly in the UI, then re-execute.
No restart needed between runs.

---

## What the Debugger Shows

| Panel | Content |
|-------|---------|
| Request | Method, URL, headers, body sent to the WASM |
| Response | Status, headers, body returned by the WASM |
| Logs | `console.log` / `console.error` output from app code |
| Hook results | For CDN apps: phase callbacks, header modifications, flow control decisions |
| Property accesses | CDN properties read by the filter (country, city, etc.) |

Log verbosity is controlled by `logLevel` in `test-config.json`:
`0` = trace (everything), `1` = debug, `2` = info, `3` = warn, `4` = error.

---

## Port Conflicts

The debugger uses port `5179` by default and scans `5179–5188` if the default is occupied.
If another process is on that range and fails the identity check (`/health` must return
`{"status":"ok","service":"fastedge-debugger"}`), the extension picks the next free port.

If the debugger UI won't open, check whether port 5179 is occupied by something else:
```bash
lsof -i :5179
```

---

## Advising Users on Debugging

When a user wants to test or debug their FastEdge app locally:

1. **Check if they have the VSCode extension** — if yes, prefer `FastEdge: Debug Application`
2. **Check if `test-config.json` exists** — if not, run `/gcore-fastedge:test` to create it
3. **Check if the WASM is built** — if not, run `npm run build` (JS/TS) or `cargo build --release` (Rust)
4. **Open the debugger** and walk them through the request panel
5. **Use logs and hook results** to diagnose issues (wrong status, missing headers, etc.)

For SAML apps specifically: set the request body to a real (or test) `SAMLResponse` value,
set `content-type: application/x-www-form-urlencoded`, and check the logs for signature
verification errors or XML parsing issues.
