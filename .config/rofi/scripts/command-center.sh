#!/usr/bin/env bash
set -euo pipefail

rofi_theme="$HOME/.config/rofi/launcher.rasi"

choice="$(cat <<'EOF' | rofi -dmenu -i -p "command" -theme "$rofi_theme"
󰀻  Applications
󰖲  Recent Windows
󰅌  Clipboard
󰞅  Emoji
󱎫  Time Tracker
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
  "󰀻  Applications")
    exec rofi -show drun -theme "$rofi_theme"
    ;;
  "󰖲  Recent Windows")
    exec "$HOME/.config/rofi/scripts/recent-windows.sh"
    ;;
  "󱎫  Time Tracker")
    exec "$HOME/.config/rofi/scripts/time-tracker.sh"
    ;;
  "󰖔  Toggle night mode")
    exec "$HOME/.config/rofi/scripts/night-mode-toggle.sh"
    ;;
  "󰍹  Toggle laptop screen")
    exec "$HOME/.config/niri/toggle-laptop-brightness.sh"
    ;;
  "󰅌  Clipboard")
    exec "$HOME/.config/rofi/scripts/clipboard.sh"
    ;;
  "󰞅  Emoji")
    exec "$HOME/.config/rofi/scripts/emoji.sh"
    ;;
  "  Power")
    exec "$HOME/.config/rofi/scripts/powermenu.sh"
    ;;
  "󰑓  Reload niri")
    exec niri msg action load-config-file
    ;;
  "󰑓  Restart waybar")
    exec sh -c "$HOME/.config/waybar/restart_waybar.sh"
    ;;
  "  Edit dotfiles")
    exec zeditor "$HOME/.dotfiles"
    ;;
  "  Edit NixOS config")
    exec zeditor "$HOME/.dotfiles/nixos"
    ;;
  "󰒲  Rebuild NixOS")
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
  "󰠮  Open wiki")
    exec zeditor "$HOME/wiki"
    ;;
  "󰲋  Open repos")
    exec zeditor "$HOME/repos"
    ;;
esac
