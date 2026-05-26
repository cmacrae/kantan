{ lib }:

# Reads entries from a directory, filters them with `predicate`, and builds
# each surviving entry into an attrset value. `name` derives the attrname
# from the entry's filename and dirent type.
{
  dir,
  predicate,
  name ? (n: _: n),
  build,
}:
let
  entries = lib.filterAttrs predicate (builtins.readDir dir);
in
lib.mapAttrs' (n: t: lib.nameValuePair (name n t) (build n t)) entries
