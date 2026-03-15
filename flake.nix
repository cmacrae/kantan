{
  description = "A beautifully simple status bar for macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt.url = "github:numtide/treefmt-nix";
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

      go = import ./nix/go.nix { inherit pkgs; };
      swift = import ./nix/swift.nix { inherit pkgs; };
      shell = import ./nix/shell.nix { inherit pkgs; };

      plugins = import ./nix/plugins.nix {
        inherit pkgs;
        inherit (go) buildGoPlugin;
        inherit (swift) buildSwiftPlugin;
        inherit (shell) buildShellPlugin;
        pluginsDir = ./packages/plugins;
      };

      themes = import ./nix/themes.nix {
        inherit pkgs;
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

      _kantan = buildSwiftPackage {
        pname = "kantan";
        src = pkgs.lib.cleanSourceWith {
          src = ./packages/kantan;
          filter =
            name: type:
            let
              baseName = baseNameOf (toString name);
            in
            pkgs.lib.cleanSourceFilter name type && baseName != "README.org" && baseName != "examples";
        };
        meta = {
          description = "A beautifully simple status bar for macOS";
          mainProgram = "kantan";
        };
      };

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
        if allPlugins == [ ] && themes == [ ] then
          _kantan
        else
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
        themes = themePackages;
      };

    in
    {
      packages.${system}.default = kantan;
      formatter.${system} = treefmtEval.config.build.wrapper;
      checks.${system}.formatting = treefmtEval.config.build.check self;
    };
}
