# Synthesis Instructions: vscode-debugger.md

## Target file
`plugins/gcore-fastedge/skills/test/reference/vscode-debugger.md`

## Audience
AI agents helping developers launch and use the FastEdge visual debugger (interactive WASM debugging in a browser UI).

## Output goal
A practical usage guide. Agents use this to walk developers through launching the debugger, providing secrets, and understanding what the UI shows. Focus on what a developer does — not how the debugger is built.

## Required sections (in this order)

1. **Two ways to launch** — side by side:
   - VSCode Extension: command name (`FastEdge: Debug Application`), prerequisites (extension installed), what happens (bundled server starts, browser opens)
   - npm / any editor: exact `npx @gcoredev/fastedge-test` command, prerequisite (Node.js), what happens

2. **Dual-mode behaviour** — the same binary operates in two modes depending on whether a test file is passed:
   - No argument → visual debugger UI at `http://localhost:5179`
   - With test file argument → headless test runner, exits 0/1
   - Include the exact command for each mode

3. **Providing secrets and environment variables** — both methods:
   - Inline in `test-config.json` (`envVars`, `secrets` fields) — best for placeholder values
   - Via dotenv files — list all supported prefixes: `FASTEDGE_VAR_ENV_`, `FASTEDGE_VAR_SECRET_`, `FASTEDGE_VAR_REQ_HEADER_`, `FASTEDGE_VAR_RSP_HEADER_`

4. **Variable priority** — ordered list from highest to lowest: VSCode `launch.json` > `.env` > `.env.variables` / `.env.secrets` / `.env.req_headers` / `.env.rsp_headers`

5. **What the UI shows** — brief list of panels so agents can describe the debugger to developers:
   - Request panel (method, URL, headers, body)
   - Response panel (status, headers, body)
   - Log stream (filterable by level: trace/debug/info/warn/error/critical)
   - Hook results (CDN only: onRequestHeaders, onRequestBody, onResponseHeaders, onResponseBody)
   - Property accesses (CDN only: which properties the filter read)

6. **What to commit / gitignore** — what is safe to commit (`test-config.json` with placeholders, `.env.example`) vs what must be ignored (`.env`, `.env.secrets`, `.env.variables`, etc.)

## What to exclude
- Bundling details or how the VSCode extension packages the server
- Port scanning / server identity logic (implementation detail)
- Architecture of the Express server or React frontend
- How to write test files (that belongs in testing-api.md)

## Quality bar
The existing file at `plugins/gcore-fastedge/skills/test/reference/vscode-debugger.md` sets the quality bar. Update launch commands and dotenv prefix list to match the current package version — do not restructure unless the debugger interface has changed.
