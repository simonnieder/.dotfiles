#!/usr/bin/env bash
set -euo pipefail

device="platform::kbd_backlight"
current="$(brightnessctl -d "$device" get)"
max="$(brightnessctl -d "$device" max)"
next=$(((current + 1) % (max + 1)))

brightnessctl -q --min-value=0 -d "$device" set "$next"
notify-send -a Brightness -u low -t 2000 \
    -h string:x-dunst-stack-tag:keyboard-brightness \
    -h "int:value:$((next * 100 / max))" "Keyboard light: $next/$max" 2>/dev/null || true
