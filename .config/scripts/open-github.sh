#!/usr/bin/env bash

pane_path="$(tmux display-message -p '#{pane_current_path}')"
cd "$pane_path" || exit 1
url="$(git remote get-url origin)"

if [[ $url == *github.com* ]]; then
    if [[ $url == git@* ]]; then
        url="${url#git@}"
        url="${url/:/\/}"
        url="https://$url"
    fi
    xdg-open "$url"
else
    echo "This repository is not hosted on GitHub"
fi
