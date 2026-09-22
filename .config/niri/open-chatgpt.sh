#!/bin/sh

set -eu

app_id='chrome-chatgpt.com__-Default'
current_workspace_id=$(niri msg -j windows 2>/dev/null \
    | jq -r '[.[] | select(.is_focused)] | .[0].workspace_id // empty')
current_column_index=$(niri msg -j windows 2>/dev/null \
    | jq -r '[.[] | select(.is_focused)] | .[0].layout.pos_in_scrolling_layout[0] // empty')
current_app_id=$(niri msg -j windows 2>/dev/null \
    | jq -r '[.[] | select(.is_focused)] | .[0].app_id // empty')

find_window() {
    niri msg -j windows 2>/dev/null \
        | jq -r --arg app_id "$app_id" \
            '[.[] | select(.app_id == $app_id)] | max_by(.id) | .id // empty'
}

window_id=$(find_window)

if [ -z "$window_id" ]; then
    helium --app=https://chatgpt.com --class=ChatGPT --name=ChatGPT >/dev/null 2>&1 &
fi

# Chromium may reuse its existing process, so wait for the Wayland window
# rather than relying on the launcher's PID.
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    window_id=$(find_window)

    if [ -n "$window_id" ]; then
        if [ "$current_app_id" = "$app_id" ]; then
            exit 0
        fi
        window_workspace_id=$(niri msg -j windows 2>/dev/null \
            | jq -r --arg app_id "$app_id" \
                '[.[] | select(.app_id == $app_id)] | max_by(.id) | .workspace_id // empty')
        niri msg action focus-window --id "$window_id"
        if [ -n "$current_workspace_id" ] && [ "$window_workspace_id" != "$current_workspace_id" ]; then
            niri msg action move-column-to-workspace "$current_workspace_id"
        fi
        if [ -n "$current_column_index" ]; then
            niri msg action move-column-to-index "$((current_column_index + 1))"
        fi
        exit 0
    fi

    sleep 0.25
done

exit 1
