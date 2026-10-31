#!/usr/bin/env bash
set -euo pipefail

wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
volume="$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@)"
if [[ "$volume" == *"[MUTED]"* ]]; then
    title="Microphone muted"
    icon="microphone-sensitivity-muted-symbolic"
else
    title="Microphone on"
    icon="audio-input-microphone-symbolic"
fi
notify-send -a Microphone -i "$icon" -u low -t 2000 \
    -h string:x-dunst-stack-tag:microphone "$title"
