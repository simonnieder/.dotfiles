#!/bin/sh

set -eu

# Niri captures the focused window directly into the clipboard.
niri msg action screenshot-window --write-to-disk false

# Focus an existing ChatGPT window or open one, then paste into the composer.
chatgpt_app_id='chrome-chatgpt.com__-Default'
existing_window_id=$(niri msg -j windows | jq -r --arg app_id "$chatgpt_app_id" \
    '[.[] | select(.app_id == $app_id)] | max_by(.id) | .id // empty')
"$HOME/.config/niri/open-chatgpt.sh"

# Wait for the target to receive focus. A new browser window needs a brief
# extra moment for its page and composer to become ready.
attempt=0
while [ "$attempt" -lt 40 ]; do
    focused_window=$(niri msg -j focused-window 2>/dev/null || true)
    focused_app_id=$(printf '%s\n' "$focused_window" | jq -r '.app_id // empty')
    focused_window_id=$(printf '%s\n' "$focused_window" | jq -r '.id // empty')
    if [ "$focused_app_id" = "$chatgpt_app_id" ]; then
        if [ "$focused_window_id" != "$existing_window_id" ]; then
            sleep 1
        else
            sleep 0.2
        fi
        if [ "$(niri msg -j focused-window | jq -r '.id // empty')" = "$focused_window_id" ]; then
            wtype -M ctrl -k v
            exit 0
        fi
    fi
    sleep 0.25
    attempt=$((attempt + 1))
done

printf '%s\n' 'ChatGPT did not receive focus; screenshot remains in the clipboard.' >&2
exit 1
