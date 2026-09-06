---
name: notebooklm
description: "Load when the user's research lives in Google NotebookLM (now Gemini Notebook) and the agent must query it — answer questions from notebook sources, add sources, list notebooks, run the research loop. Triggers: \"ask the notebook\", \"check my research\", \"notebooklm\", \"gemini notebook\", \"research in my sources\", \"what does my notebook say\", \"query my sources\"."
---

# NotebookLM (Gemini Notebook) — research backend

NotebookLM holds the user's research corpus. It is a **grounded** engine: Gemini reads the sources and answers **only from them, with citations**. The agent orchestrates (`list → add source → ask`) while NotebookLM does the heavy reading server-side — zero-token research offload.

## How to reach it

The **`/nlm` extension** ships with every install and is the setup/status surface: `/nlm` opens a menu — pick or change the **current notebook** (remembered for queries and source adds; `/nlm select` / `/nlm current` do the same from the command line) — plus auth status, notebooks, query, sources, doctor, and "Install / Remove MCP server in Docker" installs or tears down the backend (wrapper around `~/.pi/scripts/setup-notebooklm.sh`). The menu's "Ask a question" (and `/nlm notebook query …`) surfaces **only the answer** — citation metadata stays hidden; use the `notebook_query` MCP tool when you need it.

Primary: **MCP tools** — the `notebooklm` server is registered in the Docker MCP gateway and its tools appear in the connected Pi-side MCP surface (`MCP_DOCKER_*` tools / `mcp` tool / `docker mcp tools call ...`). The tool surface may drift between releases, so **discover before assuming**:

1. `docker mcp tools ls | rg -i notebook` — list the current tool names.
2. Inspect a tool's args: `docker mcp tools inspect <tool> --format json` (merge into `./tool-schemas.cache.json` beside this file if you keep one).
3. Call it: `docker mcp tools call <tool> key=value`.

Fallback (stable, semver-covered): the **CLI** — `nlm <command>` (installed with the backend). Use the CLI when MCP tools are missing or fail.

## Core workflows

### Answer a question from the user's research

1. `notebook_list` (or `nlm notebook list`) — find the relevant notebook.
2. Ask: `notebook_query(notebook_id=<name-or-id>, question="...")` — or CLI `nlm notebook query <id> "<question>" --json` (answer **plus source references**; `--json` gives machine-readable citations).
3. Report the answer **with its citations** — the citations are the point of using NotebookLM.

### Add new research to a notebook

- `source_add(notebook_id=<name-or-id>, ...)` then wait for the source to reach `ready` (CLI: `nlm source add <id> --url <url> --wait`).
- Deep research from a topic: `nlm research start "<topic>"` (auto-imports results into the notebook).
- Cross-notebook questions: `nlm cross query "<question>"` (MCP: `cross_notebook_query`).

### Distill research into durable output

NotebookLM answers are grounded but transient — when the user wants a lasting artifact, distill the answer into a repo doc or a `SKILL.md` (build once, reuse with zero runtime tokens).

## Key facts

- **Name or ID.** Every `notebook`/`source` argument accepts a title or an ID, both by unique prefix (an exact title wins). Ambiguous names return a validation error listing candidates. Responses echo canonical IDs — chain the next call on them.
- **Citations.** `notebook_query` returns source references with the answer. Always surface them.
- **Auth.** The server binds the profile created by `nlm login` (auth lives in `~/.notebooklm-mcp-cli` — NOT in `~/.pi`, so it survives bundle reinstalls). If tools fail with auth errors, tell the user to run `/nlm` → "Auth status / login" (or `nlm login --check` / `nlm login`).

## Safety

The auth cookies are a **durable full-account Google credential** (kept in `~/.notebooklm-mcp-cli`, private). Never copy them into prompts, logs, or repo files. If the integration was set up with a personal account, treat the whole auth dir as a secret.
