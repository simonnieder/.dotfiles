#!/usr/bin/env bash
set -euo pipefail

uptime_text="$(uptime -p 2>/dev/null | sed 's/^up //' || uptime | sed 's/.*up *//; s/, *[0-9][0-9]* user.*//')"

lock='  Lock'
suspend='  Sleep + Hibernate'
hibernate='󰒲  Hibernate'
logout='󰈆  Logout'
reboot='  Reboot'
shutdown='  Shutdown'
yes='  Yes'
no='  No'

rofi_theme="$HOME/.config/rofi/launcher.rasi"

confirm() {
  printf '%s\n%s\n' "$yes" "$no" |
    rofi -dmenu -i -p 'Confirm' -mesg "Run: $1?" -theme "$rofi_theme"
}

run_confirmed() {
  local label="$1"
  shift
  if [[ "$(confirm "$label")" == "$yes" ]]; then
    "$@"
  fi
}

chosen="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
  "$lock" "$suspend" "$hibernate" "$logout" "$reboot" "$shutdown" |
  rofi -dmenu -i -p 'Power' -mesg "Uptime: $uptime_text" -theme "$rofi_theme")"

case "$chosen" in
  "$lock")
    "$HOME/.config/rofi/scripts/time-tracker.sh" lock
    ;;
  "$suspend")
    run_confirmed 'sleep + hibernate' "$HOME/.config/rofi/scripts/time-tracker.sh" systemctl-break suspend-then-hibernate
    ;;
  "$hibernate")
    run_confirmed 'hibernate' "$HOME/.config/rofi/scripts/time-tracker.sh" systemctl-break hibernate
    ;;
  "$logout")
    run_confirmed 'logout' niri msg action quit --skip-confirmation
    ;;
  "$reboot")
    run_confirmed 'reboot' systemctl reboot
    ;;
  "$shutdown")
    run_confirmed 'shutdown' systemctl poweroff
    ;;
esac
