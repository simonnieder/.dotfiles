#!/usr/bin/env bash
# Focus a window by app-id pattern, preferring the currently focused monitor.
# Usage: focus-app.sh <app-id-pattern> <launch-command...>

set -euo pipefail

PATTERN="${1:?Usage: focus-app.sh <app-id-pattern> <launch-command...>}"
shift

FOCUSED_OUTPUT="$(niri msg -j focused-output | jq -r '.name')"
WINDOWS_JSON="$(niri msg -j windows)"
WORKSPACES_JSON="$(niri msg -j workspaces)"

ID="$({
    jq -rn \
        --arg pat "$PATTERN" \
        --arg focused_output "$FOCUSED_OUTPUT" \
        --argjson windows "$WINDOWS_JSON" \
        --argjson workspaces "$WORKSPACES_JSON" '
        def workspace_output($workspace_id):
            ($workspaces[] | select(.id == $workspace_id) | .output);

        [ $windows[]
          | select((.app_id // "") | test($pat; "i"))
          | . + { output: workspace_output(.workspace_id) }
        ]
        | sort_by(
            (if .output == $focused_output then 0 else 1 end),
            .workspace_id,
            -.focus_timestamp.secs,
            -.focus_timestamp.nanos
          )
        | .[0].id // empty
        '
} )"

if [ -n "$ID" ]; then
    niri msg action focus-window --id "$ID"
else
    exec "$@"
fi
