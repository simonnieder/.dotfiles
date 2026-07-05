#!/usr/bin/env bash
set -euo pipefail

rofi_theme="${ROFI_THEME:-$HOME/.config/rofi/launcher.rasi}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/time-tracker"
current_file="$state_dir/current"              # mirror of active timew tag for DNS blocker
started_file="$state_dir/started_at"          # mirror for display/backcompat
active_elapsed_file="$state_dir/active_elapsed" # mirror for display/backcompat
last_tick_file="$state_dir/last_tick"          # legacy; removed when idle
paused_file="$state_dir/paused"                # legacy; removed when idle
break_category_file="$state_dir/break_category" # category to restart after lock/suspend
recent_file="$state_dir/recent"
legacy_log_file="$state_dir/log.tsv"
legacy_import_marker="$state_dir/timew-imported"
mkdir -p "$state_dir"
umask 077

recent_defaults=(work study media coding reading writing admin meeting personal)

now_wall() {
  date +%s
}

format_duration() {
  local total="$1" minutes hours remaining_minutes
  (( total < 0 )) && total=0
  minutes=$((total / 60))
  hours=$((minutes / 60))
  remaining_minutes=$((minutes % 60))
  if (( hours > 0 )); then
    printf '%dh%02dm' "$hours" "$remaining_minutes"
  else
    printf '%dm' "$minutes"
  fi
}

format_started_at() {
  date -d "@$1" '+%H:%M' 2>/dev/null || printf '%s' "$1"
}

