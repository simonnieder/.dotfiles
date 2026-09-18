#!/bin/sh

set -u

player=""

# Prefer something currently playing. If everything is paused, show the first
# player that still has metadata so the module does not disappear unexpectedly.
for candidate in $(playerctl -l 2>/dev/null); do
    if [ "$(playerctl -p "$candidate" status 2>/dev/null || true)" = "Playing" ]; then
        player=$candidate
        break
    fi
done

if [ -z "$player" ]; then
    for candidate in $(playerctl -l 2>/dev/null); do
        if playerctl -p "$candidate" metadata --format '{{title}}' >/dev/null 2>&1; then
            player=$candidate
            break
        fi
    done
fi

if [ -z "$player" ]; then
    printf '%s\n' '{"text":"","class":"empty","tooltip":"No media player"}'
    exit 0
fi

status=$(playerctl -p "$player" status 2>/dev/null || printf 'Stopped')
artist=$(playerctl -p "$player" metadata --format '{{artist}}' 2>/dev/null || true)
title=$(playerctl -p "$player" metadata --format '{{title}}' 2>/dev/null || true)

if [ -z "$title" ] && [ -z "$artist" ]; then
    printf '%s\n' '{"text":"","class":"empty","tooltip":"No media"}'
    exit 0
fi

if [ -n "$artist" ] && [ -n "$title" ]; then
    text="$title · $artist"
elif [ -n "$title" ]; then
    text="$title"
else
    text="$artist"
fi

jq -cn \
    --arg text "$text" \
    --arg title "$title" \
    --arg artist "$artist" \
    --arg player "$player" \
    --arg status "$status" \
    '{text:$text, tooltip:([$title,$artist] | map(select(length > 0)) | join(" · ")) + "\n" + $player + " · " + $status, class:($status | ascii_downcase)}'
