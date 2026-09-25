{
  pkgs,
  plugin,
}:

{
  buildGoPlugin =
    {
      name,
      src,
    }:
    let
      bin = plugin.binName name;
    in
    pkgs.buildGoModule (
      plugin.pluginAttrs { inherit name src; }
      // {
        vendorHash = null;

        buildPhase = ''
          runHook preBuild
          go build -o ${bin} .
          runHook postBuild
        '';

        checkPhase = ''
          runHook preCheck
          go test ./...
          runHook postCheck
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin
          cp ${bin} $out/bin/${bin}
          runHook postInstall
        '';
      }
    );
}
