---
name: herdr
description: Load when the user wants to run or orchestrate multiple AI coding agents, spawn an agent to work in parallel, hand work between agents, check what agents are running, or mentions herdr, agent orchestration, agent multiplexing, "run another agent", "let X review this". Teaches how to use herdr (the background terminal multiplexer) to launch, monitor, message, and collect results from coding agents (pi, claude, codex, gemini, ...) in real terminal panes.
---

# Herdr — orchestrate coding agents in real terminal panes

Herdr is a background terminal multiplexer for AI coding agents (like tmux, mouse-first): a **server owns real terminal processes** that keep running after detach/SSH-drop; agents live in **panes** inside tabs/workspaces. It is an *orchestration layer* — one agent can spawn other agents, inspect their state, hand them work, and read their results.

Pi is a first-class Herdr agent kind (`pi` in `--kind`, plus a lifecycle extension installed by `herdr integration install pi`). This skill covers the local, CLI-native orchestration route.

## 1. Check availability first

```sh
command -v herdr && herdr --version     # e.g. herdr 0.7.5
herdr integration status                # pi: installed (path under ~/.pi/agent/extensions/…)
```

- If `herdr` is missing: it is **not available** — say so plainly and do not fake orchestration. Offer `herdr install` (see <https://herdr.dev>) or herdr-free alternatives (pi subagents, worktrees).
- If the Pi integration shows `not installed`, run `herdr integration install pi` — otherwise Herdr falls back to screen-scraping Pi's UI (less reliable states, no session restore). The file is `~/.pi/agent/extensions/herdr-agent-state.ts`; keep it (the installer re-ships it).
- No server running? `herdr` inside a project dir auto-launches/attaches the default session and workspace.

## 2. Vocabulary

- **pane id** — terminal location, e.g. `w1:p1` (workspace:tab:pane).
- **agent name** — an alias for the agent currently in a pane, e.g. `reviewer`. Must match `[a-z][a-z0-9_-]{0,31}`, unique among live agents; cleared when the agent exits/is released/replaced.
- **state** — `idle` / `working` / `blocked` / `done`, rolled up per tab/workspace. Agents are usually **blocked waiting on you** (permission prompts) — that is what needs attention.
- Agent commands accept either a live name or the hosting pane id.

## 3. See what is running

```sh
herdr status                      # server/client summary
herdr agent list                  # agents + state (idle/working/blocked/done)
herdr agent explain <name> --json # why a pane is classified that way
herdr pane list                   # panes and their foreground process
herdr session list                # background sessions
```

## 4. Orchestrate

The pane you target must be at its interactive shell prompt (no foreground command/editor/agent) before spawning.

```sh
# Spawn an agent in a new pane; returns once Herdr detects it ready (waits up to ~30s)
herdr agent start --kind pi --name reviewer -- "review the diff in /tmp/x and report"
# kinds include: pi, claude, codex, gemini, cursor, opencode, qwen, copilot, kimi, ... (herdr docs /docs/agents/)
# everything after `--` is passed unchanged to the agent executable

herdr agent list                    # confirm it is up, see its state
herdr agent read <name>             # read that agent's pane output (context handoff)
herdr agent wait <name> --state idle  # block until it settles (finish a handoff loop)
herdr agent send-keys <name> -- "summarize what you changed"   # type + Enter into it
herdr agent rename <name> worker2   # re-alias while it lives
herdr agent focus <name>            # jump the UI to it
```

Running pi inside herdr manually is also fine: open a pane, run `pi`. Herdr detects it; the extension (when installed) reports real lifecycle state + session identity so Herdr can resume with `pi --resume`-style restores.

## 5. Environment Herdr sets for agents

Inside a Herdr pane, agent processes get `HERDR_ENV=1`, `HERDR_SOCKET_PATH`, and `HERDR_PANE_ID`. Do not clear/override them — the Pi integration extension uses them as its activation gate and transport.

## Caveats

- **No herdr = no orchestration.** Do not pretend; report unavailability and offer install or fallbacks.
- State without the integration is screen-manifest detection — it can lag or misread. `herdr agent explain <name> --json` tells you the authority and why.
- One foreground process per pane; the pane must be at a shell prompt before `agent start`.
- Pi's internal lifecycle actions (`/reload`, `/new`, `/resume`, `/fork`) rebind the extension runtime but are **not** quits — Herdr intentionally keeps lifecycle authority there; only a real quit releases it.
- Logs/config live in `~/.config/herdr/` (Linux/macOS). Remote use: SSH and run `herdr`, or attach with `herdr --remote <host>`.
