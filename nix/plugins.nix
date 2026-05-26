{
  pkgs,
  buildSwiftPlugin,
  buildGoPlugin,
  buildShellPlugin,
  pluginsDir,
  discover,
}:

let
  builders = {
    "Package.swift" = buildSwiftPlugin;
    "go.mod" = buildGoPlugin;
    "main.sh" = buildShellPlugin;
  };

  markers = builtins.attrNames builders;

  buildPlugin =
    {
      name,
      src,
    }:
    let
      dirContents = builtins.readDir (pluginsDir + "/${name}");
      marker = pkgs.lib.findFirst (m: builtins.hasAttr m dirContents) null markers;
    in
    if marker == null then
      throw "Plugin '${name}' has none of: ${pkgs.lib.concatStringsSep ", " markers}"
    else
      builders.${marker} { inherit name src; };
in
{
  pluginPackages = discover {
    dir = pluginsDir;
    predicate = _: type: type == "directory";
    build =
      name: _:
      buildPlugin {
        inherit name;
        src = pkgs.lib.cleanSource (pluginsDir + "/${name}");
      };
  };
}
