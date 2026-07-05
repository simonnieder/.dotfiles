{
  desktopItemArgs ? {
    categories = [ "Network" ];
    genericName = "VPN Client";
    icon = "nordvpn";
    type = "Application";
  },
  version ? "5.1.0",

  buildGoModule,
  copyDesktopItems,
  e2fsprogs,
  fetchFromGitHub,
  iproute2,
  lib,
  libxslt,
  makeDesktopItem,
  makeWrapper,
  nftables,
  openvpn,
  procps,
  systemdMinimal,
  wireguard-tools,
}:
let
  src = fetchFromGitHub {
    owner = "NordSecurity";
    repo = "nordvpn-linux";
    tag = version;
    hash = "sha256-I0PBv2EBfy8oCtYBIalUwfLESa3Od5yvl/Gj96za+60=";
  };

  patchedOpenvpn = openvpn.overrideAttrs (old: {
    # Apply XOR obfuscation patches to disguise OpenVPN traffic,
    # enabling connectivity on networks that block VPN protocols via DPI.
    patches =
      let
        tunnelblickSrc = fetchFromGitHub {
          owner = "Tunnelblick";
          repo = "Tunnelblick";
          tag = "v6.0beta09";
          hash = "sha256-uLYrBgwX3HkEV06snlIYLsgfhD5lNDVR21D56ygoStY=";
        };

        pathDir = "third_party/sources/openvpn/openvpn-2.6.12/patches";
      in
      (old.patches or [ ])
      ++ (map (fname: "${tunnelblickSrc}/${pathDir}/${fname}") [
        "02-tunnelblick-openvpn_xorpatch-a.diff"
        "03-tunnelblick-openvpn_xorpatch-b.diff"
        "04-tunnelblick-openvpn_xorpatch-c.diff"
        "05-tunnelblick-openvpn_xorpatch-d.diff"
        "06-tunnelblick-openvpn_xorpatch-e.diff"
      ]);
  });
in
buildGoModule (finalAttrs: {
  inherit src version;

  pname = "nordvpn-cli";

  nativeBuildInputs = [
    copyDesktopItems
    makeWrapper
  ];

  vendorHash = "sha256-nGKIY95R9nfE0IBC8htz+2src3tqLnNLoRXcT/CgEqM=";

  preBuild = ''
    substituteInPlace internal/constants.go \
      --replace-fail "/usr/lib/nordvpn" "$out/bin"

    old_ovpn_path='filepath.Join(internal.AppDataPathStatic, "openvpn")'
    new_ovpn_path='"${patchedOpenvpn}/bin/openvpn"'
    substituteInPlace daemon/vpn/openvpn/config.go \
      --replace-fail "$old_ovpn_path" "$new_ovpn_path"
  '';

  ldflags = [
    "-X main.Environment=prod"
    "-X main.Version=${finalAttrs.version}"
  ];

  subPackages = [
    "cmd/cli"
    "cmd/daemon"
    "cmd/norduser"
  ];

  checkPhase = ''
    runHook preCheck
    go test ./cli
    go test ./daemon -skip 'TestTransports|TestH1Transport_RoundTrip|Test.*FileList_RealURL'
    go test ./norduser
    runHook postCheck
  '';

  postInstall = ''
    BIN_DIR=$out/bin
    mv $BIN_DIR/cli $BIN_DIR/nordvpn
    mv $BIN_DIR/daemon $BIN_DIR/nordvpnd
    mv $BIN_DIR/norduser $BIN_DIR/norduserd

    ICONS_PATH=$out/share/icons/hicolor/scalable/apps
    install -d $ICONS_PATH
    install --mode=0444 assets/icon.svg $ICONS_PATH/nordvpn.svg
    for file in assets/tray-*.svg; do
      install --mode=0444 "$file" "$ICONS_PATH/nordvpn-$(basename $file)"
    done
  '';

  postFixup = ''
    wrapProgram $out/bin/nordvpnd --prefix PATH : ${
      lib.makeBinPath [
        e2fsprogs
        iproute2
        libxslt
        nftables
        patchedOpenvpn
        procps
        systemdMinimal
        wireguard-tools
      ]
    }
  '';

  desktopItems = [
    (makeDesktopItem (desktopItemArgs // {
      comment = "Handles NordVPN OAuth browser login callbacks.";
      desktopName = "NordVPN CLI";
      exec = "nordvpn click %u";
      mimeTypes = [ "x-scheme-handler/nordvpn" ];
      name = "nordvpn";
      noDisplay = true;
      terminal = true;
    }))
  ];

  meta = {
    description = "NordVPN command-line client and daemon";
    homepage = "https://github.com/NordSecurity/nordvpn-linux";
    changelog = "https://github.com/NordSecurity/nordvpn-linux/releases/tag/${version}";
    license = lib.licenses.gpl3Only;
    mainProgram = "nordvpn";
    platforms = lib.platforms.linux;
  };
})
