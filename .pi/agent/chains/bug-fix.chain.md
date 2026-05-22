---
name: bug-fix
description: Lightweight bug fix — scout the area, fix it, reviewer confirms
---

## scout
output: context.md

Find the source of this bug: {task}

Locate the relevant code and produce a focused brief:
- Files and functions directly involved
- The code path that triggers the bug
- Any obvious cause visible from a read-only pass
- Related tests that should be checked or updated
- Suggested fix if it is straightforward

## worker
reads: context.md
progress: true

Fix the bug: {task}

Use the scout's context from {previous}. Apply the fix:
- Minimal change — don't refactor unrelated code
- Add or update a test to catch this regression
- Run tests if a command is available
- Leave a one-paragraph summary of what changed and why

## reviewer

Review the bug fix for: {task}

The worker's changes are in {previous}. Confirm:
- Fix is correct and addresses the actual problem
- No regressions or unintended side effects
- Test added is meaningful
- Change is appropriately scoped

Pass or fail with a brief explanation.
