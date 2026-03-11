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

      _kantan = buildSwiftPackage {
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

      buildSwiftPlugin =
        {
          name,
          src,
        }:
        let
          bin = "kantan-plugin-${name}";
          built = buildSwiftPackage {
            pname = bin;
            inherit src;
          };
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = bin;
          version = "0.1.0";
          dontUnpack = true;
          dontFixup = true;
          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin
            cp ${built}/bin/${bin} $out/bin/${bin}

            if [ -d "${src}/examples" ]; then
              mkdir -p $out/share/examples
              cp ${src}/examples/* $out/share/examples/
            fi

            runHook postInstall
          '';
          meta = {
            platforms = [ "aarch64-darwin" ];
          };
        };

      pluginDirs = builtins.readDir ./packages/plugins;
      pluginPackages = builtins.listToAttrs (
        builtins.filter (entry: entry != null) (
          builtins.map (
            dirName:
            if pluginDirs.${dirName} == "directory" then
              {
                name = dirName;
                value = buildSwiftPlugin {
                  name = dirName;
                  src = pkgs.lib.cleanSource ./packages/plugins/${dirName};
                };
              }
            else
              null
          ) (builtins.attrNames pluginDirs)
        )
      );

      kantanWithPlugins =
        {
          plugins ? builtins.attrValues pluginPackages,
          extraPlugins ? [ ],
        }:
        let
          allPlugins = plugins ++ extraPlugins;
        in
        if allPlugins == [ ] then
          _kantan
        else
          pkgs.symlinkJoin {
            name = "kantan-${_kantan.version}";
            paths = [ _kantan ] ++ allPlugins;
            nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
            postBuild = ''
              wrapProgram $out/bin/kantan \
                --prefix PATH : $out/bin
            '';
            meta = _kantan.meta;
          };

      kantan = (kantanWithPlugins { }) // {
        override =
          args:
          kantanWithPlugins (
            {
              plugins = builtins.attrValues pluginPackages;
              extraPlugins = [ ];
            }
            // args
          );
        withoutPlugins = _kantan;
        withPlugins = kantanWithPlugins;
        plugins = pluginPackages;
      };

      allSwiftSourceDirs = [
        "packages/kantan/Sources"
      ]
      ++ builtins.map (name: "packages/plugins/${name}/Sources") (builtins.attrNames pluginPackages);
    in
    {
      packages.${system}.default = kantan;

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
