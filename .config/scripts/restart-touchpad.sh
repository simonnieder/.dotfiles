#!/usr/bin/env bash
set -euo pipefail

printf 'Restarting the ELAN touchpad. Enter your sudo password if prompted.\n'
if sudo sh -c '
  printf "%s" "0018:04F3:327E.0001" > /sys/bus/hid/drivers/hid-multitouch/unbind &&
  printf "%s" "0018:04F3:327E.0001" > /sys/bus/hid/drivers/hid-multitouch/bind
'; then
  printf 'Touchpad restarted.\n'
else
  printf 'Touchpad restart failed.\n' >&2
  read -r -p 'Press Enter to close...' || true
  exit 1
fi
