{
  pkgs,
  plugin,
}:

let
  swiftBuildPhase = pname: ''
    runHook preBuild

    export DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
    export SDKROOT=$(/usr/bin/xcrun --show-sdk-path)
    export TOOLCHAINS=default
    export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$DEVELOPER_DIR/usr/bin:/usr/bin:$PATH"
    export HOME="$TMPDIR"

    swift build -c release --disable-sandbox --scratch-path .build --product ${pname}

    runHook postBuild
  '';

  swiftInstallPhase = pname: ''
    runHook preInstall
    mkdir -p $out/bin
    cp .build/arm64-apple-macosx/release/${pname} $out/bin/${pname}
    runHook postInstall
  '';

  buildSwiftPackage =
    args@{
      pname,
      src,
      meta ? { },
      ...
    }:
    pkgs.stdenvNoCC.mkDerivation (
      {
        version = "0.1.0";
        dontFixup = true;
      }
      // builtins.removeAttrs args [ "meta" ]
      // {
        buildPhase = swiftBuildPhase pname;
        installPhase = swiftInstallPhase pname;
        meta = {
          platforms = [ "aarch64-darwin" ];
        }
        // meta;
      }
    );
in
{
  inherit buildSwiftPackage;

  buildSwiftPlugin =
    {
      name,
      src,
    }:
    buildSwiftPackage (plugin.pluginAttrs { inherit name src; });
}
