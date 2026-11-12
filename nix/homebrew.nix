{
  pkgs,
  version,
  tarballs,
  releaseUrl,
}:

let
  mkFormula =
    {
      pname,
      className,
      desc,
      tarball,
      hasPlugins,
      conflictsWith ? null,
      tarballUrl,
    }:
    let
      pluginInstall = pkgs.lib.optionalString hasPlugins "\n    Dir[\"bin/kantan-plugin-*\"].each { |f| bin.install f }";

      conflictsLine = pkgs.lib.optionalString (
        conflictsWith != null
      ) "\n  conflicts_with \"${conflictsWith}\", because: \"both install a kantan binary\"";

      sha256 = builtins.hashFile "sha256" "${tarball}";
    in
    pkgs.writeText "${pname}.rb" ''
      class ${className} < Formula
        desc "${desc}"
        homepage "https://github.com/cmacrae/kantan"
        version "${version}"
        url "${tarballUrl tarball}"
        sha256 "${sha256}"

        depends_on arch: :arm64
        depends_on macos: :sequoia${conflictsLine}

        def install
          bin.install "bin/kantan"${pluginInstall}
          (share/"fonts").install Dir["share/fonts/*"]
          (share/"themes").install Dir["share/themes/*"] if Dir.exist?("share/themes")
        end

        service do
          run [opt_bin/"kantan"]
          keep_alive true
          process_type :interactive
        end
      end
    '';

  # Both formulae, downloading each tarball from `tarballUrl tarball`.
  mkFormulae = tarballUrl: {
    kantan = mkFormula {
      inherit tarballUrl;
      pname = "kantan";
      className = "Kantan";
      desc = "A beautifully simple status bar for macOS";
      tarball = tarballs.full;
      hasPlugins = true;
      conflictsWith = "kantan-without-plugins";
    };

    kantan-without-plugins = mkFormula {
      inherit tarballUrl;
      pname = "kantan-without-plugins";
      className = "KantanWithoutPlugins";
      desc = "A beautifully simple status bar for macOS (without plugins)";
      tarball = tarballs.core;
      hasPlugins = false;
      conflictsWith = "kantan";
    };
  };

  # Formulae for the tarballs in the Nix store.
  formulae = mkFormulae (tarball: "file://${tarball}");

  # The tap's Formula directory, for the tarballs attached to the release.
  tap = pkgs.linkFarm "homebrew-tap-${version}" (
    pkgs.lib.mapAttrsToList (name: formula: {
      name = "Formula/${name}.rb";
      path = formula;
    }) (mkFormulae (tarball: "${releaseUrl}/${tarball.name}"))
  );
in
formulae
// {
  inherit tap;
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
