---
name: notebooklm-qa
description: Ask questions to a NotebookLM notebook by calling the local `nlm notebook query` CLI (JSON) and returning the answer + optional citations. Use when you want NotebookLM-style answers grounded in your notebook.
---

# NotebookLM QA (nlm notebook query)

## Setup (run once)

- Ensure the local `nlm` CLI exists:
  - `nlm --help` works.
- Ensure you’re authenticated:
  - Run `nlm login --check` and expect it to succeed (or run `nlm login`).

## Workspace configuration: notebook URL in `./.env`

This skill must not rely on notebook URLs stored in your home directory.

- Create `./.env` in the current workspace and set:
  - `NOTEBOOKLM_NOTEBOOK_URL=<paste the NotebookLM notebook URL here>`

If `./.env` or `NOTEBOOKLM_NOTEBOOK_URL` is missing/empty, ask the user to create it and stop.

## Inputs (what the user must provide)

- `question` (required)
- `session_id` (optional; for follow-ups)
- `source_format` (optional; default: `footnotes`)

### `source_format` semantics (Pi output only)

The `nlm notebook query` CLI always computes citations. Here, `source_format` controls both:

- whether this skill includes a `Citations:` section, and
- whether citation markers like `[1]` / `[2, 3]` remain in the final `Answer:` text.

- `source_format = none` → omit the `Citations:` section and remove citation markers from `Answer:` (including conversation-history markers like `[User Conversation]` / `[Conversation History]`).
- anything else → include the `Citations:` section and keep citation markers in `Answer:`

## Notebook reference rules

- If the user explicitly provided a `notebook_id`, use it.
- Else derive notebook id from the URL:
  - `NOTEBOOKLM_NOTEBOOK_URL` is typically like `https://notebooklm.google.com/notebook/<NOTEBOOK_ID>`
  - Extract `<NOTEBOOK_ID>` as the last path segment (strip any querystring).

If you can’t derive a notebook id, ask the user to provide `notebook_id` or fix `NOTEBOOKLM_NOTEBOOK_URL`.

## Workflow (agent steps)

1. **Extract inputs**
   - Read `question` (required), optional `session_id`, and optional `source_format`.
   - Set `source_format := user value > NOTEBOOKLM_QA_SOURCE_FORMAT > footnotes`.

2. **Resolve notebook id**
   - Load `NOTEBOOKLM_NOTEBOOK_URL` from `./.env` (via `bash`, e.g. grep).
   - Derive `NOTEBOOK_ID` from it (last path segment).

3. **Build `SHAPED_QUESTION` (verbatim template; do not paraphrase)**
   - Choose exactly ONE template based on the **user’s question**:
     - overview/summary/main takeaways/key sections/themes → Template 1
     - definitions/glossary/key terms → Template 2
     - follow-up deep dive on a specific theme (must include both `Theme #<k>` and the exact theme name you used previously) → Template 3
     - otherwise → Generic template
   - Set `SHAPED_QUESTION` to the selected template text **copy/pasted verbatim** (no shortening, summarizing, or rewording).
   - The prompt passed to `nlm` MUST be exactly `SHAPED_QUESTION` (never a shorter paraphrase).

4. **Decide conversation reuse**
   - If `session_id` is provided, call CLI with `--conversation-id "$session_id"`.
   - Else omit it.

5. **Run the CLI and store JSON (avoid flooding context; MUST use --json)**
   - Set `TMP_JSON=$(mktemp -t notebooklm-qa.XXXX.json)`.
   - If `session_id` is provided:
     - Run `nlm notebook query "$NOTEBOOK_ID" "$SHAPED_QUESTION" --conversation-id "$session_id" --json > "$TMP_JSON"`.
   - Else:
     - Run `nlm notebook query "$NOTEBOOK_ID" "$SHAPED_QUESTION" --json > "$TMP_JSON"`.

