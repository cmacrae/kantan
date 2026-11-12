{
  lib,
  stdenvNoCC,
  fetchurl,
  python3,
}:

let
  fonttools = python3.withPackages (ps: [ ps.fonttools ]);

  # Renames the filled font family so both outline and filled variants
  # can be registered simultaneously without name collision.
  renameScript = ''
    import sys
    from fontTools.ttLib import TTFont

    font = TTFont(sys.argv[1])
    name_table = font["name"]
    for record in name_table.names:
        if record.nameID in (1, 3, 4, 6):
            old = record.toUnicode()
            new = old.replace("tabler-icons", "tabler-icons-filled")
            record.string = new
    font.save(sys.argv[2])
    font.close()
  '';
in
stdenvNoCC.mkDerivation rec {
  pname = "tabler-icons-font";
  version = "3.44.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@tabler/icons-webfont/-/icons-webfont-${version}.tgz";
    hash = "sha256-BF0YahFpEk1tBXH38s+s7YWbNqCBHobH4YHR8tT0MbI=";
  };

  nativeBuildInputs = [ fonttools ];

  dontConfigure = true;
  dontFixup = true;

  unpackPhase = ''
    tar xzf $src
  '';

  buildPhase = ''
    runHook preBuild
    python3 -c ${lib.escapeShellArg renameScript} \
      package/dist/fonts/tabler-icons-filled.ttf \
      tabler-icons-filled.ttf
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/fonts
    cp package/dist/fonts/tabler-icons.ttf $out/share/fonts/tabler-icons.ttf
    cp tabler-icons-filled.ttf $out/share/fonts/tabler-icons-filled.ttf
    install -D -m 644 package/LICENSE $out/share/doc/tabler-icons/LICENSE
    runHook postInstall
  '';

  meta = with lib; {
    description = "Tabler Icons webfont.";
    homepage = "https://tabler.io/icons";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
