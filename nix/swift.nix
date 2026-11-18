{
  pkgs,
  plugin,
}:

let
  # The Swift toolchain, and the SDK and macOS version kantan builds for.
  inherit (pkgs.swiftPackages) stdenv;
  nativeBuildInputs = [
    pkgs.swift
    pkgs.swiftpm
  ];
  buildInputs = [
    # The newest SDK whose module interfaces nixpkgs' Swift can read.
    pkgs.apple-sdk_26
    (pkgs.darwinMinVersionHook "15.0")
  ];

  # Runs the package's tests, when it has any, with Swift Testing.
  swiftCheckPhase = ''
    runHook preCheck
    if [ -d Tests ]; then
      swift test --disable-xctest --disable-get-task-allow-entitlement
    fi
    runHook postCheck
  '';

  # Removes the binaries' and libraries' rpaths into the Nix store, as they
  # link only the system's Swift runtime, and signs them again.
  dropStoreRpaths = ''
    for bin in $out/bin/* $out/share/*/*.dylib; do
      [ -e "$bin" ] || continue
      for rpath in $(otool -l "$bin" | awk '$1 == "path" && $2 ~ /^\/nix\/store\// { print $2 }'); do
        install_name_tool -delete_rpath "$rpath" "$bin"
      done
      codesign --force --sign - "$bin"
    done
  '';

  # Builds the Swift package at `src` and installs its `pname` executable,
  # with the dynamic libraries it builds under share/`pname`.
  buildSwiftPackage =
    args@{
      pname,
      meta ? { },
      postInstall ? "",
      ...
    }:
    stdenv.mkDerivation (
      builtins.removeAttrs args [
        "meta"
        "postInstall"
      ]
      // {
        nativeBuildInputs = nativeBuildInputs ++ [ pkgs.darwin.sigtool ] ++ args.nativeBuildInputs or [ ];
        buildInputs = buildInputs ++ args.buildInputs or [ ];
        installPhase = ''
          runHook preInstall
          install -D -m 755 "$(swiftpmBinPath)/${pname}" $out/bin/${pname}
          for lib in "$(swiftpmBinPath)"/*.dylib; do
            [ -e "$lib" ] && install -D -m 644 "$lib" "$out/share/${pname}/$(basename "$lib")"
          done
          runHook postInstall
        '';
        postInstall = dropStoreRpaths + postInstall;
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
  inherit buildSwiftPackage withSwiftTests;

  # The toolchain, SDK and macOS version, for a development shell.
  shell = {
    inherit stdenv;
    packages = nativeBuildInputs;
    inherit buildInputs;
  };

  buildSwiftPlugin =
    {
      name,
      src,
    }:
    withSwiftTests (buildSwiftPackage (plugin.pluginAttrs { inherit name src; }));
}
