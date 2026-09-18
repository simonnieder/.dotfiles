---
name: create-flashcard
description: "Create effective spaced repetition flashcards following Matuschak's principles for deep understanding. Use for generating focused, precise, tractable Q&A and cloze deletion cards in Anki-compatible JSON format. Output is ready for anki-connect skill ingestion."
metadata:
---

# Create Flashcards Skill

Create effective spaced repetition flashcards following Andy Matuschak's principles for deep understanding.

## Principles (Matuschak Method)

### The Five Key Properties

| Property | Description |
|----------|-------------|
| **Focused** | One detail per prompt |
| **Precise** | Clearly specifies what's asked |
| **Consistent** | Same answer every time |
| **Tractable** | Answerable ~90% of the time |
| **Effortful** | Requires actual retrieval |

### Prompt Types

| Type | Use For | Example |
|------|---------|---------|
| **Simple Q&A** | Facts, definitions | "What is X?" |
| **Cloze Deletion** | Lists, sequences | "The three steps are: {{c1::A}}, {{c2::B}}, {{c3::C}}" |
| **Procedural** | Processes, workflows | "When should you do X?" |
| **Multi-lens** | Concepts, understanding | Attributes, differences, causes, significance |
| **Salience** | Habits, behavior change | Context-specific triggers |

## Workflow

1. **Research** the topic thoroughly
2. **Store findings** in a markdown file (e.g., `memory/notes/topic-name.md`)
3. **Identify key concepts** worth remembering
4. **Create flashcards** in JSON format
5. **Add to Anki** via anki-connect skill

## Output Format

When creating flashcards, generate a JSON file ready for anki-connect:

```json
{
  "action": "addNotes",
  "version": 6,
  "params": {
    "notes": [
      {
        "deckName": "DeckName",
        "modelName": "Basic",
        "fields": {
          "Front": "Question text with \\(math\\) if needed",
          "Back": "Answer text"
        },
        "tags": ["subject", "topic"]
      }
    ]
  }
}
```

**Tags are optional** — only include them if they meaningfully organize the cards (e.g., by topic, source material, or difficulty). Don't tag every card.

For cloze deletions, use `modelName: Cloze` and format as:
```json
{
  "deckName": "DeckName",
  "modelName": "Cloze",
  "fields": {
    "Text": "The five properties are: {{c1::focused}}, {{c2::precise}}, and {{c3::consistent}}"
  },
  "tags": ["srs"]
}
```

## Card Type Examples

### Simple Q&A (Factual)
```json
{
  "action": "addNotes",
  "version": 6,
  "params": {
    "notes": [{
      "deckName": "ML",
      "modelName": "Basic",
      "fields": {
        "Front": "What is the 'naive' assumption in Naive Bayes?",
        "Back": "Attributes are conditionally independent given the class"
      },
      "tags": ["ml", "naive-bayes"]
    }]
  }
}
```

### Cloze Deletion (Lists)
```json
{
  "action": "addNotes",
  "version": 6,
  "params": {
    "notes": [{
      "deckName": "SRS",
      "modelName": "Cloze",
      "fields": {
        "Text": "The five key properties are {{c1::focused}}, {{c2::precise}}, {{c3::consistent}}, {{c4::tractable}}, and {{c5::effortful}}"
      }
    }]
  }
}
```

### Procedural (Keywords)
```json
{
  "action": "addNotes",
  "version": 6,
  "params": {
    "notes": [{
      "deckName": "Cooking",
      "modelName": "Basic",
      "fields": {
        "Front": "When making chicken stock, when should you lower the heat?",
        "Back": "After the pot reaches a simmer"
      }
    }]
  }
}
```

### With MathJax
```json
{
  "action": "addNotes",
  "version": 6,
  "params": {
    "notes": [{
      "deckName": "ML",
      "modelName": "Basic",
      "fields": {
        "Front": "What is the numerically stable softmax formula?",
        "Back": "\\(\\text{softmax}(z)_i = \\frac{\\exp(z_i - \\max(z))}{\\sum_j \\exp(z_j - \\max(z))}\\)"
      },
      "tags": ["ml", "softmax"]
    }]
  }
}
```

## Guidelines

