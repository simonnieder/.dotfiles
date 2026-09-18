#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-$(hostname)}"

# Use the repository as a path flake so new files are visible without silently
# staging every change under nixos/.
exec sudo nixos-rebuild switch --impure \
  --flake "path:$HOME/.dotfiles?dir=nixos#$HOST"
