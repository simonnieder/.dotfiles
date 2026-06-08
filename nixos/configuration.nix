# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, zed-1_3_5, ... }:

let
  zen-browser = (import (builtins.fetchTarball {
    url = "https://github.com/youwen5/zen-browser-flake/archive/90d4d395e2be09b2d314816dadd34660528c4ee4.tar.gz";
    sha256 = "19m3mqdbd865drfwa11ay6dn5v0b0sqq9rjg54vvzcy4mqq4b6c4";
  }) {
    inherit pkgs;
  }).default;
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  # Select internationalisation properties.
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

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };

  # Configure console keymap
  console.keyMap = "de";

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.simonnieder = {
    isNormalUser = true;
    description = "simonnieder";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    packages = with pkgs; [];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    neovim
    typst
    tinymist
    typstyle
    websocat
    wget
    git
    nodejs
    glib
    ntfs3g
    evince
    loupe

    # session / desktop
    niri
    xwayland-satellite
    waybar
    rofi
    nautilus
    dunst
    ghostty
    tmux
    fish
    networkmanager
    networkmanagerapplet
    blueman
    brightnessctl
    pavucontrol
    pamixer
    playerctl
    xdg-utils
    wl-clipboard

    # theming / UI
    matugen
    papirus-icon-theme
    adwaita-icon-theme
    adw-gtk3
    libsForQt5.qt5ct
    qt6Packages.qt6ct
    noto-fonts-color-emoji
    adw-gtk3

    # utilities used by configs/scripts
    grim
    slurp
    satty
    hypridle
    hyprlock
    jq
    ripgrep
    fd
    python3
    clingo
    zip
    unzip
    poppler-utils
    stow
    eza
    fzf
    starship
    lazygit
    diff-so-fancy
    mpv
    syncthing

    # apps referenced in config
    obsidian
    telegram-desktop
    thunderbird
    (pkgs.symlinkJoin {
      name = "spotify";
      paths = [ pkgs.spotify ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/spotify --add-flags "--no-sandbox"
      '';
    })
    protege-distribution
    qbittorrent
    ollama
    zed-1_3_5
    zen-browser
    gh
    lazydocker
    calibre
    anki
    inkscape
    digikam
    localsend
    discord
    warp-terminal
    (pkgs.gnome-power-manager.overrideAttrs (oldAttrs: {
      postInstall = (oldAttrs.postInstall or "") + ''
        substituteInPlace $out/share/applications/org.gnome.PowerStats.desktop \
          --replace "OnlyShowIn=GNOME;Unity;" ""
      '';
    }))
  ];

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORMTHEME = "qt6ct";
    QT_STYLE_OVERRIDE = "Fusion";
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "18";
    HYPRCURSOR_SIZE = "18";
  };

  xdg.mime.defaultApplications = {
    "application/pdf" = [ "org.gnome.Evince.desktop" ];
    "text/html" = [ "zen.desktop" ];
    "application/xhtml+xml" = [ "zen.desktop" ];
    "x-scheme-handler/http" = [ "zen.desktop" ];
    "x-scheme-handler/https" = [ "zen.desktop" ];
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
    BROWSER = "zen-browser";
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
    atkinson-hyperlegible-next
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
          cursor-size = lib.gvariant.mkInt32 18;
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
    user = "simonnieder";
    dataDir = "/home/simonnieder";
    configDir = "/home/simonnieder/.config/syncthing";
    openDefaultPorts = true;
  };
  services.ollama.enable = true;
  services.tlp.enable = true;
  services.upower.enable = true;
  services.keyd.enable = true;

  services.keyd.keyboards.default.settings = {
    main = {
      capslock = "overload(control, esc)";
    };
  };

  services.logind.settings.Login = {
    HandlePowerKey = "ignore";
    HandleLidSwitch = "suspend-then-hibernate";
  };

  # Explicit hibernate delay so systemd uses a timer instead of waiting
  # for the battery to drain (<5%). Without this, suspend-then-hibernate
  # on AC/battery may never hibernate because it relies on ACPI low-battery
  # alarms rather than an RTC wake alarm.
  systemd.sleep.extraConfig = ''
    HibernateDelaySec=45m
  '';

  # Tell the kernel where to resume from hibernation.
  boot.resumeDevice = "/dev/disk/by-uuid/48995cae-2c41-4c73-b12c-16125c0c1c4d";

  services.greetd = {
    enable = true;
    settings.default_session = {
	user = "greeter";
 	command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd niri-session";
    };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?

}
