# Synthesis Instructions: test-config.md

## Target file
`plugins/gcore-fastedge/skills/test/reference/test-config.md`

## Audience
AI agents helping developers configure the `test-config.json` file for their FastEdge app.

## Output goal
A complete schema reference for `test-config.json`. Agents use this to generate correct config files and to explain each field to developers. Prioritise precision and completeness over brevity.

## Required sections (in this order)

1. **Purpose** — one sentence: what test-config.json does and when it auto-loads (debugger + test framework)

2. **Schema** — every top-level field as a table: field | type | required | default | description. Include:
   - `$schema` — path to the bundled JSON schema for IDE validation
   - `description` — human label for this config
   - `wasm.path` — relative path to the compiled WASM binary
   - `wasm.description` — optional label
   - `request.method`, `request.url`, `request.headers`, `request.body`
   - `properties` — CDN-only; list all 9 available property keys with their types
   - `logLevel` — numeric values 0–4 mapped to trace/debug/info/warn/error
   - `envVars` — key/value object for environment variables
   - `secrets` — key/value object for secrets (use placeholder values when committing)

3. **Secrets and env vars via .env** — the two approaches side by side:
   - Option A: inline in test-config.json (suitable for placeholders)
   - Option B: dotenv file with prefixes (`FASTEDGE_VAR_ENV_`, `FASTEDGE_VAR_SECRET_`, `FASTEDGE_VAR_REQ_HEADER_`, `FASTEDGE_VAR_RSP_HEADER_`)

4. **CDN example** — complete `test-config.json` for a proxy-wasm app with realistic values

5. **HTTP-WASM example** — complete `test-config.json` for an HTTP-WASM app (no `properties` field needed)

6. **What to commit / gitignore** — two-line rule: commit `test-config.json` (with placeholders), ignore `.env*` files that contain real secrets

## What to exclude
- How to run tests (that belongs in testing-api.md)
- Debugger UI details (that belongs in vscode-debugger.md)
- Installation instructions
- History or changelog

## Quality bar
The existing file at `plugins/gcore-fastedge/skills/test/reference/test-config.md` sets the quality bar. Update field descriptions and property list to match the current package version — do not restructure unless the config schema has changed.
