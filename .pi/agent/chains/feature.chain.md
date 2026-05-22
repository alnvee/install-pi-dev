---
name: feature
description: Full feature cycle — scout context, plan, implement, then review
---

## scout
output: context.md

Gather codebase context for implementing: {task}

Produce a compressed handoff covering:
- Relevant files and their responsibilities
- Existing patterns to follow (naming, error handling, testing style)
- Data flow and interfaces the new code must integrate with
- Any constraints, gotchas, or prior art to be aware of
- Suggested entry points for the planner

## planner
reads: context.md
model: gpt-5.4-nano
thinking: xhigh
progress: true

Create a detailed implementation plan for: {task}

Use the scout context from {previous}. The plan must include:
- Clear list of files to create or modify with specific changes per file
- Interfaces, types, and function signatures to define
- Data flow and integration points
- Test cases to write (unit and integration)
- Order of changes to minimize breakage
- Any migrations, config changes, or deployment notes

Do NOT edit any files. Produce only the plan.
Output as plan.md.

## worker
reads: context.md, plan.md
progress: true

Implement the feature: {task}

Follow the plan from {previous} exactly. Do not make unapproved decisions —
if you encounter an ambiguity or a required decision not covered by the plan,
stop and note it rather than guessing.

After all changes:
- Run the test suite if a test command is available
- Verify the implementation compiles/runs without errors
- Leave a short summary of what was done and any follow-up items

## reviewer
reads: context.md

Review the implementation of: {task}

The implementation is complete. Use the scout context and worker summary from
{previous} to guide your review. Check:
- Correctness against the plan and requirements
- Test coverage — are happy path, edge cases, and error paths tested?
- Consistency with existing patterns found by scout
- Security: input validation, auth, sensitive data handling
- Any leftover TODOs, debug code, or incomplete work

Report findings grouped by severity. Flag anything that must be fixed before
the feature is considered done.
