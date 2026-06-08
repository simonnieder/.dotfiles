{ config, ... }:

let
  dotfilesConfigDir = "${config.home.homeDirectory}/.dotfiles/.config";
  sym = config.lib.file.mkOutOfStoreSymlink;

  mkConfigEntry = name: type:
    if type == "directory" then {
      source = sym "${dotfilesConfigDir}/${name}";
      recursive = true;
    } else {
      source = sym "${dotfilesConfigDir}/${name}";
    };

  managedConfigEntries = builtins.mapAttrs mkConfigEntry
    (builtins.readDir (/. + dotfilesConfigDir));
in
{
  home.username = "simonnieder";
  home.homeDirectory = "/home/simonnieder";
  home.stateVersion = "25.11";

  xdg.enable = true;
  xdg.configFile = managedConfigEntries;

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    TERMINAL = "ghostty";
    BROWSER = "zen-browser";
    RIPGREP_CONFIG_PATH = "${config.xdg.configHome}/rgrc";
  };
}
