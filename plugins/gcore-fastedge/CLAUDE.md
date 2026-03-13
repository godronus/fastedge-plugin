# Gcore FastEdge — Shared Knowledge Base

## RULE 0 — FILE SYSTEM SCOPE (READ THIS BEFORE ANYTHING ELSE)

**You operate exclusively inside the user's active project directory. You have no access to anything outside it.**

Before every single file read, glob, grep, or directory listing — check: does this path stay inside the project root? If the answer is anything other than a definite YES, do not proceed.

Specific prohibitions — these are NEVER acceptable under any circumstance:
- Any path containing `../` — even one level up
- Listing or reading the parent directory of the project
- Reading or grepping sibling folders (e.g. other projects that happen to be nearby on disk)
- Searching for "related" or "example" projects anywhere outside the current project root
- Using the workspace root or repository root as a starting point for searches unless it IS the project root

**There is no exception.** Not for gathering context. Not for finding examples. Not for understanding patterns. Not for "just a quick look". If information isn't in the current project or in this plugin's knowledge base, ask the user rather than searching the filesystem.

If you are about to form a path that goes above the current project directory — stop. Do not execute the tool call. Ask the user for the information instead.

---

## Interaction Protocol

### When a user wants to build something

**Collect before you research.** When a user describes an application they want to build, do not read examples, browse GitHub repos, or look up SDK patterns until you have confirmed all three of:

1. **App type** — CDN app or HTTP app (ask if not explicitly stated — use-case descriptions are NOT explicit)
2. **Language** — determined by type constraints (ask if multiple options exist for the confirmed type)
3. **Project name** — required before scaffolding

Only after all three are confirmed, use **parallel sub-agents** to research. Do not do sequential research in the main agent. Scope all research strictly to the confirmed type + language — do not read resources for types or languages that won't be used.

**What counts as explicit vs ambiguous:**
- Explicit: "I want a CDN filter", "HTTP app in TypeScript", "Proxy-WASM filter in Rust"
- Ambiguous (always ask): "gateway for CDN resources", "auth for CDN traffic", "edge middleware", "SAML at the edge", "protect my CDN"

### Scaffolding new projects — HARD CONSTRAINT

**Never manually create project files (package.json, tsconfig.json, src/index.ts, Cargo.toml, etc.) from scratch.** Always scaffold using `create-fastedge-app`:

```bash
npx create-fastedge-app <project-name> --template <template> <language-flag> --no-verify
```

Language flags: `--typescript` / `--javascript` / `--rust` / `--as`

Templates:
- `http-base` — JS/TS/Rust HTTP app (APIs, gateways, edge functions)
- `http-react` — React SSR (JS/TS only)
- `http-react-hono` — React SSR with Hono routing (JS/TS only)
- `cdn-base` — CDN filter (AssemblyScript or Rust)

Examples:
```bash
npx create-fastedge-app my-api --template http-base --typescript --no-verify
npx create-fastedge-app my-filter --template cdn-base --as --no-verify
```

Do not look for existing projects in the workspace to use as a template reference. Do not look at sibling folders to copy package.json or tsconfig.json structure. The `create-fastedge-app` CLI produces the correct structure — run it, then add the application-specific code on top.

After scaffolding, if the user's application requires non-trivial logic (auth, integrations, custom protocols), plan and write only the app-specific files on top of what the scaffold generated.

### When a user asks a question (not building)

Answer from this knowledge base and the SDK reference files directly. No research needed for factual questions about FastEdge APIs, error codes, or SDK usage.

---

## Platform Overview

Gcore FastEdge is a serverless edge computing platform that runs WebAssembly (Wasm) workloads on 210+ global Points of Presence (PoPs). Apps are compiled to Wasm and deployed instantly worldwide with sub-millisecond cold starts.

**Supported languages:** JavaScript/TypeScript, Rust, AssemblyScript
**Default framework (HTTP apps):** Hono (lightweight, edge-native, official FastEdge examples use it)

---

## App Types — CDN vs HTTP

This is the most important distinction when creating a FastEdge application. The two app types run in fundamentally different environments and have different capabilities.

### HTTP Apps
Run as **standalone serverless functions**. They own the entire request/response cycle — the Wasm module receives an HTTP request and returns an HTTP response, just like a normal server endpoint.

**Use HTTP apps for:**
- APIs and API gateways
- Server-side rendering (React, Hono)
- Edge middleware with full request control
- MCP servers at the edge
- Anything that behaves like a web server endpoint

**Languages:** JavaScript, TypeScript, Rust
**ABI:** HTTP-WASM (HTTP handler interface)
**Templates:** `http-base`, `http-react`, `http-react-hono`

### CDN Apps
Run **inside the CDN proxy layer** using the Proxy-WASM ABI. These are HTTP filters — they intercept and modify traffic flowing through Gcore's CDN. The CDN handles the actual request/response; the Wasm module hooks into specific phases of that flow.

