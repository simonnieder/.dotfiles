---
name: calorie-tracker
description: Tracks daily calories, macros, bodyweight, and reusable meal templates via a local Python CLI backed by SQLite. Use when logging meals, checking day totals, editing entries, or applying meal templates.
compatibility: Linux, Python 3, SQLite. Uses a local OpenNutrition TSV copy.
---

# Calorie Tracker

Files:
- CLI: `./calorie_tracker_simple.py`
- Local OpenNutrition copy: `./opennutrition_foods.tsv`
- DB: `~/.local/share/calorie-tracker-simple/calorie_tracker.db`

Default assumption:
- unless stated otherwise, weights are **raw**
- fruit in units uses the matched serving size

## Init

```bash
python ~/.pi/agent/skills/calorie-tracker/calorie_tracker_simple.py init
```

## Examples

```bash
python ~/.pi/agent/skills/calorie-tracker/calorie_tracker_simple.py search "haferflocken"
python ~/.pi/agent/skills/calorie-tracker/calorie_tracker_simple.py log meal-1 100 --query "Rolled Oats"
python ~/.pi/agent/skills/calorie-tracker/calorie_tracker_simple.py entries
python ~/.pi/agent/skills/calorie-tracker/calorie_tracker_simple.py totals
python ~/.pi/agent/skills/calorie-tracker/calorie_tracker_simple.py rm 12
```

## Custom foods

```bash
python ~/.pi/agent/skills/calorie-tracker/calorie_tracker_simple.py custom add "Food Name" kcal protein carbs fat [--serving-g X]
python ~/.pi/agent/skills/calorie-tracker/calorie_tracker_simple.py custom list
```
