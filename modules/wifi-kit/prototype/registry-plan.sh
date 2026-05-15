#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  registry-plan.sh [--fixture PATH]

Read a Wifi-Kit registry fixture and print a boot reconnect plan.
This is read-only and plan-only. It performs no network action.
EOF
}

fixture="modules/wifi-kit/fixtures/registry/known-networks.fixture.json"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --fixture)
      fixture="${2:-}"
      [ -n "$fixture" ] || {
        echo "error=missing-fixture" >&2
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

if [ ! -f "$fixture" ]; then
  echo "error=fixture-not-found path=$fixture" >&2
  exit 2
fi

if grep -Eiq '"(psk|passphrase|password|secret|token|private_key|tailscaled\.state|ssh_host_)"[[:space:]]*:' "$fixture"; then
  echo "error=forbidden-secret-like-field path=$fixture" >&2
  exit 3
fi

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

"$node_bin" - "$fixture" <<'NODE'
const fs = require('fs');
const path = process.argv[2];
const data = JSON.parse(fs.readFileSync(path, 'utf8'));
const errors = [];
const networks = Array.isArray(data.known_networks) ? data.known_networks : [];

if (data.schema !== 'wifi-kit.registry.v0') errors.push('schema-unsupported');
if (!networks.length) errors.push('known-networks-empty');

const seen = new Set();
for (const net of networks) {
  if (!net.ssid) errors.push('network-missing-ssid');
  if (!net.ssid_hash) errors.push(`network-missing-ssid-hash:${net.ssid || 'unknown'}`);
  if (typeof net.priority !== 'number') errors.push(`network-invalid-priority:${net.ssid || 'unknown'}`);
  if (net.validated !== true && net.role === 'fallback') errors.push(`fallback-not-validated:${net.ssid || 'unknown'}`);
  if (net.ssid) {
    if (seen.has(net.ssid)) errors.push(`duplicate-ssid:${net.ssid}`);
    seen.add(net.ssid);
  }
}

const fallback = data.fallback_network || null;
if (!fallback || !fallback.ssid) {
  errors.push('fallback-missing');
} else if (!networks.some((net) => net.ssid === fallback.ssid)) {
  errors.push(`fallback-not-in-known-networks:${fallback.ssid}`);
}

const validated = networks
  .filter((net) => net.validated === true)
  .sort((a, b) => {
    const pa = typeof a.priority === 'number' ? a.priority : 9999;
    const pb = typeof b.priority === 'number' ? b.priority : 9999;
    if (pa !== pb) return pa - pb;
    if (a.favorite !== b.favorite) return a.favorite ? -1 : 1;
    return String(a.ssid || '').localeCompare(String(b.ssid || ''));
  });

const primary = validated[0] || null;

console.log('wifi_kit_registry_plan=true');
console.log('mode=read-only');
console.log('network_writes=false');
console.log('real_apply_allowed=false');
console.log('secrets_allowed=false');
console.log(`fixture=${path}`);
console.log(`known_networks=${networks.length}`);
console.log(`validated_networks=${validated.length}`);
console.log(`priority_network=${primary ? primary.ssid : 'none'}`);
console.log(`fallback_network=${fallback && fallback.ssid ? fallback.ssid : 'none'}`);
console.log(`last_success=${data.last_success && data.last_success.ssid ? data.last_success.ssid : 'none'}`);
console.log('boot_candidates=');
validated.forEach((net, index) => {
  console.log(`${index + 1}. ssid=${net.ssid} priority=${net.priority} role=${net.role || 'unknown'} favorite=${net.favorite === true}`);
});
if (errors.length) {
  console.log('registry_errors=');
  errors.forEach((error) => console.log(`- ${error}`));
  process.exitCode = 1;
} else {
  console.log('registry_errors=none');
}
NODE