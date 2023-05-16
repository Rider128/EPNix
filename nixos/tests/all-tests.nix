{
  nixpkgs,
  pkgs,
  self,
  system,
}: let
  inherit (pkgs) lib;

  nixosTesting = import (nixpkgs + "/nixos/lib/testing-python.nix") {
    inherit pkgs system;
    extraConfigurations = [
      self.nixosModules.nixos
    ];
  };

  handleTest = path: args: nixosTesting.simpleTest (import path (pkgs // args));
in {
  phoebus-alarm = handleTest ./phoebus/alarm.nix {};
  phoebus-olog = handleTest ./phoebus/olog.nix {};
}