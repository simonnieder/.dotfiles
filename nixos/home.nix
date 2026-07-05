{ config, pkgs, inputs, user, homeDirectory, ... }:

let
  dotfilesConfigDir = "${homeDirectory}/.dotfiles/.config";
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
  imports = [
    inputs.codex-desktop-linux.homeManagerModules.default
  ];

  home.username = user;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "25.11";

  xdg.enable = true;
  xdg.configFile = managedConfigEntries;

  programs.codexDesktopLinux.enable = true;

  systemd.user.services.cliphist-text = {
    Unit = {
      Description = "Clipboard history store for text";
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "/run/current-system/sw/bin/wl-paste --type text --watch /run/current-system/sw/bin/cliphist store";
      Restart = "always";
      RestartSec = 1;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.cliphist-image = {
    Unit = {
      Description = "Clipboard history store for images";
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "/run/current-system/sw/bin/wl-paste --type image --watch /run/current-system/sw/bin/cliphist store";
      Restart = "always";
      RestartSec = 1;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.voxtype = {
    Unit = {
      Description = "Voxtype push-to-talk voice-to-text daemon";
      Documentation = "https://voxtype.io";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.voxtype-onnx}/bin/voxtype daemon";
      Restart = "on-failure";
      RestartSec = 5;
      Environment = "XDG_RUNTIME_DIR=%t";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  services.wlsunset = {
    enable = false;
    sunrise = "05:00";
    sunset = "20:30";
    temperature = {
      day = 6500;
      night = 4000;
    };
    gamma = 1.0;
  };

  home.sessionVariables = {
    CODEX_CLI_PATH = "${homeDirectory}/.local/bin/codex";
    EDITOR = "nvim";
    VISUAL = "nvim";
    TERMINAL = "ghostty";
    BROWSER = "helium-browser";
    RIPGREP_CONFIG_PATH = "${config.xdg.configHome}/rgrc";
  };
}
