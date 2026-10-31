{ lib, pkgs }:

let
  version = "26.1007.21434";
  upstream = pkgs.fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${version}_amd64.deb";
    hash = "sha256-J2tTQcPXSyYdOtUhBvf6ft3gaEHkdn/ipAy1QJmx8+0=";
  };
  # Keep OpenAI's app and bundled helpers intact. Supply their Linux runtime
  # through an FHS environment instead of patching the app's JavaScript or ELF.
  payload = pkgs.stdenvNoCC.mkDerivation {
    pname = "chatgpt-official-payload";
    inherit version;
    src = upstream;
    nativeBuildInputs = [ pkgs.dpkg ];
    dontUnpack = true;
    dontBuild = true;
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      dpkg-deb -x "$src" extracted
      mkdir -p "$out"
      cp -a extracted/usr/lib extracted/usr/share "$out/"
      runHook postInstall
    '';
  };
in
pkgs.buildFHSEnv {
  pname = "chatgpt";
  inherit version;
  targetPkgs = p: with p; [
    payload
    alsa-lib atk at-spi2-atk at-spi2-core cairo cups dbus expat
    fontconfig gdk-pixbuf glib gtk3 libdrm libgbm libglvnd libnotify
    libusb1 libxkbcommon mesa nspr nss openssl pango pipewire
    stdenv.cc.cc.lib systemd tpm2-tss wayland xz zlib zstd
    libX11 libXcomposite libXcursor libXdamage libXext libXfixes
    libXi libXrandr libXScrnSaver libXtst libxcb libxcrypt-legacy
    bash bubblewrap coreutils curl findutils git gnugrep gnused
    procps xdg-utils
  ];
  multiPkgs = _: [ ];
  # On niri, the native Wayland backend gives the non-resizable pet overlay
  # oversized bounds and ignores compositor resize requests. Use XWayland.
  runScript = "/usr/lib/chatgpt/ChatGPT --ozone-platform=x11";
  extraInstallCommands = ''
    mkdir -p "$out/share/applications"
    cp ${payload}/share/applications/chatgpt.desktop "$out/share/applications/"
    substituteInPlace "$out/share/applications/chatgpt.desktop" \
      --replace-fail "Exec=chatgpt %U" "Exec=$out/bin/chatgpt %U" \
      --replace-fail "x-scheme-handler/http;x-scheme-handler/https;" ""
    mkdir -p "$out/share/pixmaps"
    cp ${payload}/share/pixmaps/chatgpt.png "$out/share/pixmaps/"
  '';
  passthru = { inherit payload upstream; };
  meta = {
    description = "Official ChatGPT desktop app by OpenAI";
    homepage = "https://learn.chatgpt.com/docs/linux/linux-app";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "chatgpt";
  };
}
