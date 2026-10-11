#!/usr/bin/env bash
set -euo pipefail

device="amdgpu_bl1"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/display"
state_file="$state_dir/laptop-brightness"
current="$(brightnessctl -d "$device" get)"
max="$(brightnessctl -d "$device" max)"

mkdir -p "$state_dir"

if (( current == 0 )); then
    restore=""
    if [[ -r "$state_file" ]]; then
        read -r restore < "$state_file" || true
    fi
    if [[ ! "$restore" =~ ^[0-9]+$ ]] || (( restore <= 1 || restore > max )); then
        restore=$((max * 30 / 100))
    fi
    brightnessctl -q --min-value=0 -d "$device" set "$restore"
    dunstify -a brightness -u low "Laptop screen on" 2>/dev/null || true
else
    printf '%s\n' "$current" > "$state_file"
    brightnessctl -q --min-value=0 -d "$device" set 0
    dunstify -a brightness -u low "Laptop screen brightness: 0" 2>/dev/null || true
fi
