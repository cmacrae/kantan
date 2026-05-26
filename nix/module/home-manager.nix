defaultPackage:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.kantan;
  yaml = pkgs.formats.yaml { };

  package = import ./wrap.nix {
    inherit pkgs lib;
    package = cfg.package;
    addFlags = lib.optional (cfg.extraArgs != [ ]) (lib.escapeShellArgs cfg.extraArgs);
    pathPackages = cfg.extraPackages;
  };
in
{
  options.programs.kantan = import ./options.nix {
    inherit lib yaml defaultPackage;
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ package ];

    xdg.configFile = lib.mkMerge [
      (lib.mkIf (cfg.settings != { }) {
        "kantan/config.yaml".source = yaml.generate "kantan-config.yaml" cfg.settings;
      })
      (lib.mapAttrs' (
        name: value:
        lib.nameValuePair "kantan/themes/${name}.yaml" {
          source = yaml.generate "kantan-theme-${name}.yaml" value;
        }
      ) cfg.themes)
    ];

    launchd.agents.kantan = {
      enable = true;
      config = import ./launchd.nix { inherit package; };
    };
  };
}
