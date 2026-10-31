#!/usr/bin/env bash
set -euo pipefail

case "${1:-status}" in
  toggle)
    hokum dnd toggle >/dev/null
    # Keep in sync with custom/do-not-disturb.signal in Waybar.
    pkill -RTMIN+9 -x 'waybar|\.waybar-wrapped' 2>/dev/null || true
    ;;
  status)
    if [[ "$(hokum dnd)" == on ]]; then
      printf '%s\n' '{"text":"󰂛","class":"enabled","tooltip":"Do Not Disturb on. Click to resume notifications."}'
    else
      printf '%s\n' '{"text":"󰂚","class":"disabled","tooltip":"Do Not Disturb off. Click to pause notifications."}'
    fi
    ;;
  *)
    printf 'Usage: %s [status|toggle]\n' "$0" >&2
    exit 1
    ;;
esac
