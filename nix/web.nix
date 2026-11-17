{ pkgs }:
let
  inherit (pkgs) lib;

  # React, from the npm registry, for esbuild to bundle.
  npmPackage = name: version: hash: {
    inherit name;
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/${name}/-/${name}-${version}.tgz";
      inherit hash;
    };
  };

  nodeModules = pkgs.runCommand "kantan-web-node-modules" { } (
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

  # The apps: everything a bundle is made of.
  src = lib.fileset.toSource {
    root = ../web;
    fileset = ../web/apps;
  };
in
{
  inherit src;

  # The `entries`, paths within web/, each bundled with React into a
  # minified script named after it. YAML files import as text.
  bundle =
    { name, entries }:
    pkgs.stdenvNoCC.mkDerivation {
      name = "kantan-web-${name}";
      inherit src;
      nativeBuildInputs = [ pkgs.esbuild ];
      buildPhase = ''
        cp -r ${nodeModules} node_modules
        esbuild ${lib.escapeShellArgs entries} --bundle --minify --format=iife --jsx=automatic \
          --define:process.env.NODE_ENV='"production"' \
          --loader:.yaml=text \
          --entry-names='[name]' \
          --outdir=$out
      '';
      dontInstall = true;
    };
}
