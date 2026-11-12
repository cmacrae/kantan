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

sh "$installer" --uninstall
test ! -e "$local/lib/kantan"
test "$(ls "$local/bin")" = other
if sh "$installer" --uninstall; then exit 1; fi
