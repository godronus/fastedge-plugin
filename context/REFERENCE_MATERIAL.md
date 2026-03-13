# Reference Material — How It Was Built & How to Update It

This documents the sources, method, and maintenance process for the `fastedge-docs` reference files.

---

## Reference Files

| File                   | Content                                                                             | Primary Source                                          | Status              |
| ---------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------- | ------------------- |
| `sdk-reference.md`     | Full JS + Rust SDK API                                                              | `FastEdge-sdk-js/types/*.d.ts` + `docs.rs/fastedge`     | ✅ Has real content |
| `platform-overview.md` | Architecture, PoPs, limits, app types                                               | Written from platform knowledge                         | ✅ Has real content |
| `best-practices.md`    | Patterns, Hono, KV usage, optimisation                                              | `FastEdge-sdk-js/docs/examples/` + `FastEdge-examples/` | ⚠️ Review needed    |
| `error-codes.md`       | 530–533 debugging guidance                                                          | Written from platform knowledge                         | ⚠️ Review needed    |
| `js-runtime.md`        | StarlingMonkey runtime constraints, crypto.subtle matrix, SAML implementation guide | Derived from SAML app development (March 2026)          | ✅ Has real content |

---

## Sources Used (March 2026)

### 1. `FastEdge-sdk-js` repo (local — in coordinator)

**Path:** `FastEdge-sdk-js/`

The authoritative source for all JavaScript SDK APIs. Read these files directly:

| File                                   | What it contains                                                                                            |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `types/fastedge-env.d.ts`              | `getEnv()` API                                                                                              |
| `types/fastedge-secret.d.ts`           | `getSecret()`, `getSecretEffectiveAt()` APIs                                                                |
| `types/fastedge-kv.d.ts`               | Full `KvStore` API with all methods and signatures                                                          |
| `types/fastedge-fs.d.ts`               | `readFileSync()` build-time API                                                                             |
| `types/globals.d.ts`                   | All Web APIs: `FetchEvent`, `ClientInfo`, `Request`, `Response`, `Headers`, `crypto`, streams, timers, etc. |
| `docs/examples/*.js`                   | Canonical working examples                                                                                  |
| `docs/src/content/docs/reference/`     | Astro docs reference pages                                                                                  |
| `docs/src/content/docs/examples/*.mdx` | Example walkthroughs                                                                                        |

**Critical:** The `types/*.d.ts` files are the ground truth for the JS SDK API. Always read these when updating — do not guess from memory.

### 2. `FastEdge-examples` repo (local — in coordinator)

**Path:** `FastEdge-examples/`

Working example code for both JS and Rust. Useful for verifying patterns and finding real-world usage:

| Path                            | What it contains                    |
| ------------------------------- | ----------------------------------- |
| `javascript/src/*/src/index.ts` | Working TypeScript examples         |
| `rust/http/*/`                  | Working Rust HTTP handler examples  |
| `rust/cdn/*/`                   | Working Rust CDN wireframe examples |

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

## GitHub Actions Sync Pipeline

Reference files are updated automatically via a GitHub Actions pipeline. A human reviews and merges the generated PRs.

### Three Documents a Maintainer Needs

| Document                                    | Purpose                                                                                                            |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `sources.json` (repo root)                  | Declares which repos are fetched, which paths, which reference files are written, and which agents generate/review |
| `.github/workflows/sync-reference-docs.yml` | The pipeline workflow — triggers, per-repo loop, dry_run guard, step summary                                       |
| `context/sources-json-schema.md`            | Authoritative schema + validation rules + traceability frontmatter format                                          |

### Pipeline Architecture

```
workflow_dispatch / repository_dispatch (fastedge-ref-update)
  │
  ├── validate-sources.sh sources.json     ← exits 1 on any schema violation
  │
  └── process-repos.sh
        for each repo in sources.json:
          process_repo()                   ← isolated; failure does not block others
            fetch-repo.sh                  ← sparse checkout only; compare baseline tag
            │
            for each UpdateEntry:
              invoke-agent.sh --role generator ← claude -p with synthesis intent
              invoke-agent.sh --role reviewer  ← OpenAI gpt-4o, VERDICT + FINDINGS
            │
            [dry_run gate — skips writes/PR/tag when dry_run=true]
            │
            if all steps succeed:
              invoke-agent.sh --role splice ← section-splice into reference file
              manage-pr.sh                  ← create/update PR; add/remove labels
              git tag ref-update/<repo-id>  ← update baseline (branchless)
            else:
              record_failure(), continue    ← per-repo isolation
```

### Triggers

| Trigger                                       | Input                                              | Behaviour                                                          |
| --------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------ |
| `workflow_dispatch`                           | `source_repo_id` (optional), `dry_run` (bool)      | Process all `schedule`/`both` repos, or only the named one         |
| `repository_dispatch` (`fastedge-ref-update`) | `client_payload.source_repo_id`, `.ref`, `.commit` | Process only the identified repo; validated against `sources.json` |

### Scripts

| Script                             | Purpose                                                                                   |
| ---------------------------------- | ----------------------------------------------------------------------------------------- |
| `scripts/sync/validate-sources.sh` | Validates `sources.json` against all schema rules including `intent_file` existence       |
| `scripts/sync/fetch-repo.sh`       | Sparse checkout a single source repo; emit `CHANGED=true/false`; read/write baseline tags |
| `scripts/sync/invoke-agent.sh`     | Generator (claude), reviewer (OpenAI gpt-4o), and section-splice roles                    |
| `scripts/sync/manage-pr.sh`        | Create-or-update PR via `gh` CLI; `needs-review` label management                         |
| `scripts/sync/process-repos.sh`    | Main pipeline loop; per-repo isolation via `process_repo()` / `record_failure()`          |

### Synthesis Intent Files

Each `UpdateEntry` in `sources.json` may specify an `intent_file` pointing to a Markdown file under `agent-intent-skills/<repo-id>/`. When set, the generator prompt receives a `## Synthesis Instructions` block from that file, giving per-reference-file shaping guidance.

### Testing

Plain bash test suite — no external dependencies. Uses path-shimable mocks in `scripts/sync/tests/mocks/` for `gh` and `git`. Run all tests with:

```bash
bash scripts/sync/tests/run-all-tests.sh
```

| Test file                  | Coverage                                                                             |
| -------------------------- | ------------------------------------------------------------------------------------ |
| `test-validate-sources.sh` | All 7 schema rules                                                                   |
| `test-fetch-repo.sh`       | Arg validation, path anchoring, `CHANGED` detection, baseline tag parsing            |
| `test-verdict-parse.sh`    | `VERDICT`/`FINDINGS` parse logic                                                     |
| `test-section-splice.sh`   | Section splice — mid-file, EOF, not found, multiple sections, multi-repo frontmatter |
| `test-process-repos.sh`    | Loop isolation — trigger filter, `FILTER_REPO_ID`, dry_run gate, fetch failure       |

### Notes

- `FastEdge-examples` is excluded from `sources.json` — repo is being deprecated. `best-practices.md` source is TBD.
- `gh api` is used for Rule 2 URL reachability checks (supports SAML-protected private repos via PAT).
- Baseline state is stored as annotated git tags (`refs/tags/ref-update/<repo-id>`), not committed files — branchless and queryable via `git ls-remote`.
- `OPENAI_API_KEY` and `ANTHROPIC_API_KEY` must be configured as repository secrets. See `specs/001-auto-ref-update/quickstart.md` for required PAT scopes.
