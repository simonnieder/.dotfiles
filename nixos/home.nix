{ config, ... }:

let
  dot = "${config.home.homeDirectory}/.dotfiles/.config";
  sym = config.lib.file.mkOutOfStoreSymlink;
in
{
  home.username = "simonnieder";
  home.homeDirectory = "/home/simonnieder";
  home.stateVersion = "25.11";

  home.file = {
    ".config/alacritty".source      = sym "${dot}/alacritty";
    ".config/btop".source           = sym "${dot}/btop";
    ".config/dunst".source          = sym "${dot}/dunst";
    ".config/eza".source            = sym "${dot}/eza";
    ".config/fish" = {
      source = sym "${dot}/fish";
      force = true;
    };
    ".config/ghostty".source        = sym "${dot}/ghostty";
    ".config/gtk-3.0".source        = sym "${dot}/gtk-3.0";
    ".config/gtk-4.0".source        = sym "${dot}/gtk-4.0";
    ".config/htop".source           = sym "${dot}/htop";
    ".config/hypr".source           = sym "${dot}/hypr";
    ".config/kitty".source          = sym "${dot}/kitty";
    ".config/lazygit".source        = sym "${dot}/lazygit";
    ".config/matugen".source        = sym "${dot}/matugen";
    ".config/mpv".source            = sym "${dot}/mpv";
    ".config/niri".source           = sym "${dot}/niri";
    ".config/nvim".source           = sym "${dot}/nvim";
    ".config/qt5ct".source          = sym "${dot}/qt5ct";
    ".config/qt6ct".source          = sym "${dot}/qt6ct";
    ".config/rofi".source           = sym "${dot}/rofi";
    ".config/scripts".source        = sym "${dot}/scripts";
    ".config/sway".source           = sym "${dot}/sway";
    ".config/swaylock".source       = sym "${dot}/swaylock";
    ".config/tmux".source           = sym "${dot}/tmux";
    ".config/waybar".source         = sym "${dot}/waybar";
    ".config/wofi".source           = sym "${dot}/wofi";
    ".config/zed".source            = sym "${dot}/zed";
    ".config/starship.toml".source  = sym "${dot}/starship.toml";
    ".rgrc".source                  = sym "${dot}/rgrc";
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    TERMINAL = "ghostty";
    BROWSER = "zen-browser";
  };
}
