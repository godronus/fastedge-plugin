# FastEdge SDK Reference

## JavaScript SDK (`@gcoredev/fastedge-sdk-js`)

**Source:** `FastEdge-sdk-js` repo — `types/*.d.ts` are the authoritative API surface.

### Installation

```bash
npm install --save-dev @gcoredev/fastedge-sdk-js
```

Add triple-slash reference to your entry file:
```ts
/// <reference types="@gcoredev/fastedge-sdk-js" />
```

Or in `tsconfig.json`:
```json
{ "compilerOptions": { "types": ["@gcoredev/fastedge-sdk-js"] } }
```

---

### Two Programming Models

#### Model 1: Service Worker style (`addEventListener`)

The `addEventListener` callback **must synchronously call** `event.respondWith()`. The response itself can be a Promise.

```js
addEventListener('fetch', (event) => {
  event.respondWith(handler(event));
});

async function handler(event) {
  return new Response(`Hello from ${event.request.url}`);
}
```

#### Model 2: Hono framework (`app.fire()`)

`app.fire()` connects Hono's router to FastEdge's fetch event handler. Use this for routing.

```ts
import { Hono } from "hono";

const app = new Hono();
app.get("/", (c) => c.json({ message: "Hello FastEdge!" }));
app.get("/health", (c) => c.json({ status: "ok" }));
app.post("/data", async (c) => {
  const body = await c.req.json();
  return c.json({ received: body });
});
app.fire();  // Not export default, not Deno.serve — use fire()
```

---

### `fastedge::env` — Environment Variables

Only available **during request handling**, not at build-time initialization.

```ts
import { getEnv } from "fastedge::env";

const value = getEnv("MY_VAR");  // returns string
```

| Function | Signature | Description |
|----------|-----------|-------------|
| `getEnv` | `(name: string) => string` | Get environment variable by name |

---

### `fastedge::secret` — Encrypted Secrets

Only available **during request handling**, not at build-time initialization.

```ts
import { getSecret, getSecretEffectiveAt } from "fastedge::secret";

const token = getSecret("API_TOKEN");
const slotted = getSecretEffectiveAt("API_TOKEN", 1); // specific slot index or unix timestamp
```

| Function | Signature | Description |
|----------|-----------|-------------|
| `getSecret` | `(name: string) => string` | Get secret by name |
| `getSecretEffectiveAt` | `(name: string, effectiveAt: number) => string` | Get secret at specific slot or unix timestamp |

**Secret slots** allow zero-downtime rotation. `effectiveAt` can be a slot index (`1`, `2`...) or a unix timestamp.

---

### `fastedge::kv` — Key-Value Store

KV stores must be created in the Gcore portal first, then referenced by name. **Note:** `get()` returns `ArrayBuffer | null`, not a string — decode it explicitly.

```ts
import { KvStore } from "fastedge::kv";

// Open a named store (not `new KvStore(...)`)
const store = KvStore.open("my-store-name");

// Get a value
const buf = store.get("key");                          // ArrayBuffer | null
const text = buf ? new TextDecoder().decode(buf) : null;

// Prefix scan (wildcard required in pattern)
const keys = store.scan("user:*");                     // Array<string>

// Sorted set: get members by score range
const items = store.zrangeByScore("leaderboard", 0, 100);  // Array<[ArrayBuffer, number]>

// Sorted set: get members by value prefix
const matches = store.zscan("leaderboard", "alice*");  // Array<[ArrayBuffer, number]>

// Bloom filter: check if value exists
const exists = store.bfExists("seen-ids", "abc123");   // boolean
```

| Method | Signature | Description |
|--------|-----------|-------------|
| `KvStore.open` | `(name: string) => KvStoreInstance` | Open a named KV store |
| `.get` | `(key: string) => ArrayBuffer \| null` | Get value by exact key |
| `.scan` | `(pattern: string) => Array<string>` | Get keys matching prefix pattern — must include `*` wildcard |
| `.zrangeByScore` | `(key: string, min: number, max: number) => Array<[ArrayBuffer, number]>` | Get sorted set members with scores in range |
| `.zscan` | `(key: string, pattern: string) => Array<[ArrayBuffer, number]>` | Get sorted set members matching value prefix |
| `.bfExists` | `(key: string, value: string) => boolean` | Check if value exists in Bloom Filter |

