# .dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Clone

```bash
git clone git@github.com:simonnieder/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

## Stow on a new machine

This repo is currently laid out as a **single Stow package rooted at the repo root**.
That means the normal install command is:

```bash
cd ~/.dotfiles
stow -vt ~ .
```

Dry-run first if you want to preview changes:

```bash
cd ~/.dotfiles
stow -nvt ~ .
```

## Unstow

```bash
cd ~/.dotfiles
stow -Dvt ~ .
```

## Notes

- This creates symlinks into `~`, e.g. `~/.config/...`, `~/wallpapers`, etc.
- If Stow reports conflicts, move or delete the existing files first.
- Because the repo is one package, it is **not stowed individually per app** right now.
  If I ever want per-app stowing, the repo needs to be reorganized into separate package directories.
- Keep secrets, tokens, and machine-specific private state out of this public repo.
