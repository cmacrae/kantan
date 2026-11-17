{
  pkgs,
  buildSwiftPlugin,
  buildGoPlugin,
  buildShellPlugin,
  pluginsDir,
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

  # The file marking how the plugin `name` is built.
  markerOf =
    name:
    let
      marker = pkgs.lib.findFirst (
        m: builtins.hasAttr m (builtins.readDir (pluginsDir + "/${name}"))
      ) null markers;
    in
    if marker == null then
      throw "Plugin '${name}' has none of: ${pkgs.lib.concatStringsSep ", " markers}"
    else
      marker;

  # The plugin `name`'s own sources: its directory, less the generator of
  # its preview.
  sourceOf =
    name:
    pkgs.lib.cleanSourceWith {
      src = pluginsDir + "/${name}";
      filter =
        path: type:
        path != toString (pluginsDir + "/${name}/preview") && pkgs.lib.cleanSourceFilter path type;
    };

  # Builds the plugin `name` from `src`, its sources or a tree made of them.
  buildPlugin =
    {
      name,
      src,
    }:
    let
      marker = markerOf name;
    in
    builders.${marker} {
      inherit name;
      src = if marker == "Package.swift" then composeSwiftSrc name src else src;
    };

  pluginNames = builtins.attrNames (
    pkgs.lib.filterAttrs (name: type: type == "directory" && !pkgs.lib.hasPrefix "_" name) (
      builtins.readDir pluginsDir
    )
  );
in
{
  inherit
    pluginNames
    markerOf
    sourceOf
    buildPlugin
    binName
    ;

  pluginPackages = pkgs.lib.genAttrs pluginNames (
    name:
    buildPlugin {
      inherit name;
      src = sourceOf name;
    }
  );
}
