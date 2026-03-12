{
  pkgs,
  buildSwiftPlugin,
  buildGoPlugin,
  buildShellPlugin,
  pluginsDir,
}:

let
  buildPlugin =
    {
      name,
      src,
    }:
    let
      dirContents = builtins.readDir (pluginsDir + "/${name}");
    in
    if dirContents ? "Package.swift" then
      buildSwiftPlugin { inherit name src; }
    else if dirContents ? "go.mod" then
      buildGoPlugin { inherit name src; }
    else if dirContents ? "main.sh" then
      buildShellPlugin { inherit name src; }
    else
      throw "Plugin '${name}' has no Package.swift, go.mod, or main.sh";

  pluginDirs = builtins.readDir pluginsDir;
in
{
  pluginPackages = builtins.listToAttrs (
    builtins.filter (entry: entry != null) (
      builtins.map (
        dirName:
        if pluginDirs.${dirName} == "directory" then
          {
            name = dirName;
            value = buildPlugin {
              name = dirName;
              src = pkgs.lib.cleanSource (pluginsDir + "/${dirName}");
            };
          }
        else
          null
      ) (builtins.attrNames pluginDirs)
    )
  );
}
