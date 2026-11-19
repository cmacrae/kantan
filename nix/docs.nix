{
  pkgs,
  web,
  previews,
  pluginsDir,
  version,
  siteUrl,
}:
let
  inherit (pkgs) lib;

  docsDir = ../docs;

  pluginNames = builtins.filter (name: builtins.pathExists (pluginsDir + "/${name}/README.md")) (
    builtins.attrNames (builtins.readDir pluginsDir)
  );

  # "system-monitor" → "System Monitor"
  pluginTitle =
    name:
    lib.concatMapStringsSep " " (
      word: lib.toUpper (lib.substring 0 1 word) + lib.substring 1 (-1) word
    ) (lib.splitString "-" name);

  pluginSummary = lib.concatMapStrings (
    name: "  - [${pluginTitle name}](plugins/${name}.md)\\n"
  ) pluginNames;

  # The script drawing the plugin previews.
  previewScript = web.bundle {
    name = "docs-preview";
    entries = [ "apps/docs-preview/main.jsx" ];
  };

  # Each plugin's README becomes its page, listed under Plugins, with its
  # preview below its title, and the preview of a variant of it wherever
  # the README asks for one, as `<!-- preview: calendar-full -->`. A
  # README's github-only block links to that page, so the page drops it. The previews, their icons and the script
  # drawing them sit in the book's preview directory.
  assembledSrc = pkgs.runCommand "kantan-docs-src" { nativeBuildInputs = [ pkgs.perl ]; } ''
    mkdir -p $out/src/plugins $out/src/preview
    cp -r ${docsDir}/* $out/
    chmod -R u+w $out
    cp ${../web/static/favicon.svg} $out/theme/favicon.svg
    cp ${previews.icons}/* ${previewScript}/main.js $out/src/preview/
    ${lib.concatMapStringsSep "\n" (name: ''
      grep -qF '${siteUrl}/docs/plugins/${name}.html' ${pluginsDir}/${name}/README.md \
        || { echo "${name}'s README must link to ${siteUrl}/docs/plugins/${name}.html" >&2; exit 1; }
      cp ${previews.documents}/${name}.json $out/src/preview/
      for variant in ${previews.documents}/${name}-*.json; do
        if [ -e "$variant" ]; then cp "$variant" $out/src/preview/; fi
      done
      perl -0pe 's/<!-- github-only -->.*?<!-- \/github-only -->\n+//gs;
        s/\A(# [^\n]*\n)/$1\n<div class="kantan-preview" data-preview="${name}"><\/div>\n/;
        s/<!-- preview: (${name}-[\w-]+) -->/<div class="kantan-preview" data-preview="$1"><\/div>/g' \
        ${pluginsDir}/${name}/README.md > $out/src/plugins/${name}.md
      ! grep -q 'github-only' $out/src/plugins/${name}.md
      # Every preview a page asks for is one the build made.
      for asked in $(grep -o 'data-preview="[^"]*"' $out/src/plugins/${name}.md | cut -d'"' -f2); do
        test -e "$out/src/preview/$asked.json" \
          || { echo "${name}'s README asks for the preview $asked, which isn't one of its variants" >&2; exit 1; }
      done
    '') pluginNames}
    perl -0pi -e 's|(  - \[API Reference\]\(plugins/api-reference\.md\)\n)|$1${pluginSummary}|' \
      $out/src/SUMMARY.md
    grep -qF '](plugins/${lib.head pluginNames}.md)' $out/src/SUMMARY.md
  '';

  # The kantan logo, drawn in the menu bar icons' colour
  logo = builtins.replaceStrings [ ''width="32" height="32" '' ''fill="#f38ba8"'' ] [ "" "" ] (
    builtins.readFile ../web/static/favicon.svg
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
