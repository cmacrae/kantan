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

  hasConfig = cfg.settings != { };
  hasThemes = cfg.themes != { };
  hasExtraArgs = cfg.extraArgs != [ ];

  configFile = yaml.generate "kantan-config.yaml" cfg.settings;

  customThemes = lib.mapAttrsToList (name: value: {
    name = "${name}.yaml";
    path = yaml.generate "kantan-theme-${name}.yaml" value;
  }) cfg.themes;

  themesDir = pkgs.runCommand "kantan-themes" { } ''
    mkdir -p $out
    if [ -d "${cfg.package}/share/themes" ]; then
      cp -rL ${cfg.package}/share/themes/* $out/ 2>/dev/null || true
    fi
    ${lib.concatMapStringsSep "\n" (t: "cp ${t.path} $out/${t.name}") customThemes}
  '';

  package = import ./wrap.nix {
    inherit pkgs lib;
    package = cfg.package;
    addFlags =
      lib.optional hasConfig "--config ${configFile}"
      ++ lib.optional hasThemes "--themes-dir ${themesDir}"
      ++ lib.optional hasExtraArgs (lib.escapeShellArgs cfg.extraArgs);
    pathPackages = cfg.extraPackages;
  };
in
{
  options.programs.kantan =
    import ./options.nix {
      inherit lib yaml defaultPackage;
    }
    // {
      fonts = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Font packages to install for use with kantan.";
      };
    };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ package ];
    fonts.packages = cfg.fonts;

    launchd.user.agents.kantan.serviceConfig = import ./launchd.nix { inherit package; };
  };
}
