#!/usr/bin/env bash
set -euo pipefail

cd "$HOME/.dotfiles"
stow -Rvt "$HOME/.config" .config

echo "Restowed .config into $HOME/.config"
