#!/usr/bin/env bash
set -euo pipefail

device="platform::kbd_backlight"
current="$(brightnessctl -d "$device" get)"
max="$(brightnessctl -d "$device" max)"
next=$(((current + 1) % (max + 1)))

brightnessctl -q --min-value=0 -d "$device" set "$next"
dunstify -a brightness -u low "Keyboard light: $next/$max" 2>/dev/null || true
