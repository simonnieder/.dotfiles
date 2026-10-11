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

# Launch immediately. If an early launch fails to create a window, retry while
# polling niri rather than imposing a fixed delay on every successful startup.
for attempt in 1 2 3; do
  if has_helium_window; then
    log "Helium window already present"
    exit 0
  fi

  log "Starting Helium (attempt $attempt)"
  helium-browser >>"$log_file" 2>&1 &

  for _ in {1..20}; do
    sleep 0.5
    if has_helium_window; then
      log "Helium window present"
      exit 0
    fi
  done
done

log "Helium autostart gave up: no niri window detected"
