{
  pkgs,
}:

{
  buildGoPlugin =
    {
      name,
      src,
    }:
    let
      bin = "kantan-plugin-${name}";
    in
    pkgs.buildGoModule {
      pname = bin;
      version = "0.1.0";
      inherit src;
      vendorHash = null;

      buildPhase = ''
        runHook preBuild
        go build -o ${bin} .
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p $out/bin
        cp ${bin} $out/bin/${bin}

        if [ -d "${src}/examples" ]; then
          mkdir -p $out/share/examples
          cp ${src}/examples/* $out/share/examples/
        fi

        runHook postInstall
      '';

      meta = {
        platforms = [ "aarch64-darwin" ];
      };
    };
}
