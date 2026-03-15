{
  pkgs,
  themesDir,
}:

let
  entries = builtins.readDir themesDir;

  isThemeEntry =
    name: type: (type == "regular" && pkgs.lib.hasSuffix ".yaml" name) || type == "directory";

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
  themePackages = builtins.listToAttrs (
    builtins.filter (entry: entry != null) (
      builtins.map (
        entryName:
        let
          type = entries.${entryName};
        in
        if isThemeEntry entryName type then
          {
            name = themeName entryName type;
            value = buildTheme entryName type;
          }
        else
          null
      ) (builtins.attrNames entries)
    )
  );
}
