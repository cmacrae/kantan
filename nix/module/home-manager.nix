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

  hasExtraArgs = cfg.extraArgs != [ ];

  wrappedPackage = pkgs.symlinkJoin {
    name = "kantan-configured";
    paths = [ cfg.package ];
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    postBuild = ''
      wrapProgram $out/bin/kantan \
        --add-flags "${lib.escapeShellArgs cfg.extraArgs}"
    '';
  };

  package = if hasExtraArgs then wrappedPackage else cfg.package;
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
      config = {
        ProgramArguments = [ "${package}/bin/kantan" ];
        KeepAlive = true;
        RunAtLoad = true;
        ProcessType = "Interactive";
      };
    };
  };
}
