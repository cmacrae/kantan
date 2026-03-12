{
  pkgs,
}:

{
  buildShellPlugin =
    {
      name,
      src,
    }:
    let
      bin = "kantan-plugin-${name}";
    in
    pkgs.stdenvNoCC.mkDerivation {
      pname = bin;
      version = "0.1.0";
      inherit src;
      dontFixup = true;
      installPhase = ''
        runHook preInstall

        mkdir -p $out/bin
        cp main.sh $out/bin/${bin}
        chmod +x $out/bin/${bin}

        if [ -d "examples" ]; then
          mkdir -p $out/share/examples
          cp examples/* $out/share/examples/
        fi

        runHook postInstall
      '';
      meta = {
        platforms = [ "aarch64-darwin" ];
      };
    };
}
