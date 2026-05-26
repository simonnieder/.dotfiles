#!/usr/bin/env bash
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

if ! tmux has-session -t "$selected_name" 2>/dev/null; then
    tmux new-session -ds "$selected_name" -c "$selected"
fi

tmux switch-client -t "$selected_name"
