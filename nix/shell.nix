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
        doCheck = builtins.pathExists (src + "/main_test.sh");
        checkPhase = ''
          runHook preCheck
          sh main_test.sh ./main.sh
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
