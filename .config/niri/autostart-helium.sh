#!/usr/bin/env bash
set -euo pipefail

log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/niri"
log_file="$log_dir/helium-autostart.log"
mkdir -p "$log_dir"

log() {
  printf '%s %s\n' "$(date -Is)" "$*" >>"$log_file"
}

has_helium_window() {
  niri msg -j windows 2>/dev/null |
    jq -e 'any(.[]; ((.app_id // "") | test("^(helium|Helium|helium-browser)$")))' >/dev/null
}

# Direct niri startup was firing Helium too early: the process briefly started
# but did not leave a window. Wait for the session to settle, then retry until
# niri actually sees a Helium window.
sleep 8

for attempt in 1 2 3; do
  if has_helium_window; then
    log "Helium window already present"
    exit 0
  fi

  log "Starting Helium (attempt $attempt)"
  helium-browser >>"$log_file" 2>&1 &
  sleep 10
done

if has_helium_window; then
  log "Helium window present after retry"
else
  log "Helium autostart gave up: no niri window detected"
fi
