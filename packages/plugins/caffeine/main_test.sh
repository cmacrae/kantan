#!/bin/sh
# Tests the caffeine plugin at $1 with its state in a temporary directory.
set -eu

plugin=$1
XDG_CACHE_HOME=$(mktemp -d)
export XDG_CACHE_HOME
unset KANTAN_PID
pid_file=$XDG_CACHE_HOME/kantan/caffeine.pid
mkdir -p "$XDG_CACHE_HOME/kantan"

fail() {
  echo "caffeine: $*" >&2
  exit 1
}

# A PID file left naming a process that isn't caffeinate, as after a
# reboot, reads as off, and turning caffeine off leaves that process be.
sleep 30 &
other=$!
trap 'kill "$other" 2>/dev/null || true' EXIT
echo "$other" >"$pid_file"
sh "$plugin" | grep -q '"active":false' || fail "a reused PID reads as on"
sh "$plugin" --deactivate
kill -0 "$other" 2>/dev/null || fail "turning caffeine off killed another process"
