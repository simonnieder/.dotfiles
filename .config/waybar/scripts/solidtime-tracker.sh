#!/usr/bin/env bash

# Waybar uses the same Solidtime controller as the Mod+P Rofi menu.
if (( $# == 0 )); then
  set -- status
fi
exec "$HOME/.config/scripts/solidtime-tracker.sh" "$@"
