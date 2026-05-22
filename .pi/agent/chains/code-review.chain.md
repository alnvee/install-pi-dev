---
name: code-review
description: Scout the diff then run a focused code review — correctness, tests, and edge cases
---

## scout
output: context.md

Scan the codebase to understand the change described in: {task}

Focus on:
- What files changed and what each does
- Entry points, data flow, and state boundaries touched
- Any obvious risks, missing guards, or edge cases
- Where the reviewer should look first

## reviewer
reads: context.md

Review the change for: {task}

Use the scout's context from {previous} to guide your review. Cover:
- Correctness: logic errors, off-by-ones, null/undefined cases
- Tests: missing coverage, edge cases not exercised, brittle assertions
- Simplicity: unnecessary complexity, duplication, or dead code
- Security: input validation, auth checks, data exposure
- Performance: N+1 queries, unbounded loops, expensive operations in hot paths

List each finding as: **[severity]** file:line — description and suggested fix.
Summarize what must be fixed versus what is optional polish.
