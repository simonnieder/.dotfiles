{ pkgs, lib, user, homeDirectory, ... }:

let
  nordvpn-cli = pkgs.callPackage ../pkgs/nordvpn-cli.nix { };

  socialMediaBlocker = pkgs.writeShellApplication {
    name = "social-media-blocker";
    runtimeInputs = with pkgs; [ coreutils procps ];
    text = ''
      set -euo pipefail

      state_file="${homeDirectory}/.local/state/time-tracker/current"
      dnsmasq_hosts="/run/social-block/hosts"
      marker_begin="# BEGIN time-tracker social block"
      marker_end="# END time-tracker social block"
      exempt_categories=(media)
      block_domains=(
        facebook.com www.facebook.com m.facebook.com mobile.facebook.com
        instagram.com www.instagram.com m.instagram.com
        x.com www.x.com twitter.com www.twitter.com mobile.twitter.com
        reddit.com www.reddit.com old.reddit.com
        tiktok.com www.tiktok.com m.tiktok.com
        threads.net www.threads.net
        linkedin.com www.linkedin.com
        youtube.com www.youtube.com m.youtube.com youtu.be
        twitch.tv www.twitch.tv m.twitch.tv
        snapchat.com www.snapchat.com
        pinterest.com www.pinterest.com
      )

      current_category=""

      read_state() {
        if [[ -f "$state_file" ]]; then
          current_category="$(<"$state_file")"
        else
          current_category=""
        fi
      }

      should_block() {
        local category_lower="$1"
        [[ -z "$category_lower" ]] && return 1
        for exempt in "''${exempt_categories[@]}"; do
          if [[ "$category_lower" == "$exempt" ]]; then
            return 1
          fi
        done
        return 0
      }

      generate_hosts() {
        local category_lower="''${current_category,,}"
        if should_block "$category_lower"; then
          {
            printf '%s\n' "$marker_begin"
            for domain in "''${block_domains[@]}"; do
              printf '0.0.0.0 %s\n' "$domain"
              printf '::1 %s\n' "$domain"
            done
            printf '%s\n' "$marker_end"
          }
        fi
      }

      write_hosts_file() {
        local tmp
        tmp="$(mktemp /run/social-block/hosts.XXXXXX)"
        generate_hosts >"$tmp"

        if ! cmp -s "$tmp" "$dnsmasq_hosts" 2>/dev/null; then
          install -m 0644 "$tmp" "$dnsmasq_hosts"
          pkill -HUP -x dnsmasq 2>/dev/null || true
        fi
        rm -f "$tmp"
      }

      mkdir -p /run/social-block
      touch "$dnsmasq_hosts"

      last_category="__social_blocker_initial__"
      while true; do
        read_state
        if [[ "$current_category" != "$last_category" ]]; then
          write_hosts_file
          last_category="$current_category"
        fi
        # Poll fast instead of relying on inotify ordering. The timer updates
        # several files in quick succession, and queued inotify events could
        # briefly apply a stale category after switching to idle/media.
        sleep 0.2
      done
    '';
  };
in
{
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Enable networking.
  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "dnsmasq";

  environment.etc."NetworkManager/dnsmasq.d/social-block.conf".text = ''
    addn-hosts=/run/social-block/hosts
    # Keep category switches effectively immediate; cached social-domain answers
    # were otherwise observable for up to the upstream TTL (~1 minute).
    cache-size=0
    neg-ttl=0
  '';

  systemd.tmpfiles.rules = [
    "d /run/social-block 0755 root root -"
    "f /run/social-block/hosts 0644 root root -"
  ];

  systemd.services.social-media-blocker = {
    description = "Apply category-based social media blocking";
    after = [ "NetworkManager.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${socialMediaBlocker}/bin/social-media-blocker";
      Restart = "always";
      RestartSec = 2;
    };
  };

  # Locale / keyboard.
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
  };
  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };
  console.keyMap = "de";

  users.users.${user} = {
    isNormalUser = true;
    description = user;
    extraGroups = [ "networkmanager" "wheel" "docker" "nordvpn" "kvm" ];
    packages = [ ];
  };
  users.groups.nordvpn = { };

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORMTHEME = "qt6ct";
    QT_STYLE_OVERRIDE = "Fusion";
    XCURSOR_THEME = "Adwaita";
  };

  xdg.mime.defaultApplications = {
    "application/pdf" = [ "org.gnome.Evince.desktop" ];
    "text/html" = [ "helium.desktop" ];
    "application/xhtml+xml" = [ "helium.desktop" ];
    "x-scheme-handler/http" = [ "helium.desktop" ];
    "x-scheme-handler/https" = [ "helium.desktop" ];
    "inode/directory" = [ "org.gnome.Nautilus.desktop" ];
    "image/png" = [ "org.gnome.Loupe.desktop" ];
    "image/jpeg" = [ "org.gnome.Loupe.desktop" ];
    "image/gif" = [ "org.gnome.Loupe.desktop" ];
    "image/webp" = [ "org.gnome.Loupe.desktop" ];
    "image/svg+xml" = [ "org.gnome.Loupe.desktop" ];
    "image/bmp" = [ "org.gnome.Loupe.desktop" ];
    "image/tiff" = [ "org.gnome.Loupe.desktop" ];
    "image/avif" = [ "org.gnome.Loupe.desktop" ];
    "image/heic" = [ "org.gnome.Loupe.desktop" ];
  };

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    TERMINAL = "ghostty";
    BROWSER = "helium-browser";
    ANDROID_HOME = "${homeDirectory}/Android/Sdk";
    ANDROID_SDK_ROOT = "${homeDirectory}/Android/Sdk";
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
    atkinson-hyperlegible-next
    corefonts
  ];

  programs.niri.enable = true;
  programs.nix-ld.enable = true;
  programs.dconf.enable = true;
  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
          gtk-theme = "Adwaita-dark";
          cursor-theme = "Adwaita";
          cursor-size = lib.gvariant.mkInt32 24;
        };
      };
    }
  ];

  virtualisation.docker.enable = true;
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;
  services.fwupd.enable = true;
  security.polkit.enable = true;
  services.udisks2.enable = true;
  services.gvfs.enable = true;
  services.syncthing = {
    enable = true;
    inherit user;
    dataDir = homeDirectory;
    configDir = "${homeDirectory}/.config/syncthing";
    openDefaultPorts = true;
  };
  services.ollama.enable = true;
  services.upower.enable = true;
  services.keyd.enable = true;
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  # Required by NordVPN/NordLynx and Tailscale when the firewall's reverse-path filter is enabled.
  networking.firewall.checkReversePath = "loose";

  systemd.services.nordvpnd = {
    description = "NordVPN daemon";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${nordvpn-cli}/bin/nordvpnd";
      Restart = "on-failure";
      RuntimeDirectory = "nordvpn";
      StateDirectory = "nordvpn";
    };
  };

  services.keyd.keyboards.default.settings = {
    main = {
      capslock = "overload(control, esc)";
    };
  };

  services.greetd = {
    enable = true;
    settings.default_session = {
      user = "greeter";
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd niri-session";
    };
  };

  system.stateVersion = "25.11";
}
