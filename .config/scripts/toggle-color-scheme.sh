#!/usr/bin/env bash
set -euo pipefail

# Ignore duplicate activations from the same key press. Without this guard two
# rofi instances can toggle to light and immediately back to dark.
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
exec 9>"$runtime_dir/toggle-color-scheme.lock"
flock -n 9 || exit 0
stamp_file="$runtime_dir/toggle-color-scheme.stamp"
now_ms="$(date +%s%3N)"
last_ms="$(cat "$stamp_file" 2>/dev/null || printf '0')"
if (( now_ms - last_ms < 1000 )); then
  exit 0
fi
printf '%s\n' "$now_ms" > "$stamp_file"

current_scheme="$(dconf read /org/gnome/desktop/interface/color-scheme)"

if [[ "$current_scheme" == "'prefer-dark'" ]]; then
  mode="light"
else
  mode="dark"
fi

# Broadcast the system preference first so browsers and system-aware apps
# react as soon as the command-center entry is selected.
dconf write /org/gnome/desktop/interface/color-scheme "'prefer-$mode'"
matugen --mode "$mode" color hex '#a7c8ff'

notify-send "Color scheme" "${mode^} mode" 2>/dev/null || true
