{
  pkgs,
  pluginsDir,
  version,
  siteUrl,
}:
let
  docsDir = ../docs;

  pluginNames = builtins.filter (name: builtins.pathExists (pluginsDir + "/${name}/README.md")) (
    builtins.attrNames (builtins.readDir pluginsDir)
  );

  assembledSrc = pkgs.runCommand "kantan-docs-src" { } ''
    mkdir -p $out/src/plugins
    cp -r ${docsDir}/* $out/
    chmod u+w $out/theme
    cp ${../site/favicon.svg} $out/theme/favicon.svg
    ${builtins.concatStringsSep "\n" (
      map (name: "cp ${pluginsDir}/${name}/README.md $out/src/plugins/${name}.md") pluginNames
    )}
  '';

  # The kantan logo, drawn in the menu bar icons' colour
  logo = builtins.replaceStrings [ ''width="32" height="32" '' ''fill="#f38ba8"'' ] [ "" "" ] (
    builtins.readFile ../site/favicon.svg
  );

  websiteLink = ''<a href="${siteUrl}/" title="Website" aria-label="Website"><span class=fa-svg>${logo}</span></a>'';

  docs = pkgs.stdenvNoCC.mkDerivation {
    pname = "kantan-docs";
    inherit version;

    src = assembledSrc;

    nativeBuildInputs = [
      pkgs.mdbook
      pkgs.perl
    ];

    inherit websiteLink;

    buildPhase = ''
      mdbook build
      grep -rl --include='*.html' '<div class="right-buttons">' book \
        | xargs perl -0pi -e 's|(<div class="right-buttons">.*?)(\s*</div>)|$1$ENV{websiteLink}$2|s'
    '';

    installPhase = ''
      cp -r book $out
    '';
  };

  serve = pkgs.writeShellScriptBin "kantan-docs-serve" ''
    TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT

    cp -r ${assembledSrc}/. "$TMPDIR/"
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
