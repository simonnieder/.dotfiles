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
    (builtins.removeAttrs (builtins.readDir ../.config) [ "mimeapps.list" ]);
in
{
  imports = [ inputs.hex.homeManagerModules.hex ];

  programs.hex = {
    enable = true;
    autostart = true;
  };

  home.username = user;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "25.11";

  xdg.enable = true;
  xdg.configFile = managedConfigEntries;
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = [ "helium.desktop" ];
      "application/xhtml+xml" = [ "helium.desktop" ];
      "text/markdown" = [ "obsidian.desktop" ];
      "text/x-markdown" = [ "obsidian.desktop" ];
    };
  };

  home.file.".agents/skills".source =
    sym "${homeDirectory}/.dotfiles/agent-skills";
  home.file.".npmrc".source =
    sym "${homeDirectory}/.dotfiles/.npmrc";

  home.packages = [ (pkgs.callPackage ./pkgs/chatgpt.nix { }) ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

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

  systemd.user.services.hex = {
    Unit = {
      After = [ "internal-microphone.service" ];
      Requires = [ "internal-microphone.service" ];
    };
    Service.Environment = [
      "PIPEWIRE_NODE=alsa_input.pci-0000_04_00.6.HiFi__Mic2__source"
    ];
  };

  systemd.user.services.internal-microphone = {
    Unit = {
      Description = "Restore internal microphone capture and gain";
      After = [ "pipewire.service" "wireplumber.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 2;
      ExecStart = pkgs.writeShellScript "setup-internal-microphone" ''
        set -eu
        ${pkgs.alsa-utils}/bin/amixer -D hw:Generic_1 sset 'Internal Mic Boost' 24dB
        ${pkgs.alsa-utils}/bin/amixer -D hw:Generic_1 sset Capture 0dB cap
      '';
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.battery-notifications = {
    Unit = {
      Description = "Low battery notifications through Hokum";
      After = [ "hokum.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 ${homeDirectory}/.config/scripts/battery-notifications.py";
      Environment = "PATH=${pkgs.libnotify}/bin";
    };
  };

  systemd.user.timers.battery-notifications = {
    Unit = {
      Description = "Check battery charge every minute";
      PartOf = [ "graphical-session.target" ];
    };
    Timer = {
      OnActiveSec = "15s";
      OnUnitActiveSec = "60s";
      AccuracySec = "5s";
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
