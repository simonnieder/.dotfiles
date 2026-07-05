#!/usr/bin/env bash
set -euo pipefail

# Manual night-mode toggle. This intentionally does not enable the Home Manager
# wlsunset service; it only starts/stops a foreground-session wlsunset process.

if pgrep -x wlsunset >/dev/null; then
  pkill -x wlsunset
  notify-send "Night mode" "Off" 2>/dev/null || true
  exit 0
fi

if ! command -v wlsunset >/dev/null 2>&1; then
  notify-send "Night mode" "wlsunset not found" 2>/dev/null || true
  exit 1
fi

nohup wlsunset -S05:00 -T6500 -g1.0 -s20:30 -t4000 >/dev/null 2>&1 &
disown
notify-send "Night mode" "On" 2>/dev/null || true
