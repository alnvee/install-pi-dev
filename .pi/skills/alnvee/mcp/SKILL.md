---
name: mcp
description: Load when the user wants to access MCP. Explore the available MCP tools, servers, and gateway configuration in the workspace before choosing the right action.
---

# MCP Gateway

Use this skill when the task is to access MCP, inspect the gateway, or figure out which MCP servers and tools are available in the workspace.

## Generic Flow

1. Check the active Docker MCP profile and confirm which servers are attached.
2. List the available tools before choosing an action.
3. Inspect the target tool if its schema is unclear.
4. Call the tool through `docker mcp tools call` using the exact tool name and required arguments.

## Startup and Verification

1. Check the active Docker MCP profile:
   `docker mcp profile server ls --filter profile=${PI_DOCKER_MCP_PROFILE:-default}`
2. Confirm the available tools are visible:
   `docker mcp tools ls --format human`
3. If the gateway is missing expected servers, verify the profile attachment and the current Docker MCP setup.
4. If a tool needs workspace-local input, read the relevant workspace config files or docs first.

## Tool Usage

- Use `docker mcp tools inspect <tool-name>` when the input schema is unclear.
- Use `docker mcp tools call <tool-name> <args>` to invoke the selected tool.
- Prefer the smallest tool that solves the task rather than guessing at a broader server.

## If MCP Is Unavailable

- Use the Docker MCP CLI to confirm whether the gateway is attached to the current profile.
- If no gateway is attached, ask the user to start or attach Docker MCP in that workspace.
- Do not guess tool names; inspect the gateway and tool list first.
