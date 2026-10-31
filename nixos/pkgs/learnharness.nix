{ lib, symlinkJoin, writeShellScriptBin, makeDesktopItem, electron
, repository ? "/home/simonnieder/repos/learnharness"
}:

let
  launcher = writeShellScriptBin "learnharness" ''
    cd ${lib.escapeShellArg repository}
    exec ${electron}/bin/electron . "$@"
  '';
  desktop = makeDesktopItem {
    name = "learnharness";
    desktopName = "LearnHarness";
    comment = "LearnHarness from your local fork";
    exec = "learnharness %U";
    icon = "${repository}/build/icon.png";
    categories = [ "Education" ];
    startupWMClass = "learnharness";
  };
in
symlinkJoin {
  name = "learnharness-fork";
  paths = [ launcher desktop ];
  meta = {
    description = "Desktop launcher for the local LearnHarness fork";
    homepage = "https://github.com/simonnieder/learnharness";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "learnharness";
  };
}