**Use CDN apps for:**
- Modifying request or response headers in flight
- Enforcing auth or rate limits at the CDN layer (before traffic reaches origin)
- URL rewriting and traffic routing logic
- Inspecting/transforming payloads for all CDN traffic
- Custom caching logic
- Bot detection and traffic filtering

**Languages:** AssemblyScript, Rust
**ABI:** Proxy-WASM (filter phase callbacks)
**Templates:** `cdn-base`

**Key difference:** CDN apps use a callback model — you implement methods like `onRequestHeaders`, `onResponseHeaders`, `onRequestBody`, etc. You don't "return a response"; you call `continue_request()` or `send_local_response()` to control flow.

### Decision Guide

| Question | Answer → |
|----------|----------|
| Do I need to build an API or web endpoint? | HTTP app |
| Do I need to modify traffic passing through the CDN? | CDN app |
| Do I need full control over the response body? | HTTP app |
| Do I want to intercept headers before they reach origin? | CDN app |
| Am I using JavaScript or TypeScript? | HTTP app (JS/TS not supported for CDN) |
| Am I writing something that behaves like a filter or plugin? | CDN app |

---

## Authentication

All API calls require `GCORE_API_KEY` environment variable.

```
Authorization: APIKey <GCORE_API_KEY>
```

Verify auth is set before any API operation:
```bash
if [ -z "$GCORE_API_KEY" ]; then
  echo "Error: GCORE_API_KEY environment variable is not set"
  echo "Get your API key from https://portal.gcore.com → API Keys"
  exit 1
fi
```

## API Endpoints

Base URL: `https://api.gcore.com/fastedge/v1`

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/binaries/raw` | Upload Wasm binary (Content-Type: application/octet-stream) |
| GET | `/apps` | List all apps |
| POST | `/apps` | Create new app |
| GET | `/apps/{id}` | Get app details |
| PUT | `/apps/{id}` | Update app |
| DELETE | `/apps/{id}` | Delete app |
| GET | `/apps/{id}/stats` | Get app statistics |
| GET | `/secrets` | List all secrets |
| GET | `/secrets/{id}` | Get secret details |

### Upload Binary
```bash
BINARY_ID=$(curl -s -X POST "https://api.gcore.com/fastedge/v1/binaries/raw" \
  -H "Authorization: APIKey $GCORE_API_KEY" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @<path-to-wasm> | jq -r '.id')
```

### Create App
```bash
curl -s -X POST "https://api.gcore.com/fastedge/v1/apps" \
  -H "Authorization: APIKey $GCORE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "<app-name>",
    "binary": <binary-id>,
    "status": 1,
    "env_vars": {}
  }'
```

### Update App
```bash
curl -s -X PUT "https://api.gcore.com/fastedge/v1/apps/<app-id>" \
  -H "Authorization: APIKey $GCORE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{ "binary": <new-binary-id> }'
```

### Secrets

Secrets are encrypted environment variables. They're referenced by ID when assigning to apps.

```bash
# List all secrets
curl -s "https://api.gcore.com/fastedge/v1/secrets" \
  -H "Authorization: APIKey $GCORE_API_KEY"
```

Response contains an array of secrets with `id` and `name` fields.

To assign secrets to an app, use the `secrets` field in the update payload:
```bash
curl -s -X PUT "https://api.gcore.com/fastedge/v1/apps/<app-id>" \
  -H "Authorization: APIKey $GCORE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "secrets": {"MY_SECRET": {"id": <secret-id>}},
    "rsp_headers": {"X-Custom-Header": "value"}
  }'
```

## Build Pipelines

### JavaScript/TypeScript (HTTP apps only)
```bash
fastedge-build ./src/index.js ./<project-name>.wasm
# Output: ./<project-name>.wasm (in project root)
```

Requires `@gcoredev/fastedge-sdk-js` as a dev dependency. The `fastedge-build` tool compiles JS → Wasm using ComponentizeJS.

### Rust (HTTP or CDN apps)
```bash
cargo build --release --target wasm32-wasip1
# Output: ./target/wasm32-wasip1/release/<crate-name>.wasm
```

Requires `.cargo/config.toml` with `[build] target = "wasm32-wasip1"`.

### AssemblyScript (CDN apps only)
```bash
npm run asbuild:release
# Output: build/release.wasm (as configured in asconfig.json)
```

Requires `@gcoredev/proxy-wasm-sdk-as` as a dependency and `assemblyscript` as a dev dependency. The `asc` compiler compiles AssemblyScript → Wasm using the Proxy-WASM ABI. Project is identified by the presence of `asconfig.json`.

## SDK Capabilities

### JavaScript SDK (`@gcoredev/fastedge-sdk-js`) — HTTP apps

```typescript
import { getEnv } from "fastedge::env";
import { getSecret } from "fastedge::secret";
import { KvStore } from "fastedge::kv";

