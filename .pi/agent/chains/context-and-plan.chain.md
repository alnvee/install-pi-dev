---
name: context-and-plan
description: Deep context gathering then implementation plan — use before any significant change
---

## context-builder
output: context.md
thinking: xhigh
progress: true

Build a thorough context package for: {task}

Gather and synthesize everything the planner will need:
- Relevant files, modules, and their responsibilities
- Existing patterns: naming conventions, error handling style, testing approach
- Data models, interfaces, and API contracts involved
- Key constraints: performance requirements, backward compatibility, security rules
- Prior art: similar past work in the codebase, migration patterns
- Open questions that need a product/architecture decision before coding begins

Output a structured context.md and meta-prompt.md that a planner can use
without needing to re-read the source.

## planner
reads: context.md
thinking: xhigh
progress: true

Create an implementation plan for: {task}

Use the context package from {previous}. The plan must be detailed enough
that a worker can execute it without making unapproved decisions:

- Goals and non-goals (scope boundary)
- Files to create or modify with specific changes
- New interfaces, types, and function signatures
- Data flow and integration points
- Test plan: what to test, how, and at what layer
- Order of changes with validation checkpoints
- Config, migration, or deployment steps if needed
- Open decisions that require human sign-off before starting

Do NOT edit any files. The plan is the output.
