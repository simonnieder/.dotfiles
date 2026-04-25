---
name: obsidian
description: Operate on the local Obsidian wiki vault. Use when working with notes, wikilinks, backlinks, log/daily entries, wiki maintenance, or opening notes in Obsidian.
compatibility: Requires the local `obsidian` CLI.
---

# Obsidian

This skill is for the **single local wiki vault** at `~/wiki`. Always default to `vault=wiki`.

For canonical workflow, naming, and directory rules, follow `~/wiki/AGENTS.md`.

## Defaults

- vault: `wiki`
- `file=<name>` resolves like a wikilink
- `path=<path>` uses an exact vault path
- many commands default to the active note if `file=` / `path=` is omitted

## Essentials

### Read and search

```bash
obsidian file file="deep-learning"
obsidian read path=concepts/deep-learning.md
obsidian search query="neuromechanical matching" path=sources
obsidian search:context query="backpropagation"
obsidian outline path=concepts/deep-learning.md format=md
```

### Create / update

```bash
obsidian create path=inbox/quick-note.md content="# Quick note"
obsidian move path=inbox/quick-note.md to=sources/quick-note.md
obsidian append path=log.md content="\n## [$(date +%Y-%m-%d\ %H:%M)] ingest | Processed source X"
```

### Links and wiki hygiene

```bash
obsidian links path=concepts/deep-learning.md
obsidian backlinks path=concepts/deep-learning.md counts
obsidian unresolved counts verbose
obsidian orphans
obsidian deadends
```

### Daily notes

```bash
obsidian daily:read
obsidian daily:append content="\n- processed source X"
obsidian daily:path
```

### Open in Obsidian app

```bash
obsidian open path=wiki-index.md
obsidian open file="deep-learning" newtab
```

## Workflow guidance

Per `AGENTS.md`:

- **Ingest**: from message or `inbox/` put raw in `raw/`, create/update `sources/`, update `concepts/`/`projects/`/`entities/`, update `wiki-index.md`, append `log.md`
- **Query**: check `wiki-index.md` first, read relevant pages, synthesize
- **Lint**: fix broken links, orphan pages, stale nav, unprocessed `inbox/` items

Use normal file tools for bulk rewrites. Use the CLI when wikilink resolution, backlinks, or Obsidian-native features are needed.

For all commands and flags, run `obsidian --help` or `obsidian <command> --help`.
