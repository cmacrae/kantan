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
  hasExtraPackages = cfg.extraPackages != [ ];

  wrappedPackage = pkgs.symlinkJoin {
    name = "kantan-configured";
    paths = [ cfg.package ];
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    postBuild = ''
      wrapProgram $out/bin/kantan \
        ${lib.optionalString hasExtraArgs ''--add-flags "${lib.escapeShellArgs cfg.extraArgs}"''} \
        ${lib.optionalString hasExtraPackages "--prefix PATH : ${lib.makeBinPath cfg.extraPackages}"}
    '';
  };

  needsWrapping = hasExtraArgs || hasExtraPackages;
  package = if needsWrapping then wrappedPackage else cfg.package;
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
