#!/bin/sh
# Installs kantan from its GitHub release.
#
#   curl -fsSL https://kantan.bar/install.sh | sh
#   curl -fsSL https://kantan.bar/install.sh | sh -s -- --version 0.1.0
#   curl -fsSL https://kantan.bar/install.sh | sh -s -- --uninstall
#
# The release is unpacked into <prefix>/lib/kantan, and its binaries are
# symlinked into <prefix>/bin.

set -eu

releases=${KANTAN_RELEASES_URL:-https://github.com/cmacrae/kantan/releases}
prefix=$HOME/.local
version=
name=kantan
action=install

usage() {
  cat <<EOF
usage: install.sh [--prefix <dir>] [--version <version>] [--without-plugins]
       install.sh [--prefix <dir>] --uninstall

  --prefix <dir>       install under <dir> (default: ~/.local)
  --version <version>  install <version> instead of the latest release
  --without-plugins    install kantan without its bundled plugins
  --uninstall          remove kantan from <prefix>
  -h, --help           show this help
EOF
}

say() { printf '%s\n' "$*"; }
die() {
  printf 'install.sh: %s\n' "$*" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case $1 in
  --prefix)
    [ $# -gt 1 ] || die "--prefix needs a directory"
    prefix=$2
    shift
    ;;
  --version)
    [ $# -gt 1 ] || die "--version needs a version"
    version=${2#v}
    shift
    ;;
  --without-plugins) name=kantan-without-plugins ;;
  --uninstall) action=uninstall ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
  esac
  shift
done

[ "$action" = uninstall ] || mkdir -p "$prefix"
[ -d "$prefix" ] || die "kantan isn't installed in $prefix"
prefix=$(cd "$prefix" && pwd -P)
keg=$prefix/lib/kantan
bin=$prefix/bin

# Removes the links in <prefix>/bin into the installed release, then the release.
uninstall() {
  if [ -d "$bin" ]; then
    for link in "$bin"/*; do
      [ -L "$link" ] || continue
      case $(readlink "$link") in
      "$keg"/*) rm -f "$link" ;;
      esac
    done
  fi
  rm -rf "$keg"
}

if [ "$action" = uninstall ]; then
  [ -d "$keg" ] || die "kantan isn't installed in $prefix"
  uninstall
  say "Removed kantan from $prefix"
  exit 0
fi

[ "$(uname -s)" = Darwin ] || die "kantan runs only on macOS"
[ "$(uname -m)" = arm64 ] || die "kantan runs only on Apple silicon"
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 15 ] || die "kantan needs macOS 15 (Sequoia) or later"

if [ -z "$version" ]; then
  # The latest release's page redirects to its tag.
  latest=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$releases/latest") ||
    die "couldn't find the latest release"
  version=${latest##*/v}
  [ "$version" != "$latest" ] || die "couldn't find the latest release"
fi

tarball=$name-$version-aarch64-darwin.tar.gz
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

say "Downloading kantan $version"
curl -fsSL -o "$tmp/$tarball" "$releases/download/v$version/$tarball" ||
  die "couldn't download $tarball"
curl -fsSL -o "$tmp/SHA256SUMS" "$releases/download/v$version/SHA256SUMS" ||
  die "couldn't download the release's checksums"
expected=$(awk -v f="$tarball" '$2 == f { print $1 }' "$tmp/SHA256SUMS")
[ -n "$expected" ] || die "the release's checksums don't list $tarball"
actual=$(shasum -a 256 "$tmp/$tarball" | cut -d' ' -f1)
[ "$actual" = "$expected" ] || die "$tarball doesn't match its checksum"
mkdir "$tmp/keg"
tar -xzf "$tmp/$tarball" -C "$tmp/keg"
[ -x "$tmp/keg/bin/kantan" ] || die "$tarball has no kantan binary"

# Leaves files in <prefix>/bin that aren't kantan's links untouched.
for exe in "$tmp"/keg/bin/*; do
  link=$bin/${exe##*/}
  if [ -e "$link" ] || [ -L "$link" ]; then
    case $(readlink "$link" || true) in
    "$keg"/*) ;;
    *) die "$link exists and isn't kantan's" ;;
    esac
  fi
done

# Replaces any earlier install.
[ ! -d "$keg" ] || uninstall
mkdir -p "$prefix/lib" "$bin"
mv "$tmp/keg" "$keg"
for exe in "$keg"/bin/*; do
  ln -s "$exe" "$bin/${exe##*/}"
done

# A launchd agent that runs this install at login, for copying into
# ~/Library/LaunchAgents.
mkdir -p "$keg/share/examples"
cat >"$keg/share/examples/bar.kantan.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>bar.kantan</string>
  <key>ProgramArguments</key>
  <array>
    <string>$bin/kantan</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/kantan.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/kantan.log</string>
</dict>
</plist>
EOF

say "Installed $("$keg/bin/kantan" --version) in $prefix"
case :$PATH: in
*:"$bin":*) ;;
*) say "Add $bin to your PATH to run kantan" ;;
esac
