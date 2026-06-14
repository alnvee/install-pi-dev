---
name: notebooklm
description: Load when the user wants grounded answers about NotebookLM resources, notebook/source summaries, or auth/session recovery through the Docker MCP integration.
---

# NotebookLM

Use this skill when the task is to ask grounded questions about the active NotebookLM notebook and its resources, summarize notebook/source material, or fix auth/session issues before retrying the NotebookLM tool call.

## Preferred Flow

1. Read the workspace `.env` file and locate `NOTEBOOKLM_NOTEBOOK_URL`.
2. Extract `notebook_id` as the final path segment after `/notebook/`.
3. Prefer the smallest useful tool for the user’s intent:
   - `docker mcp tools call notebook_describe notebook_id=<notebook_id>` for notebook summaries.
   - `docker mcp tools call source_describe notebook_id=<notebook_id>` for source-level summaries.
   - `docker mcp tools call notebooklm_ask notebook_id=<notebook_id> question="..."` (or the closest available question-answer tool) when the user wants grounded answers over the notebook’s resources.
4. If the tool fails because of auth or an expired session, first run:
   - `docker mcp tools call notebooklm_login mode=check`
5. Only fall back to `mode=login` when you truly need to re-authenticate, and use `mode=manual` if the browser-based path is unavailable.
6. Retry the original NotebookLM tool call once after the auth check or re-authentication step.

## Guardrails

- Use `mode=check` first to avoid unnecessary interactive login prompts.
- Only use `mode=login` or `mode=manual` when the session is actually broken or the user explicitly asks for re-authentication.
- Prefer the smallest tool that solves the task; do not guess at broader operations when a notebook summary, source summary, or grounded question-answer is enough.
- If you need to inspect the tool schema first, run `docker mcp tools inspect <tool-name> --format json` and use the returned fields.

## Result Handling

- Return the tool output directly when the user asked for a summary, grounded answer, or notebook/source facts.
- Mention the auth recovery step only when it changed the outcome or the user asked for troubleshooting.
