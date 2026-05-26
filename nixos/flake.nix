{
  description = "Simon's NixOS config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      zed-1_3_5 = pkgs.stdenv.mkDerivation rec {
        pname = "zed";
        version = "1.3.5";

        src = pkgs.fetchurl {
          url = "https://github.com/zed-industries/zed/releases/download/v${version}/zed-linux-x86_64.tar.gz";
          hash = "sha256-l4anY9AwG3Q/XxVXHcyWMwOMp8SpovFj9Ihpbubkz6Y=";
        };

        nativeBuildInputs = [ pkgs.autoPatchelfHook ];

        buildInputs = with pkgs; [
          alsa-lib
          fontconfig
          freetype
          glib
          libGL
          libxkbcommon
          nspr
          nss
          stdenv.cc.cc.lib
          vulkan-loader
          wayland
          xorg.libX11
          xorg.libXcursor
          xorg.libXi
          xorg.libXrandr
          xorg.libXext
          xorg.libxcb
        ];

        sourceRoot = ".";

        installPhase = ''
          runHook preInstall

          mkdir -p $out/opt $out/bin $out/share
          cp -r zed.app $out/opt/

          cat > $out/bin/zed <<EOF
          #!${pkgs.runtimeShell}
          export ZED_UPDATE_EXPLANATION="Zed has been installed using Nix. Auto-updates have thus been disabled."
          export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [
            pkgs.wayland
            pkgs.libGL
            pkgs.vulkan-loader
            pkgs.xorg.libX11
            pkgs.xorg.libXcursor
            pkgs.xorg.libXi
            pkgs.xorg.libXrandr
            pkgs.xorg.libXext
            pkgs.xorg.libxcb
            pkgs.libxkbcommon
            pkgs.glib
            pkgs.nss
            pkgs.nspr
            pkgs.alsa-lib
            pkgs.stdenv.cc.cc.lib
          ]}:$LD_LIBRARY_PATH"
          exec "$out/opt/zed.app/bin/zed" "$@"
          EOF
          chmod +x $out/bin/zed

          if [ -d $out/opt/zed.app/share/icons ]; then
            ln -s $out/opt/zed.app/share/icons $out/share/icons
          fi

          if [ -d $out/opt/zed.app/share/applications ]; then
            mkdir -p $out/share/applications
            cp -r $out/opt/zed.app/share/applications/* $out/share/applications/
            substituteInPlace $out/share/applications/*.desktop \
              --replace-fail "Exec=zed" "Exec=$out/bin/zed" \
              --replace-fail "Icon=zed" "Icon=$out/opt/zed.app/share/icons/hicolor/512x512/apps/zed.png"
          fi

          runHook postInstall
        '';
      };
    in {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit zed-1_3_5;
        };
        modules = [
          ./configuration.nix
          home-manager.nixosModules.home-manager
          ({ ... }: {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "hm-backup";
              users.simonnieder = import ./home.nix;
            };
          })
        ];
      };
    };
}
