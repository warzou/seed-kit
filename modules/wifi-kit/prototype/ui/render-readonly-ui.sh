#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WIFI_KIT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
WIFI_KIT_SH="$WIFI_KIT_ROOT/wifi-kit.sh"
TEMPLATE="$SCRIPT_DIR/index.html"
TMP_DIR="${TMPDIR:-/tmp}/wifi-kit-ui.$$"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TMP_DIR"
diagnose_json="$TMP_DIR/safe-diagnose.json"
snapshot_json="$TMP_DIR/state-snapshot.json"
scan_json="$TMP_DIR/scan-real.json"

sh "$WIFI_KIT_SH" safe-diagnose --json > "$diagnose_json"
sh "$WIFI_KIT_SH" state-snapshot --simulate --json > "$snapshot_json"
sh "$WIFI_KIT_SH" scan-real --json > "$scan_json"

awk -v diagnose="$diagnose_json" -v snapshot="$snapshot_json" -v scan="$scan_json" '
  function print_json_file(path, prefix, suffix, line, first) {
    first=1
    while ((getline line < path) > 0) {
      gsub(/</, "\\u003c", line)
      if (first) {
        print prefix line
        first=0
      } else {
        print line
      }
    }
    close(path)
    print suffix
  }
  BEGIN {
    in_data=0
  }
  /<script id="wifi-kit-data" type="application\/json">/ {
    print
    print "{"
    print_json_file(diagnose, "  \"diagnose\": ", ",")
    print_json_file(snapshot, "  \"snapshot\": ", ",")
    print_json_file(scan, "  \"scan\": ", "")
    print "}"
    in_data=1
    next
  }
  /<\/script>/ && in_data {
    print
    in_data=0
    next
  }
  !in_data { print }
' "$TEMPLATE"
