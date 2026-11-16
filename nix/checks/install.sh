#!/usr/bin/env bash
# Usage: install.sh <install-script> <release-assets> <version>
set -euo pipefail

installer=$1
assets=$2
version=$3

releases=$PWD/releases
mkdir -p "$releases/download"
cp -r "$assets" "$releases/download/v$version"
chmod -R u+w "$releases"
export KANTAN_RELEASES_URL=file://$releases HOME=$PWD/home
install() { sh "$installer" --version "$version" "$@"; }
local=$HOME/.local
mkdir -p "$local/bin" "$local/share/fish"
touch "$local/bin/other"

install
test "$("$local/bin/kantan" --version)" = "kantan $version"
test -x "$local/bin/kantan-plugin-calendar"
test -f "$local/lib/kantan/share/fonts/tabler-icons.ttf"
test -f "$local/lib/kantan/share/doc/kantan/THIRD_PARTY_NOTICES"
python3 - "$local/lib/kantan/share/examples/bar.kantan.plist" <<EOF
import os, plistlib, sys
agent = plistlib.load(open(sys.argv[1], "rb"))
bin = os.environ["HOME"] + "/.local/bin"
assert agent["ProgramArguments"] == [bin + "/kantan"], agent
assert agent["EnvironmentVariables"]["PATH"].split(":")[0] == bin, agent
log = os.environ["HOME"] + "/Library/Logs/kantan.log"
assert agent["StandardOutPath"] == agent["StandardErrorPath"] == log, agent
EOF

install --without-plugins
test "$("$local/bin/kantan" --version)" = "kantan $version"
test ! -e "$local/bin/kantan-plugin-calendar"

sums=$releases/download/v$version/SHA256SUMS
cp "$sums" sums
awk '{ print "0000000000000000000000000000000000000000000000000000000000000000", $2 }' sums >"$sums"
if install; then exit 1; fi
test ! -e "$local/lib/kantan/bin/kantan-plugin-calendar"
grep -v -- '-without-plugins-' sums >"$sums"
if install --without-plugins; then exit 1; fi
cp sums "$sums"

touch "$local/bin/kantan-plugin-calendar"
if install; then exit 1; fi
test ! -e "$local/lib/kantan/bin/kantan-plugin-calendar"
rm "$local/bin/kantan-plugin-calendar"

# A script cut short as it downloads, here just before the new
# release moves into place, leaves the install as it was.
head -n "$(($(grep -n 'mv "$tmp/keg" "$keg"' "$installer" | cut -d: -f1) - 1))" \
  "$installer" >truncated.sh
sh truncated.sh --version "$version" 2>/dev/null || true
test "$("$local/bin/kantan" --version)" = "kantan $version"

# A prefix holding characters XML escapes reaches the agent intact.
odd="$HOME/a&b<c>"
mkdir -p "$odd"
install --prefix "$odd"
python3 - "$odd" <<EOF
import plistlib, sys
agent = plistlib.load(open(sys.argv[1] + "/lib/kantan/share/examples/bar.kantan.plist", "rb"))
assert agent["ProgramArguments"] == [sys.argv[1] + "/bin/kantan"], agent
EOF
sh "$installer" --prefix "$odd" --uninstall

sh "$installer" --uninstall
test ! -e "$local/lib/kantan"
test "$(ls "$local/bin")" = other
if sh "$installer" --uninstall; then exit 1; fi
