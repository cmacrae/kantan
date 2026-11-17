{ pkgs }:
let
  inherit (pkgs) lib;

  # A package from the npm registry, for esbuild to bundle.
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
        (npmPackage "yaml" "2.9.1"
          "sha512-3NxN8+78OdzbT7C/WjGsyfPAtJaN3FNDsWxv7Y7mcDsT/oOmgW8BpyQQFFBnvZE3j9Y2Sdz1ULFLezL7Eb2yFw=="
        )
      ]
  );

  # The engine, the builder's logic, the components and the apps: everything
  # a bundle is made of.
  src = lib.fileset.toSource {
    root = ../web;
    fileset = lib.fileset.unions [
      ../web/engine
      ../web/builder
      ../web/components
      ../web/apps
    ];
  };

  # The cases kantan's tests and the engine's tests both run.
  fixtures = lib.fileset.toSource {
    root = ../web/fixtures;
    fileset = lib.fileset.fileFilter (file: file.hasExt "json") ../web/fixtures;
  };
in
{
  inherit src fixtures;

  # The engine's tests, the shared cases among them, and the tests of the
  # builder's logic, which read the schemas the docs publish.
  engineTests = pkgs.runCommand "kantan-web-engine-tests" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    cp -r ${../web/engine} engine
    cp -r ${../web/builder} builder
    cp -r ${fixtures} fixtures
    cp -r ${../docs/schemas} schemas
    cp -r ${nodeModules} node_modules
    cp ${../web/package.json} package.json
    node --test 'engine/test/*.test.js' 'builder/test/*.test.js'
    touch $out
  '';

  # The `entries`, paths within web/, each bundled with React into a
  # minified script named after it. YAML files import as text. `generated`
  # are files built elsewhere, by the name the sources import each under
  # from web/generated.
  bundle =
    {
      name,
      entries,
      generated ? { },
    }:
    pkgs.stdenvNoCC.mkDerivation {
      name = "kantan-web-${name}";
      inherit src;
      nativeBuildInputs = [ pkgs.esbuild ];
      buildPhase = ''
        cp -r ${nodeModules} node_modules
        mkdir generated
        ${lib.concatStrings (lib.mapAttrsToList (file: path: "cp ${path} generated/${file}\n") generated)}
        esbuild ${lib.escapeShellArgs entries} --bundle --minify --format=iife --jsx=automatic \
          --define:process.env.NODE_ENV='"production"' \
          --loader:.yaml=text \
          --entry-names='[name]' \
          --outdir=$out
      '';
      dontInstall = true;
    };
}
