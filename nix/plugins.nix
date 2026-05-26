{
  pkgs,
  buildSwiftPlugin,
  buildGoPlugin,
  buildShellPlugin,
  pluginsDir,
  discover,
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
