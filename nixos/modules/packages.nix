{ pkgs, ... }:

let
  zen-browser = (import (builtins.fetchTarball {
    url = "https://github.com/youwen5/zen-browser-flake/archive/90d4d395e2be09b2d314816dadd34660528c4ee4.tar.gz";
    sha256 = "19m3mqdbd865drfwa11ay6dn5v0b0sqq9rjg54vvzcy4mqq4b6c4";
  }) {
    inherit pkgs;
  }).default;

  nordvpn-cli = pkgs.callPackage ../pkgs/nordvpn-cli.nix { };

  helium-browser = pkgs.appimageTools.wrapType2 rec {
    pname = "helium-browser";
    version = "0.13.3.1";

    src = pkgs.fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64.AppImage";
      sha256 = "0kf3wq9w0jfm45v612zy06b2lliin8vdfkcdqg17iy4mingr4bs5";
    };

    appimageContents = pkgs.appimageTools.extract { inherit pname version src; };

    extraInstallCommands = ''
      mkdir -p $out/share/applications $out/share/icons/hicolor/256x256/apps

      # Chromium/Electron keeps its own DNS host cache (~1 minute), which made
      # time-tracker DNS category switches feel delayed even though system DNS
      # changed immediately. Disable the browser cache/prefetch path so it
      # re-queries NetworkManager/dnsmasq on each navigation.
      helium_wrapped="$(readlink -f $out/bin/${pname})"
      rm $out/bin/${pname}
      cat > $out/bin/${pname} <<EOF
      #!${pkgs.runtimeShell}
      exec "$helium_wrapped" \\
        --host-cache-size=0 \\
        --dns-prefetch-disable \\
        --disable-async-dns \\
        --disable-features=AsyncDns \\
        "\$@"
      EOF
      chmod +x $out/bin/${pname}

      # Make both the upstream name and our package name launch the wrapper.
      ln -s $out/bin/${pname} $out/bin/helium

      # AppImage desktop integration is not installed by wrapType2 by default,
      # so rofi drun cannot see Helium unless we install it ourselves.
      cp ${appimageContents}/helium.desktop $out/share/applications/helium.desktop
      ${pkgs.perl}/bin/perl -0pi -e 's/^Exec=helium(?!-browser)(.*)$/Exec=helium-browser --host-cache-size=0 --dns-prefetch-disable --disable-async-dns --disable-features=AsyncDns$1/mg' \
        $out/share/applications/helium.desktop

      cp ${appimageContents}/helium.png $out/share/icons/hicolor/256x256/apps/helium.png
    '';
  };

  spotify = pkgs.symlinkJoin {
    name = "spotify";
    paths = [ pkgs.spotify ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/spotify --add-flags "--no-sandbox"
    '';
  };

  android-studio = pkgs.symlinkJoin {
    name = "android-studio";
    paths = [ pkgs.android-studio ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/android-studio \
        --set-default DISPLAY :0 \
        --set-default QT_QPA_PLATFORM xcb
    '';
  };

  gnome-power-manager = pkgs.gnome-power-manager.overrideAttrs (oldAttrs: {
    postInstall = (oldAttrs.postInstall or "") + ''
      substituteInPlace $out/share/applications/org.gnome.PowerStats.desktop \
        --replace "OnlyShowIn=GNOME;Unity;" ""
    '';
  });
in
{
  # Shared package set: every host imports this module unchanged.
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    neovim
    typst
    typstyle
    websocat
    wget
    git
    nodejs
    tree-sitter
    gcc
    glib
    ntfs3g
    evince
    pdfpc
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
    networkmanager-openvpn
    blueman
    brightnessctl
    pavucontrol
    pamixer
    playerctl
    xdg-utils
    wl-clipboard
    cliphist
    rofimoji
    voxtype-onnx

    # theming / UI
    matugen
    papirus-icon-theme
    adwaita-icon-theme
    adw-gtk3
    libsForQt5.qt5ct
    qt6Packages.qt6ct
    noto-fonts-color-emoji

    # utilities used by configs/scripts
    grim
    slurp
    satty
    hypridle
    hyprlock
    wlsunset
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
    yt-dlp
    syncthing
    timewarrior
    nordvpn-cli

    # apps referenced in config
    obsidian
    zotero
    telegram-desktop
    thunderbird
    spotify
    protege-distribution
    qbittorrent
    ollama
    zed-editor
    zen-browser
    helium-browser
    chromium
    gh
    lazydocker
    android-studio
    android-tools
    calibre
    anki
    inkscape
    digikam
    localsend
    discord
    warp-terminal
    gnome-power-manager
  ];
}
