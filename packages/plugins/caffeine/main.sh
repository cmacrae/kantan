#!/bin/sh
set -e

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/kantan"
PID_FILE="$STATE_DIR/caffeine.pid"

# Whether the PID file names a running caffeinate, and not another process
# that has since taken its PID.
is_active() {
  [ -f "$PID_FILE" ] || return 1
  case "$(ps -p "$(cat "$PID_FILE")" -o comm= 2>/dev/null)" in
  caffeinate | */caffeinate) return 0 ;;
  *) return 1 ;;
  esac
}

activate() {
  if is_active; then
    return 0
  fi

  mkdir -p "$STATE_DIR"

  if [ -n "$KANTAN_PID" ]; then
    caffeinate -d -w "$KANTAN_PID" &
  else
    caffeinate -d &
  fi

  echo $! >"$PID_FILE"
}

deactivate() {
  if is_active; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
}

toggle() {
  if is_active; then
    deactivate
  else
    activate
  fi
}

default_mode() {
  if is_active; then
    printf '{"value":"","active":true,"variables":{"status":"On"}}\n'
  else
    printf '{"value":"","active":false,"variables":{"status":"Off"}}\n'
  fi
}

case "${1:-}" in
--toggle) toggle ;;
--activate) activate ;;
--deactivate) deactivate ;;
*) default_mode ;;
esac
