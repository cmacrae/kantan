{
  pkgs,
  version,
  tarballs,
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
    }:
    let
      pluginInstall = pkgs.lib.optionalString hasPlugins "\n    Dir[\"bin/kantan-plugin-*\"].each { |f| bin.install f }";

      conflictsLine = pkgs.lib.optionalString (
        conflictsWith != null
      ) "\n  conflicts_with \"${conflictsWith}\", because: \"both install a kantan binary\"";
    in
    pkgs.runCommand "${pname}.rb" { } ''
      HASH=$(sha256sum ${tarball} | cut -d' ' -f1)
      cat > $out <<FORMULA
      class ${className} < Formula
        desc "${desc}"
        homepage "https://github.com/cmacrae/kantan"
        version "${version}"
        url "file://${tarball}"
        sha256 "$HASH"

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
      FORMULA
    '';
  formulae = {
    kantan = mkFormula {
      pname = "kantan";
      className = "Kantan";
      desc = "A beautifully simple status bar for macOS";
      tarball = tarballs.full;
      hasPlugins = true;
      conflictsWith = "kantan-without-plugins";
    };

    kantan-without-plugins = mkFormula {
      pname = "kantan-without-plugins";
      className = "KantanWithoutPlugins";
      desc = "A beautifully simple status bar for macOS (without plugins)";
      tarball = tarballs.core;
      hasPlugins = false;
      conflictsWith = "kantan";
    };
  };
in
formulae
// {
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
