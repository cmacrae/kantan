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

      # NOTE: We depend on system installed Xcode & Swift until Swift 6 lands
      #       in nixpkgs
      swiftBuildPhase = bin: ''
        runHook preBuild

        export DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
        export SDKROOT=$(/usr/bin/xcrun --show-sdk-path)
        export TOOLCHAINS=default
        export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$DEVELOPER_DIR/usr/bin:/usr/bin:$PATH"
        export HOME="$TMPDIR"

        swift build -c release --disable-sandbox --scratch-path .build

        runHook postBuild
      '';

      swiftInstallPhase = bin: ''
        runHook preInstall
        mkdir -p $out/bin
        cp .build/arm64-apple-macosx/release/${bin} $out/bin/${bin}
        runHook postInstall
      '';

      buildSwiftPackage =
        {
          pname,
          version ? "0.1.0",
          src,
          meta ? { },
        }:
        pkgs.stdenvNoCC.mkDerivation {
          inherit pname version src;

          buildPhase = swiftBuildPhase pname;
          installPhase = swiftInstallPhase pname;
          dontFixup = true;

          meta = {
            platforms = [ "aarch64-darwin" ];
          }
          // meta;
        };

      pluginDirs = builtins.readDir ./packages/plugins;
      pluginPackages = builtins.listToAttrs (
        builtins.filter (entry: entry != null) (
          builtins.map (
            name:
            if pluginDirs.${name} == "directory" then
              {
                inherit name;
                value = buildSwiftPackage {
                  pname = name;
                  src = pkgs.lib.cleanSource ./packages/plugins/${name};
                };
              }
            else
              null
          ) (builtins.attrNames pluginDirs)
        )
      );

      allSwiftSourceDirs = [
        "packages/kantan/Sources"
      ]
      ++ builtins.map (name: "packages/plugins/${name}/Sources") (builtins.attrNames pluginPackages);
    in
    {
      packages.${system}.default = buildSwiftPackage {
        pname = "kantan";
        src = pkgs.lib.cleanSourceWith {
          src = ./packages/kantan;
          filter =
            name: type:
            let
              baseName = baseNameOf (toString name);
            in
            pkgs.lib.cleanSourceFilter name type && baseName != "config.yaml" && baseName != "README.org";
        };
        meta = {
          description = "A beautifully simple status bar for macOS";
          mainProgram = "kantan";
        };
      };

      legacyPackages.${system}.plugins = pluginPackages;

      formatter.${system} = pkgs.writeShellApplication {
        name = "swift-fmt";
        runtimeInputs = [ pkgs.swift-format ];
        text =
          let
            formatCmds = builtins.map (dir: ''
              if [ -d "${dir}" ]; then
                swift-format format --in-place --recursive --parallel "${dir}"
              fi
            '') allSwiftSourceDirs;
          in
          builtins.concatStringsSep "\n" formatCmds;
      };

      devShells.${system}.default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          swift-format
        ];
      };
    };
}
