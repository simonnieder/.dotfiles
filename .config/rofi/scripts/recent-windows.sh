#!/usr/bin/env bash
set -euo pipefail

rofi_theme="${ROFI_THEME:-$HOME/.config/rofi/launcher.rasi}"

if [[ -z "${ROFI_RETV+x}" ]]; then
  exec rofi -show recent-windows -i -sort -matching normal -theme "$rofi_theme"
fi

if [[ "${ROFI_RETV:-0}" -eq 1 ]]; then
  [[ -n "${ROFI_INFO:-}" ]] || exit 0
  niri msg action focus-window --id "$ROFI_INFO"
  exit 0
fi

mapfile -t window_rows < <(niri msg -j windows | jq -r '
  sort_by(.focus_timestamp.secs, .focus_timestamp.nanos)
  | reverse[]
  | [.id, (.app_id // "app"), (.title // ""), (.workspace_id|tostring)]
  | @tsv
')

desktop_dirs=("${XDG_DATA_HOME:-$HOME/.local/share}/applications")
IFS=: read -ra xdg_data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for data_dir in "${xdg_data_dirs[@]}"; do
  desktop_dirs+=("$data_dir/applications")
done

declare -A drun_desktop_ids
rofi_drun_cache="${XDG_CACHE_HOME:-$HOME/.cache}/rofi3.druncache"
if [[ -r "$rofi_drun_cache" ]]; then
  while read -r _ desktop_file _; do
    desktop_id="${desktop_file%.desktop}"
    [[ -n "$desktop_id" ]] || continue
    drun_desktop_ids["${desktop_id,,}"]="$desktop_id"
  done < "$rofi_drun_cache"
fi

desktop_entry_name=""
desktop_entry_icon=""
desktop_entry_for_app() {
  local app="$1" candidate app_key desktop_id desktop_dir desktop_file line name icon
  local -a candidates=("$app")
  [[ "$app" == *.* ]] && candidates+=("${app##*.}")

  desktop_entry_name="$app"
  desktop_entry_icon=""

  for candidate in "${candidates[@]}"; do
    app_key="${candidate,,}"
    desktop_id="${drun_desktop_ids[$app_key]:-$candidate}"

    for desktop_dir in "${desktop_dirs[@]}"; do
      desktop_file="$desktop_dir/$desktop_id.desktop"
      [[ -f "$desktop_file" ]] || continue

      name=""
      icon=""
      while IFS= read -r line; do
        if [[ -z "$name" && "$line" == Name=* ]]; then
          name="${line#Name=}"
        elif [[ -z "$icon" && "$line" == Icon=* ]]; then
          icon="${line#Icon=}"
        fi

        [[ -n "$name" && -n "$icon" ]] && break
      done < "$desktop_file"

      [[ -n "$name" && "$desktop_entry_name" == "$app" ]] && desktop_entry_name="$name"
      [[ -n "$icon" ]] && desktop_entry_icon="$icon"
      [[ -n "$name" && -n "$icon" ]] && return 0
    done
  done
}

printf '\0prompt\x1fWindows\n'
printf '\0no-custom\x1ftrue\n'
window_count=0
for window_row in "${window_rows[@]}"; do
  IFS=$'\t' read -r id app title ws <<< "$window_row"
  [[ -n "$id" ]] || continue

  desktop_entry_for_app "$app"

  if (( ${#title} > 96 )); then
    title="${title:0:93}..."
  fi

  printf '%s\0icon\x1f%s\x1finfo\x1f%s\n' \
    "$desktop_entry_name — $title (ws $ws)" "$desktop_entry_icon" "$id"
  ((window_count += 1))
done

(( window_count > 0 )) || exit 0
