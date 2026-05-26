#!/usr/bin/env bash
set -euo pipefail

cd "$HOME/.dotfiles"
git add nixos
sudo nixos-rebuild switch --impure --flake "$HOME/.dotfiles/nixos#nixos"
