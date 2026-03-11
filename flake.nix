{
  description = "A beautifully simple status bar for macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system}.default = pkgs.stdenvNoCC.mkDerivation {
        pname = "kantan";
        version = "0.1.0";

        src = pkgs.lib.cleanSourceWith {
          src = ./.;
          filter =
            name: type:
            let
              baseName = baseNameOf (toString name);
            in
            pkgs.lib.cleanSourceFilter name type && baseName != "config.yaml" && baseName != "README.org";
        };

        # NOTE: We depend on system installed XCode & Swift until Swift 6 lands
        #       in nixpkgs
        buildPhase = ''
          runHook preBuild

          export DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
          export SDKROOT=$(/usr/bin/xcrun --show-sdk-path)
          export TOOLCHAINS=default
          export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$DEVELOPER_DIR/usr/bin:/usr/bin:$PATH"
          export HOME="$TMPDIR"

          swift build -c release --disable-sandbox --scratch-path .build

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin
          cp .build/arm64-apple-macosx/release/kantan $out/bin/kantan
          runHook postInstall
        '';

        dontFixup = true;

        meta = {
          description = "A beautifully simple status bar for macOS";
          platforms = [ "aarch64-darwin" ];
          mainProgram = "kantan";
        };
      };

      formatter.${system} = pkgs.writeShellApplication {
        name = "swift-fmt";
        runtimeInputs = [ pkgs.swift-format ];
        text = ''
          swift-format format --in-place --recursive --parallel Sources/
        '';
      };

      devShells.${system}.default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          swift-format
        ];
      };
    };
}
