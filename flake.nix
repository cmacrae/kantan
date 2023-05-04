{
  description = "A beautifully simple status bar for macOS";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    flake-utils.url = github:numtide/flake-utils;
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in rec {
        devShell = pkgs.mkShell {
          nativeBuildInputs =
            with pkgs.swiftPackages;
            with pkgs.darwin.apple_sdk_11_0.frameworks;
            [
              bintools
              clang
              sourcekit-lsp
              swift
              swiftpm
              swift-docc
              xcbuild
              XCTest

              Cocoa
            ];
        };
      });
}
