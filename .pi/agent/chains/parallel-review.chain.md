---
name: parallel-review
description: Three-angle sequential review — correctness, test coverage, and security/style — then a synthesis pass
---

## scout
output: context.md

Map the change for review: {task}

Identify what files changed, what the change is supposed to do, and where each
reviewer should focus. Note any obvious risks up front.

## reviewer
reads: context.md
progress: true
output: review-correctness.md

Correctness review for: {task}

Use the scout context from {previous}. Focus ONLY on correctness:
- Logic errors, off-by-ones, null/undefined/unhandled cases
- Wrong assumptions about data shape or control flow
- Race conditions, ordering issues, state bugs
- Missing guards or error handling that could cause crashes

List each issue as: **[severity]** file:line — problem and fix.
Skip style and test observations — a dedicated pass covers those.

## reviewer
reads: context.md, review-correctness.md
progress: true
output: review-tests.md

Test coverage review for: {task}

Use the scout context and correctness review from {previous}. Focus ONLY on
tests:
- Happy path covered?
- Edge cases and boundary conditions tested?
- Error paths and failure modes tested?
- Assertions meaningful or just existence checks?
- Any correctness issues from the prior review that lack test coverage?

List each gap as: **[severity]** test file or area — what is missing and why it matters.
Skip implementation and style issues.

## reviewer
reads: context.md, review-correctness.md, review-tests.md
progress: true
output: review-synthesis.md

Synthesize and prioritize findings for: {task}

You have the scout context, the correctness review, and the test coverage review
from {previous}. Your job is to produce a final, actionable summary:

1. **Must fix before merge** — list each blocking issue (file:line, description, fix)
2. **Should fix soon** — non-blocking but important
3. **Optional polish** — low-priority style or cleanup notes
4. **Overall verdict** — PASS / PASS WITH MINOR FIXES / BLOCK

Keep the synthesis concise. Do not re-list every finding — group and prioritize.
