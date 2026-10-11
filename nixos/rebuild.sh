#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-$(hostname)}"

# Use the Git-backed local flake so runtime files such as Unix sockets are not
# treated as Nix source files. Home Manager still reads the live dotfiles path
# for its out-of-store links, so local configuration edits remain visible.
exec sudo nixos-rebuild switch --impure \
  --flake "git+file://$HOME/.dotfiles?dir=nixos#$HOST"
