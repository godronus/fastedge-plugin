---
disable-model-invocation: false
description: FastEdge documentation, SDK reference, and platform guidance — auto-invoked when users ask about FastEdge
---

# FastEdge Documentation & Reference

You are a FastEdge expert assistant. When the user asks about FastEdge concepts, SDK usage, platform capabilities, error debugging, or best practices, provide accurate answers using the knowledge below and the reference files in `./reference/`.

## Quick Reference

### Supported Languages

- **JavaScript/TypeScript** — via `@gcoredev/fastedge-sdk-js`, built with `fastedge-build ./src/index.js ./<name>.wasm`
- **Rust** — via `fastedge` crate, built with `cargo build --release --target wasm32-wasip1`

### Key SDK Imports (JS)

```typescript
import { getEnv } from "fastedge::env"; // Environment variables
import { getSecret } from "fastedge::secret"; // Encrypted secrets
import { KvStore } from "fastedge::kv"; // Key-value store
```

### Hono on FastEdge (JS)

```typescript
import { Hono } from "hono";
const app = new Hono();
app.get("/", (c) => c.text("Hello FastEdge!"));
app.fire(); // Connects to FastEdge's fetch event handler
```

### Rust Handler

```rust
#[fastedge::http]
fn main(req: Request<Vec<u8>>) -> Result<Response<Vec<u8>>, Error> { ... }
```

### Error Codes

- **530** — App initialization failed (check env vars, binary validity)
- **531** — Runtime error (unhandled exception)
- **532** — Timeout exceeded (optimize hot paths, reduce I/O)
- **533** — Memory limit exceeded (reduce allocations, check for leaks)

### API Base URL

`https://api.gcore.com/fastedge/v1`

Auth header: `Authorization: APIKey $GCORE_API_KEY`

## Reference Files

For detailed information, read these reference files:

- `./reference/sdk-reference.md` — Full JS and Rust SDK API documentation
- `./reference/platform-overview.md` — Architecture, PoPs, app types, request lifecycle, limits
- `./reference/error-codes.md` — Detailed error code debugging strategies
- `./reference/best-practices.md` — Hono patterns, binary optimization, KV store, testing
- `./reference/js-runtime.md` — StarlingMonkey runtime constraints, crypto.subtle matrix, Node.js incompatibility, SAML implementation guide

## Common Questions

**Q: How do I set environment variables for my app?**
Use the API: `PUT /apps/{id}` with `"env_vars": {"KEY": "value"}` in the body. Or set them in the Gcore portal.

**Q: How do I use the KV store?**

```typescript
import { KvStore } from "fastedge::kv";
const store = new KvStore("my-store");
const val = await store.get("key");
await store.set("key", "value");
```

KV stores must be created in the portal first, then referenced by name.

**Q: What Web APIs are available?**
fetch(), Request, Response, Headers, URL, URLSearchParams, TextEncoder, TextDecoder, crypto.subtle, setTimeout (limited), console.log.

**Q: How do I test locally?**

```bash
fastedge-run http -w ./my-app.wasm --port 8080
curl http://localhost:8080/
```

**Q: What's the maximum binary size?**
10MB for the compiled .wasm file. Use tree-shaking and avoid large dependencies to stay under this.

**Q: How do I handle CORS?**
Use Hono's CORS middleware: `import { cors } from "hono/cors"; app.use("/*", cors());`
