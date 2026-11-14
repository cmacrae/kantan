{
  description = "A beautifully simple status bar for macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt.url = "github:numtide/treefmt-nix";
    treefmt.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt,
      ...
    }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};

      version = import ./nix/version.nix { inherit self; };
      plugin = import ./nix/plugin.nix { version = version.release; };
      go = import ./nix/go.nix { inherit pkgs plugin; };
      swift = import ./nix/swift.nix { inherit pkgs plugin; };
      shell = import ./nix/shell.nix { inherit pkgs plugin; };
      discover = import ./nix/discover.nix { inherit (pkgs) lib; };
      docs = import ./nix/docs.nix {
        inherit pkgs;
        pluginsDir = ./packages/plugins;
        version = version.release;
      };
      site = import ./nix/site.nix {
        inherit pkgs docs buildSwiftPackage;
        version = version.release;
      };

      plugins = import ./nix/plugins.nix {
        inherit pkgs discover;
        inherit (go) buildGoPlugin;
        inherit (swift) buildSwiftPlugin;
        inherit (shell) buildShellPlugin;
        pluginsDir = ./packages/plugins;
      };

      themes = import ./nix/themes.nix {
        inherit pkgs discover;
        themesDir = ./packages/themes;
      };

      inherit (swift) buildSwiftPackage;
      inherit (plugins) pluginPackages;
      inherit (themes) themePackages;

      tabler-icons = pkgs.callPackage ./packages/tabler-icons { };

      commits = import ./nix/commits.nix {
        inherit pkgs;
        cogConfig = ./cog.toml;
      };

      treefmtEval = treefmt.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.swift-format.enable = true;
        programs.gofmt.enable = true;
        programs.shfmt.enable = true;
        programs.actionlint.enable = true;
      };

      mkKantan =
        kantanVersion:
        buildSwiftPackage {
          pname = "kantan";
          version = kantanVersion;
          src = ./packages/kantan;
          swiftpmDeps = pkgs.fetchSwiftPMDeps {
            src = ./packages/kantan;
            hash = "sha256-jtRNPJ+2f7agoEUgHT+d0AAh+EWXf5NKmyQq7UEgaDs=";
          };
          preBuild = ''
            printf 'let kantanVersion = "%s"\n' '${kantanVersion}' > Sources/kantan/Version.swift
          '';
          postInstall = ''
            install -D -m 644 ${./LICENSE} $out/share/doc/kantan/LICENSE
            install -D -m 644 ${./THIRD_PARTY_NOTICES} $out/share/doc/kantan/THIRD_PARTY_NOTICES
            mkdir -p $out/share/examples
            cp -r --no-preserve=mode ${./examples} $out/share/examples/reference
          '';
          meta = {
            description = "A beautifully simple status bar for macOS";
            license = pkgs.lib.licenses.mit;
            mainProgram = "kantan";
          };
        };

      _kantan = mkKantan version.build;

      kantanWithPlugins =
        {
          plugins ? builtins.attrValues pluginPackages,
          extraPlugins ? [ ],
          themes ? builtins.attrValues themePackages,
        }:
        let
          allPlugins = plugins ++ extraPlugins;
          allPaths = [
            _kantan
            tabler-icons
          ]
          ++ allPlugins
          ++ themes;
        in
        pkgs.symlinkJoin {
          name = "kantan-${_kantan.version}";
          paths = allPaths;
          nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
          postBuild = ''
            wrapProgram $out/bin/kantan \
              --prefix PATH : $out/bin
          '';
          inherit (_kantan) meta;
        };

      kantan = (kantanWithPlugins { }) // {
        override = args: kantanWithPlugins args;
        withoutPlugins = _kantan;
        withPlugins = kantanWithPlugins;
        plugins = pluginPackages;
        themes = themePackages;
      };

      release = import ./nix/release.nix {
        inherit pkgs tabler-icons;
        version = version.release;
        kantanBin = mkKantan version.release;
        plugins = builtins.attrValues pluginPackages;
        themes = builtins.attrValues themePackages;
      };

      homebrew = import ./nix/homebrew.nix {
        inherit pkgs;
        version = version.release;
        tarballs = release;
        releaseUrl = "https://github.com/cmacrae/kantan/releases/download/v${version.release}";
      };

      releaseAssets = pkgs.runCommand "kantan-release-assets-${version.release}" { } ''
        mkdir $out
        cd $out
        cp ${release.full} ${release.full.name}
        cp ${release.core} ${release.core.name}
        cp ${homebrew.bottles}/* .
        sha256sum * > SHA256SUMS
      '';
    in
    {
      packages.${system} = {
        inherit kantan;
        default = kantan;
        docs = docs.package;
        site = site.package;
        without-plugins = kantanWithPlugins { plugins = [ ]; };
        release = release.full;
        release-without-plugins = release.core;
        homebrew-formula = homebrew.kantan;
        homebrew-formula-without-plugins = homebrew.kantan-without-plugins;
        homebrew-tap = homebrew.tap;
        homebrew-bottles = homebrew.bottles;
        release-assets = releaseAssets;
      };

      apps.${system} = {
        docs = docs.app;
        site = site.app;
        render-site-images = site.renderImagesApp;
        assemble-site = site.assembleApp;
        generate-homebrew-formulae = homebrew.generateApp;
        check-commits = commits.app;
      };

      darwinModules.default = import ./nix/module/darwin.nix kantan;
      homeManagerModules.default = import ./nix/module/home-manager.nix kantan;

      devShells.${system}.default = pkgs.mkShell.override { inherit (swift.shell) stdenv; } {
        packages = swift.shell.packages ++ [
          pkgs.cocogitto
          pkgs.gh
          pkgs.gh-actions-lock
          pkgs.go
          pkgs.zizmor
        ];
        inherit (swift.shell) buildInputs;
        shellHook = ''
          if hook=$(git rev-parse --git-path hooks/pre-push 2>/dev/null); then
            if [ ! -e "$hook" ] || grep -q '^# kantan: ' "$hook" \
              || { grep -q 'git lfs pre-push' "$hook" && [ "$(wc -l < "$hook")" -le 3 ]; }; then
              if ! cmp -s ${commits.prePushHook} "$hook"; then
                install -m 755 ${commits.prePushHook} "$hook"
              fi
            else
              echo "kantan: $hook isn't kantan's, so commits aren't checked before pushing. cog install-hook --overwrite pre-push replaces it." >&2
            fi
          fi
        '';
      };

      formatter.${system} = treefmtEval.config.build.wrapper;
      checks.${system} = import ./nix/checks {
        inherit
          self
          pkgs
          version
          swift
          docs
          site
          pluginPackages
          themePackages
          tabler-icons
          commits
          treefmtEval
          _kantan
          kantan
          release
          homebrew
          releaseAssets
          ;
      };
    };
}
