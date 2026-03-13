---
disable-model-invocation: true
argument-hint: "[app-name]"
description: Build and deploy a FastEdge app to the edge
---

# Build & Deploy to FastEdge

Deploy the current project (or a specified app) to Gcore FastEdge.

## Instructions

### Step 1: Pre-flight Checks

1. **Verify API key** — Check that `GCORE_API_KEY` environment variable is set:
   ```bash
   if [ -z "$GCORE_API_KEY" ]; then
     echo "Error: GCORE_API_KEY is not set."
     echo "Get your API key from https://portal.gcore.com → API Keys"
     echo "Then: export GCORE_API_KEY=your-key-here"
     exit 1
   fi
   ```
   If not set, tell the user how to get and set it. Do not proceed.

2. **Detect project type** — Look for these files in the current directory or the specified app directory:
   - `asconfig.json` → AssemblyScript CDN app
   - `Cargo.toml` → Rust app
   - `package.json` (without `asconfig.json`) → JavaScript/TypeScript app

3. **Determine app name** — Use the argument if provided, otherwise use the directory name or `name` field from `package.json` / `Cargo.toml`.

### Step 1.5: Pre-deploy Test Check

**Do not deploy code that hasn't been tested locally.** Check for a test setup before building:

1. Look for `tests/*.test.ts`, `tests/*.test.js`, or `src/*.test.ts`
2. Look for a `test` script in `package.json`

**If tests exist:** Run them.
```bash
npm test
```
If tests fail, stop. Do not proceed to build or upload. Report the failures and tell the user
to fix them before deploying:
```
Tests failed — fix these before deploying:
  ✗ <failing test name>: <error>

Run `npm test` to check, or `npm run debug` to debug interactively.
```

**If no tests exist:** Warn the user:
```
No tests found for this project. It is strongly recommended to write tests before deploying.
Run `/gcore-fastedge:test` to generate a test suite.

Continuing with deployment anyway — but consider adding tests.
```
Do not block deployment if there are no tests, but make the recommendation clear.

### Step 2: Build

**JavaScript/TypeScript project:**
```bash
fastedge-build ./src/index.js ./<project-name>.wasm
```
The output `.wasm` file will be in the project root, named `<project-name>.wasm`.

**Rust project:**
```bash
cargo build --release --target wasm32-wasip1
```
The output `.wasm` file will be at `./target/wasm32-wasip1/release/<crate-name>.wasm`.

**AssemblyScript project (CDN app):**
```bash
npm run asbuild:release
```
The output `.wasm` file will be at `./build/release.wasm` (as configured in `asconfig.json`).

If the build fails, show the error output and help the user fix it. Do not proceed to upload.

### Step 3: Upload Binary

Upload the compiled `.wasm` file to FastEdge:

```bash
WASM_FILE="<path-to-wasm>"
BINARY_RESPONSE=$(curl -s -X POST "https://api.gcore.com/fastedge/v1/binaries/raw" \
  -H "Authorization: APIKey $GCORE_API_KEY" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"$WASM_FILE")

echo "$BINARY_RESPONSE"
BINARY_ID=$(echo "$BINARY_RESPONSE" | jq -r '.id')

if [ -z "$BINARY_ID" ] || [ "$BINARY_ID" = "null" ]; then
  echo "Error: Failed to upload binary"
  exit 1
fi
```

### Step 4: Create or Update App

**Check if app already exists by name:**
```bash
APP_NAME="<app-name>"
EXISTING_APP=$(curl -s "https://api.gcore.com/fastedge/v1/apps" \
  -H "Authorization: APIKey $GCORE_API_KEY" | jq -r ".[] | select(.name == \"$APP_NAME\") | .id")
```

**If app exists — update it:**
```bash
curl -s -X PUT "https://api.gcore.com/fastedge/v1/apps/$EXISTING_APP" \
  -H "Authorization: APIKey $GCORE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"binary\": $BINARY_ID}"
```

**If app doesn't exist — create it:**
```bash
APP_RESPONSE=$(curl -s -X POST "https://api.gcore.com/fastedge/v1/apps" \
  -H "Authorization: APIKey $GCORE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"$APP_NAME\",
    \"binary\": $BINARY_ID,
    \"status\": 1,
    \"env_vars\": {}
  }")

echo "$APP_RESPONSE"
APP_ID=$(echo "$APP_RESPONSE" | jq -r '.id')
```

### Step 5: Verify Deployment

Wait a few seconds for propagation, then verify:
```bash
sleep 3
APP_URL=$(echo "$APP_RESPONSE" | jq -r '.url')
echo "App URL: $APP_URL"
echo "Testing $APP_URL ..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$APP_URL")
echo "HTTP Status: $HTTP_STATUS"
```

### Step 6: Report Results

Print a deployment summary:
```
Deployment successful!

  App name:  <app-name>
  App ID:    <app-id>
  Binary ID: <binary-id>
  URL:       <url-from-api-response>
  Status:    <http-status>

  Manage: /gcore-fastedge:manage get <app-id>
```

If the status code is not 200, suggest debugging steps:
- 530: Check env vars and binary validity
- 531: Check for runtime errors in app code
- 532: App is timing out — optimize or upgrade plan
- 533: Memory limit exceeded — reduce binary/memory usage
- Other: The app may need a few more seconds to propagate

### Step 7: Insert Deployment Comments

After a successful deployment, insert a "magic comments" block at the top of the project's entry file (`src/index.ts` or `src/index.js` for JS, `src/lib.rs` for Rust) to track deployment metadata.

**For JavaScript/TypeScript (`src/index.ts` or `src/index.js`):**
```
/* FastEdge Deployment
 * appName: "<app-name>"
 * appId: "<app-id>"
 * appUrl: "<url-from-api-response>"
 * outputFile: "<path-to-wasm>"
 */
```

**For Rust (`src/lib.rs`):**
```
/* FastEdge Deployment
 * appName: "<app-name>"
 * appId: "<app-id>"
 * appUrl: "<url-from-api-response>"
 * outputFile: "<path-to-wasm>"
 */
```

**For AssemblyScript (`assembly/index.ts`):**
```
/* FastEdge Deployment
 * appName: "<app-name>"
 * appId: "<app-id>"
 * appUrl: "<url-from-api-response>"
 * outputFile: "build/release.wasm"
 */
```

If the file already contains a `/* FastEdge Deployment` block, replace it with the updated values. Otherwise, insert it at the top of the file (before any imports).
