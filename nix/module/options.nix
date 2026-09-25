{
  lib,
  yaml,
  defaultPackage,
}:
{
  enable = lib.mkEnableOption "kantan status bar";

  package = lib.mkOption {
    type = lib.types.package;
    default = defaultPackage;
    description = "Package to install.";
  };

  settings = lib.mkOption {
    type = yaml.type;
    default = { };
    description = "Configuration for kantan, written as config.yaml.";
  };

  themes = lib.mkOption {
    type = lib.types.attrsOf yaml.type;
    default = { };
    description = ''
      Custom themes. Each attribute becomes a YAML file in the themes directory.
      For example, `themes.mytheme = { ... }` produces `mytheme.yaml`.
    '';
  };

  extraArgs = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Extra command-line arguments to pass to kantan.";
  };

  extraPackages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    description = ''
      Extra packages to add to kantan's PATH at runtime.
      Useful for tools that kantan modules shell out to, such as the
      commands run by `command` modules.
    '';
  };
}
