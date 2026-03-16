{ pkgs, pluginsDir }:
let
  docsDir = ../docs;

  pluginNames = builtins.filter (name: builtins.pathExists (pluginsDir + "/${name}/README.md")) (
    builtins.attrNames (builtins.readDir pluginsDir)
  );

  assembledSrc = pkgs.runCommand "kantan-docs-src" { } ''
    mkdir -p $out/src/plugins
    cp -r ${docsDir}/* $out/
    ${builtins.concatStringsSep "\n" (
      map (name: "cp ${pluginsDir}/${name}/README.md $out/src/plugins/${name}.md") pluginNames
    )}
  '';

  docs = pkgs.stdenvNoCC.mkDerivation {
    pname = "kantan-docs";
    version = "0.1.0";

    src = assembledSrc;

    nativeBuildInputs = [ pkgs.mdbook ];

    buildPhase = ''
      mdbook build
    '';

    installPhase = ''
      cp -r book $out
    '';
  };

  serve = pkgs.writeShellScriptBin "kantan-docs-serve" ''
    TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT

    mkdir -p "$TMPDIR/src/plugins"
    cp -r ${docsDir}/* "$TMPDIR/"

    # Collect plugin READMEs into the plugins/ section
    ${builtins.concatStringsSep "\n" (
      map (name: "cp ${pluginsDir}/${name}/README.md \"$TMPDIR/src/plugins/${name}.md\"") pluginNames
    )}

    # Make copied files writable (Nix store originals are read-only)
    chmod -R u+w "$TMPDIR"

    cd "$TMPDIR"
    echo "Serving kantan docs at http://localhost:3000"
    ${pkgs.mdbook}/bin/mdbook serve --open --port 3000
  '';
in
{
  package = docs;

  app = {
    type = "app";
    program = "${serve}/bin/kantan-docs-serve";
  };
}
