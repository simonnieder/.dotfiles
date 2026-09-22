#!/usr/bin/env bash
set -u -o pipefail
umask 077

keyboard_backlight="platform::kbd_backlight"
keyboard_state_file="${XDG_RUNTIME_DIR:-/tmp}/display-power-kbd-${UID}"

power_off_monitors() {
  if [[ -n "${NIRI_SOCKET:-}" ]]; then
    niri msg action power-off-monitors
  elif [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl dispatch dpms off
  fi
}

power_on_monitors() {
  if [[ -n "${NIRI_SOCKET:-}" ]]; then
    niri msg action power-on-monitors
  elif [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl dispatch dpms on
  fi
}

case "${1:-}" in
  off)
    if [[ ! -s "$keyboard_state_file" ]]; then
      brightnessctl -d "$keyboard_backlight" get >"$keyboard_state_file" 2>/dev/null || true
    fi
    brightnessctl -d "$keyboard_backlight" set 0 >/dev/null 2>&1 || true
    power_off_monitors
    ;;
  on)
    power_on_monitors
    if [[ -s "$keyboard_state_file" ]] && read -r keyboard_level <"$keyboard_state_file" && [[ "$keyboard_level" =~ ^[0-9]+$ ]]; then
      brightnessctl -d "$keyboard_backlight" set "$keyboard_level" >/dev/null 2>&1 || true
    fi
    rm -f -- "$keyboard_state_file"
    ;;
  *)
    printf 'Usage: %s {off|on}\n' "$0" >&2
    exit 2
    ;;
esac