category_total_today() {
  local category="$1"
  timew export "$category" :today 2>/dev/null | jq -r '
    def twdate:
      capture("(?<y>[0-9]{4})(?<m>[0-9]{2})(?<d>[0-9]{2})T(?<H>[0-9]{2})(?<M>[0-9]{2})(?<S>[0-9]{2})Z")
      | "\(.y)-\(.m)-\(.d)T\(.H):\(.M):\(.S)Z"
      | fromdateiso8601;
    [ .[] | ((.end // (now | strftime("%Y%m%dT%H%M%SZ"))) | twdate) - (.start | twdate) ]
    | add // 0
    | floor
  '
}

active_timew() {
  [[ "$(timew get dom.active 2>/dev/null || printf 0)" == 1 ]]
}

active_category_from_timew() {
  active_timew || return 0
  timew get dom.active.tags.1 2>/dev/null || true
}

timew_timestamp_to_epoch() {
  local timestamp="$1"
  if [[ "$timestamp" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z$ ]]; then
    timestamp="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}T${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}Z"
  fi
  date -d "$timestamp" +%s
}

active_start_from_timew() {
  active_timew || return 0
  local started
  started="$(timew get dom.active.start 2>/dev/null || true)"
  [[ -n "$started" ]] || return 0
  timew_timestamp_to_epoch "$started"
}

sync_state_from_timew() {
  current_category="$(active_category_from_timew)"
  started_at="$(active_start_from_timew)"
  [[ -n "${started_at:-}" ]] || started_at=0

  if [[ -n "$current_category" && "$started_at" -gt 0 ]]; then
    active_elapsed=$(( $(now_wall) - started_at ))
    (( active_elapsed < 0 )) && active_elapsed=0
    printf '%s\n' "$current_category" >"$current_file"
    printf '%s\n' "$started_at" >"$started_file"
    printf '%s\n' "$active_elapsed" >"$active_elapsed_file"
  else
    current_category=""
    started_at=0
    active_elapsed=0
    rm -f "$current_file" "$started_file" "$active_elapsed_file" "$last_tick_file" "$paused_file"
  fi
}

load_state() {
  sync_state_from_timew
}

migrate_legacy_log_once() {
  [[ -f "$legacy_log_file" ]] || return 0
  [[ ! -f "$legacy_import_marker" ]] || return 0

  local start end duration category start_iso end_iso
  while IFS=$'\t' read -r start end duration category; do
    [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ ]] || continue
    [[ -n "${category:-}" ]] || continue
    (( end > start )) || continue
    start_iso="$(date -d "@$start" '+%Y-%m-%dT%H:%M:%S')"
    end_iso="$(date -d "@$end" '+%Y-%m-%dT%H:%M:%S')"
    if ! timew track "$start_iso" - "$end_iso" "$category" >/dev/null; then
      printf 'Failed to import legacy time entry: %s - %s %s\n' "$start_iso" "$end_iso" "$category" >&2
      return 1
    fi
  done <"$legacy_log_file"

  # Preserve an active session from the previous file-backed tracker, but start
  # it fresh in Timewarrior so lock/suspend breaks stay as clean intervals.
  if ! active_timew && [[ -f "$current_file" ]]; then
    local legacy_current
    legacy_current="$(<"$current_file")"
    [[ -n "$legacy_current" ]] && timew start "$legacy_current" >/dev/null 2>&1 || true
  fi

  printf 'imported %s\n' "$(date -Is)" >"$legacy_import_marker"
}

remember_category() {
  local category="$1"
  local tmp
  tmp="$(mktemp "$state_dir/recent.XXXXXX")"
  {
    printf '%s\n' "$category"
    [[ -f "$recent_file" ]] && cat "$recent_file"
    printf '%s\n' "${recent_defaults[@]}"
  } | awk 'NF && !seen[$0]++ && count < 50 { print; count++ }' >"$tmp"
  mv "$tmp" "$recent_file"
}

last_recent_category() {
  [[ -f "$recent_file" ]] || return 0
  sed -n '1p' "$recent_file"
}

stop_current() {
  load_state
  if [[ -z "$current_category" ]]; then
    return 0
  fi

  # Ensure the timer is really off. Very short intervals can make `timew stop`
  # fail; in that case cancel the zero-length active interval. Loop defensively
  # because Timewarrior can leave an active interval if a command failed.
  local attempts=0
  while active_timew && (( attempts < 5 )); do
    if ! timew stop >/dev/null 2>&1; then
      timew cancel >/dev/null 2>&1 || true
    fi
    attempts=$((attempts + 1))
  done

  sync_state_from_timew
  flush_dns_cache
}

flush_dns_cache() {
  if command -v resolvectl >/dev/null 2>&1 && systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    resolvectl flush-caches >/dev/null 2>&1 || true
  fi
  pkill -HUP -x dnsmasq 2>/dev/null || true

  # Helium/Chromium can keep blocked 0.0.0.0 answers in its NetworkService
  # even after system DNS changes. Killing only that utility process is cheap:
  # Chromium restarts it automatically and tabs stay open, but DNS is fresh.
  pgrep -f '[h]elium.*--type=utility.*network\.mojom\.NetworkService' |
    xargs -r kill 2>/dev/null || true
}

start_category() {
  local category="$1"
  [[ -n "$category" ]] || return 0
  stop_current
  timew start "$category" >/dev/null
  remember_category "$category"
  sync_state_from_timew
  flush_dns_cache
}

stop_for_break() {
  load_state
  if [[ -n "$current_category" ]]; then
    printf '%s\n' "$current_category" >"$break_category_file"
    stop_current
  fi
  return 0
}

restart_after_break() {
  local category=""
  if [[ -f "$break_category_file" ]]; then
    category="$(<"$break_category_file")"
    rm -f "$break_category_file"
  fi
  if [[ -n "$category" ]]; then
    start_category "$category"
  fi
  return 0
}

lock_with_timer_break() {
  stop_for_break
  trap 'restart_after_break' RETURN
  hyprlock
}

systemctl_with_timer_break() {
  stop_for_break
  trap 'restart_after_break' RETURN
  systemctl "$@"
}

prompt_category() {
  local tmp choice
  tmp="$(mktemp "$state_dir/categories.XXXXXX")"
  trap 'rm -f "$tmp"' RETURN
  {
    [[ -f "$recent_file" ]] && cat "$recent_file"
    printf '%s\n' "${recent_defaults[@]}"
  } | awk 'NF && !seen[$0]++' >"$tmp"

  choice="$(rofi -dmenu -i -p 'Category' -mesg 'Type a new named category or pick one below.' -theme "$rofi_theme" <"$tmp" || true)"
  printf '%s' "$choice"
}

show_menu() {
  load_state

  local elapsed action switch_action choice status_line category
  local -a items
  if [[ -n "$current_category" && "$started_at" -gt 0 ]]; then
    elapsed="$active_elapsed"
    status_line="${current_category} · $(format_duration "$elapsed") · started $(format_started_at "$started_at")"
    action='󰐥  Stop / Close'
    switch_action='󰜉  Switch category'
  else
    status_line='No active category'
    action='󰐥  Close'
    switch_action='󰜉  Start category'
  fi

  items=("$switch_action" "$action")

  choice="$(printf '%s\n' "${items[@]}" |
    rofi -dmenu -i -p 'Time tracker' -mesg "$status_line" -theme "$rofi_theme")"

  case "$choice" in
    '󰐥  Stop / Close'|'󰐥  Close')
      stop_current
      ;;
    '󰜉  Switch category'|'󰜉  Start category')
      category="$(prompt_category || true)"
      [[ -n "${category:-}" ]] && start_category "$category"
      ;;
    *)
      :
      ;;
  esac
}

print_status() {
  load_state
  if [[ -n "$current_category" && "$started_at" -gt 0 ]]; then
    local formatted total_today total_formatted
    formatted="$(format_duration "$active_elapsed")"
    total_today="$(category_total_today "$current_category")"
    total_formatted="$(format_duration "$total_today")"
    jq -nc \
      --arg text "󱎫 ${current_category} ${formatted}" \
      --arg class "running" \
      --arg tooltip "${formatted} current · ${total_formatted} today" \
      '{text:$text, class:$class, tooltip:$tooltip}'
  else
    jq -nc \
      --arg text '󱎫 idle' \
      --arg class 'idle' \
      --arg tooltip 'No active category' \
      '{text:$text, class:$class, tooltip:$tooltip}'
  fi
}

case "${1:-menu}" in
  status)
    migrate_legacy_log_once
    print_status
    ;;
  start)
    migrate_legacy_log_once
    start_category "${2:-$(prompt_category || true)}"
    ;;
  stop)
    migrate_legacy_log_once
    stop_current
    ;;
  pause-for-lock|stop-for-break) stop_for_break ;;
  resume-after-lock|restart-after-break) restart_after_break ;;
  lock) lock_with_timer_break ;;
  systemctl-break) shift; systemctl_with_timer_break "$@" ;;
  menu|*)
    migrate_legacy_log_once
    show_menu
    ;;
esac
