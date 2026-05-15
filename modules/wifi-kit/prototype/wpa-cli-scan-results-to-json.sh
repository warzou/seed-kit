#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  wpa-cli-scan-results-to-json.sh --input FILE [--interface IFACE] [--backend BACKEND]

Convert an already exported `wpa_cli scan_results` text file to Wifi-Kit
wifi-kit.scan.v0 JSON.

This script does not call wpa_cli, does not trigger scans, does not read /etc,
and does not modify networking.
EOF
}

input=""
iface="wlan0"
backend="wpa_cli"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --input)
      input="${2:-}"
      [ -n "$input" ] || {
        echo "error=missing-input" >&2
        exit 2
      }
      shift 2
      ;;
    --interface)
      iface="${2:-}"
      [ -n "$iface" ] || {
        echo "error=missing-interface" >&2
        exit 2
      }
      shift 2
      ;;
    --backend)
      backend="${2:-}"
      [ -n "$backend" ] || {
        echo "error=missing-backend" >&2
        exit 2
      }
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error=unknown-argument arg=$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$input" ]; then
  echo "error=input-required" >&2
  usage >&2
  exit 2
fi

if [ ! -f "$input" ]; then
  echo "error=input-not-found path=$input" >&2
  exit 2
fi

node_bin=""
for candidate in node node.exe; do
  if command -v "$candidate" >/dev/null 2>&1; then
    node_bin="$candidate"
    break
  fi
done

if [ -z "$node_bin" ]; then
  echo "error=node-required-for-conversion" >&2
  exit 2
fi

"$node_bin" - "$input" "$iface" "$backend" <<'NODE'
const fs = require('fs');
const inputPath = process.argv[2];
const iface = process.argv[3];
const backend = process.argv[4];
const text = fs.readFileSync(inputPath, 'utf8');

function channelFromFrequency(freq) {
  if (!Number.isFinite(freq)) return null;
  if (freq === 2484) return 14;
  if (freq >= 2412 && freq <= 2472) return Math.floor((freq - 2407) / 5);
  return null;
}

function securityFromFlags(flags) {
  if (!flags) return 'unknown';
  if (flags.includes('SAE') || flags.includes('WPA3')) return 'WPA3';
  if (flags.includes('WPA2')) return 'WPA2';
  if (flags.includes('WPA')) return 'WPA';
  if (flags.includes('WEP')) return 'WEP';
  if (flags.includes('ESS')) return 'open';
  return 'unknown';
}

const networks = [];
const lines = text.split(/\r?\n/);
for (const rawLine of lines) {
  const line = rawLine.trimEnd();
  if (!line) continue;
  if (/^bssid\s*\/\s*frequency\s*\//i.test(line)) continue;

  const tabParts = line.split('\t');
  if (tabParts.length < 4) continue;

  const bssid = tabParts[0].trim();
  const frequency = Number.parseInt(tabParts[1].trim(), 10);
  const signal = Number.parseInt(tabParts[2].trim(), 10);
  const flags = tabParts[3].trim();
  const ssid = tabParts.slice(4).join('\t');
  const hidden = ssid.length === 0;

  networks.push({
    ssid,
    ssid_hash: '',
    signal_dbm: Number.isFinite(signal) ? signal : null,
    channel: channelFromFrequency(frequency),
    frequency: Number.isFinite(frequency) ? frequency : null,
    security: securityFromFlags(flags),
    hidden,
    bssid
  });
}

const output = {
  schema: 'wifi-kit.scan.v0',
  metadata: {
    description: 'Converted from exported wpa_cli scan_results text. No secrets.',
    source: 'wpa_cli scan_results export',
    backend,
    interface: iface,
    refresh_attempted: false
  },
  networks
};

process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
NODE