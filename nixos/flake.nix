{
  description = "Simon's NixOS config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    hex = {
      url = "github:anomalyco/hex";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    hokum = {
      url = "github:anomalyco/hokum/4f620ff7c41e04baf2c8653960b58d8af9d40611";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
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
