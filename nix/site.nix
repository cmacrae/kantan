{
  pkgs,
  docs,
}:
let
  siteDir = ../site;

  landing = pkgs.stdenvNoCC.mkDerivation {
    pname = "kantan-landing";
    version = "0.1.0";
    src = pkgs.lib.cleanSource siteDir;
    nativeBuildInputs = [ pkgs.esbuild ];
    buildPhase = ''
      esbuild main.jsx --bundle --format=esm --jsx=automatic \
        --external:react --external:"react-dom/client" --external:"react/jsx-runtime" \
        --loader:.yaml=text \
        --outfile=main.js
    '';
    installPhase = ''
      mkdir -p $out
      cp index.html main.js favicon.svg $out/
    '';
  };

  site = pkgs.runCommand "kantan-site" { } ''
    mkdir -p $out/docs
    cp ${landing}/* $out/
    cp -r ${docs.package}/* $out/docs/
  '';

  serve = pkgs.writeShellScriptBin "kantan-site-serve" ''
    PORT=''${1:-3000}
    TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT

    echo "Building landing page..."
    mkdir -p "$TMPDIR"
    cp ${siteDir}/index.html ${siteDir}/favicon.svg "$TMPDIR/"
    ${pkgs.esbuild}/bin/esbuild ${siteDir}/main.jsx --bundle --format=esm --jsx=automatic \
      --external:react --external:"react-dom/client" --external:"react/jsx-runtime" \
      --loader:.yaml=text \
      --outfile="$TMPDIR/main.js"

    echo "Building docs..."
    cp -r ${docs.package} "$TMPDIR/docs"
    chmod -R u+w "$TMPDIR/docs"

    echo ""
    echo "Serving site at http://localhost:$PORT"
    echo ""
    ${pkgs.python3}/bin/python3 -m http.server -d "$TMPDIR" "$PORT"
  '';
in
{
  package = site;

  app = {
    type = "app";
    program = "${serve}/bin/kantan-site-serve";
  };
}
