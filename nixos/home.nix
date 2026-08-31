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
    (builtins.readDir ../.config);
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

  # Nixpkgs ships the GUI as `obsidian` and the native CLI as
  # `obsidian-cli`. The GUI cannot register the CLI itself because its NixOS
  # wrapper ultimately runs an executable named `electron`.
  programs.obsidian = {
    enable = true;
    cli.enable = true;
  };

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
    enable = true;
    sunrise = "05:00";
    sunset = "20:30";
    temperature = {
      day = 6500;
      night = 4000;
    };
    gamma = 1.0;
  };

  # The command-center toggle may stop wlsunset for the rest of the night.
  # Start it again the next morning so the manual override never persists.
  systemd.user.timers.wlsunset-auto-enable = {
    Unit.Description = "Re-enable automatic night mode";
    Timer = {
      OnCalendar = "*-*-* 05:00:00";
      Persistent = true;
      Unit = "wlsunset.service";
    };
    Install.WantedBy = [ "timers.target" ];
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
