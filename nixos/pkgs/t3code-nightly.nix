{
  appimageTools,
  fetchurl,
  lib,
}:

let
  pname = "t3code";
  version = "0.0.29-nightly.20260712.791";

  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
    hash = "sha256-TbNmiQnmQX7kqthSuqSKxryBTiW2nFvDOlqjVcDLw8I=";
  };

  appimageContents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    desktopFile="$(find ${appimageContents} -maxdepth 1 -name '*.desktop' -print -quit)"
    iconFile="$(find ${appimageContents} -maxdepth 1 -name '*.png' -print -quit)"

    install -Dm444 "$desktopFile" "$out/share/applications/t3code.desktop"
    install -Dm444 "$iconFile" "$out/share/icons/t3code.png"

    sed -i \
      -e 's|^Exec=.*|Exec=t3code %U|' \
      -e 's|^Icon=.*|Icon=t3code|' \
      "$out/share/applications/t3code.desktop"
  '';

  meta = {
    description = "Nightly build of the minimal GUI for coding agents";
    homepage = "https://t3.codes";
    license = lib.licenses.mit;
    mainProgram = "t3code";
    platforms = [ "x86_64-linux" ];
  };
}
