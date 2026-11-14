{
  pkgs,
  docs,
  version,
  buildSwiftPackage,
}:
let
  inherit (pkgs) lib;

  siteDir = ../site;

  url = "https://kantan.bar";

  # React, from the npm registry, for esbuild to bundle.
  npmPackage = name: version: hash: {
    inherit name;
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/${name}/-/${name}-${version}.tgz";
      inherit hash;
    };
  };

  nodeModules = pkgs.runCommand "kantan-site-node-modules" { } (
    lib.concatMapStrings
      (package: ''
        mkdir -p $out/${package.name}
        tar -xzf ${package.src} -C $out/${package.name} --strip-components=1
      '')
      [
        (npmPackage "react" "19.3.1"
          "sha512-QNhWdt7nrgVWWQG58QuGsAR3jv3Hbe4mb4vz7w2csnHavciZJgda1CPNaldF6eVxv90ud3jUXpKlHL69gO38yw=="
        )
        (npmPackage "react-dom" "19.3.1"
          "sha512-Y0bARz53lhEC1NMCASs0/j+faB/zqt3R8hpvg1e8+61ZVJ4UL0UdC4cBbXfZMcIuhrfgeILTLe+ZeBCavQPtKQ=="
        )
        (npmPackage "scheduler" "0.28.0"
          "sha512-juorfCmIkIw8tT+p5BXSm6PJjQF/ycEYmKyzURCIt/RaZIhL+PulbQ9Yu2z1HdOJDdqDTlxA1+xKBmHXJsczAw=="
        )
      ]
  );

  # The wordmark's fonts, from the Google Fonts repository.
  googleFont =
    path: hash:
    pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/google/fonts/29b4ec6df2522a8aee279414b78a07910b065874/ofl/${path}";
      inherit hash;
    };

  # Each font cut down to the characters the wordmark writes in, with its
  # licence beside it.
  fonts =
    pkgs.runCommand "kantan-site-fonts"
      {
        nativeBuildInputs = [
          (pkgs.python3.withPackages (ps: [
            ps.fonttools
            ps.brotli
          ]))
        ];
      }
      ''
        mkdir -p $out
        pyftsubset ${googleFont "singleday/SingleDay-Regular.ttf" "sha256-cW/2eksGdbNcJtYKS7gxc/fRU6t1RHTtNsM2lZPKHKg="} \
          --unicodes=U+0020-007E --flavor=woff2 --output-file=$out/SingleDay.woff2
        cp ${googleFont "singleday/OFL.txt" "sha256-OX6DsFcDpCQL5R4sOivh0NdpPXotix/zZ8JqK5r8AT4="} \
          $out/SingleDay-OFL.txt
        pyftsubset ${googleFont "darumadropone/DarumadropOne-Regular.ttf" "sha256-vu9tkDGRiCMXbqD59ynLgRpfJQWY18jGhLPe4zOBBok="} \
          --unicodes=U+3040-309F --flavor=woff2 --output-file=$out/DarumadropOne.woff2
        cp ${googleFont "darumadropone/OFL.txt" "sha256-vYmMhvtVXwYO6eXTGNYxu9zRlrmK6AGeAHdCH0baEy8="} \
          $out/DarumadropOne-OFL.txt

        cat > $out/fonts.css <<EOF
        @font-face {
          font-family: "Single Day";
          src: url("SingleDay.woff2") format("woff2");
          font-display: swap;
        }
        @font-face {
          font-family: "Darumadrop One";
          src: url("DarumadropOne.woff2") format("woff2");
          font-display: swap;
        }
        EOF
      '';

  # The landing page and the preview page, each bundled with React.
  pages = pkgs.stdenvNoCC.mkDerivation {
    pname = "kantan-site-pages";
    inherit version;
    # Everything but the rendered images and the tool that renders them
    src = lib.fileset.toSource {
      root = siteDir;
      fileset = lib.fileset.difference siteDir (
        lib.fileset.unions [
          (lib.fileset.maybeMissing ../site/images)
          ../site/snapshot
        ]
      );
    };
    nativeBuildInputs = [ pkgs.esbuild ];
    buildPhase = ''
      cp -r ${nodeModules} node_modules
      esbuild main.jsx preview.jsx --bundle --minify --format=iife --jsx=automatic \
        --define:process.env.NODE_ENV='"production"' \
        --loader:.yaml=text \
        --outdir=.
    '';
    installPhase = ''
      mkdir -p $out/fonts
      cp index.html 404.html main.js preview.html preview.js favicon.svg install.sh docs-versions.js $out/
      cp ${fonts}/* $out/fonts/
    '';
  };

  # Assembles the site in a directory from the landing page and the docs of
  # each release, given as <version>=<docs> pairs with the latest first. The
  # latest docs sit at /docs/ and the others at /docs/v<version>/, where
  # search engines are asked not to index them. Every docs page gets the
  # version picker.
  assemble = pkgs.writeShellApplication {
    name = "kantan-site-assemble";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnused
    ];
    text = ''
      if [ $# -lt 2 ]; then
        echo "usage: kantan-site-assemble <out> <version>=<docs>..." >&2
        exit 2
      fi
      out=$1
      shift

      mkdir -p "$out/docs" "$out/images"
      cp -r ${pages}/{index.html,404.html,main.js,favicon.svg,install.sh,fonts} "$out/"
      cp ${pages}/docs-versions.js "$out/docs/versions.js"
      cp ${../site/images/og.png} "$out/images/og.png"
      chmod -R u+w "$out"

      latest=true
      versions=""
      for pair in "$@"; do
        version=''${pair%%=*}
        if $latest; then path=/docs/; else path=/docs/v$version/; fi

        mkdir -p "$out$path"
        cp -r "''${pair#*=}"/. "$out$path"
        chmod -R u+w "$out$path"

        # The latest docs are copied first, so no older release is in /docs/ yet.
        head='<script src="/docs/versions.js" defer></script>'
        $latest || head="<meta name=\"robots\" content=\"noindex\">$head"
        find "$out$path" -name '*.html' -exec sed -i "s|</head>|$head</head>|" {} +

        versions+="''${versions:+,}{\"version\":\"$version\",\"path\":\"$path\",\"latest\":$latest}"
        latest=false
      done
      echo "[$versions]" > "$out/docs/versions.json"

      # The landing page and the latest docs, but not their print, 404 and
      # sidebar pages
      {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
        echo "  <url><loc>${url}/</loc></url>"
        (cd "$out" && find docs -path 'docs/v[0-9]*' -prune -o -name '*.html' \
          ! -name print.html ! -name 404.html ! -name toc.html -print) \
          | sort | while read -r page; do
            echo "  <url><loc>${url}/$page</loc></url>"
          done
        echo '</urlset>'
      } > "$out/sitemap.xml"

      printf 'User-agent: *\nAllow: /\n\nSitemap: %s/sitemap.xml\n' ${url} > "$out/robots.txt"
    '';
  };

  # The site with this checkout's docs as the only release
  site = pkgs.runCommand "kantan-site" { } ''
    ${lib.getExe assemble} $out ${lib.versions.majorMinor version}=${docs.package}
  '';

  serve = pkgs.writeShellScriptBin "kantan-site-serve" ''
    PORT=''${1:-3000}
    echo "Serving site at http://localhost:$PORT"
    ${pkgs.python3}/bin/python3 -m http.server -d ${site} "$PORT"
  '';

  snapshot = buildSwiftPackage {
    pname = "kantan-site-snapshot";
    inherit version;
    src = ../site/snapshot;
  };

  # Renders the README's light and dark images and the link preview image
  # into site/images, from the preview page.
  renderImages = pkgs.writeShellApplication {
    name = "kantan-site-render-images";
    runtimeInputs = [ pkgs.oxipng ];
    text = ''
      out=site/images
      if [ ! -d "$out" ]; then
        echo "Run this from the root of the kantan repository" >&2
        exit 1
      fi
      page=${pages}/preview.html
      snap=${snapshot}/bin/kantan-site-snapshot
      "$snap" "$page?dark=0" 960 380 2 "$out/readme-light.png"
      "$snap" "$page?dark=1" 960 380 2 "$out/readme-dark.png"
      "$snap" "$page?dark=1&fill=1&width=880&desktop=300&zoom=1.2" 1200 630 1 "$out/og.png"
      oxipng --quiet --opt max --strip safe "$out"/*.png
      echo "Rendered the images in $out"
    '';
  };
in
{
  package = site;

  app = {
    type = "app";
    program = "${serve}/bin/kantan-site-serve";
  };

  assembleApp = {
    type = "app";
    program = lib.getExe assemble;
  };

  renderImagesApp = {
    type = "app";
    program = lib.getExe renderImages;
  };
}
