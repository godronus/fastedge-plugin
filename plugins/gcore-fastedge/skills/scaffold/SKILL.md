---
disable-model-invocation: false
argument-hint: "[http|cdn] [project-name]"
description: Scaffold a new FastEdge project — starts with the CDN vs HTTP choice
---

# Scaffold a New FastEdge Project

Delegates entirely to `create-fastedge-app` — the single source of truth for FastEdge project templates.

## Scope Boundary — ABSOLUTE CONSTRAINT

**You operate exclusively inside the user's active project directory.**

Before every file read, glob, grep, or directory listing, verify the path stays inside the project root. If it does not, stop — do not execute the tool call.

Prohibited at all times, no exceptions:
- Any path containing `../`
- Listing or reading the parent directory of the project
- Reading sibling directories (other projects, nearby repos, example repos)
- Using the workspace root as a base for searches unless it IS the project root

**All information needed for scaffolding is in this skill file and the plugin knowledge base.** If you need to understand what template to use, what SDK to import, or how to structure the project — read the skill instructions and knowledge base, not the filesystem. Ask the user if something is unclear.

---

## Intake Protocol — Collect Before You Research

**Before doing any research, reading examples, or searching documentation, collect the three inputs below. Do not read external repos, browse GitHub, or look up SDK patterns until all three are confirmed.**

This applies even when the user's description sounds like it implies a type — "gateway for CDN resources", "auth filter at the edge", "SAML for CDN" are all ambiguous. Do not assume. Ask.

---

## Step 1: Establish App Type (CDN vs HTTP)

**This is the most important decision.** The two app types run in completely different environments.

Always ask unless the user has used one of these exact phrases: "CDN app", "CDN filter", "Proxy-WASM", "HTTP app", "HTTP handler", or explicitly named a template (`cdn-base`, `http-base`, etc.). Descriptions of use cases — no matter how suggestive — require clarification.

---

**HTTP apps** run as standalone serverless functions — they receive an HTTP request and return an HTTP response, like a normal server endpoint. Use these for APIs, web apps, MCP servers, or edge middleware.

- Languages: **JavaScript, TypeScript, Rust**
- Templates: `http-base`, `http-react`, `http-react-hono`

**CDN apps** run as filters inside Gcore's CDN proxy layer. They intercept traffic flowing through the CDN and can modify requests/responses in flight — before requests reach origin and before responses reach clients. Use these for header manipulation, auth enforcement, URL rewriting, traffic filtering, and custom caching logic.

- Languages: **AssemblyScript, Rust**
- Templates: `cdn-base`

Ask: **"Are you building an HTTP app (standalone API/endpoint) or a CDN app (traffic filter running inside the CDN proxy layer)?"** Include a one-sentence description of each to help the user decide.

---

## Step 2: Determine Template and Language

**For HTTP apps:**

| Template          | Use case                            | Supported languages          | Default    |
| ----------------- | ----------------------------------- | ---------------------------- | ---------- |
| `http-base`       | Plain HTTP handler, API, MCP server | TypeScript, JavaScript, Rust | TypeScript |
| `http-react`      | React SSR at the edge               | TypeScript, JavaScript       | TypeScript |
| `http-react-hono` | React SSR with Hono routing         | TypeScript, JavaScript       | TypeScript |

If the user hasn't specified a template, use `http-base` by default (or ask if they mentioned React).
If the user hasn't specified a language, use TypeScript.

**For CDN apps:**

| Template   | Supported languages  | Default  |
| ---------- | -------------------- | -------- |
| `cdn-base` | AssemblyScript, Rust | Ask user |

For `cdn-base`, ask the user to choose between AssemblyScript and Rust if they haven't specified. Both are valid — AssemblyScript is TypeScript-like syntax, Rust gives more control.

## Step 3: Get Project Name

Require a project name if not provided. Must be a valid package/crate name (lowercase, hyphens allowed).

## Step 3.5: Research Phase (only after Steps 1–3 are complete)

If the user's request involves non-trivial logic (e.g. auth, routing, third-party integrations), this is the point to do research — not before.

**Use parallel sub-agents for all research.** Do not read multiple resources sequentially in the main agent. Launch independent agents concurrently, each scoped to a specific question. Examples of parallel research tasks:

- Agent 1: Find relevant FastEdge examples for the confirmed app type + language
- Agent 2: Look up SDK docs or external library patterns relevant to the feature
- Agent 3: Check for existing patterns in the user's codebase

Research is scoped to the confirmed `type + language` combination. Do not read resources for other types or languages (e.g., if building a CDN app in AssemblyScript, skip HTTP/JS examples entirely).

If the request is simple (just scaffolding a base template with no custom logic), skip this step and proceed directly to Step 4.

## Step 4: Determine Language Flag

Language flag mapping:

- TypeScript → `--typescript`
- JavaScript → `--javascript`
- Rust → `--rust`
- AssemblyScript → `--as`

## Step 5: Run create-fastedge-app

```bash
npx create-fastedge-app <project-name> --template <template> <language-flag> --no-verify
```

Examples:

```bash
npx create-fastedge-app my-api --template http-base --typescript --no-verify
npx create-fastedge-app my-site --template http-react --typescript --no-verify
npx create-fastedge-app my-filter --template cdn-base --as --no-verify
npx create-fastedge-app my-cdn --template cdn-base --rust --no-verify
```

If the command fails, show the error output and stop. Do not attempt to create files manually.

## Step 6: Print Next Steps

After successful scaffolding, print a summary appropriate to the app type:

**HTTP apps:**

```
FastEdge project "<project-name>" created!  [<template> / <language>]

  cd <project-name>

  Build:
    npm run build                     (JS/TS projects)
    cargo build --release             (Rust projects)

  Test locally:
    /gcore-fastedge:test <project-name>

  Deploy:
    /gcore-fastedge:deploy <project-name>
```

**CDN apps:**

```
FastEdge CDN project "<project-name>" created!  [cdn-base / <language>]

  cd <project-name>

  Build:
    npm run asbuild:release           (AssemblyScript projects)
    cargo build --release             (Rust projects)

  Test locally:
    /gcore-fastedge:test <project-name>

  Deploy:
    /gcore-fastedge:deploy <project-name>

  Note: CDN apps use the Proxy-WASM filter model — implement onRequestHeaders,
  onResponseHeaders, etc. to intercept and modify CDN traffic.
```
