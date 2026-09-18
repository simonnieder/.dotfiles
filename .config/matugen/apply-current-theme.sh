#!/usr/bin/env bash
set -euo pipefail

# Matugen image currently fails non-interactively in this session, so use a
# stable wallpaper-derived accent color and retain the current system mode.
scheme="$(dconf read /org/gnome/desktop/interface/color-scheme)"
if [[ "$scheme" == "'prefer-dark'" ]]; then
  mode="dark"
else
  mode="light"
fi

exec matugen --mode "$mode" color hex '#a7c8ff'
