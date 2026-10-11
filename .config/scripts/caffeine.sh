#!/usr/bin/env bash
set -euo pipefail

# Inhibit suspend/hibernate only. Idle handling can still turn the display off.
if ! command -v systemd-inhibit >/dev/null 2>&1; then
  printf 'systemd-inhibit is not available\n' >&2
  exit 1
fi

printf 'Caffeine mode enabled. Press Ctrl-C to stop.\n'
exec systemd-inhibit \
  --what=sleep \
  --who=caffeinate \
  --why='Caffeine mode' \
  --mode=block \
  sleep infinity
