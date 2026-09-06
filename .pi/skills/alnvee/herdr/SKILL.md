---
name: herdr
description: Load when there is a need to run or orchestrate multiple AI coding agents, spawn a fresh/worker agent for parallel, detached, or ad-hoc work that does not need the main agent's full context, keep the main agent's context lean by delegating heavy or long-running work to separate agents, hand work between agents, or check what agents are running — or when the user mentions herdr, agent orchestration, agent multiplexing, "run another agent", "spawn an agent", "worker agent", "let X review this". Teaches how to use herdr (the background terminal multiplexer) to launch, monitor, message, and collect results from coding agents (pi, claude, codex, gemini, ...) in real terminal panes.
---

# Herdr — orchestrate coding agents in real terminal panes

Herdr is a background terminal multiplexer for AI coding agents (like tmux, mouse-first): a **server owns real terminal processes** that keep running after detach/SSH-drop; agents live in **panes** inside tabs/workspaces. It is an *orchestration layer* — one agent can spawn other agents, inspect their state, hand them work, and read their results.

Pi is a first-class Herdr agent kind (`pi` in `--kind`, plus a lifecycle extension installed by `herdr integration install pi`). This skill covers the local, CLI-native orchestration route.

## 1. When to use herdr (main agent's call)

Herdr's value is **context and lifecycle management**, not delegation for its own sake. Spawn a herdr worker when the work would otherwise bloat the main agent's context or needs to run independently:

- **Context management** — the task needs heavy reading (large logs, whole-repo exploration, long test/build output) or long-running work that should not occupy the main agent's window. The worker keeps its own context; the main agent only pulls back a summary via `agent read`.
- **Parallel / independent work** — multiple tasks that don't depend on each other or on the main conversation.
- **Detached / persistent work** — work that should keep running after the main session ends or detaches (server-owned panes survive).
- **Handoffs between agents** — one agent reviews or continues another's result (`agent prompt`, `agent read`).

It is still the main agent's judgment whether an ad-hoc task needs a *fresh* agent at all:

- Tasks that don't require full context and are small enough to do inline — do inline (directly or with a lightweight subagent); don't start herdr panes for ceremony.
- Tasks that **do** depend on the main conversation's full context (decisions so far, unwritten constraints) should not be thrown into a fresh worker — `agent start -- "…"` begins with a clean slate and cannot see this session. Keep those inline, or hand them off with the needed context spelled out in the prompt.
- Ad-hoc tasks that benefit from a clean, focused context or a different model/kind are a good herdr fit even when small.

## 2. Check availability first

```sh
command -v herdr && herdr --version     # e.g. herdr 0.7.5
herdr integration status                # pi: installed (path under ~/.pi/agent/extensions/…)
```

