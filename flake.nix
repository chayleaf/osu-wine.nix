{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    {
      overlays.default = final: prev: {
        osu-wine = final.callPackage ./. { };
      };
      checks.x86_64-linux = {
        inherit (self.packages.x86_64-linux) osu-wine;
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        formatter = pkgs.nixpkgs-fmt;
        packages = rec {
          osu-wine = pkgs.callPackage ./. { };
          default = osu-wine;
        };
      }
    );
}
