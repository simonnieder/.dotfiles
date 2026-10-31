#!/usr/bin/env bash
set -euo pipefail

# Serialize repeated key presses and use the requested level, not the panel's
# nonlinear actual_brightness reading. F9 remains the separate screen-off key.
exec 9>"${XDG_RUNTIME_DIR:?}/brightness-step.lock"
flock 9

device="amdgpu_bl1"
current="$(brightnessctl -d "$device" get)"
max="$(brightnessctl -d "$device" max)"
percent=$(((current * 100 + max / 2) / max))
case "${1:-}" in
    up) target=$(((percent / 10 + 1) * 10)) ;;
    down) target=$((((percent + 9) / 10 - 1) * 10)) ;;
    show) target="$percent" ;;
    *) printf 'Usage: %s [up|down|show]\n' "$0" >&2; exit 1 ;;
esac
if [[ "$1" != show ]]; then
    (( target < 10 )) && target=10
    (( target > 100 )) && target=100
    brightnessctl -q -d "$device" set "$target%"
fi
notify-send -a Brightness -u low -t 2000 \
    -h string:x-dunst-stack-tag:screen-brightness \
    -h "int:value:$target" "Brightness $target%"
