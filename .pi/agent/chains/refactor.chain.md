---
name: refactor
description: Safe refactor — understand code, assess risks, plan, implement, verify no regressions
---

## scout
output: context.md

Map the code to be refactored: {task}

Produce a structural brief covering:
- All files and call sites involved
- Current data flow, interfaces, and dependencies
- Test coverage in the affected area (what tests exist, what they cover)
- Callers and consumers that will be affected by the change
- Any global state, side effects, or implicit contracts to preserve
- Risk areas: tight coupling, missing tests, hidden dependencies

## oracle
reads: context.md
thinking: xhigh

Assess the refactor: {task}

Review the scout's map from {previous}. Your job is to:
- Identify the highest-risk parts of this refactor
- Challenge the approach — are there simpler paths? Hidden traps?
- Check: will behavior be preserved for all callers?
- Flag missing tests that must exist before refactoring begins
- Recommend the safest sequence of changes
- Produce a go/no-go recommendation with conditions

Do NOT edit any files.

## planner
reads: context.md
thinking: xhigh
progress: true

Plan the refactor: {task}

Use the scout context and oracle assessment from {previous}. Produce a step-by-step plan:
- Exact order of changes to minimize breakage (smallest safe increments)
- Files to modify with specific changes per file
- Any tests to add BEFORE starting the refactor (safety net)
- Interfaces or types to define first
- How to validate each step (compile check, test run, smoke test)
- Rollback points if a step goes wrong

Do NOT edit any files. Output as plan.md.

## worker
reads: context.md, plan.md
progress: true

Execute the refactor: {task}

Follow the plan from {previous} step by step. Requirements:
- Implement only what the plan specifies — no scope creep
- Run tests after each logical step if possible
- If you encounter a decision not covered by the plan, STOP and document it
  rather than guessing
- Leave the codebase in a working state at every commit point
- Write a summary of all changes and test results

## reviewer
reads: context.md

Review the refactored code for: {task}

Use the scout context from {previous}. Verify:
- Behavior is preserved — no unintended semantic changes
- All original call sites still work correctly
- Tests pass and coverage has not decreased
- Code is simpler or clearer than before (the refactor achieved its goal)
- No dead code, accidental duplication, or introduced complexity
- Any oracle-flagged risks were handled correctly

Verdict: safe to merge / needs fixes. List required fixes separately from
optional polish.
