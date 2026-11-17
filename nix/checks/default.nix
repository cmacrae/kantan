{
  self,
  pkgs,
  version,
  swift,
  web,
  docs,
  site,
  pluginPackages,
  themePackages,
  tabler-icons,
  commits,
  treefmtEval,
  _kantan,
  kantan,
  release,
  homebrew,
  releaseAssets,
}:
let
  inherit (pkgs) lib;

  mkModuleCheck =
    {
      name,
      module,
      stubModule,
      extract,
    }:
    let
      eval = lib.evalModules {
        specialArgs = { inherit pkgs; };
        modules = [
          module
          stubModule
          {
            programs.kantan.enable = true;
            programs.kantan.settings.dummy = "value";
          }
        ];
      };
    in
    pkgs.writeText "kantan-${name}-module-eval" (extract eval.config);

  darwinStubs =
    { lib, ... }:
    {
      options = {
        environment.systemPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
        };
        fonts.packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
        };
        launchd.user.agents = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
      };
    };

  homeManagerStubs =
    { lib, ... }:
    {
      options = {
        home.packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
        };
        xdg.configFile = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
        launchd.agents = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
      };
    };

  prefixAttrs = prefix: attrs: lib.mapAttrs' (n: v: lib.nameValuePair "${prefix}-${n}" v) attrs;
