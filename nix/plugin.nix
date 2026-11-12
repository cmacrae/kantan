{ version }:

let
  binName = name: "kantan-plugin-${name}";

  examplesPostInstall = src: ''
    if [ -d "${src}/examples" ]; then
      mkdir -p $out/share/examples
      cp ${src}/examples/* $out/share/examples/
    fi
  '';
in
{
  inherit binName;

  # Shared base attrs for plugin derivations across various builders.
  pluginAttrs =
    { name, src }:
    {
      pname = binName name;
      inherit version;
      inherit src;
      dontFixup = true;
      postInstall = examplesPostInstall src;
      meta.platforms = [ "aarch64-darwin" ];
    };
}
