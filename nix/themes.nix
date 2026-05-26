{
  pkgs,
  themesDir,
  discover,
}:

let
  themeName =
    name: type: if type == "regular" then builtins.replaceStrings [ ".yaml" ] [ "" ] name else name;

  buildTheme =
    name: type:
    pkgs.runCommand "kantan-theme-${themeName name type}" { } (
      ''
        mkdir -p $out/share/themes
      ''
      + (
        if type == "directory" then
          ''
            cp -r ${themesDir}/${name} $out/share/themes/${name}
          ''
        else
          ''
            cp ${themesDir}/${name} $out/share/themes/${name}
          ''
      )
    );
in
{
  themePackages = discover {
    dir = themesDir;
    predicate =
      name: type: (type == "regular" && pkgs.lib.hasSuffix ".yaml" name) || type == "directory";
    name = themeName;
    build = buildTheme;
  };
}
