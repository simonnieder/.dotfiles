#!/usr/bin/env bash
set -euo pipefail

rofi_theme="$HOME/.config/rofi/launcher.rasi"

# Return the original row number rather than the rendered label. This avoids
# dispatch failures caused by icon/font text differing from the source string.
choice="$(cat <<'EOF' | rofi -dmenu -i -format i -p "command" -theme "$rofi_theme"
󰀻  Applications
󰖲  Recent Windows
󰅌  Clipboard
󰞅  Emoji
󱎫  Time Tracker
󰔎  Toggle light/dark mode
󰖔  Toggle night mode
󰍹  Toggle laptop screen
  Power
󰑓  Reload niri
󰑓  Restart waybar
  Edit dotfiles
  Edit NixOS config
󰒲  Rebuild NixOS
󰠮  Open wiki
󰲋  Open repos
EOF
)"

case "$choice" in
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
