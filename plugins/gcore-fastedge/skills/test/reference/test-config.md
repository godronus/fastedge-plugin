# test-config.json Reference

`test-config.json` is a persistent configuration file for the `@gcoredev/fastedge-test` visual debugger.
It saves the WASM path, request setup, and CDN properties so you can re-run the same scenario repeatedly
without reconfiguring each time. It can also be loaded programmatically in test suites.

---

## Full Schema

```json
{
  "$schema": "./node_modules/@gcoredev/fastedge-test/schemas/test-config.schema.json",
  "description": "Human-readable description of this test scenario",
  "wasm": {
    "path": "build/app.wasm",
    "description": "What this binary does"
  },
  "request": {
    "method": "GET",
    "url": "https://example.com/path",
    "headers": {
      "content-type": "application/json"
    },
    "body": ""
  },
  "properties": {
    "request.country": "US",
    "request.city": "New York",
    "request.geo.lat": "40.7128",
    "request.geo.long": "-74.0060",
    "request.continent": "NA",
    "request.region": "NY",
    "request.country.name": "United States"
  },
  "logLevel": 0,
  "envVars": {
    "API_URL": "https://api.example.com"
  },
  "secrets": {
    "AUTH_TOKEN": "local-test-value"
  }
}
```

---

## Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `$schema` | string | no | JSON schema path for editor validation |
| `description` | string | no | Human-readable label for this config |
| `wasm.path` | string | yes | Path to compiled `.wasm` file, relative to project root |
| `wasm.description` | string | no | What the binary does |
| `request.method` | string | yes | HTTP method: `GET`, `POST`, `PUT`, `DELETE`, etc. |
| `request.url` | string | yes | Full URL including scheme, host, and path |
| `request.headers` | object | no | HTTP request headers as key-value pairs |
| `request.body` | string | no | Request body (for POST/PUT requests) |
| `properties` | object | no | CDN properties to simulate (CDN apps only — see below) |
| `logLevel` | number | no | `0`=trace, `1`=debug, `2`=info, `3`=warn, `4`=error |
| `envVars` | object | no | Environment variables injected into the WASM app |
| `secrets` | object | no | Secret values for local testing (not committed in production) |

---

## Available CDN Properties

The `properties` block simulates CDN-provided request context for proxy-wasm apps.
These are the commonly available properties:

| Property | Type | Example |
|----------|------|---------|
| `request.country` | string | `"US"` (ISO 3166-1 alpha-2) |
| `request.country.name` | string | `"United States"` |
| `request.city` | string | `"New York"` |
| `request.region` | string | `"NY"` |
| `request.continent` | string | `"NA"` |
| `request.geo.lat` | string | `"40.7128"` |
| `request.geo.long` | string | `"-74.0060"` |
| `request.asn` | string | `"15169"` |
| `request.ip` | string | `"1.2.3.4"` |

Properties not listed here may be read but can trigger property access violations if
`enforceProductionPropertyRules` is `true` (the default).

---

## Using with the Visual Debugger

```bash
npx @gcoredev/fastedge-test
# OR if you added the script:
npm run debug
```

Opens at `http://localhost:5179`. The debugger auto-loads `test-config.json` from the
project root if it exists. You can also load config files manually from the UI.

The debugger lets you:
- Execute the WASM with a click
- See all hook results, logs, and property accesses visually
- Edit request/properties on the fly and re-run

---

## Loading Programmatically

Use `loadConfigFile()` to reuse your test-config.json inside test suites — avoids duplicating
the request setup:

```typescript
import { defineTestSuite, runAndExit, runFlow, loadConfigFile } from '@gcoredev/fastedge-test/test';
import { assertFinalStatus } from '@gcoredev/fastedge-test/test';

const config = await loadConfigFile('./test-config.json');

await runAndExit(defineTestSuite({
  wasmPath: config.wasm.path,
  tests: [
    {
      name: 'happy path from saved config',
      run: async (runner) => {
        const result = await runFlow(runner, {
          url: config.request.url,
          method: config.request.method ?? 'GET',
          requestHeaders: config.request.headers ?? {},
          properties: config.properties ?? {},
        });
        assertFinalStatus(result, 200);
      },
    },
  ],
}));
```

---

## Two Ways to Provide Secrets

The `secrets` field in `test-config.json` is convenient but stores values in plaintext.
For real secrets, use `.env` files instead and enable dotenv support.

### Option A — In test-config.json (commit-safe placeholders only)

```json
{
  "secrets": {
    "SESSION_SECRET": "local-only-placeholder",
    "IDP_CERT": "REPLACE_WITH_REAL_CERT_IN_ENV"
  }
}
```

Commit the file with placeholder values. Developers replace them locally if needed.
Do not commit real secret values.

### Option B — Via .env file (recommended for real secrets)

Create a `.env` file in the project root (add to `.gitignore`):

```bash
FASTEDGE_VAR_SECRET_SESSION_SECRET=real-local-secret
FASTEDGE_VAR_SECRET_IDP_CERT=-----BEGIN CERTIFICATE-----...
FASTEDGE_VAR_ENV_IDP_ENTITY_ID=https://idp.example.com
```

Then enable dotenv in your test suite:
```typescript
defineTestSuite({
  wasmPath: './build/app.wasm',
  runnerConfig: { dotenvEnabled: true },
  tests: [ ... ],
})
```

Or in VSCode's `.vscode/launch.json`:
```json
{ "version": "0.2.0", "configurations": [{ "dotenv": true }] }
```

When both `secrets` in `test-config.json` AND a `.env` file are present, the `.env` values
take precedence (higher in the override hierarchy).

Full dotenv documentation: `./vscode-debugger.md` — "Providing Secrets, Variables, and Headers"

---

## Best Practices

- **Commit `test-config.json`** — it encodes your test scenario and is useful for other developers.
- **Create multiple configs** for different scenarios:
  - `test-config.json` — default happy path
  - `test-config.error-case.json` — triggers an error condition
  - `test-config.geo-block.json` — tests geo-blocking with a blocked country
- **Do not commit real secrets** in `secrets` — use placeholder values; put real values in `.env`.
- **Commit a `.env.example`** — placeholder values showing teammates what to configure locally.
- **HTTP-WASM apps** can omit the `properties` field entirely (CDN properties are not available).
- **Match `wasm.path` to your build output** — usually `build/app.wasm` for JS apps or
  `target/wasm32-wasip1/release/<crate>.wasm` for Rust apps.