// Environment variables (set via API or portal)
const value = getEnv("MY_VAR");

// Secrets (encrypted env vars)
const secret = getSecret("API_TOKEN");

// KV Store
const store = new KvStore("my-store");
await store.get("key");
await store.set("key", "value");

// Standard Web APIs available:
// fetch(), Request, Response, Headers, URL, TextEncoder/Decoder, crypto
```

### Rust SDK (`fastedge` crate) — HTTP apps

```rust
use fastedge::http::{Request, Response, StatusCode, Error};

#[fastedge::http]
fn main(req: Request<Vec<u8>>) -> Result<Response<Vec<u8>>, Error> {
    let body = format!("Hello from FastEdge! Path: {}", req.uri().path());
    Ok(Response::builder()
        .status(StatusCode::OK)
        .header("Content-Type", "text/plain")
        .body(body.into_bytes())?)
}
```

### AssemblyScript SDK (`@gcoredev/proxy-wasm-sdk-as`) — CDN apps

CDN apps use a **callback/filter model**, not a request/response model. Implement a `Context` class and override phase callbacks:

```typescript
export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy";
import {
  RootContext,
  Context,
  registerRootContext,
  FilterHeadersStatusValues,
  stream_context,
} from "@gcoredev/proxy-wasm-sdk-as/assembly";
import { getEnv } from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";
import { KvStore } from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";
import { getSecret } from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";

class MyRoot extends RootContext {
  createContext(context_id: u32): Context {
    return new MyFilter(context_id, this);
  }
}

class MyFilter extends Context {
  // Called when request headers arrive — modify before forwarding to origin
  onRequestHeaders(a: i32, end_of_stream: bool): FilterHeadersStatusValues {
    stream_context.headers.request.add("X-Custom", "value");
    return FilterHeadersStatusValues.Continue; // or StopIteration to block
  }

  // Called when response headers arrive — modify before sending to client
  onResponseHeaders(a: i32, end_of_stream: bool): FilterHeadersStatusValues {
    stream_context.headers.response.add("X-Powered-By", "FastEdge");
    return FilterHeadersStatusValues.Continue;
  }
}

registerRootContext((context_id: u32) => new MyRoot(context_id), "my-filter");
```

**FastEdge-specific APIs available in AssemblyScript CDN apps:**
```typescript
import { getEnv, getSecret, KvStore } from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";

// Environment variables
const val = getEnv("MY_VAR");

// Secrets
const token = getSecret("API_TOKEN");

// KV Store (read-only from CDN filter context)
const store = KvStore.open("my-store"); // returns KvStore | null
if (store) {
  const buf = store.get("key");          // returns ArrayBuffer | null
  const keys = store.scan("prefix*");   // returns Array<string>
}
```

**Flow control in CDN apps:**
- `FilterHeadersStatusValues.Continue` — pass headers to next filter/origin
- `FilterHeadersStatusValues.StopIteration` — pause processing (e.g. waiting for async)
- `stream_context.sendLocalResponse(403, "Forbidden", ...)` — short-circuit, return response directly without hitting origin

## Error Codes

| Code | Meaning | Common Cause |
|------|---------|--------------|
| 530 | App initialization failed | Missing env vars, invalid Wasm binary |
| 531 | Runtime error | Unhandled exception in app code |
| 532 | Timeout | App exceeded execution time limit (typically 50ms for basic plan) |
| 533 | Memory limit exceeded | App exceeded memory limit (typically 128MB) |

## Local Testing

### Visual Debugger

`@gcoredev/fastedge-test` is a dual-mode package:

```bash
# Visual debugger mode (no args) — Express + React UI at http://localhost:5179
npm run debug                          # requires: "debug": "npx @gcoredev/fastedge-test" in package.json
npx @gcoredev/fastedge-test            # or directly

# Test runner mode (with test file) — runs suite, exits with pass/fail
npm test                               # requires: "test": "npx @gcoredev/fastedge-test ./tests/app.test.ts"
npx @gcoredev/fastedge-test ./tests/app.test.ts
```

**VSCode users:** The FastEdge extension bundles the same debugger server — use
`FastEdge: Debug Application` from the Command Palette (no Node.js required).

The debugger auto-loads `test-config.json` from the project root. Use `/gcore-fastedge:test`
to create it. Full details: `skills/test/reference/vscode-debugger.md`.

### Raw CLI runner

```bash
fastedge-run http -w <path-to-wasm> --port 8080
curl http://localhost:8080/
```

## App URL Pattern

Once deployed, apps are accessible at the URL returned by the API (in the `url` field of the response), typically:
```
https://<app-name>-<id>.fastedge.app
```
