#!/usr/bin/env bash
set -euo pipefail

# matugen image currently fails non-interactively in this session,
# so use a stable wallpaper-derived accent color instead.
exec matugen color hex '#a7c8ff'
