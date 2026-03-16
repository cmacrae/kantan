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

  wrappedPackage = pkgs.symlinkJoin {
    name = "kantan-configured";
    paths = [ cfg.package ];
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    postBuild = ''
      wrapProgram $out/bin/kantan \
        ${lib.optionalString hasConfig ''--add-flags "--config ${configFile}"''} \
        ${lib.optionalString hasThemes ''--add-flags "--themes-dir ${themesDir}"''} \
        ${lib.optionalString hasExtraArgs ''--add-flags "${lib.escapeShellArgs cfg.extraArgs}"''}
    '';
  };

  needsWrapping = hasConfig || hasThemes || hasExtraArgs;
  package = if needsWrapping then wrappedPackage else cfg.package;
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

    launchd.user.agents.kantan = {
      serviceConfig = {
        ProgramArguments = [ "${package}/bin/kantan" ];
        KeepAlive = true;
        RunAtLoad = true;
        ProcessType = "Interactive";
      };
    };
  };
}
