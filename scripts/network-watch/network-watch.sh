#!/bin/sh
set -eu

LOG_DIR=${NETWORK_WATCH_LOG_DIR:-/var/log/seed-kit/network-watch}
LOG_FILE=${NETWORK_WATCH_LOG_FILE:-$LOG_DIR/network-watch.log}
STATE_FILE=${NETWORK_WATCH_STATE_FILE:-$LOG_DIR/network-watch.state}
TARGETS=${NETWORK_WATCH_TARGETS:-1.1.1.1}
INTERVAL_SECONDS=${NETWORK_WATCH_INTERVAL_SECONDS:-5}
PING_TIMEOUT_SECONDS=${NETWORK_WATCH_PING_TIMEOUT_SECONDS:-2}
PING_BIN=${NETWORK_WATCH_PING_BIN:-ping}

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

hostname_value() {
  hostname 2>/dev/null || printf 'unknown\n'
}

detect_interface() {
  target=$1
  if command -v ip >/dev/null 2>&1; then
    ip route get "$target" 2>/dev/null | awk '
      {
        for (i = 1; i <= NF; i++) {
          if ($i == "dev" && (i + 1) <= NF) {
            print $(i + 1)
            exit
          }
        }
      }'
    return 0
  fi
  printf 'unknown\n'
}

ensure_log_dir() {
  mkdir -p "$LOG_DIR"
  chmod 0755 "$LOG_DIR" 2>/dev/null || true
}

write_state() {
  state=$1
  target=$2
  latency_ms=${3:-}
  interface=${4:-unknown}
  {
    printf 'timestamp=%s\n' "$(timestamp)"
    printf 'state=%s\n' "$state"
    printf 'target=%s\n' "$target"
    printf 'latency_ms=%s\n' "$latency_ms"
    printf 'hostname=%s\n' "$(hostname_value)"
    printf 'interface=%s\n' "$interface"
  } > "$STATE_FILE"
  chmod 0644 "$STATE_FILE" 2>/dev/null || true
}

log_event() {
  event=$1
  shift
  line="timestamp=$(timestamp) event=$event hostname=$(hostname_value)"
  for item in "$@"; do
    line="$line $item"
  done
  printf '%s\n' "$line" >> "$LOG_FILE"
  chmod 0644 "$LOG_FILE" 2>/dev/null || true
}

ping_target() {
  target=$1
  output=$("$PING_BIN" -c 1 -W "$PING_TIMEOUT_SECONDS" "$target" 2>/dev/null || true)
  if printf '%s\n' "$output" | grep -Eq 'time[=<][0-9.]+'; then
    latency=$(printf '%s\n' "$output" | sed -n 's/.*time[=<]\([0-9.][0-9.]*\).*/\1/p' | sed -n '1p')
    printf '%s\n' "$latency"
    return 0
  fi
  return 1
}

check_targets() {
  for target in $TARGETS; do
    if latency=$(ping_target "$target"); then
      printf '%s %s\n' "$target" "$latency"
      return 0
    fi
  done
  return 1
}

monitor() {
  case "$INTERVAL_SECONDS" in
    ''|*[!0-9]*)
      echo "NETWORK_WATCH_INTERVAL_SECONDS must be a positive integer" >&2
      return 2
      ;;
  esac
  if [ "$INTERVAL_SECONDS" -lt 1 ]; then
    echo "NETWORK_WATCH_INTERVAL_SECONDS must be >= 1" >&2
    return 2
  fi

  ensure_log_dir
  log_event monitor-started "targets=$TARGETS" "interval_seconds=$INTERVAL_SECONDS"

  previous_state=unknown
  down_since=0
  down_target=""

  while :; do
    now=$(date +%s)
    if result=$(check_targets); then
      target=$(printf '%s\n' "$result" | awk '{print $1}')
      latency=$(printf '%s\n' "$result" | awk '{print $2}')
      interface=$(detect_interface "$target")
      write_state ok "$target" "$latency" "$interface"
      if [ "$previous_state" = "down" ]; then
        duration=$((now - down_since))
        log_event internet-restored "target=$target" "latency_ms=$latency" "interface=$interface" "duration_seconds=$duration"
      elif [ "$previous_state" != "ok" ]; then
        log_event internet-ok "target=$target" "latency_ms=$latency" "interface=$interface"
      fi
      previous_state=ok
      down_since=0
      down_target=""
    else
      first_target=$(printf '%s\n' "$TARGETS" | awk '{print $1}')
      interface=$(detect_interface "$first_target")
      write_state down "$first_target" "" "$interface"
      if [ "$previous_state" != "down" ]; then
        down_since=$now
        down_target=$first_target
        log_event internet-down "target=$down_target" "interface=$interface"
      fi
      previous_state=down
    fi
    sleep "$INTERVAL_SECONDS"
  done
}

status() {
  if [ -r "$STATE_FILE" ]; then
    cat "$STATE_FILE"
  else
    echo "state=unknown"
    echo "state_file=$STATE_FILE"
  fi
}

logs() {
  if [ -r "$LOG_FILE" ]; then
    tail -n "${NETWORK_WATCH_LOG_LINES:-80}" "$LOG_FILE"
  else
    echo "log_file=$LOG_FILE"
    echo "logs=unavailable"
  fi
}

follow() {
  if [ ! -r "$LOG_FILE" ]; then
    echo "log_file=$LOG_FILE"
    echo "logs=unavailable"
    return 1
  fi
  tail -f "$LOG_FILE"
}

case "${1:-monitor}" in
  monitor)
    monitor
    ;;
  status)
    status
    ;;
  logs)
    logs
    ;;
  follow)
    follow
    ;;
  *)
    echo "usage: sh network-watch.sh [monitor|status|logs|follow]" >&2
    exit 2
    ;;
esac
