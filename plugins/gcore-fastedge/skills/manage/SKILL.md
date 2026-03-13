---
disable-model-invocation: true
argument-hint: "[list|get|update|delete|secrets|sync-env] [app-id]"
description: List, get, update, or delete FastEdge apps, manage secrets, and sync dotenv files
---

# Manage FastEdge Apps

Manage your deployed FastEdge applications.

## Instructions

Parse the user's arguments to determine the subcommand:
- `list` — List all apps
- `get <id>` — Get details for a specific app
- `update <id>` — Update an app's configuration
- `delete <id>` — Delete an app (with confirmation)
- `secrets list` — List all secrets
- `secrets get <name>` — Get secret ID by name
- `sync-env <id-or-name>` — Sync dotenv files to a deployed app

If no subcommand is provided, default to `list`. For `secrets` with no further argument, default to `secrets list`.

### Pre-flight

Always verify `GCORE_API_KEY` is set first:
```bash
if [ -z "$GCORE_API_KEY" ]; then
  echo "Error: GCORE_API_KEY is not set."
  echo "Get your API key from https://portal.gcore.com → API Keys"
  exit 1
fi
```

---

## Subcommand: `list`

Fetch all apps and display as a formatted table.

```bash
APPS=$(curl -s "https://api.gcore.com/fastedge/v1/apps" \
  -H "Authorization: APIKey $GCORE_API_KEY")
```

Format the output as a table with columns: **ID**, **Name**, **Status**, **URL**

Status values: `0` = Disabled, `1` = Enabled, `2` = Suspended

Example output:
```
ID      Name              Status    URL
─────   ────────────────  ────────  ──────────────────────────────
12345   my-app            Enabled   https://my-app.gcore.dev
12346   api-gateway       Enabled   https://api-gateway.gcore.dev
12347   old-service       Disabled  https://old-service.gcore.dev
```

If there are no apps, tell the user and suggest `/gcore-fastedge:scaffold` to create one.

---

## Subcommand: `get <id>`

Fetch details for a specific app.

```bash
APP=$(curl -s "https://api.gcore.com/fastedge/v1/apps/$APP_ID" \
  -H "Authorization: APIKey $GCORE_API_KEY")
```

Display all app details: name, ID, status, binary ID, plan, env vars, URL.

Optionally also fetch stats:
```bash
STATS=$(curl -s "https://api.gcore.com/fastedge/v1/apps/$APP_ID/stats" \
  -H "Authorization: APIKey $GCORE_API_KEY")
```

Show request count, error rates, and latency percentiles if stats are available.

---

## Subcommand: `update <id>`

Ask the user what they want to update. Supported fields:

- **name** — Change app name
- **status** — Enable (1) or disable (0) the app
- **binary** — Update to a new binary ID (or re-deploy with `/gcore-fastedge:deploy`)
- **env_vars** — Add, update, or remove environment variables
- **secrets** — Add or update secrets by referencing secret IDs: `"secrets": {"SECRET_NAME": {"id": <secret-id>}}`
- **rsp_headers** — Add or update response headers: `"rsp_headers": {"Header-Name": "value"}`
- **plan** — Change plan (basic/pro)

Build the update payload with only the changed fields:

```bash
curl -s -X PUT "https://api.gcore.com/fastedge/v1/apps/$APP_ID" \
  -H "Authorization: APIKey $GCORE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '<update-payload>'
```

Show the updated app details after the update.

---

## Subcommand: `delete <id>`

**Always confirm with the user before deleting.**

First, show the app details so the user knows what they're deleting:
```bash
APP=$(curl -s "https://api.gcore.com/fastedge/v1/apps/$APP_ID" \
  -H "Authorization: APIKey $GCORE_API_KEY")
```

Display the app name, ID, and URL. Ask: "Are you sure you want to delete this app? This cannot be undone."

Only after user confirms:
```bash
curl -s -X DELETE "https://api.gcore.com/fastedge/v1/apps/$APP_ID" \
  -H "Authorization: APIKey $GCORE_API_KEY"
```

Confirm deletion was successful.

---

## Subcommand: `secrets list`

Fetch all secrets and display as a formatted table.

```bash
SECRETS=$(curl -s "https://api.gcore.com/fastedge/v1/secrets" \
  -H "Authorization: APIKey $GCORE_API_KEY")
```

Format the output as a table with columns: **ID**, **Name**

Example output:
```
ID      Name
─────   ────────────────
1001    API_TOKEN
1002    DB_PASSWORD
```

If there are no secrets, tell the user.

---

## Subcommand: `secrets get <name>`

Look up a secret by name and return its ID. Use the `get-secret-id` tool to resolve the name.

Display the secret ID so the user can reference it in `update` commands (e.g., `"secrets": {"SECRET_NAME": {"id": <secret-id>}}`).

---

## Subcommand: `sync-env <id-or-name>`

Read dotenv files from the project directory and push all environment variables, secrets, and response headers to a deployed app in one operation.

### Step 1: Identify the app

Resolve the argument to an app — accept either an app ID or app name.

### Step 2: Find and read dotenv files

Search the project directory (starting from the current directory, walking upward) for these files:

| File | Purpose |
|------|---------|
| `.env` | General dotenv file (parsed by prefix) |
| `.env.variables` | Environment variables only |
| `.env.secrets` | Secret references only |
| `.env.rsp_headers` | Response headers only |

All files are optional. If none are found, tell the user and exit.

### Step 3: Parse variables by prefix

Variables are categorized by prefix convention:

| Prefix | Category | Example |
|--------|----------|---------|
| `FASTEDGE_VAR_ENV_` | Environment variable | `FASTEDGE_VAR_ENV_API_URL=https://api.example.com` → `{"API_URL": "https://api.example.com"}` |
| `FASTEDGE_VAR_SECRET_` | Secret reference | `FASTEDGE_VAR_SECRET_AUTH_TOKEN=my-auth-token` → looks up secret named `my-auth-token` |
| `FASTEDGE_VAR_RSP_HEADER_` | Response header | `FASTEDGE_VAR_RSP_HEADER_X_Frame_Options=DENY` → `{"X-Frame-Options": "DENY"}` |

Variables in `.env.variables`, `.env.secrets`, and `.env.rsp_headers` don't need prefixes — their category is implied by the file.

### Step 4: Resolve secrets

For each secret reference, look up the secret ID via the API:

```bash
SECRET=$(curl -s "https://api.gcore.com/fastedge/v1/secrets?secret_name=$SECRET_NAME" \
  -H "Authorization: APIKey $GCORE_API_KEY")
```

Build the secrets payload: `{"SECRET_KEY": {"id": <resolved-id>}}`

If a secret name can't be resolved, warn the user and skip it.

### Step 5: Confirm with user

Display a summary of what will be pushed:

```
Environment variables:
  API_URL = https://api.example.com
  DEBUG = false

Secrets:
  AUTH_TOKEN → secret ID 1001

Response headers:
  X-Frame-Options = DENY

Push these to app "<app-name>" (ID: <app-id>)?
```

Wait for user confirmation before proceeding.

### Step 6: Push to app

```bash
curl -s -X PUT "https://api.gcore.com/fastedge/v1/apps/$APP_ID" \
  -H "Authorization: APIKey $GCORE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "env": {<env-vars>},
    "secrets": {<resolved-secrets>},
    "rsp_headers": {<response-headers>}
  }'
```

Show the result and confirm success.
