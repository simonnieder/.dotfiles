#!/usr/bin/env bash

# Keep the old niri/Hyprland entry point while sharing the Solidtime
# implementation with Waybar.
if (( $# == 0 )); then
  set -- menu
fi
exec "$HOME/.config/scripts/solidtime-tracker.sh" "$@"
