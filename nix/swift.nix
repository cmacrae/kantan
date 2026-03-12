{
  pkgs,
}:

let
  swiftBuildPhase = bin: ''
    runHook preBuild

    export DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
    export SDKROOT=$(/usr/bin/xcrun --show-sdk-path)
    export TOOLCHAINS=default
    export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$DEVELOPER_DIR/usr/bin:/usr/bin:$PATH"
    export HOME="$TMPDIR"

    swift build -c release --disable-sandbox --scratch-path .build

    runHook postBuild
  '';

  swiftInstallPhase = bin: ''
    runHook preInstall
    mkdir -p $out/bin
    cp .build/arm64-apple-macosx/release/${bin} $out/bin/${bin}
    runHook postInstall
  '';

  buildSwiftPackage =
    {
      pname,
      version ? "0.1.0",
      src,
      meta ? { },
    }:
    pkgs.stdenvNoCC.mkDerivation {
      inherit pname version src;

      buildPhase = swiftBuildPhase pname;
      installPhase = swiftInstallPhase pname;
      dontFixup = true;

      meta = {
        platforms = [ "aarch64-darwin" ];
      }
      // meta;
    };
in
{
  inherit buildSwiftPackage;

  buildSwiftPlugin =
    {
      name,
      src,
    }:
    let
      bin = "kantan-plugin-${name}";
      built = buildSwiftPackage {
        pname = bin;
        inherit src;
      };
    in
    pkgs.stdenvNoCC.mkDerivation {
      pname = bin;
      version = "0.1.0";
      dontUnpack = true;
      dontFixup = true;
      installPhase = ''
        runHook preInstall

        mkdir -p $out/bin
        cp ${built}/bin/${bin} $out/bin/${bin}

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
