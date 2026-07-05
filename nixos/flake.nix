{
  description = "Simon's NixOS config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    codex-desktop-linux = {
      url = "path:/home/simonnieder/repos/codex-desktop-linux";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, codex-desktop-linux, ... }@inputs:
    let
      user = "simonnieder";
      homeDirectory = "/home/${user}";

      mkHost = { hostName, system ? "x86_64-linux" }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs user homeDirectory hostName;
          };
          modules = [
            (./hosts + "/${hostName}")
            home-manager.nixosModules.home-manager
            ({ ... }: {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "hm-backup";
                extraSpecialArgs = {
                  inherit inputs user homeDirectory hostName;
                };
                users.${user} = import ./home.nix;
              };
            })
          ];
        };
    in {
      nixosConfigurations = {
        nixos = mkHost { hostName = "nixos"; };
        # Add another PC by creating hosts/<name>/default.nix and uncommenting:
        # desktop = mkHost { hostName = "desktop"; };
      };
    };
}
