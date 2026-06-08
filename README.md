# .dotfiles

Personal dotfiles managed with NixOS + Home Manager.

## Clone

```bash
git clone git@github.com:simonnieder/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

## Apply config

```bash
~/.dotfiles/nixos/rebuild.sh
```

This makes every top-level entry in `~/.dotfiles/.config/` appear in `~/.config/` via Home Manager.

Examples:

```bash
~/.config/nvim
~/.config/waybar
~/.config/kitty
```

Home Manager manages the links, so they resolve through `/nix/store`, but the final source stays your repo in `~/.dotfiles/.config`.

## Add a new config

1. Add a new top-level file or directory under `~/.dotfiles/.config/`
2. Rebuild:

```bash
~/.dotfiles/nixos/rebuild.sh
```

## Typst packages

Only `.local/share/typst` is synced manually:

```bash
ln -sf ~/.dotfiles/.local/share/typst ~/.local/share/typst
```

## Notes

- `~/.config` itself is not symlinked wholesale.
- All top-level entries under `.dotfiles/.config/` are managed by Home Manager.
- Keep secrets and machine-specific private state out of this repo.
