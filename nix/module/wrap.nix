# Wraps the kantan package with optional arguments, each passed as one
# argument whatever it contains, and a PATH prefix.
# Returns the input package unchanged when no wrapping is needed.
{
  pkgs,
  lib,
  package,
  addFlags ? [ ],
  pathPackages ? [ ],
}:
let
  hasFlags = addFlags != [ ];
  hasPath = pathPackages != [ ];
  flagArgs = lib.concatMapStringsSep " " (f: "--add-flag ${lib.escapeShellArg f}") addFlags;
  pathArg = lib.optionalString hasPath "--prefix PATH : ${lib.makeBinPath pathPackages}";
  wrapped = pkgs.symlinkJoin {
    name = "kantan-configured";
    paths = [ package ];
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    postBuild = ''
      wrapProgram $out/bin/kantan ${flagArgs} ${pathArg}
    '';
  };
in
if hasFlags || hasPath then wrapped else package
