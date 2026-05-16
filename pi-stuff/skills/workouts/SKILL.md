---
name: workouts
description: Operate the local fullstack workout CLI as a chat-driven workout logger with prompts, logging, skipping, notes, and finish flow.
compatibility: Requires Go and the local `fullstack` CLI in this skill directory.
---

# workouts

Use this skill for the workout CLI in `pi-stuff/skills/workouts`.

This CLI is built for an agent-led flow:
- start a workout
- read the current exercise + last-time performance
- log sets
- move to next/prev or jump exercises
- skip unused planned sets explicitly
- finish the workout

## Build

```bash
cd pi-stuff/skills/workouts
go build .
```

## DB

Default:
- `./fullstack.db`

Override:
- `FULLSTACK_DB_PATH=/path/to/fullstack.db`

Deleting and recreating the DB is acceptable during development.

## Main commands

```bash
fullstack workout start --template <template-id>
fullstack workout start --name "Ad hoc"

fullstack workout prompt
fullstack workout log --weight-kg 52.5 --reps 8 [--rir 1] [--side left|right|none]
fullstack workout note --text "felt strong"

fullstack workout next
fullstack workout prev
fullstack workout goto --exercise <exercise-id>
fullstack workout goto --entry <exercise-entry-id>

fullstack workout skip-set
fullstack workout skip-exercise
fullstack workout add-exercise --exercise <exercise-id>

fullstack workout finish
```

## Notes

- `workout log` logs against the current exercise by default.
- Logged sets are automatically marked done.
- Notes are per exercise only, not per set.
- If planned sets are exhausted, extra `workout log` calls append more sets.
- `skip-set` removes one remaining empty planned set.
- `skip-exercise` removes all remaining empty planned sets for the current exercise.
- `finish` cleans up remaining empty placeholder sets before completing the workout.

## Prompt output

`workout prompt` returns the actionable context:
- workout title
- current exercise
- position in workout
- last time for that exercise
- today’s logged sets
- current exercise note, if any

## Example flow

```bash
fullstack workout start --template 1
# => shows first exercise and last-time numbers

fullstack workout log --weight-kg 52.5 --reps 8
fullstack workout log --weight-kg 52.5 --reps 7 --rir 1
fullstack workout note --text "second set was grindy"

fullstack workout next
fullstack workout log --weight-kg 60 --reps 10

fullstack workout skip-exercise
fullstack workout add-exercise --exercise 21
fullstack workout goto --exercise 21
fullstack workout log --weight-kg 70 --reps 9

fullstack workout finish
```
