---
name: mcp
description: Load when the user wants to access MCP. Discover the available MCP gateway, servers, and tools, then inspect and call the right tool from Docker CLI.
---

# MCP Gateway

Use this skill when the task is to access MCP, inspect the gateway, or figure out which MCP servers and tools are available in the workspace. This skill is the operating guide when no Pi-side MCP extension is available.

## Core Rule

Do not assume a direct MCP bridge is already connected in the agent session. Use the Docker MCP CLI as the source of truth.

## Execution Contract (important)

When this skill is invoked, you must **execute** the Docker MCP CLI commands needed to produce the user-facing result. If the user asked for discovery/listing, run the relevant `docker mcp ... ls/profile ...` commands and return their output; otherwise, don’t stop at listing/inspecting—make the required `docker mcp tools call` and base your answer on the tool output.

In practice:

- Determine the smallest MCP tool that satisfies the request.
- If needed, run `docker mcp tools inspect <tool-name> --format json` (and update `./tool-schemas.cache.json`).
- Then immediately run `docker mcp tools call <tool-name> <key=value arguments>` and base your answer on the tool output.

## NotebookLM fast path (this repo)

If the task is to summarize the _active_ NotebookLM notebook (e.g. “summarize the notebook”, “get notebook summary”, “what’s in the notebook”), prefer `notebook_describe`:

1. Read `NOTEBOOKLM_NOTEBOOK_URL` from the workspace `.env`.
2. Extract `notebook_id` as the final path segment (the part after `/notebook/`).
3. Call:
   `docker mcp tools call notebook_describe notebook_id=<notebook_id>`
4. If the call fails due to auth/session, call:
   `docker mcp tools call notebooklm_login mode=login`
   and retry the `notebook_describe` call once.

(If the task is about sources instead of the whole notebook, use `source_describe` analogously.)

## Discovery Flow

1. Check which Docker MCP profile is active.
2. List attached servers for that profile.
3. List the available tools and narrow to the relevant ones.
4. Check the cached tool schema for the selected tool in `./tool-schemas.cache.json` (same directory as this SKILL.md).
   - If it’s not present (or you suspect it’s outdated):
     - Run `docker mcp tools inspect <tool-name> --format json`.
     - Merge the resulting JSON into `./tool-schemas.cache.json` under `tools["<tool-name>"]` (creating the file/`tools` object if needed) so future discovery/calls can skip the inspect step.
5. Call the chosen tool with the exact arguments it expects.

## Cached Tool Schemas (optional)

- Cached schemas live in `./tool-schemas.cache.json` (kept separate from this file).
- Cache format: the full JSON from `docker mcp tools inspect <tool-name> --format json` is stored under `tools["<tool-name>"]`.
- Use it to determine required input keys for known tools (avoids extra `inspect` passes).
- If a tool isn’t listed in the cache, fall back to live `docker mcp tools inspect <tool-name> --format json`, then **immediately** merge it into `./tool-schemas.cache.json` under `tools["<tool-name>"]` (creating the file/`tools` object if needed).

## Startup and Verification

1. Check the active Docker MCP profile:
   `docker mcp profile server ls --filter profile=${PI_DOCKER_MCP_PROFILE:-default}`
2. Confirm the available tools are visible:
   `docker mcp tools ls --format human`
3. If a specific server matters, filter the tool list by name with `rg` after listing tools.
4. If the gateway is missing expected servers, verify the current Docker MCP setup and profile attachment.
5. If a tool needs workspace-local input, read the relevant workspace config files or docs first.

## How To Call Tools

- If the tool appears in `./tool-schemas.cache.json`, use the cached input keys; otherwise run `docker mcp tools inspect <tool-name> --format json` and immediately merge the result into `./tool-schemas.cache.json`.
- Use `docker mcp tools call <tool-name> key=value key2='value with spaces'` to invoke the selected tool.
- Prefer the smallest tool that solves the task rather than guessing at a broader server.
- If a tool accepts optional arguments, only pass what is needed.
- If the tool returns a validation error, re-run `inspect` and correct the argument shape before trying again.

## Result Handling

- For discovery or listing requests, return the discovered servers/tools with minimal framing so the caller can act on them directly.
- For execution requests, treat the tool output as the primary evidence and preserve the key fields the user asked for.
- Summarize only when the user explicitly asked for a summary or when you need to explain a failure and the recovery step.

## Practical Patterns

- To discover available tools: `docker mcp tools ls --format human`
- To inspect a tool: `docker mcp tools inspect <tool-name>`
- To invoke a tool: `docker mcp tools call <tool-name> <key=value arguments>`
- To confirm server attachment: `docker mcp profile server ls --filter profile=${PI_DOCKER_MCP_PROFILE:-default}`
- To verify a subset of tools, pipe the tool list through `rg` for the server or capability name

## When Workspace Context Is Needed

- Read the workspace `.env` for workspace-specific values.
- Read workspace docs or config files if the tool depends on local setup.
- Do not assume the same notebook, auth, or profile details carry across workspaces.
