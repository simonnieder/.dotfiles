#!/usr/bin/env bash
set -euo pipefail

state_dir="${XDG_RUNTIME_DIR:-/tmp}/waycal-${UID}"
pid_file="$state_dir/pid"
mkdir -p "$state_dir"

if [[ -f "$pid_file" ]]; then
  pid="$(<"$pid_file")"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null \
      && tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q waycal; then
    kill "$pid"
    rm -f "$pid_file"
    exit 0
  fi
  rm -f "$pid_file"
fi

if [[ -x "$HOME/.local/bin/waycal" ]]; then
  waycal_bin="$HOME/.local/bin/waycal"
elif [[ -x /run/current-system/sw/bin/waycal ]]; then
  waycal_bin=/run/current-system/sw/bin/waycal
else
  printf 'waycal is not installed\n' >/tmp/waycal.log
  exit 1
fi

"$waycal_bin" >/tmp/waycal.log 2>&1 &
printf '%s\n' "$!" >"$pid_file"
