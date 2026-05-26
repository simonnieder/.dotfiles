# .dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Clone

```bash
git clone git@github.com:simonnieder/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

## Stow only into `~/.config`

Stow the `.config` package into `~/.config`:

```bash
cd ~/.dotfiles
stow -Rvt ~/.config .config
```

This creates links like:

```bash
~/.config/nvim -> ~/.dotfiles/.config/nvim
~/.config/waybar -> ~/.dotfiles/.config/waybar
```

Dry-run first if you want to preview changes:

```bash
cd ~/.dotfiles
stow -nvt ~/.config .config
```

### Add a new config to dotfiles

```bash
# 1. Move the live config into dotfiles
mv ~/.config/someapp ~/.dotfiles/.config/someapp
# 2. Re-stow
cd ~/.dotfiles && stow -Rvt ~/.config .config
```

### Typst packages (manual symlink, not stow)

Only `.local/share/typst` is synced:

```bash
ln -sf ~/.dotfiles/.local/share/typst ~/.local/share/typst
```

## Unstow

```bash
cd ~/.dotfiles
stow -Dvt ~/.config .config
```

## Notes

- Stow target is `~/.config`, not `~`.
- `.stow-local-ignore` is kept in the repo, but when using `stow ... .config` only the `.config` package is stowed.
- `~/.local/share/typst` is a separate manual symlink to `~/.dotfiles/.local/share/typst`.
- Keep secrets and machine-specific private state out of this repo.
