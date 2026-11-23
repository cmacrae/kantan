{
  pkgs,
  plugin,
}:

{
  buildShellPlugin =
    {
      name,
      src,
    }:
    let
      bin = plugin.binName name;
    in
    pkgs.stdenvNoCC.mkDerivation (
      plugin.pluginAttrs { inherit name src; }
      // {
        # Runs main_test.sh, when the plugin has one, against main.sh.
        doCheck = true;
        checkPhase = ''
          runHook preCheck
          if [ -f main_test.sh ]; then
            sh main_test.sh ./main.sh
          fi
          runHook postCheck
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p $out/bin
          cp main.sh $out/bin/${bin}
          chmod +x $out/bin/${bin}

          runHook postInstall
        '';
      }
    );
}
