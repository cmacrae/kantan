{
  pkgs,
  plugin,
}:

let
  # Puts the system Xcode's Swift toolchain and SDK first.
  xcodeEnv = ''
    export DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
    export SDKROOT=$(/usr/bin/xcrun --show-sdk-path)
    export TOOLCHAINS=default
    export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$DEVELOPER_DIR/usr/bin:/usr/bin:$PATH"
  '';

  swiftBuildPhase = pname: ''
    runHook preBuild

    ${xcodeEnv}
    export HOME="$TMPDIR"

    swift build -c release --disable-sandbox --scratch-path .build --product ${pname}

    runHook postBuild
  '';

  # Runs the package's tests, when it has any.
  swiftCheckPhase = ''
    runHook preCheck
    if [ -d Tests ]; then
      swift test --disable-sandbox --scratch-path .build
    fi
    runHook postCheck
  '';

  swiftInstallPhase = pname: ''
    runHook preInstall
    ${xcodeEnv}
    mkdir -p $out/bin
    cp "$(swift build -c release --scratch-path .build --show-bin-path)/${pname}" $out/bin/${pname}
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
  # Runs a Swift package's tests after building it.
  withSwiftTests =
    drv:
    drv.overrideAttrs {
      doCheck = true;
      checkPhase = swiftCheckPhase;
    };
in
{
  inherit buildSwiftPackage withSwiftTests xcodeEnv;

  buildSwiftPlugin =
    {
      name,
      src,
    }:
    withSwiftTests (buildSwiftPackage (plugin.pluginAttrs { inherit name src; }));
}
