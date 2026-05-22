---
name: debug
description: Systematic debug cycle — recon, root-cause diagnosis, targeted fix, verify
---

## scout
output: context.md

Investigate the bug: {task}

Produce a diagnostic brief covering:
- Relevant files, functions, and execution paths involved
- How data flows through the affected code
- Any existing error handling, guards, or logging in the area
- Similar past fixes or related patterns in the codebase
- Hypothesis about where the defect likely lives and why
- Exact lines or functions the oracle should focus on

## oracle
reads: context.md
thinking: xhigh

Diagnose the root cause of: {task}

You have the scout's codebase context from {previous}. Your job is to:
- Identify the most likely root cause with evidence from the code
- Challenge any assumptions — consider off-by-ones, race conditions, type
  coercion, null/undefined, lifecycle ordering, and config issues
- Rule out red herrings
- Propose the minimal, safest fix
- Flag any other latent bugs discovered along the way

Produce a diagnosis with: root cause, supporting evidence, proposed fix
(file + line), and risk notes. Do NOT edit any files.

## worker
reads: context.md
progress: true

Fix the bug: {task}

Apply the fix from oracle's diagnosis in {previous}. Requirements:
- Make only the targeted change — no unrelated cleanup or refactoring
- Preserve existing behavior for all non-bug paths
- Add or update a test that would catch this regression
- Run tests if a test command is available and confirm they pass
- Note any related issues found but NOT fixed (leave them for a separate task)

## reviewer
reads: context.md

Verify the bug fix for: {task}

Review the worker's changes from {previous}. Confirm:
- The fix addresses the root cause identified by oracle
- No new bugs or regressions introduced
- Test added is meaningful and would catch this specific failure
- The change is minimal — no unintended scope creep
- Any latent issues noted by oracle are documented

Give a clear pass/fail verdict with reasoning.
