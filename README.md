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

The rebuild script uses the current hostname as the flake output. You can also pass one explicitly:

```bash
~/.dotfiles/nixos/rebuild.sh nixos
```

## NixOS layout

```text
nixos/
  flake.nix
  hosts/
    nixos/
      default.nix
      hardware-configuration.nix
  modules/
    common.nix
    packages.nix
```

`modules/packages.nix` is intentionally shared by every PC. Host-specific hardware, hostname, resume UUIDs, and laptop power behavior live under `hosts/<hostname>/`.

To add another PC:

1. create `nixos/hosts/<hostname>/`
2. copy that machine's generated `hardware-configuration.nix` into it
3. create `default.nix` importing `../../modules/common.nix` and `../../modules/packages.nix`
4. add it to `nixos/flake.nix` under `nixosConfigurations`

## Home Manager dotfiles

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
