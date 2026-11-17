#!/bin/sh
# Prints the states of the caffeine module's preview, on and off, by running
# the plugin at $1 and toggling it, with its state in a temporary directory.
# Stand-ins for caffeinate and ps keep it from touching the system's.
set -eu

plugin=$1
XDG_CACHE_HOME=$(mktemp -d)
export XDG_CACHE_HOME
unset KANTAN_PID

stubs=$XDG_CACHE_HOME/stubs
mkdir -p "$stubs"
cat >"$stubs/caffeinate" <<STUB
#!/bin/sh
echo \$\$ >>"$stubs/pids"
exec sleep 30
STUB
cat >"$stubs/ps" <<STUB
#!/bin/sh
grep -qx "\$2" "$stubs/pids" 2>/dev/null && echo caffeinate
STUB
chmod +x "$stubs/caffeinate" "$stubs/ps"
PATH=$stubs:$PATH
trap 'sh "$plugin" --deactivate' EXIT

# The command a click on the module runs, as the example config sets it.
toggle="kantan-plugin-caffeine --toggle"

off=$(sh "$plugin")
sh "$plugin" --toggle
sleep 0.2
on=$(sh "$plugin")

printf '{"states":[{"name":"On","output":%s,"after":{"%s":%s}},{"name":"Off","output":%s,"after":{"%s":%s}}]}\n' \
  "$on" "$toggle" "$off" "$off" "$toggle" "$on"
