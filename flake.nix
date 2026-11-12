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
        inherit pkgs docs;
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

      treefmtEval = treefmt.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.swift-format.enable = true;
        programs.gofmt.enable = true;
        programs.shfmt.enable = true;
      };

      mkKantan =
        kantanVersion:
        buildSwiftPackage {
          pname = "kantan";
          version = kantanVersion;
          src = ./packages/kantan;
          preBuild = ''
            printf 'let kantanVersion = "%s"\n' '${kantanVersion}' > Sources/kantan/Version.swift
          '';
          meta = {
            description = "A beautifully simple status bar for macOS";
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
      };
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
      };

      apps.${system} = {
        docs = docs.app;
        site = site.app;
        generate-homebrew-formulae = homebrew.generateApp;
      };

      darwinModules.default = import ./nix/module/darwin.nix kantan;
      homeManagerModules.default = import ./nix/module/home-manager.nix kantan;

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
          treefmtEval
          _kantan
          kantan
          release
          homebrew
          ;
      };
    };
}
