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

  binName = name: "kantan-plugin-${name}";

  sharedSwiftSrc = pkgs.lib.cleanSource (pluginsDir + "/_shared/swift");

  # Compose a plugin source tree that vendors the shared sources into the
  # Swift target's `Sources/<bin>/_shared/` directory so SwiftPM picks them
  # up as part of the executable target.
  composeSwiftSrc =
    name: src:
    pkgs.runCommand "${binName name}-src" { } ''
      cp -r ${src} $out
      chmod -R u+w $out
      mkdir -p $out/Sources/${binName name}/_shared
      cp -r ${sharedSwiftSrc}/. $out/Sources/${binName name}/_shared/
    '';

  buildPlugin =
    {
      name,
      src,
    }:
    let
      dirContents = builtins.readDir (pluginsDir + "/${name}");
      marker = pkgs.lib.findFirst (m: builtins.hasAttr m dirContents) null markers;
      pluginSrc = if marker == "Package.swift" then composeSwiftSrc name src else src;
    in
    if marker == null then
      throw "Plugin '${name}' has none of: ${pkgs.lib.concatStringsSep ", " markers}"
    else
      builders.${marker} {
        inherit name;
        src = pluginSrc;
      };
in
{
  pluginPackages = discover {
    dir = pluginsDir;
    predicate = name: type: type == "directory" && !pkgs.lib.hasPrefix "_" name;
    build =
      name: _:
      buildPlugin {
        inherit name;
        src = pkgs.lib.cleanSource (pluginsDir + "/${name}");
      };
  };
}
