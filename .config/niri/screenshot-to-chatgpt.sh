#!/bin/sh

set -eu

# Keep the screenshot in the clipboard as PNG data; no screenshot file is
# written to disk.
grim -t png - | wl-copy --type image/png

# Focus an existing ChatGPT window or open one, then paste into the composer.
"$HOME/.config/niri/open-chatgpt.sh"

# Give a newly opened ChatGPT page time to load and focus its composer.
sleep "${CHATGPT_PASTE_DELAY_SECONDS:-3.5}"
wtype -M ctrl -k v
