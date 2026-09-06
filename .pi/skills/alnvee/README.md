# alnvee

Workspace-specific skills for this repo (`alnvee/install-pi-dev`), shipped as part of the Pi bundle and installed to `~/.pi/skills/alnvee`.

These skills cover operational tooling for this workspace — how to access MCP, inspect the gateway, and work with attached MCP servers and tools. They are the local fallback operating guide when working inside this environment.

## Skills

- **[herdr](./herdr/SKILL.md)** — Use herdr (the agent multiplexer) to orchestrate multiple coding agents: spawn agents in panes, inspect their state, hand work between them, and collect results.
- **[mcp](./mcp/SKILL.md)** — Access MCP, inspect the gateway, and discover/call available MCP servers and tools via the connected Pi-side MCP tools (or the Docker MCP CLI when no bridge is connected).
- **[notebooklm](./notebooklm/SKILL.md)** — Query the user's NotebookLM (Gemini Notebook) research corpus: list notebooks, add/read sources, and ask grounded questions with citations.

## Layout

Each subdirectory under this namespace is a skill with its own `SKILL.md` (loadable instructions) and optional `README.md` (index/overview).
