{ self }:
let
  release = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile ../VERSION);
  commit = self.shortRev or self.dirtyShortRev or "unknown";
in
{
  # The release number, from VERSION, reported by release builds.
  inherit release;

  # The release number with the commit built, reported by every other build.
  build = "${release}-dev+${commit}";
}
