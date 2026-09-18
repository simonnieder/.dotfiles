---
name: daily-journal
description: Create or complete an Obsidian journal entry at journal/YYYY-MM-DD.md for today or a specified date. Use for requests to make a daily journal, daily reflection, or journal page; preserve existing content, choose one recent-question-aware prompt, and add a weekly review only on a configured review day.
argument-hint: "[today | YYYY-MM-DD | context]"
---

# Daily Journal

Create a small, honest journal page the user can finish in **3–5 minutes**. The page should make it easy to notice identity, attention, learning, meaningful work, curiosity, and tomorrow's next step. Keep it personal and plainspoken.

## Workflow

### 1. Establish the target and journal location

- Use an explicit date from the request when provided; otherwise use the local system date. Render it as `YYYY-MM-DD` in both the filename and the page title.
- When working in a wiki, read `AGENTS.md` and `wiki-index.md` first. Treat the vault as the source of truth for naming and placement.
- Always use the dedicated journal subfolder with the ISO date filename: `journal/YYYY-MM-DD.md`. The daily-note folder and `.obsidian/daily-notes.json` are unrelated to this skill.
- If `journal/` already contains journal notes, inspect a recent one and any relevant journal template only as needed. Reuse its frontmatter and heading style while keeping the `journal/YYYY-MM-DD.md` path.
- Read the target note before writing. The target may already contain ordinary notes, logs, or a partial journal.
- Inspect the five most recent applicable journal entries before the target date. Read the question under their `Reflection` sections so today's rotating question is not repeated. Recent notes without a structured journal prompt do not count as used questions.

Completion criterion: the target path `journal/YYYY-MM-DD.md`, the target date, the existing target content, and the five-question repetition window are known.

### 2. Choose exactly one rotating question

Read [`question-bank.md`](question-bank.md) and select one question verbatim.

- Use clear context from the user's request and target note: attention or habits for heavy scrolling or an automatic habit; learning for substantial study; creating and work for a personal project; direction for aimlessness; identity or habits for a strong or weak habit day.
- When several contexts fit, choose the one most useful for tomorrow rather than trying to cover every theme.
- With no useful context, vary the category from the recent entries and choose a question that has not appeared in those five entries.
- Treat exact question wording as the identity of a question. Paraphrasing a recent question still counts as a repetition.
- Put the selected question as the only bold question under `### Reflection`. The fixed prompts in the weekly review are separate from the one rotating daily question.

Completion criterion: one verbatim question is selected, is absent from the previous five applicable journal entries, and fits the day's strongest useful signal.

### 3. Add the smallest complete journal

For a new note, use the fallback template below, adapting only frontmatter or heading style from an existing note in `journal/`. For an existing note, preserve every existing line and add only missing journal structure.

Recognize these as the journal's atomic pieces:

- `## Today` with the identity prompt and one blank answer line
- `### Reflection` (or the vault's equivalent) with exactly one rotating question and one blank answer line
- `## Tomorrow` with the one-time-making prompt and one blank answer line
- `## Habits` with the three habit checkboxes
- `## Weekly Review` with the five weekly prompts, only when the weekly rule below applies

When a section already exists, complete only missing pieces inside it. If safe placement is unclear, append the missing block at the end rather than moving or rewriting user content. Add missing habit checkboxes individually instead of replacing an existing checklist. If today's note already has a reflection question, keep it and do not add a second one.

Leave every newly added answer blank unless the user explicitly asks for answers drafted from known context. In that exception, use only facts the user supplied or the note clearly records, and never invent feelings, intentions, or outcomes. Keep prompts as prompts rather than turning them into tasks or commentary.

Completion criterion: the note contains the complete daily structure exactly once, with one rotating question, untouched existing answers, blank newly added answer areas unless explicitly requested otherwise, and all pre-existing content unchanged.

### 4. Apply the weekly review rule

Append the weekly review only when the user's chosen review day is explicit in the request, established by an existing vault convention/configuration, or directly confirmed in available user preferences. Do not assume Sunday or another weekday when no preference is known.

If the target is the chosen review day, add the weekly block once. If it already exists, preserve it and add only missing weekly prompts. The weekly block does not replace the daily prompts.

Completion criterion: a weekly review is present exactly when a known review-day rule matches the target date, and never merely because the date feels like a week boundary.

### 5. Verify the result

Re-read the finished note and check:

- the path and title use the target date;
- the note is at `journal/YYYY-MM-DD.md` and follows the journal folder's established style;
- there is exactly one rotating daily question;
- that question is not in the previous five applicable journal entries;
- newly added answer lines and checkboxes are blank unless the user explicitly requested drafted answers;
- existing answers and checkboxes were preserved, with no existing content overwritten or reordered;
- the weekly review obeys the configured-day rule; and
- the page remains short enough for a 3–5 minute completion.

Completion criterion: every check passes and the final response names the created or updated path succinctly.

## Fallback template

Use this only when the vault has no stronger convention. Replace both date placeholders and insert one exact question from `question-bank.md`.

```md
---
date: YYYY-MM-DD
type: journal
---

# YYYY-MM-DD

## Today

**What did I do today that was a vote for the person I want to become?**

-

### Reflection

**ROTATING_QUESTION**

-

## Tomorrow

**What is one thing I want to make time for tomorrow?**

-

## Habits

- [ ] Learned something
- [ ] Built / created / worked on something meaningful
- [ ] Kept social media reasonable
```

### Weekly review block

Use this exact block when the weekly rule applies:

```md
## Weekly Review

**What was the best use of my time this week?**

-

**What was the biggest waste?**

-

**What did I learn or get better at?**

-

**What should I do more of next week?**

-

**What should I reduce or remove?**

-
```

## Guardrails

- Keep the page short, warm, and easy to maintain.
- Use ordinary personal language. Keep the prompts about identity, habits, attention, learning, creating, meaningful progress, and curiosity.
- Keep the question bank as the single source of truth for rotating prompts.
- Do not add scores, streaks, trackers, motivational quotes, extra sections, or extra questions unless the user asks for them.
- Preserve existing content; this skill is additive, not a cleanup pass.
