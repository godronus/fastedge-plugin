# Gcore FastEdge Plugin for Claude Code

Build, deploy, and manage serverless WebAssembly applications on [Gcore FastEdge](https://gcore.com/fastedge) — directly from Claude Code.

FastEdge runs Wasm workloads on 210+ global edge Points of Presence with sub-millisecond cold starts. This plugin gives Claude the skills to scaffold projects, deploy apps, and manage your edge infrastructure through natural language.

## Installation

Clone the repo:

```bash
git clone https://github.com/G-Core/fastedge-plugin.git
```

**Option 1: For testing (session only)**

Quit Claude Code and restart with the plugin loaded:

```bash
claude --plugin-dir /path/to/fastedge-plugin
```

**Option 2: Install via marketplace commands**

From inside Claude Code, add the local marketplace and install the plugin:

```
/plugin marketplace add /path/to/fastedge-plugin
/plugin install gcore-fastedge@gcore-fastedge-marketplace
```

This persists across sessions.

## Setup

1. Go to the [Gcore Portal](https://portal.gcore.com/)
2. Navigate to **Profile** → **API Keys** (or visit `portal.gcore.com/api-keys` directly)
3. Click **Create API Key**, give it a name, and copy the generated key
4. Set the environment variable:

```bash
export GCORE_API_KEY="your-api-key"
```

Or create a `.env` file in your project directory:

```
GCORE_API_KEY=your-api-key
```

Claude Code automatically loads `.env` files from the working directory.

## Available Skills

| Skill        | Command                                                                       | Description                                               |
| ------------ | ----------------------------------------------------------------------------- | --------------------------------------------------------- |
| **Scaffold** | `/gcore-fastedge:scaffold [http-base\|http-react\|http-react-hono\|cdn-base] [name]` | Generate a new FastEdge project via create-fastedge-app   |
| **Deploy**   | `/gcore-fastedge:deploy [app-name]`                                           | Build and deploy a Wasm app to FastEdge                   |
| **Manage**   | `/gcore-fastedge:manage [list\|get\|update\|delete] [id]`                    | List, inspect, update, or delete apps                     |
| **Docs**     | Auto-invoked                                                                  | FastEdge platform docs, SDK reference, and best practices |

## Example Usage

Ask Claude naturally:

- **"Scaffold a new http-base app called my-api"** — runs `create-fastedge-app` to generate a TypeScript + Hono project
- **"Deploy this app to FastEdge"** — builds the Wasm binary and deploys it to the edge
- **"List my FastEdge apps"** — shows all your deployed apps with status and URLs
- **"How does the FastEdge KV store work?"** — pulls up SDK reference docs inline

## Plugin Structure

```
fastedge-plugin/
├── .claude-plugin/
│   ├── marketplace.json
│   └── plugin.json
└── plugins/
    └── gcore-fastedge/
        ├── .claude-plugin/
        │   └── plugin.json
        ├── CLAUDE.md
        └── skills/
            ├── fastedge-docs/
            │   ├── SKILL.md
            │   └── reference/
            │       ├── best-practices.md
            │       ├── error-codes.md
            │       ├── platform-overview.md
            │       └── sdk-reference.md
            ├── deploy/
            │   └── SKILL.md
            ├── manage/
            │   └── SKILL.md
            └── scaffold/
                └── SKILL.md
```

## Links

- [Gcore FastEdge Documentation](https://gcore.com/docs/fastedge)
- [Gcore Portal](https://portal.gcore.com/)
- [FastEdge API Reference](https://api.gcore.com/docs/fastedge)