- If `herdr` is missing: it is **not available** — say so plainly and do not fake orchestration. Offer `herdr install` (see <https://herdr.dev>) or herdr-free alternatives (pi subagents, worktrees).
- If the Pi integration shows `not installed`, run `herdr integration install pi` — otherwise Herdr falls back to screen-scraping Pi's UI (less reliable states, no session restore). The file is `~/.pi/agent/extensions/herdr-agent-state.ts`; keep it (the installer re-ships it).
- No server running? `herdr` inside a project dir auto-launches/attaches the default session and workspace.

## 3. Vocabulary

- **pane id** — terminal location, e.g. `w1:p1` (workspace:tab:pane).
- **agent name** — an alias for the agent currently in a pane, e.g. `reviewer`. Must match `[a-z][a-z0-9_-]{0,31}`, unique among live agents; cleared when the agent exits/is released/replaced.
- **state** — `idle` / `working` / `blocked` / `done` (plus `unknown` before first detection), rolled up per tab/workspace. Agents are usually **blocked waiting on you** (permission prompts) — that is what needs attention.
- Agent commands accept either a live name or the hosting pane id.

## 4. See what is running

```sh
herdr status                      # server/client summary
herdr agent list                  # agents + state (idle/working/blocked/done)
herdr agent explain <name> --json # why a pane is classified that way
herdr pane list                   # panes and their foreground process
herdr session list                # background sessions
```

## 5. Orchestrate

Agents run in panes, and `agent start` only places an agent into an **existing pane that is at an interactive shell prompt** (no foreground command/editor/agent) — it never creates a pane. Create the pane first:

```sh
# 1. Make a pane at a shell prompt to host the agent
herdr pane split --direction right --ratio 50   # split the current pane into two
herdr pane list                                 # note the new pane id, e.g. w1:p2
#    new panes inherit the split pane's cwd; override with --cwd <PATH>.
#    For N parallel workers: split N panes (--direction right|down), start one agent per pane.
#    Prefer a fresh tab? herdr tab create, then split inside it.

# 2. Spawn the agent INTO that pane; returns once Herdr detects it ready for input
#    (waits up to --timeout, default 30000ms, max 300000ms)
herdr agent start reviewer --kind pi --pane w1:p2 -- "review the diff in /tmp/x and report"
#    <NAME> is positional — there is no --name flag. --pane <ID> is required.
#    kinds: run `herdr agent start --help` for the canonical list (pi, claude, codex, gemini, ...)
#    everything after `--` is passed unchanged to the agent executable

# 3. Watch, hand off, collect
herdr agent list                    # agents + state (idle/working/blocked/done/unknown)
herdr agent explain <name> --json   # why that state: lifecycle-hook vs screen-detection authority
herdr agent wait <name> --until idle --timeout 120000  # block until it settles (default: idle/done/blocked)
herdr agent read <name> --source recent-unwrapped  # its result as clean, unwrapped lines (the default source soft-wraps)
herdr agent prompt <name> "summarize what you changed" --wait  # submit a prompt, block until it settles
herdr agent send-keys <name> -- "…" # type + Enter (raw keystrokes; prefer `prompt` for task handoff)
herdr agent rename <name> worker2   # re-alias while it lives
herdr agent focus <name>            # jump the UI to it

# 4. Stop a worker: closes its pane and frees the name
herdr pane close w1:p2
```

Reading vs settling: `agent start` returns at interactive-ready, which can precede task completion — small argv tasks can finish seconds after spawn, and `idle` is the resting state both before and after a turn. To collect a final answer, `herdr agent wait <name> --until idle` first, then read; reading straight after `start` may only show boot output. For task handoff use `herdr agent prompt <name> <text> --wait`, which blocks until the agent settles (idle/done/blocked by default; from rest it requires an observed state change within 5s or returns `agent_prompt_stalled` — tune with `--until` / `--timeout`). Treat the `agent_status` in the `prompt --wait` result as the settled confirmation before reading.

Collecting output: `agent read` returns the pane's terminal scrollback, where a column-rendering agent UI soft-wraps long lines and long answers push earlier content out of the default window. Prefer `herdr agent read <name> --source recent-unwrapped` for clean, unwrapped lines (`--lines N` bounds the window). If the answer is long and only a summary is needed, ask the agent to re-print it compactly or write it to a file in the workspace, then read the file.

Reusing an agent vs spawning fresh: renaming or prompting an idle agent continues its **same session** — its prior turns stay in context. Reuse when continuity with the previous task helps. If a new task needs fresh, untainted context, **always spawn a new agent** (`herdr pane split` + `agent start`); never reuse an agent carrying unrelated history for a task that must not inherit it.

Running pi inside herdr manually is also fine: open a pane, run `pi`. Herdr detects it; the extension (when installed) reports real lifecycle state + session identity so Herdr can resume with `pi --resume`-style restores.

## 6. Environment Herdr sets for agents

Inside a Herdr pane, agent processes get `HERDR_ENV=1`, `HERDR_SOCKET_PATH`, and `HERDR_PANE_ID`. Do not clear/override them — the Pi integration extension uses them as its activation gate and transport.

## 7. Surviving pi reinstalls and herdr updates

A pi reinstall wipes `~/.pi` — including this skill and the Herdr Pi integration (`~/.pi/agent/extensions/herdr-agent-state.ts`) — then re-ships both from the install bundle: the repo's `.pi/skills/...` is synced to `~/.pi/agent/skills/...`, and the bundled integration is refreshed from Herdr's **latest stable** GitHub release (`releases/latest`; any failure only warns and keeps the bundled copy). The repo copy of this skill is the durable source — edit it there; the `~/.pi` copy is a regenerated artifact.

The integration is versioned (`HERDR_INTEGRATION_VERSION`, socket protocol). `herdr integration status` prints `current (vN)` when it matches the running server. If it stops matching — herdr updated after the last install, or the running herdr is on the preview channel while the installer resolved stable — re-align with `herdr integration install pi`; until then states degrade to screen detection. The CLI examples in this skill were verified against herdr 0.7.5; after a herdr update, if a command errors (`unknown option`), re-check `herdr <cmd> --help` before assuming the skill is wrong.

## Caveats

- **No herdr = no orchestration.** Do not pretend; report unavailability and offer install or fallbacks.
- State without the integration is screen-manifest detection — it can lag or misread. `herdr agent explain <name> --json` tells you the authority and why.
- One foreground process per pane; the pane must be at a shell prompt before `agent start`.
- Pi's internal lifecycle actions (`/reload`, `/new`, `/resume`, `/fork`) rebind the extension runtime but are **not** quits — Herdr intentionally keeps lifecycle authority there; only a real quit releases it.
- Logs/config live in `~/.config/herdr/` (Linux/macOS). Remote use: SSH and run `herdr`, or attach with `herdr --remote <host>`.
