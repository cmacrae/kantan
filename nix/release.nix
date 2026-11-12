{
  pkgs,
  kantanBin,
  tabler-icons,
  plugins ? [ ],
  themes ? [ ],
  version,
}:

let
  mkTarball =
    {
      pname,
      components,
    }:
    pkgs.runCommand "${pname}-${version}-aarch64-darwin.tar.gz" { } ''
      mkdir -p staging/bin staging/share

      ${pkgs.lib.concatMapStringsSep "\n" (c: ''
        if [ -d "${c}/bin" ]; then
          cp -rL --no-preserve=mode "${c}"/bin/* staging/bin/
        fi
        if [ -d "${c}/share" ]; then
          cp -rL --no-preserve=mode "${c}"/share/* staging/share/
        fi
      '') components}
      chmod +x staging/bin/*

      tar -czf $out -C staging .
    '';
in
{
  full = mkTarball {
    pname = "kantan";
    components = [
      kantanBin
      tabler-icons
    ]
    ++ plugins
    ++ themes;
  };

  core = mkTarball {
    pname = "kantan-without-plugins";
    components = [
      kantanBin
      tabler-icons
    ]
    ++ themes;
  };
}
