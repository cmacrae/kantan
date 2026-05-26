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