### DO
- Write more prompts than feels natural (each costs only 10-30s/year)
- Break lists into individual cloze deletions
- Keep the "shape" of lists consistent
- Include "why" when explanations matter
- Connect to personal meaning
- Use open-ended questions, not binary yes/no
- Put mnemonic devices in the **answer**, not the cue

### DON'T
- Make prompts too broad or vague
- Use binary questions (trivial inference)
- Put cues that give away the answer
- Try to cover "more ground" per prompt (makes review harder)
- Write prompts for every detail (focus on what's important)
- Memorize without understanding

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| "I can never remember this" | Make it more tractable (add cues, break down) |
| "I know the answer but don't understand" | Add explanation prompts |
| "This feels vague" | Check precision, add context |
| "I dread this card" | Delete or radically revise |

## Iterative Process

1. **First pass:** Write 5-10 prompts on most important parts
2. **Notice tickles:** What's juicy, challenging, personally relevant?
3. **Flag gaps:** What do you struggle to remember in practice?
4. **Add connections:** Link new ideas to existing knowledge
5. **Revise:** As understanding deepens, evolve prompts

## Checklist

### When Writing
- [ ] Focused on one detail?
- [ ] Precise and unambiguous?
- [ ] Consistent answer every time?
- [ ] Tractable (~90% success)?
- [ ] Effortful (requires retrieval)?
- [ ] Avoids pattern matching?
- [ ] Not binary/yes-no?
- [ ] Cue requires work (not giveaway)?
- [ ] Includes "why" where relevant?
- [ ] Personally meaningful?

### When Reviewing
- [ ] Flag prompts that feel off
- [ ] Revise flagged prompts holistically
- [ ] Check for pattern-matched cards
- [ ] Delete irrelevant material

## Integration with Anki

Use the local Go CLI in this skill instead of raw HTTP calls.

If the CLI is missing a command you need (for example `get`, `filter`, `search`, or another AnkiConnect wrapper command), extend the Go CLI first and then use that new command. Do not fall back to ad-hoc raw HTTP if the missing behavior belongs in the CLI.

### CLI location

- Source: `cmd/ankiconnect/main.go`
- Build from the skill directory:

```bash
go build -o bin/ankiconnect ./cmd/ankiconnect
```

### What it does

- talks to AnkiConnect at `http://127.0.0.1:8765` by default
- currently supports `version`, `decks`, `models`, `can-add`, and `add`
- accepts either a full `addNotes` AnkiConnect payload or a bare `{ "notes": [...] }` JSON file
- checks `canAddNotes` before adding, so duplicates are skipped by default
- prints JSON summaries so agents can script around it
- should be extended whenever a reusable Anki workflow needs another command

### Typical usage

```bash
# if the CLI does not exist yet, create it first
mkdir -p bin
CGO_ENABLED=0 go build -o bin/ankiconnect ./cmd/ankiconnect

# inspect connectivity
./bin/ankiconnect version
./bin/ankiconnect decks
./bin/ankiconnect models

# dry-run duplicate filtering
./bin/ankiconnect add -file flashcards.json -dry-run

# add only notes that Anki says are new
./bin/ankiconnect add -file flashcards.json
```

### Flags

```text
-url                AnkiConnect URL (default http://127.0.0.1:8765)
-timeout            Request timeout (default 10s)
-file               JSON payload path
-dry-run            Show what would be added
-allow-duplicates   Skip canAddNotes filtering
```

### Recommended workflow

1. Generate flashcards in AnkiConnect JSON format
2. Save them to a file next to the source notes
3. If `./bin/ankiconnect` does not exist yet, create it first:

```bash
mkdir -p bin
CGO_ENABLED=0 go build -o bin/ankiconnect ./cmd/ankiconnect
```

4. If the command you need does not exist yet, add it to `cmd/ankiconnect/main.go`, rebuild the CLI, and then use it
5. Run `./bin/ankiconnect add -file <file>.json`
6. Let the CLI skip duplicates automatically unless you explicitly want otherwise

## File Location

Store flashcard JSON files alongside source notes:
```
memory/notes/
├── topic-name.md          (research notes)
├── topic-name-cards.json  (flashcards)
└── ...
