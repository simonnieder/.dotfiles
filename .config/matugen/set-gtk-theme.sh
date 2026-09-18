#!/usr/bin/env bash
set -euo pipefail

mode="${1:?expected light or dark}"
case "$mode" in
  light | dark) ;;
  *) exit 2 ;;
esac

dconf write /org/gnome/desktop/interface/gtk-theme "''"
dconf write /org/gnome/desktop/interface/gtk-theme "'adw-gtk3-$mode'"
