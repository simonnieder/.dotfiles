#!/usr/bin/env bash
set -euo pipefail

rofi_theme="$HOME/.config/rofi/launcher.rasi"

groups=(Apps Tools Appearance System Folders)
group_icons=(󰀻 󰜉 󰔎 󰒓 󰉋)
action_groups=(
  Apps Apps
  Tools Tools Tools
  Appearance Appearance Appearance
  System System System System
  Folders Folders Folders Folders
)
action_icons=(󰀻 󰖲 󰅌 󰞅 󱎫 󰔎 󰖔 󰍹  󰑓 󰑓 󰒲   󰠮 󰲋)
action_ids=(0 1 2 3 4 5 6 7 8 9 10 13 11 12 14 15)
action_names=(
  'Applications' 'Recent windows'
  'Clipboard' 'Emoji' 'Time tracker'
  'Toggle light/dark mode' 'Toggle night mode' 'Toggle laptop screen'
  'Power' 'Reload niri' 'Restart waybar' 'Rebuild NixOS'
  'Edit dotfiles' 'Edit NixOS config' 'Open wiki' 'Open repos'
)

run_action() {
case "$1" in
  0)
    exec rofi -show drun -theme "$rofi_theme"
    ;;
  1)
    exec "$HOME/.config/rofi/scripts/recent-windows.sh"
    ;;
  2)
    exec "$HOME/.config/rofi/scripts/clipboard.sh"
    ;;
  3)
    exec "$HOME/.config/rofi/scripts/emoji.sh"
    ;;
  4)
    exec "$HOME/.config/rofi/scripts/time-tracker.sh"
    ;;
  5)
    exec /run/current-system/sw/bin/bash "$HOME/.config/scripts/toggle-color-scheme.sh"
    ;;
  6)
    exec "$HOME/.config/rofi/scripts/night-mode-toggle.sh"
    ;;
  7)
    exec "$HOME/.config/niri/toggle-laptop-brightness.sh"
    ;;
  8)
    exec "$HOME/.config/rofi/scripts/powermenu.sh"
    ;;
  9)
    exec niri msg action load-config-file
    ;;
  10)
    exec sh -c "$HOME/.config/waybar/restart_waybar.sh"
    ;;
  11)
    exec zeditor "$HOME/.dotfiles"
    ;;
  12)
    exec zeditor "$HOME/.dotfiles/nixos"
    ;;
  13)
    before_ids="$(niri msg -j windows | jq -r '.[].id' | sort)"
    ghostty --title="NixOS Rebuild" -e bash -lc "printf '\033]0;NixOS Rebuild\007'; $HOME/.dotfiles/nixos/rebuild.sh; echo; read -rp 'Press enter to close...'" &
    for _ in {1..30}; do
      new_id="$(comm -13 <(printf '%s\n' "$before_ids") <(niri msg -j windows | jq -r '.[] | select(.app_id == "com.mitchellh.ghostty" or (.title // "" | test("NixOS Rebuild"))) | .id' | sort) | tail -n1)"
      if [[ -n "$new_id" ]]; then
        niri msg action focus-window --id "$new_id"
        niri msg action move-window-to-floating
        exit 0
      fi
      sleep 0.1
    done
    ;;
  14)
    exec zeditor "$HOME/wiki"
    ;;
  15)
    exec zeditor "$HOME/repos"
    ;;
esac
}

group=''
while :; do
  rows=()
  row_types=()
  row_values=()

  if [[ -z "$group" ]]; then
    for i in "${!groups[@]}"; do
      rows+=("${group_icons[i]}  ${groups[i]} ›")
      row_types+=(group)
      row_values+=("${groups[i]}")
    done
  else
    rows+=("‹  All commands")
    row_types+=(back)
    row_values+=("")
  fi

  for i in "${!action_names[@]}"; do
    if [[ -z "$group" || "${action_groups[i]}" == "$group" ]]; then
      rows+=("${action_icons[i]}  ${action_groups[i]} > ${action_names[i]}")
      row_types+=(action)
      row_values+=("${action_ids[i]}")
    fi
  done

  choice="$(printf '%s\n' "${rows[@]}" | rofi -dmenu -i -matching fuzzy -format i -p "${group:-command}" -theme "$rofi_theme")" || exit 0
  [[ "$choice" =~ ^[0-9]+$ ]] || exit 0

  case "${row_types[choice]}" in
    group) group="${row_values[choice]}" ;;
    back) group='' ;;
    action) run_action "${row_values[choice]}"; exit 0 ;;
  esac
done
