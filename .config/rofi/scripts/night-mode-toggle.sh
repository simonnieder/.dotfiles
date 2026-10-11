#!/usr/bin/env bash
set -euo pipefail

service="wlsunset.service"

if systemctl --user is-active --quiet "$service"; then
  systemctl --user stop "$service"
  notify-send "Night mode" "Off until tomorrow morning" 2>/dev/null || true
else
  systemctl --user start "$service"
  notify-send "Night mode" "Automatic mode on" 2>/dev/null || true
fi
