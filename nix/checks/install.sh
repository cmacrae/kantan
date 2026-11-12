#!/usr/bin/env bash
# Usage: install.sh <install-script> <release> <release-without-plugins> <version>
set -euo pipefail

installer=$1
full=$2
core=$3
version=$4

releases=$PWD/releases
mkdir -p "$releases/download/v$version"
cp "$full" "$releases/download/v$version/kantan-$version-aarch64-darwin.tar.gz"
cp "$core" "$releases/download/v$version/kantan-without-plugins-$version-aarch64-darwin.tar.gz"
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

touch "$local/bin/kantan-plugin-calendar"
if install; then exit 1; fi
test ! -e "$local/lib/kantan/bin/kantan-plugin-calendar"
rm "$local/bin/kantan-plugin-calendar"

sh "$installer" --uninstall
test ! -e "$local/lib/kantan"
test "$(ls "$local/bin")" = other
if sh "$installer" --uninstall; then exit 1; fi
