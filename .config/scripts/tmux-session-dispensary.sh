#!/bin/bash

DIRS=(
    "$HOME/documents"
    "$HOME/uni"
    "$HOME/repos"
    "$HOME"
)

# directories with depth 0
ADDITIONAL_CANDIDATES=(
    ".config/"
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

    selected=$(echo "$candidates" \
        | sk --margin 10% --color="bw")

    [[ $selected ]] && selected="$HOME/$selected"
fi

[[ ! $selected ]] && exit 0

selected_name=$(basename "$selected" | tr . _)

if ! tmux has-session -t "$selected_name"; then
    tmux new-session -ds "$selected_name" -c "$selected"
    tmux select-window -t "$selected_name:2"
fi

tmux switch-client -t "$selected_name"