6. **Parse JSON**
   - Implementation (use jq; do not guess):
     - `ANSWER=$(jq -r '.value.answer' "$TMP_JSON")`
     - `SESSION_ID=$(jq -r '.value.conversation_id' "$TMP_JSON")`
     - `CITATIONS_LINE=$(jq -r '.value.citations | to_entries | sort_by(.key|tonumber) | map("[\(.key)]=\(.value)") | join(", ")' "$TMP_JSON")`
   - Citation marker policy (deterministic):
     - If `source_format = none`:
       - Strip all citation markers from `$ANSWER` by removing any bracket token `[...]` whose contents match (case-insensitive) one of:
         - contains at least one digit (e.g., `[1]`, `[2, 3]`)
         - `User Conversation`
         - `Conversation History`
       - When removing, also delete any whitespace immediately preceding the bracket token (to avoid artifacts like `word .`).
       - Do NOT include a `Citations:` section.
     - Else:
       - Keep citation markers in `$ANSWER` as provided by `nlm`.
       - Output a single-line `Citations:` section exactly as `Citations: $CITATIONS_LINE` (NO arrows like `→`, NO semicolons, NO line breaks).
   - Do NOT rewrite/paraphrase `$ANSWER` beyond optional citation-marker stripping above; output must use the exact `$ANSWER` string extracted by jq. Also, implement this entire step (jq extraction + citation rendering) inside the bash tool call, and paste the resulting stdout verbatim in your final assistant message.

7. **Output to the user**

Return exactly in this order (no extra sections):

- `Answer: <answer>`
- `Citations: <citations_line>` (only if `source_format != none`)
- `session_id: <session_id>`

## Templates (copy/paste into SHAPED_QUESTION)

### Template 1 — Initial overview (structured + limited)

Using ONLY the attached notebook content, answer this in the exact structure below.

Rules:

- No outside knowledge.
- If something is not explicitly supported by the notebook, write exactly: `not stated in the notebook`.
- Avoid causal/decisive language; use `the notebook states/indicates/suggests`.
- Citation discipline: do not invent citation numbers; only keep the citation markers NotebookLM already attaches (e.g., [1], [2]).
- Verbosity cap: ≤ 220 words total.
- Each bullet line must be ONE sentence.

Output structure:

1. Gist: <1 sentence>.

2. Key sections / themes (Top 5):
   For each Theme i:
   Theme i: <Theme name>
   Purpose: <1 sentence>

- Bullet A: <1 sentence>
- Bullet B: <1 sentence>

3. Main takeaways (Top 7, prioritized):
   Takeaway 1: <1 sentence>
   Takeaway 2: <1 sentence>
   ...
   Takeaway 7: <1 sentence>

4. Limitations / what the notebook does NOT cover (Top 3):

- <1 sentence>
- <1 sentence>
- <1 sentence>

5. Assumptions / prerequisites (Top 3):

- <1 sentence>
- <1 sentence>
- <1 sentence>

### Template 2 — Glossary (definitions + caps)

Using ONLY the attached notebook content, produce a glossary of the key terms/frameworks.

Rules:

- Use notebook wording/meaning; no outside knowledge.
- If a term is used but not explicitly defined, write `not stated in the notebook`.
- Each definition is EXACTLY 1 sentence.
- Verbosity cap: ≤ 160 words total.
- Output exactly in the structure below; no extra text.
- Citation discipline: do not invent citation numbers; only keep citation markers NotebookLM already attaches.

Output:
Glossary (Top 8):
Term 1: <term> — <definition (1 sentence)>
...
Term 8: <term> — <definition (1 sentence)>

### Template 3 — Theme deep dive (follow-up)

Follow-up deep dive to your prior overview.

Deep dive ONLY Theme #<k> (<paste the exact Theme name you used earlier>).
Do not rename it.

Rules:

- Notebook-only evidence; no outside knowledge.
- If you can’t support something from the notebook, write `not stated in the notebook`.
- Avoid causal/decisive language; use `the notebook states/indicates/suggests`.
- Citation discipline: do not invent citation numbers; only keep citation markers NotebookLM already attaches.
- Output exactly in the structure below; no extra text.
- Verbosity cap: ≤ 180 words total.
- Each bullet line must be ONE sentence.

Output:
Theme #<k> gist: <1 sentence>

Key components / sub-claims (Top 5):

- <1 sentence>
- <1 sentence>
- <1 sentence>
- <1 sentence>
- <1 sentence>

Practical implications / how-to (Top 3):

- <1 sentence>
- <1 sentence>
- <1 sentence>

Limitations within this theme (Top 2):

- <1 sentence>
- <1 sentence>

### Generic template — general Q&A (short)

Answer the user’s question using ONLY the attached notebook content.

Rules:

- No outside knowledge.
- If something isn’t explicitly supported by the notebook, write `not stated in the notebook`.
- Avoid causal/decisive language; use `the notebook states/indicates/suggests`.
- Citation discipline: do not invent citation numbers; only keep citation markers NotebookLM already attaches.

Verbosity cap: ≤ 150 words total.
