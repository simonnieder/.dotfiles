---
name: calorie-tracker
description: Log meals, calories, macros, weight, goals, and reusable meal templates with the local calorie tracker CLI.
compatibility: Requires Python 3. Uses the external calorie_tracker_simple.py script and SQLite DB.
---

# calorie-tracker

Use this skill for local calorie and macro tracking.

Use the stable workspace skill symlink, not the underlying `.pi/git/...` install path:

```bash
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py
```

From `/home/simon/agent/workspace`, the shorter form is:

```bash
python3 .pi/skills/calorie-tracker/calorie_tracker_simple.py
```

## Data

Default database location:
- XDG data dir under `calorie-tracker-simple`
- typically `~/.local/share/calorie-tracker-simple/calorie_tracker_simple.db`

Override per command:

```bash
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py --db /path/to/calorie_tracker_simple.db ...
```

Bundled food dataset lives in the external folder:
- `/home/simon/agent/workspace/.pi/skills/calorie-tracker/opennutrition_foods.tsv`

## Setup

Initialize the DB and optionally import the bundled dataset:

```bash
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py init
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py import-opennutrition
```

Or import a specific TSV path:

```bash
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py init --import-path /home/simon/agent/workspace/.pi/skills/calorie-tracker/opennutrition_foods.tsv
```

## Core commands

Search foods:

```bash
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py search "chicken breast"
```

Log a food entry:

```bash
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py log lunch 200 --query "chicken breast"
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py log breakfast 80 --query "oats"
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py log dinner 1 --unit unit --query "protein bar"
```

View intake:

```bash
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py entries --date 2026-06-08
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py meals --date 2026-06-08
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py totals --date 2026-06-08
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py remaining --date 2026-06-08
```

Edit or remove entries:

```bash
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py entry edit 123 --amount 250
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py rm 123
```

## Goals

Set or inspect macro goals:

```bash
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py goals --calories 2400 --protein 180 --carbs 220 --fat 70 --name cut
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py goals --list
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py goals --date 2026-06-08
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py goals --close
```

## Custom foods

Add foods with your own macros:

```bash
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py custom add "my yogurt" 60 10 4 0 --serving-g 100
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py custom list
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py custom rm <food-id>
```

## Weight logging

```bash
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py weight log 81.4
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py weight log 81.0 --date 2026-06-08 --note "post-cut"
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py weight list --days 30
```

## Templates

Use templates for repeated meals:

```bash
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py template add "default breakfast" --meal-slot breakfast
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py template item-add "default breakfast" 80 --query "oats"
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py template item-add "default breakfast" 250 --query "skyr"
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py template apply "default breakfast"
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py template list
python3 /home/simon/agent/workspace/.pi/skills/calorie-tracker/calorie_tracker_simple.py template show "default breakfast"
```

## Notes

- Meal slots accept names like `breakfast`, `lunch`, `dinner`, `snack`, `preworkout`, `postworkout`, or numeric slots.
- Amounts are interpreted with `--unit g` by default unless `--unit unit` is passed.
- Prefer using `remaining` after logging so the user gets current macro budget context.
- When Simon mentions a branded supermarket product (`BILLA`, `SPAR`, `Hofer`, etc.) and the tracker does not have a confident exact match, prefer looking up the real product nutrition from the web first. If Simon says assumptions are okay or the exact variant does not matter, you may log a plausible researched variant or estimate instead — but always state clearly what you picked/assumed. Follow the workspace web policy: do web research via a subagent, not directly in the main session.
- When Simon logs food in chat, respond using the house rule from `AGENTS.md`: item-by-item kcal/p/c/f + meal total, then remaining daily macro budget, without markdown tables.
