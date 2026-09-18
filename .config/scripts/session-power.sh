#!/usr/bin/env bash
set -u -o pipefail

tracker="$HOME/.config/scripts/solidtime-tracker.sh"
hyprlock_pid=""
hyprlock_log=""
timer_pause_requested=0

finish() {
  [[ -n "$hyprlock_log" ]] && rm -f -- "$hyprlock_log"
  if (( timer_pause_requested )); then
    "$tracker" restart-after-break || true
  fi
}
trap finish EXIT

start_lock_and_wait() {
  local attempt

  if pgrep -x hyprlock >/dev/null; then
    return 0
  fi

  hyprlock_log="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/hyprlock-session.XXXXXX")" || return 1
  hyprlock --grace 0 --immediate-render --no-fade-in >"$hyprlock_log" 2>&1 &
  hyprlock_pid=$!

  # This message follows the compositor's ext-session-lock "locked" event.
  # Once received, no unlocked frame can appear when the system resumes.
  for ((attempt = 0; attempt < 100; attempt++)); do
    if grep -Fq 'onLockLocked called' "$hyprlock_log"; then
      return 0
    fi
    if ! kill -0 "$hyprlock_pid" 2>/dev/null; then
      wait "$hyprlock_pid" || true
      printf 'hyprlock exited before securing the session:\n' >&2
      sed -n '1,120p' "$hyprlock_log" >&2
      return 1
    fi
    sleep 0.05
  done

  printf 'hyprlock did not confirm that the session was secured; refusing to sleep\n' >&2
  return 1
}

pause_timer() {
  "$tracker" stop-for-break || true
  timer_pause_requested=1
}

wait_for_unlock() {
  if [[ -n "$hyprlock_pid" ]]; then
    wait "$hyprlock_pid" 2>/dev/null || true
  else
    while pgrep -x hyprlock >/dev/null; do
      sleep 0.2
    done
  fi
}

lock_session() {
  if ! start_lock_and_wait; then
    wait_for_unlock
    return 1
  fi
  pause_timer
  wait_for_unlock
}

sleep_session() {
  local action="$1" systemctl_status

  if ! start_lock_and_wait; then
    wait_for_unlock
    return 1
  fi

  # Network access for Solidtime happens only after the screen is secured.
  pause_timer
  systemctl "$action"
  systemctl_status=$?
  wait_for_unlock
  return "$systemctl_status"
}

case "${1:-}" in
  lock)
    lock_session
    ;;
  suspend|hibernate|suspend-then-hibernate)
    sleep_session "$1"
    ;;
  *)
    printf 'Usage: %s {lock|suspend|hibernate|suspend-then-hibernate}\n' "$0" >&2
    exit 2
    ;;
esac