in
{
  formatting = treefmtEval.config.build.check self;
  kantan = _kantan;
  # kantan's tests, which run the shared cases the web engine's tests run too.
  kantan-tests = (swift.withSwiftTests _kantan).overrideAttrs {
    pname = "kantan-tests";
    KANTAN_FIXTURES = web.fixtures;
  };
  web-engine = web.engineTests;
  kantan-with-plugins = kantan;
  inherit tabler-icons;
  release = release.full;
  release-core = release.core;
  workflows =
    pkgs.runCommand "kantan-workflows"
      {
        nativeBuildInputs = [
          pkgs.git
          pkgs.zizmor
        ];
      }
      ''
        cp -r ${../../.github} .github
        git init --quiet
        zizmor --offline .
        # The release attests the provenance of the assets it publishes.
        grep -qE 'uses: actions/attest-build-provenance@v' .github/workflows/release.yml \
          && grep -qE 'subject-path: dist/\*' .github/workflows/release.yml \
          || { echo "release.yml must attest the release assets' provenance" >&2; exit 1; }
        # The release checks its tag is on main and runs the checks
        # before it publishes anything.
        steps=$(grep -nE 'is-ancestor "\$GITHUB_SHA" origin/main|run: nix flake check|gh release create' \
          .github/workflows/release.yml | cut -d: -f2-)
        if [ "$(grep -c . <<<"$steps")" -ne 3 ] || ! grep -q 'gh release create' <<<"$(tail -1 <<<"$steps")"; then
          echo "release.yml must check the tag is on main and run the checks before publishing" >&2
          exit 1
        fi
        touch $out
      '';

  docs-links = pkgs.runCommand "kantan-docs-links" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 ${./check-links.py} ${docs.package}
    touch $out
  '';

  release-smoke = pkgs.runCommand "kantan-release-smoke" { } ''
    tar -xzf ${release.full}
    test "$(bin/kantan --version)" = "kantan ${version.release}"
    for plugin in bin/kantan-plugin-*; do test -x "$plugin"; done
    touch $out
  '';

  release-store-paths =
    pkgs.runCommand "kantan-release-store-paths" { nativeBuildInputs = [ pkgs.cctools ]; }
      ''
        for tarball in ${release.full} ${release.core}; do
          mkdir staging
          tar -xzf $tarball -C staging
          checked=0
          for binary in staging/bin/*; do
            otool -h "$binary" >/dev/null 2>&1 || continue
            if otool -L -l "$binary" | grep /nix/store; then
              echo "$binary refers to the Nix store" >&2
              exit 1
            fi
            checked=$((checked + 1))
          done
          test "$checked" -gt 0
          rm -rf staging
        done
        touch $out
      '';

  release-notices = pkgs.runCommand "kantan-release-notices" { } ''
    for tarball in ${release.full} ${release.core}; do
      mkdir staging
      tar -xzf $tarball -C staging
      cmp staging/share/doc/kantan/LICENSE ${../../LICENSE}
      cmp staging/share/doc/kantan/THIRD_PARTY_NOTICES ${../../THIRD_PARTY_NOTICES}
      test -f staging/share/doc/tabler-icons/LICENSE
      diff -r staging/share/examples/reference ${../../examples}
      rm -rf staging
    done
    touch $out
  '';

  third-party-notices =
    pkgs.runCommand "kantan-third-party-notices" { nativeBuildInputs = [ pkgs.perl ]; }
      ''
        tar -xzf ${pkgs.go.src} go/LICENSE
        for license in \
          ${tabler-icons}/share/doc/tabler-icons/LICENSE \
          ${_kantan.swiftpmDeps}/Packages/Yams/LICENSE \
          ${pkgs.libyaml.src}/License \
          go/LICENSE; do
          perl -0777 -e 'open my $f, "<", $ARGV[0] or die; my $n = <$f>; open $f, "<", $ARGV[1] or die; exit(index(<$f>, $n) < 0)' \
            "$license" ${../../THIRD_PARTY_NOTICES} || { echo "THIRD_PARTY_NOTICES lacks $license"; exit 1; }
        done
        touch $out
      '';
  docs = docs.package;
  site = site.package;
  commits = commits.test;
  commit-scopes = commits.scopes;
  homebrew-formula = homebrew.kantan;

  homebrew-bottles = pkgs.runCommand "kantan-homebrew-bottles" { nativeBuildInputs = [ pkgs.jq ]; } ''
    for bottle in ${homebrew.bottles}/*.bottle.tar.gz; do
      name=$(basename "$bottle")
      name=''${name%-${version.release}.*}
      tar -xzf "$bottle"
      keg=$name/${version.release}
      test "$($keg/bin/kantan --version)" = "kantan ${version.release}"
      test -f $keg/share/fonts/tabler-icons.ttf
      test -f $keg/share/doc/kantan/THIRD_PARTY_NOTICES
      jq -e .built_as_bottle $keg/INSTALL_RECEIPT.json
    done
    test -x kantan/${version.release}/bin/kantan-plugin-calendar
    test ! -e kantan-without-plugins/${version.release}/bin/kantan-plugin-calendar
    touch $out
  '';

  install-script =
    pkgs.runCommand "kantan-install-script"
      {
        nativeBuildInputs = [
          pkgs.curl
          pkgs.perl
          pkgs.python3
          pkgs.shellcheck
          (pkgs.writeShellScriptBin "sw_vers" "echo 15.0")
        ];
      }
      ''
        shellcheck ${../../web/static/install.sh}
        bash ${./install.sh} ${../../web/static/install.sh} ${releaseAssets} ${version.release}
        touch $out
      '';
  module-darwin = mkModuleCheck {
    name = "darwin";
    module = import ../module/darwin.nix kantan;
    stubModule = darwinStubs;
    extract = cfg: lib.last cfg.launchd.user.agents.kantan.serviceConfig.ProgramArguments;
  };

  module-extra-args =
    let
      stub = pkgs.writeShellScriptBin "kantan" ''printf '[%s]\n' "$@"'';
      args = [
        "--modules-dir"
        "/a b/modules.d"
        "it's"
      ];
      program =
        module: stubModule: packages:
        let
          eval = lib.evalModules {
            specialArgs = { inherit pkgs; };
            modules = [
              module
              stubModule
              {
                programs.kantan.enable = true;
                programs.kantan.package = stub;
                programs.kantan.extraArgs = args;
              }
            ];
          };
        in
        "${lib.head (packages eval.config)}/bin/kantan";
    in
    pkgs.runCommand "kantan-module-extra-args" { } ''
      expected=$(printf '[%s]\n' ${lib.escapeShellArgs args})
      test "$(${
        program (import ../module/home-manager.nix kantan) homeManagerStubs (cfg: cfg.home.packages)
      })" = "$expected"
      test "$(${
        program (import ../module/darwin.nix kantan) darwinStubs (cfg: cfg.environment.systemPackages)
      })" = "$expected"
      touch $out
    '';
  module-home-manager = mkModuleCheck {
    name = "home-manager";
    module = import ../module/home-manager.nix kantan;
    stubModule = homeManagerStubs;
    extract = cfg: lib.last cfg.launchd.agents.kantan.config.ProgramArguments;
  };
}
// prefixAttrs "plugin" pluginPackages
// prefixAttrs "theme" themePackages
