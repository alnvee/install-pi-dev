# PLAN — Encourage subagent use in the system prompt

## Context

The user asked to update the system prompt to encourage use of subagents when helpful (following a discussion of the `@tintinweb/pi-subagents` extension).

There are two agent system prompts, currently byte-identical:

- **Global**: `~/.pi/agent/SYSTEM.md`
- **Project**: `install-pi-dev/.pi/agent/SYSTEM.md` (working directory)

Both currently contain a single line on the topic:

> *"Use subagents when they will improve context usage or isolate work. Prefer a read-only exploration subagent for broad repository questions, and use targeted subagents for parallel investigation when multiple independent checks are needed."*

Goal (per user): update **both** files (keep them in sync) with a **short subsection** (bulleted block, ~4-6 lines) that encourages delegating to subagents when helpful — concrete triggers + one guardrail against over-delegation.

## Approach

Replace the single subagent paragraph in each file with a lead-in sentence + bullets. The bullets mirror triggers the tintin extension already teaches (parallel background agents, don't duplicate delegated work, prefer direct tools for known targets) so the two sources stay consistent.

### New text

```
Use subagents when they will improve context usage or isolate work:
- Prefer a read-only exploration subagent (e.g. Explore) for broad repository questions instead of loading many files into the main context.
- Use targeted subagents in parallel when multiple independent checks are needed — launch them together in one message so they run concurrently.
- Delegate well-scoped, self-contained tasks (a single file change, a focused investigation) rather than stretching the main context.
- Don't duplicate work a subagent is already doing — if you delegate a search, don't run the same searches yourself.
- Reserve direct tools (read, grep, find) for lookups where the target is already known; subagents earn their cost on breadth or isolation.
```

Placement: in the same spot the current sentence occupies (after "You are context aware. …" and before the "Use the dedicated MCP workflow…" paragraph). No other lines in the file change.

## Files to modify

- `~/.pi/agent/SYSTEM.md` — replace the subagent paragraph with the new block above (only change in the file).
- `.pi/agent/SYSTEM.md` (project) — identical edit.

## Reuse

- Default agent types: `Explore` (read-only search), `Plan` (architecture), `general-purpose` (parent twin) — referenced by name where helpful.
- tintin's Agent tool `promptGuidelines` already cover: parallel background agents, "avoid duplicating work that subagents are already doing", trust-but-verify. The new bullets reuse those ideas in SYSTEM.md prose without contradicting them.
- Existing SYSTEM.md lines ("Stay in your lane", "Stop once you have enough local evidence", "Use the dedicated MCP workflow") are untouched and remain compatible.

## Steps

- [ ] 1. Edit `~/.pi/agent/SYSTEM.md`: replace the single subagent paragraph with the new lead-in + 5 bullets (preserve all other lines verbatim).
- [ ] 2. Edit `.pi/agent/SYSTEM.md` (project) with the identical replacement.
- [ ] 3. Diff both files against each other to confirm they remain byte-identical (aside from being the same content).

## Verification

- `diff ~/.pi/agent/SYSTEM.md .pi/agent/SYSTEM.md` → no output (files in sync).
- Re-read both files to confirm only the subagent paragraph changed.
- Next pi session: inspect the effective system prompt to confirm the new guidance renders in place.
- Sanity-check the new text against the surrounding instructions (no contradictions with "Stay in your lane" / "Stop once you have enough local evidence").
