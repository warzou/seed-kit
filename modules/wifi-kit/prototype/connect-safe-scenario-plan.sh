#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  connect-safe-scenario-plan.sh [--fixture PATH]

Print a plan-only Wifi-Kit connect-safe field scenario summary.
This script reads a local fixture only. It does not call wpa_cli, read /etc,
or modify networking.
EOF
}

fixture="modules/wifi-kit/fixtures/connect-safe/scenario-gl-mt6000-to-sfr.fixture.json"

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

if grep -Eiq '"(psk|passphrase|password|secret_value|token|private_key|tailscaled\.state|ssh_host_)"[[:space:]]*:' "$fixture"; then
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
const fixturePath = process.argv[2];
const data = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
const errors = [];

if (data.schema !== 'wifi-kit.connect-safe-scenario.v0') errors.push('schema-unsupported');
if (data.mode !== 'plan-only') errors.push('mode-must-be-plan-only');
if (!data.current_network || !data.current_network.ssid) errors.push('current-network-missing');
if (!data.target_network || !data.target_network.ssid) errors.push('target-network-missing');
if (!data.rollback_network || !data.rollback_network.ssid) errors.push('rollback-network-missing');
if (data.target_network && data.target_network.secret_source !== 'operator-runtime-only') errors.push('target-secret-source-invalid');
if (!data.persistence || data.persistence.enabled !== false) errors.push('persistence-must-be-false');
if (!data.safety || data.safety.network_writes !== false) errors.push('network-writes-must-be-false');
if (!data.safety || data.safety.real_apply_allowed !== false) errors.push('real-apply-must-be-false');

console.log('wifi_kit_connect_safe_scenario_plan=true');
console.log('mode=plan-only');
console.log('network_writes=false');
console.log('real_apply_allowed=false');
console.log('secrets_in_repo=false');
console.log(`fixture=${fixturePath}`);
console.log(`current_network=${data.current_network ? data.current_network.ssid : 'none'}`);
console.log(`target_network=${data.target_network ? data.target_network.ssid : 'none'}`);
console.log(`rollback_network=${data.rollback_network ? data.rollback_network.ssid : 'none'}`);
console.log(`secret_source=${data.target_network ? data.target_network.secret_source : 'none'}`);
console.log(`persistence=${data.persistence && data.persistence.enabled === false ? 'false' : 'unknown'}`);
console.log(`save_config=${data.persistence && data.persistence.save_config === false ? 'false' : 'unknown'}`);
console.log(`promote_on_success=${data.persistence && data.persistence.promote_on_success === false ? 'false' : 'unknown'}`);
console.log('timeouts=');
const timeouts = data.timeouts || {};
for (const key of ['wait_ip_seconds', 'validation_seconds', 'rollback_seconds', 'rediscovery_seconds']) {
  console.log(`- ${key}=${timeouts[key] ?? 'missing'}`);
}
console.log('next_missing_steps=');
const steps = Array.isArray(data.next_missing_steps) ? data.next_missing_steps : [];
steps.forEach((step) => console.log(`- ${step}`));
if (errors.length) {
  console.log('scenario_errors=');
  errors.forEach((error) => console.log(`- ${error}`));
  process.exitCode = 1;
} else {
  console.log('scenario_errors=none');
}
NODE