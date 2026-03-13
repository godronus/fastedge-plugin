# Reference Material — How It Was Built & How to Update It

This documents the sources, method, and maintenance process for the `fastedge-docs` reference files.

---

## Reference Files

| File | Content | Primary Source | Status |
|------|---------|----------------|--------|
| `sdk-reference.md` | Full JS + Rust SDK API | `FastEdge-sdk-js/types/*.d.ts` + `docs.rs/fastedge` | ✅ Has real content |
| `platform-overview.md` | Architecture, PoPs, limits, app types | Written from platform knowledge | ✅ Has real content |
| `best-practices.md` | Patterns, Hono, KV usage, optimisation | `FastEdge-sdk-js/docs/examples/` + `FastEdge-examples/` | ⚠️ Review needed |
| `error-codes.md` | 530–533 debugging guidance | Written from platform knowledge | ⚠️ Review needed |
| `js-runtime.md` | StarlingMonkey runtime constraints, crypto.subtle matrix, SAML implementation guide | Derived from SAML app development (March 2026) | ✅ Has real content |

---

## Sources Used (March 2026)

### 1. `FastEdge-sdk-js` repo (local — in coordinator)

**Path:** `FastEdge-sdk-js/`

The authoritative source for all JavaScript SDK APIs. Read these files directly:

| File | What it contains |
|------|-----------------|
| `types/fastedge-env.d.ts` | `getEnv()` API |
| `types/fastedge-secret.d.ts` | `getSecret()`, `getSecretEffectiveAt()` APIs |
| `types/fastedge-kv.d.ts` | Full `KvStore` API with all methods and signatures |
| `types/fastedge-fs.d.ts` | `readFileSync()` build-time API |
| `types/globals.d.ts` | All Web APIs: `FetchEvent`, `ClientInfo`, `Request`, `Response`, `Headers`, `crypto`, streams, timers, etc. |
| `docs/examples/*.js` | Canonical working examples |
| `docs/src/content/docs/reference/` | Astro docs reference pages |
| `docs/src/content/docs/examples/*.mdx` | Example walkthroughs |

**Critical:** The `types/*.d.ts` files are the ground truth for the JS SDK API. Always read these when updating — do not guess from memory.

### 2. `FastEdge-examples` repo (local — in coordinator)

**Path:** `FastEdge-examples/`

Working example code for both JS and Rust. Useful for verifying patterns and finding real-world usage:

| Path | What it contains |
|------|-----------------|
| `javascript/src/*/src/index.ts` | Working TypeScript examples |
| `rust/http/*/` | Working Rust HTTP handler examples |
| `rust/cdn/*/` | Working Rust CDN wireframe examples |

### 3. `docs.rs/fastedge` (fetched via WebFetch)

**URL:** `https://docs.rs/fastedge/latest/fastedge/`

Rust SDK API documentation. Covers:
- `#[fastedge::http]` macro (from `fastedge-derive`)
- `fastedge::http` module (re-exports from `http` crate)
- `fastedge::key_value` — `Store::open()`, `get()`
- `fastedge::secret` — `secret::get()`
- `fastedge::send_request` — outbound HTTP
- Feature flags: `proxywasm`, `json`

**Note:** `crates.io` requires JavaScript rendering — use `docs.rs` instead which serves static HTML.

### 4. `docs.rs/fastedge-derive` (fetched via WebFetch)

**URL:** `https://docs.rs/fastedge-derive/latest/fastedge_derive/`

Documents the `#[fastedge::http]` procedural macro specifically.

---

## How to Update the Reference Files

### When the JS SDK changes

1. Check what changed in `FastEdge-sdk-js`:
   ```bash
   git -C FastEdge-sdk-js log --oneline -10
   git -C FastEdge-sdk-js diff HEAD~1 types/
   ```

2. Read the updated `types/*.d.ts` files — they are the source of truth

3. Update `sdk-reference.md` to match — pay particular attention to:
   - `KvStore` API (historically had drift between docs and actual API)
   - New modules or functions in `types/index.d.ts`