**Important:** There is no `store.set()`, `store.delete()`, or `store.list()`. The KV store is **read-only** from the app — data is written via the Gcore portal or API.

---

### `fastedge::fs` — Build-time File Embedding

**Only available at build-time initialization**, not during request handling. Used to embed static files into the Wasm binary.

```ts
import { readFileSync } from "fastedge::fs";

// Runs at build time — embeds file bytes into the binary
const html = readFileSync("./public/index.html");  // Uint8Array
```

| Function | Signature | Description |
|----------|-----------|-------------|
| `readFileSync` | `(path: string) => Uint8Array` | Read file bytes at build time |

---

### `FetchEvent` and `ClientInfo`

```ts
addEventListener('fetch', (event: FetchEvent) => {
  const ip = event.client.address;          // "1.2.3.4"
  const tls = event.client.tlsProtocol;     // "TLSv1.3"

  event.respondWith(new Response("ok"));
  event.waitUntil(sendTelemetry());         // Stay alive for post-response async work
});
```

**`FetchEvent`:**

| Member | Type | Description |
|--------|------|-------------|
| `.request` | `Request` | Incoming HTTP request |
| `.client` | `ClientInfo` | Downstream client info |
| `.respondWith(r)` | `(Response \| Promise<Response>) => void` | Send response |
| `.waitUntil(p)` | `(Promise<any>) => void` | Extend lifetime for post-response async work |

**`ClientInfo`:**

| Property | Type | Description |
|----------|------|-------------|
| `.address` | `string` | IPv4 or IPv6 address |
| `.tlsProtocol` | `string` | TLS version (e.g. `"TLSv1.3"`) |
| `.tlsCipherOpensslName` | `string` | Cipher suite name |
| `.tlsJA3MD5` | `string` | JA3 TLS fingerprint MD5 |
| `.tlsClientCertificate` | `ArrayBuffer` | Client certificate bytes |
| `.tlsClientHello` | `ArrayBuffer` | Raw TLS ClientHello bytes |

---

### Web APIs Available

FastEdge runs on **StarlingMonkey** (SpiderMonkey-based Wasm runtime).

**Fetch:** `fetch()`, `Request`, `Response`, `Headers`, `Body`
**URL:** `URL`, `URLSearchParams`
**Encoding:** `TextEncoder`, `TextDecoder`, `atob()`, `btoa()`
**Crypto:** `crypto.getRandomValues()`, `crypto.randomUUID()`, `crypto.subtle.digest()`, `crypto.subtle.sign()`, `crypto.subtle.verify()`, `crypto.subtle.importKey()`
**Streams:** `ReadableStream`, `WritableStream`, `TransformStream`
**Timers:** `setTimeout()`, `clearTimeout()`, `setInterval()`, `clearInterval()`
**Console:** `console.log/warn/error/debug/info/assert/count/time/timeEnd` etc.
**Performance:** `performance.now()`, `performance.timeOrigin`
**Other:** `structuredClone()`, `queueMicrotask()`

**NOT available:** WebSocket, localStorage, sessionStorage, DOM APIs, Node.js APIs (`fs`, `path`, `process`, etc.)

> For the full `crypto.subtle` operation matrix, why Node.js crypto polyfills don't work, and SAML/XMLDSig implementation guidance, see `./js-runtime.md`.

---

### Hono Integration

Hono is the recommended framework for routing. Use standard Hono patterns — the only FastEdge-specific change is `app.fire()` instead of `export default app`.

```ts
import { Hono } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";

const app = new Hono();

app.use("/*", cors());
app.use("/*", logger());

app.onError((err, c) => {
  return c.json({ error: "Internal Server Error" }, 500);
});

app.notFound((c) => c.json({ error: "Not Found" }, 404));

app.get("/api/items/:id", (c) => {
  const id = c.req.param("id");
  return c.json({ id });
});

app.fire();  // ← FastEdge-specific: replaces export default
```

