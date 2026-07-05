#!/usr/bin/env bash
set -euo pipefail

rofi_theme="${ROFI_THEME:-$HOME/.config/rofi/launcher.rasi}"

window_icon() {
  case "${1,,}" in
    *ghostty*|com.mitchellh.ghostty) printf '' ;;
    *helium*|*browser*|*chrome*|*chromium*|*zen*) printf '󰈹' ;;
    *spotify*) printf '' ;;
    *telegram*) printf '' ;;
    *obsidian*) printf '󱞁' ;;
    *zed*) printf '󰏫' ;;
    *thunderbird*) printf '' ;;
    *nautilus*) printf '' ;;
    *discord*) printf '󰙯' ;;
    *) printf '󰖯' ;;
  esac
}

choice="$(niri msg -j windows | jq -r '
  sort_by(.focus_timestamp.secs, .focus_timestamp.nanos)
  | reverse[]
  | [.id, (.app_id // "app"), (.title // ""), (.workspace_id|tostring)]
  | @tsv
' | awk -F'\t' '
  {
    id=$1; app=$2; title=$3; ws=$4;
    if (length(title) > 96) title=substr(title, 1, 93) "...";
    printf "%s\t%s\t%s\t%s\n", id, app, title, ws;
  }
' | while IFS=$'\t' read -r id app title ws; do
  icon="$(window_icon "$app")"
  printf '%s\t%s  %s — %s (ws %s)\n' "$id" "$icon" "$app" "$title" "$ws"
done | rofi -dmenu -i -p 'Windows' -theme "$rofi_theme")"

window_id="${choice%%$'\t'*}"
[[ -n "$window_id" ]] || exit 0
niri msg action focus-window "$window_id"
