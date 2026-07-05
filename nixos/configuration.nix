# Legacy entry point; flake builds use hosts/<hostname>/default.nix directly.
{ ... }:

{
  _module.args = {
    user = "simonnieder";
    homeDirectory = "/home/simonnieder";
    hostName = "nixos";
  };

  imports = [ ./hosts/nixos ];
}
