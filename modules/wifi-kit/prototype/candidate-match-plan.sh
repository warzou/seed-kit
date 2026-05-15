#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  candidate-match-plan.sh [--registry PATH] [--scan PATH]

Compare Wifi-Kit registry and scan fixtures and print a read-only candidate plan.
This performs no network action and reads local fixture files only.
EOF
}

registry="modules/wifi-kit/fixtures/registry/known-networks.fixture.json"
scan="modules/wifi-kit/fixtures/scan/scan-results.fixture.json"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --registry)
      registry="${2:-}"
      [ -n "$registry" ] || {
        echo "error=missing-registry" >&2
        exit 2
      }
      shift 2
      ;;
    --scan)
      scan="${2:-}"
      [ -n "$scan" ] || {
        echo "error=missing-scan" >&2
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

for file in "$registry" "$scan"; do
  if [ ! -f "$file" ]; then
    echo "error=fixture-not-found path=$file" >&2
    exit 2
  fi
  if grep -Eiq '"(psk|passphrase|password|secret|token|private_key|tailscaled\.state|ssh_host_)"[[:space:]]*:' "$file"; then
    echo "error=forbidden-secret-like-field path=$file" >&2
    exit 3
  fi
done

node_bin=""
for candidate in node node.exe; do
  if command -v "$candidate" >/dev/null 2>&1; then
    node_bin="$candidate"
    break
  fi
done

if [ -z "$node_bin" ]; then
  echo "error=node-required-for-fixture-parse" >&2
  exit 2
fi

"$node_bin" - "$registry" "$scan" <<'NODE'
const fs = require('fs');
const registryPath = process.argv[2];
const scanPath = process.argv[3];
const registry = JSON.parse(fs.readFileSync(registryPath, 'utf8'));
const scan = JSON.parse(fs.readFileSync(scanPath, 'utf8'));
const errors = [];

if (registry.schema !== 'wifi-kit.registry.v0') errors.push('registry-schema-unsupported');
if (scan.schema !== 'wifi-kit.scan.v0') errors.push('scan-schema-unsupported');

const known = Array.isArray(registry.known_networks) ? registry.known_networks : [];
const scanned = Array.isArray(scan.networks) ? scan.networks : [];
if (!known.length) errors.push('known-networks-empty');
if (!scanned.length) errors.push('scan-networks-empty');

const knownBySsid = new Map();
for (const net of known) {
  if (!net.ssid) errors.push('registry-network-missing-ssid');
  if (net.ssid) knownBySsid.set(net.ssid, net);
}

const visible = scanned.filter((net) => net && net.ssid && net.hidden !== true);
const knownVisible = [];
const unknownVisible = [];
for (const item of visible) {
  const registered = knownBySsid.get(item.ssid);
  if (registered) {
    knownVisible.push({ registry: registered, scan: item });
  } else {
    unknownVisible.push(item);
  }
}

const validatedVisible = knownVisible
  .filter((item) => item.registry.validated === true)
  .sort((a, b) => {
    const pa = typeof a.registry.priority === 'number' ? a.registry.priority : 9999;
    const pb = typeof b.registry.priority === 'number' ? b.registry.priority : 9999;
    if (pa !== pb) return pa - pb;
    if (a.registry.favorite !== b.registry.favorite) return a.registry.favorite ? -1 : 1;
    const sa = typeof a.scan.signal_dbm === 'number' ? a.scan.signal_dbm : -999;
    const sb = typeof b.scan.signal_dbm === 'number' ? b.scan.signal_dbm : -999;
    return sb - sa;
  });

const fallback = registry.fallback_network && registry.fallback_network.ssid ? registry.fallback_network : null;
const fallbackMatch = fallback ? knownVisible.find((item) => item.registry.ssid === fallback.ssid) : null;
const best = validatedVisible[0] || null;

console.log('wifi_kit_candidate_match_plan=true');
console.log('mode=read-only');
console.log('network_writes=false');
console.log('real_apply_allowed=false');
console.log('secrets_allowed=false');
console.log(`registry_fixture=${registryPath}`);
console.log(`scan_fixture=${scanPath}`);
console.log(`visible_networks=${visible.length}`);
console.log(`known_visible=${knownVisible.length}`);
console.log(`validated_visible=${validatedVisible.length}`);
console.log(`fallback_visible=${fallbackMatch ? 'true' : 'false'}`);
console.log(`best_candidate=${best ? best.registry.ssid : 'none'}`);
console.log('known_visible_list=');
knownVisible.forEach((item) => {
  console.log(`- ssid=${item.registry.ssid} validated=${item.registry.validated === true} priority=${item.registry.priority} signal_dbm=${item.scan.signal_dbm}`);
});
console.log('validated_boot_candidates=');
validatedVisible.forEach((item, index) => {
  console.log(`${index + 1}. ssid=${item.registry.ssid} priority=${item.registry.priority} favorite=${item.registry.favorite === true} signal_dbm=${item.scan.signal_dbm} role=${item.registry.role || 'unknown'}`);
});
console.log('unknown_visible_list=');
unknownVisible.forEach((item) => {
  console.log(`- ssid=${item.ssid} signal_dbm=${item.signal_dbm}`);
});
if (errors.length) {
  console.log('candidate_match_errors=');
  errors.forEach((error) => console.log(`- ${error}`));
  process.exitCode = 1;
} else {
  console.log('candidate_match_errors=none');
}
NODE