---

## Rust SDK (`fastedge` crate + `fastedge-derive`)

**Sources:** `docs.rs/fastedge` and `docs.rs/fastedge-derive`

### `Cargo.toml`

```toml
[dependencies]
fastedge = "0.1"

[lib]
crate-type = ["cdylib"]

[profile.release]
opt-level = "s"
lto = true
strip = true
codegen-units = 1
```

```toml
# .cargo/config.toml
[build]
target = "wasm32-wasip1"
```

---

### `#[fastedge::http]` — HTTP Handler Macro

From `fastedge-derive`. Marks a function as the HTTP handler and generates the WebAssembly component exports.

```rust
use fastedge::http::{Request, Response, StatusCode, Error};

#[fastedge::http]
fn main(req: Request<Vec<u8>>) -> Result<Response<Vec<u8>>, Error> {
    let path = req.uri().path();

    match path {
        "/" => Ok(Response::builder()
            .status(StatusCode::OK)
            .header("Content-Type", "text/plain")
            .body(b"Hello FastEdge!".to_vec())?),
        "/health" => Ok(Response::builder()
            .status(StatusCode::OK)
            .header("Content-Type", "application/json")
            .body(b"{\"status\":\"ok\"}".to_vec())?),
        _ => Ok(Response::builder()
            .status(StatusCode::NOT_FOUND)
            .body(b"Not Found".to_vec())?),
    }
}
```

Function signature must be: `fn(Request<Vec<u8>>) -> Result<Response<Vec<u8>>, Error>`

---

### `fastedge::http` — HTTP Types

Re-exports from the `http` crate:

```rust
use fastedge::http::{Request, Response, StatusCode, Error, Method, Uri, HeaderMap};

// Read request
let method = req.method();               // &Method
let path = req.uri().path();             // &str
let query = req.uri().query();           // Option<&str>
let headers = req.headers();             // &HeaderMap
let auth = req.headers().get("authorization");
let body: &Vec<u8> = req.body();
let body_str = String::from_utf8_lossy(body);
```

---

### `fastedge::send_request` — Outbound HTTP

```rust
use fastedge::http::{Request, Body};

let outbound = Request::builder()
    .method("GET")
    .uri("https://api.example.com/data")
    .header("Authorization", "Bearer token")
    .body(Body::empty())?;

let resp = fastedge::send_request(outbound)?;
let status = resp.status();
```

---

### `fastedge::key_value` — KV Store

```rust
use fastedge::key_value::Store;

let store = Store::open("my-store")?;
let value: Option<Vec<u8>> = store.get("key")?;

if let Some(bytes) = value {
    let text = String::from_utf8(bytes)?;
}
```

---

### `fastedge::secret` — Secrets

```rust
use fastedge::secret;

let token: Option<Vec<u8>> = secret::get("API_TOKEN")?;
if let Some(bytes) = token {
    let token_str = String::from_utf8(bytes)?;
}
```

---

### Environment Variables (Rust)

Use Rust's standard `std::env`:

```rust
use std::env;
let value = env::var("MY_CONFIG").unwrap_or_else(|_| "default".to_string());
```

---

### JSON Handling (Rust)

```toml
# Cargo.toml
[dependencies]
fastedge = "0.1"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

```rust
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
struct ApiResponse { message: String }

#[fastedge::http]
fn main(req: Request<Vec<u8>>) -> Result<Response<Vec<u8>>, Error> {
    let resp = ApiResponse { message: "Hello!".into() };
    let json = serde_json::to_vec(&resp).map_err(|e| Error::Other(e.to_string()))?;
    Ok(Response::builder()
        .status(StatusCode::OK)
        .header("Content-Type", "application/json")
        .body(json)?)
}
```

---

### Feature Flags

| Flag | Default | Description |
|------|---------|-------------|
| `proxywasm` | on | ProxyWasm compatibility layer |
| `json` | off | Enables `serde_json` body support |

```toml
fastedge = { version = "0.1", features = ["json"] }
```