4. Fix any affected patterns in `best-practices.md`

### When the Rust SDK changes

1. Fetch updated API: `WebFetch https://docs.rs/fastedge/latest/fastedge/`

2. Check the version on `crates.io` to know if there's been a release:
   ```bash
   curl -s "https://crates.io/api/v1/crates/fastedge" | jq '.crate.newest_version'
   ```

3. Update `sdk-reference.md` Rust section

### When platform limits or features change

Update `platform-overview.md` — resource limits table, app types, networking capabilities.

### After updating reference files

Bump the plugin version in `plugins/gcore-fastedge/.claude-plugin/plugin.json`:
```json
{ "version": "1.0.1" }
```

And the marketplace version in `.claude-plugin/marketplace.json` to match.

---

## Known Issues / Gaps (March 2026)

- **`platform-overview.md` resource limits** — plan limits (50ms/128MB basic, 200ms/256MB pro) are from memory, not confirmed from official docs. Verify against `gcore.com/docs/fastedge` before publishing.
- **Rust `key_value` API** — scan, sorted set, and bloom filter operations may exist in Rust but were not confirmed from docs.rs (the page was sparse). Check `docs.rs/fastedge` for the full `key_value::Store` API.
- **`fastedge-docs` SKILL.md** auto-invocation — the `disable-model-invocation: false` setting means this skill makes an additional LLM call. These reference files are loaded as context for that call.

---

## Future Enhancement: GitHub Actions Sync Pipeline

The current approach is **manual** — a human or agent reads the sources and updates the files. The long-term goal is an automated pipeline.

### Proposed Architecture

```
GitHub Actions workflow (scheduled: weekly or on SDK release)
  │
  ├── Step 1: Fetch JS SDK types
  │   git clone FastEdge-sdk-js → read types/*.d.ts → diff against current sdk-reference.md
  │
  ├── Step 2: Fetch Rust SDK docs
  │   curl https://docs.rs/fastedge/latest/fastedge/ → parse HTML → extract API
  │   curl https://crates.io/api/v1/crates/fastedge → get latest version
  │
  ├── Step 3: Read FastEdge-examples
  │   Read javascript/ and rust/ example files for pattern verification
  │
  ├── Step 4: Regenerate reference files
  │   Run a script (or Claude API call) to produce updated Markdown
  │
  ├── Step 5: Bump plugin semver
  │   If any reference file changed → bump patch version in plugin.json files
  │
  └── Step 6: Open PR (or auto-merge to main)
      Users who installed via marketplace will see update on next /plugin update
```

### Why Semver Matters Here

The Claude Code plugin marketplace uses semver for update detection. When users run `/plugin update`, it checks the version in `plugin.json`. Bumping the version on every reference update means:
- Users automatically get fresh docs on their next update
- The changelog is visible as a git diff
- No user action required beyond the initial install

### Trigger Options

| Trigger | Pros | Cons |
|---------|------|------|
| Weekly schedule | Simple, predictable | May miss same-day releases |
| On SDK release event (webhook) | Immediate sync | Requires webhook setup between repos |
| Manual dispatch | Full control | Requires human to remember |
| Recommended: weekly + manual dispatch | Best of both | Slightly more workflow config |

### Implementation Notes

- `docs.rs` serves static HTML — parseable with standard tools, but fragile if page structure changes
- `crates.io` has a JSON API (`/api/v1/crates/{name}`) — stable and easy to query
- `FastEdge-sdk-js` types are TypeScript — could parse with `ts-morph` or just read the `.d.ts` directly
- Consider using Claude API (via `claude-developer-platform` skill) to do the Markdown regeneration step rather than hand-writing a parser

### Files to Create When Implementing

- `.github/workflows/sync-reference-docs.yml` — the workflow
- `scripts/sync-reference-docs.js` (or `.sh`) — the sync script
- Update this file (`REFERENCE_MATERIAL.md`) with the new automated process
