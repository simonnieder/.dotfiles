#!/usr/bin/env bash
# Herdr workspace dispenser. Kept at its old path because tmux bindings also
# use it, but it deliberately uses Herdr's workspace API rather than tmux.
set -euo pipefail

DIRS=(
  "$HOME/uni"
  "$HOME/repos"
)

ADDITIONAL_CANDIDATES=(
  ".config"
  ".dotfiles"
  "wiki"
  "$HOME"
)

if [[ $# -eq 1 ]]; then
  selected=$1
else
  candidates=$(
    for dir in "${DIRS[@]}"; do
      [[ -d "$dir" ]] || continue
      find "$dir" -mindepth 1 -maxdepth 1 -type d
    done | sed "s|^$HOME/||" | sort -u
  )

  for extra in "${ADDITIONAL_CANDIDATES[@]}"; do
    candidates+=$'\n'"$extra"
  done

  selected=$(printf '%s\n' "$candidates" | awk 'NF' | fzf)

  if [[ -n "$selected" && "$selected" != /* ]]; then
    selected="$HOME/$selected"
  fi
fi

[[ -n "${selected:-}" ]] || exit 0
selected_name=$(basename "$selected" | tr . _)

# Reuse a workspace with this label, otherwise create one rooted at the
# selected directory. A label makes the workspace easy to recognise in Herdr.
workspace_id=$(herdr workspace list | jq -r --arg label "$selected_name" \
  '.result.workspaces[] | select(.label == $label) | .workspace_id' | head -n1)

if [[ -n "$workspace_id" ]]; then
  herdr workspace focus "$workspace_id"
else
  herdr workspace create --cwd "$selected" --label "$selected_name" --focus
fi
