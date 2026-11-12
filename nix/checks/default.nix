{
  self,
  pkgs,
  version,
  swift,
  docs,
  site,
  pluginPackages,
  themePackages,
  tabler-icons,
  treefmtEval,
  _kantan,
  kantan,
  release,
  homebrew,
}:
let
  inherit (pkgs) lib;

  mkModuleCheck =
    {
      name,
      module,
      stubModule,
      extract,
    }:
    let
      eval = lib.evalModules {
        specialArgs = { inherit pkgs; };
        modules = [
          module
          stubModule
          {
            programs.kantan.enable = true;
            programs.kantan.settings.dummy = "value";
          }
        ];
      };
    in
    pkgs.writeText "kantan-${name}-module-eval" (extract eval.config);

  darwinStubs =
    { lib, ... }:
    {
      options = {
        environment.systemPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
        };
        fonts.packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
        };
        launchd.user.agents = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
      };
    };

  homeManagerStubs =
    { lib, ... }:
    {
      options = {
        home.packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
        };
        xdg.configFile = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
        launchd.agents = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
      };
    };

  prefixAttrs = prefix: attrs: lib.mapAttrs' (n: v: lib.nameValuePair "${prefix}-${n}" v) attrs;
in
{
  formatting = treefmtEval.config.build.check self;
  kantan = _kantan;
  kantan-tests = (swift.withSwiftTests _kantan).overrideAttrs { pname = "kantan-tests"; };
  kantan-with-plugins = kantan;
  inherit tabler-icons;
  release = release.full;
  release-core = release.core;
  release-smoke = pkgs.runCommand "kantan-release-smoke" { } ''
    tar -xzf ${release.full}
    test "$(bin/kantan --version)" = "kantan ${version.release}"
    for plugin in bin/kantan-plugin-*; do test -x "$plugin"; done
    touch $out
  '';
  docs = docs.package;
  site = site.package;
  homebrew-formula = homebrew.kantan;
  module-darwin = mkModuleCheck {
    name = "darwin";
    module = import ../module/darwin.nix kantan;
    stubModule = darwinStubs;
    extract = cfg: builtins.head cfg.launchd.user.agents.kantan.serviceConfig.ProgramArguments;
  };
  module-home-manager = mkModuleCheck {
    name = "home-manager";
    module = import ../module/home-manager.nix kantan;
    stubModule = homeManagerStubs;
    extract = cfg: builtins.head cfg.launchd.agents.kantan.config.ProgramArguments;
  };
}
// prefixAttrs "plugin" pluginPackages
// prefixAttrs "theme" themePackages
