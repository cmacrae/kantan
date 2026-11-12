{
  pkgs,
  version,
  tarballs,
  releaseUrl,
}:

let
  # Bottles are built for the oldest supported macOS, and pour on newer ones.
  bottleTag = "arm64_sequoia";

  # The install receipt Homebrew reads from a bottle's keg.
  receipt = pkgs.writeText "INSTALL_RECEIPT.json" (
    builtins.toJSON {
      built_as_bottle = true;
      poured_from_bottle = false;
      changed_files = [ ];
      source_modified_time = 0;
      compiler = "clang";
      runtime_dependencies = [ ];
      arch = "arm64";
      source.spec = "stable";
    }
  );

  # A bottle of `tarball`: its contents installed as `pname`'s keg.
  mkBottle =
    pname: tarball:
    let
      file = "${pname}-${version}.${bottleTag}.bottle.tar.gz";
    in
    pkgs.runCommand "${pname}-bottle-${version}" { passthru = { inherit file; }; } ''
      keg=${pname}/${version}
      mkdir -p $keg $out
      tar -xzf ${tarball} -C $keg
      install -m 644 ${receipt} $keg/INSTALL_RECEIPT.json
      tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner \
        -czf $out/${file} ${pname}
    '';

  bottles = {
    kantan = mkBottle "kantan" tarballs.full;
    kantan-without-plugins = mkBottle "kantan-without-plugins" tarballs.core;
  };

  mkFormula =
    {
      name,
      className,
      desc,
      tarball,
      conflictsWith,
      tarballUrl,
      bottleRootUrl,
    }:
    let
      bottle = bottles.${name};
    in
    pkgs.writeText "${name}.rb" ''
      class ${className} < Formula
        desc "${desc}"
        homepage "https://github.com/cmacrae/kantan"
        version "${version}"
        url "${tarballUrl tarball}"
        sha256 "${builtins.hashFile "sha256" tarball}"

        bottle do
          root_url "${bottleRootUrl bottle}"
          sha256 cellar: :any_skip_relocation, ${bottleTag}: "${builtins.hashFile "sha256" "${bottle}/${bottle.file}"}"
        end

        depends_on arch: :arm64
        depends_on macos: :sequoia
        conflicts_with "${conflictsWith}", because: "both install a kantan binary"

        def install
          prefix.install "bin", "share"
        end

        service do
          run [opt_bin/"kantan"]
          keep_alive true
          process_type :interactive
        end
      end
    '';

  # Both formulae, downloading each tarball from `tarballUrl tarball` and
  # each bottle from under `bottleRootUrl bottle`.
  mkFormulae = urls: {
    kantan = mkFormula (
      urls
      // {
        name = "kantan";
        className = "Kantan";
        desc = "A beautifully simple status bar for macOS";
        tarball = tarballs.full;
        conflictsWith = "kantan-without-plugins";
      }
    );

    kantan-without-plugins = mkFormula (
      urls
      // {
        name = "kantan-without-plugins";
        className = "KantanWithoutPlugins";
        desc = "A beautifully simple status bar for macOS (without plugins)";
        tarball = tarballs.core;
        conflictsWith = "kantan";
      }
    );
  };

  # Formulae for the tarballs and bottles in the Nix store.
  formulae = mkFormulae {
    tarballUrl = tarball: "file://${tarball}";
    bottleRootUrl = bottle: "file://${bottle}";
  };

  # The tap's Formula directory, for the tarballs and bottles attached to the
  # release.
  tap = pkgs.linkFarm "homebrew-tap-${version}" (
    pkgs.lib.mapAttrsToList
      (name: formula: {
        name = "Formula/${name}.rb";
        path = formula;
      })
      (mkFormulae {
        tarballUrl = tarball: "${releaseUrl}/${tarball.name}";
        bottleRootUrl = _: releaseUrl;
      })
  );
in
formulae
// {
  inherit tap;

  # Both bottles, named as the release attaches them.
  bottles = pkgs.symlinkJoin {
    name = "kantan-bottles-${version}";
    paths = builtins.attrValues bottles;
  };

  generateApp = {
    type = "app";
    program = toString (
      pkgs.writeShellScript "generate-homebrew-formulae" ''
        set -euo pipefail
        mkdir -p Formula
        install -m 644 ${formulae.kantan} Formula/kantan.rb
        install -m 644 ${formulae.kantan-without-plugins} Formula/kantan-without-plugins.rb
        echo "Generated Formula/kantan.rb"
        echo "Generated Formula/kantan-without-plugins.rb"
      ''
    );
  };
}
