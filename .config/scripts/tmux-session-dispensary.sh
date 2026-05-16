#!/bin/bash

DIRS=(
    "$HOME/uni"
    "$HOME/repos"
)

# directories with depth 0
ADDITIONAL_CANDIDATES=(
    ".config/",
	"/home/simonnieder"
)

if [[ $# -eq 1 ]]; then
    selected=$1
else
    candidates=$(fd . "${DIRS[@]}" --type=dir --max-depth=1 --full-path --base-directory "$HOME" \
        | sed "s|^$HOME/||")

    # append additional candidates
    for extra in "${ADDITIONAL_CANDIDATES[@]}"; do
        candidates+=$'\n'"$extra"
    done

    selected=$(echo "$candidates" | fzf)

    if [[ $selected ]]; then
        if [[ "$selected" = /* ]]; then
            selected="$selected"
        else
            selected="$HOME/$selected"
        fi
    fi
fi

[[ ! $selected ]] && exit 0

selected_name=$(basename "$selected" | tr . _)

if ! tmux has-session -t "$selected_name"; then
    tmux new-session -ds "$selected_name" -c "$selected"
    tmux select-window -t "$selected_name:2"
fi

tmux switch-client -t "$selected_name"
