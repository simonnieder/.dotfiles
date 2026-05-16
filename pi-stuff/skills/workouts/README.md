# fullstack

Gym progress and weight tracker CLI.

## Install

```bash
cd pi-stuff/skills/workouts
go build .
ln -s "$(pwd)/fullstack" ~/.local/bin/fullstack
```

Make sure `~/.local/bin` is in your `PATH` (fish: `fish_add_path $HOME/.local/bin`).

The DB lives alongside the binary — no env vars needed. `fullstack` works from any directory.

## Usage

See `fullstack --help`.
