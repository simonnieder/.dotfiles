#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-$(hostname)}"

cd "$HOME/.dotfiles"
git add nixos
sudo nixos-rebuild switch --impure --flake "$HOME/.dotfiles/nixos#$HOST"
