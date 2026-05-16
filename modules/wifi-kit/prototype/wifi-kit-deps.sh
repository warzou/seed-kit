#!/bin/sh
set -eu

backend="${WIFI_KIT_BACKEND:-auto}"
mode=""

usage() {
  cat <<'EOF'
Usage:
  wifi-kit-deps.sh check [--backend auto|raspberrypi-networkmanager|raspberrypi-wpa]
  wifi-kit-deps.sh plan [--backend auto|raspberrypi-networkmanager|raspberrypi-wpa]
  wifi-kit-deps.sh install --dry-run [--backend auto|raspberrypi-networkmanager|raspberrypi-wpa]
  wifi-kit-deps.sh install --apply

Declarative dependency audit and planning only. Wifi-Kit declares what it
needs; Seed-Kit core will orchestrate any future real package installation.
The current implementation never installs packages, never starts services,
never changes Wi-Fi, and never reads secrets.
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

find_tool() {
  tool=$1
  if command -v "$tool" >/dev/null 2>&1; then
    command -v "$tool"
    return 0
  fi
  for dir in /usr/sbin /sbin /usr/bin /bin; do
    if [ -x "$dir/$tool" ]; then
      printf '%s\n' "$dir/$tool"
      return 0
    fi
  done
  return 1
}

has_tool() {
  find_tool "$1" >/dev/null 2>&1
}

tool_path_or_missing() {
  tool=$1
  find_tool "$tool" 2>/dev/null || printf 'missing'
}

os_field() {
  field=$1
  if [ -r /etc/os-release ]; then
    (
      . /etc/os-release
      eval "printf '%s\n' \"\${$field:-}\""
    )
  fi
}

networkmanager_active() {
  if has_tool nmcli; then
    nm_state="$(nmcli -t -f RUNNING general 2>/dev/null | sed -n '1p' || true)"
    [ "$nm_state" = "running" ] && return 0
  fi

  if has_tool systemctl; then
    systemctl is-active --quiet NetworkManager 2>/dev/null && return 0
  fi

  return 1
}

detect_backend() {
  if [ "$backend" != "auto" ]; then
    printf '%s\n' "$backend"
    return 0
  fi

  os_id="$(os_field ID || true)"
  os_name="$(os_field NAME || true)"
  os_like="$(os_field ID_LIKE || true)"
  case "$os_id $os_name $os_like" in
    *raspbian*|*raspberry*|*debian*)
      if networkmanager_active; then
        printf 'raspberrypi-networkmanager\n'
      elif has_tool wpa_cli || has_tool wpa_supplicant; then
        printf 'raspberrypi-wpa\n'
      else
        printf 'debian-generic\n'
      fi
      ;;
    *)
      printf 'generic-readonly\n'
      ;;
  esac
}

package_for_tool() {
  case "$1" in
    ip) printf 'iproute2' ;;
    iw) printf 'iw' ;;
    wpa_cli|wpa_supplicant) printf 'wpasupplicant' ;;
    ping) printf 'iputils-ping' ;;
    ssh) printf 'openssh-client' ;;
    python3) printf 'python3' ;;
    nmcli) printf 'network-manager' ;;
    systemctl) printf 'systemd' ;;
    dnsmasq) printf 'dnsmasq' ;;
    hostapd) printf 'hostapd' ;;
    *) printf 'unknown' ;;
  esac
}

class_for_tool() {
  selected_backend=$1
  tool=$2

  case "$tool" in
    hostapd|dnsmasq)
      printf 'future-ap'
      return 0
      ;;
    python3|ssh)
      printf 'optional'
      return 0
      ;;
  esac

  if [ "$selected_backend" = "raspberrypi-networkmanager" ]; then
    case "$tool" in
      ip|iw|wpa_cli|wpa_supplicant|ping|nmcli|systemctl)
        printf 'required'
        return 0
        ;;
    esac
  elif [ "$selected_backend" = "raspberrypi-wpa" ]; then
    case "$tool" in
      ip|iw|wpa_cli|wpa_supplicant|ping)
        printf 'required'
        return 0
        ;;
      nmcli|systemctl)
        printf 'optional'
        return 0
        ;;
    esac
  fi

  case "$tool" in
    ip|iw|wpa_cli|wpa_supplicant|ping)
      printf 'required'
      ;;
    *)
      printf 'optional'
      ;;
  esac
}

emit_tool() {
  selected_backend=$1
  tool=$2
  class="$(class_for_tool "$selected_backend" "$tool")"
  package="$(package_for_tool "$tool")"
  path="$(tool_path_or_missing "$tool")"
  if [ "$path" = "missing" ]; then
    state="missing"
  else
    state="present"
  fi

  printf 'tool=%s state=%s class=%s package=%s path=%s\n' "$tool" "$state" "$class" "$package" "$path"
}

emit_all_tools() {
  selected_backend=$1
  for tool in ip iw wpa_cli wpa_supplicant ping ssh python3 nmcli systemctl dnsmasq hostapd; do
    emit_tool "$selected_backend" "$tool"
  done
}

cmd_check() {
  selected_backend="$(detect_backend)"
  printf '[wifi-kit-deps] check\n'
  printf 'mode=read-only\n'
  printf 'module=wifi-kit\n'
  printf 'dependency_contract=declarative\n'
  printf 'install_orchestrator=seed-kit-core\n'
  printf 'network_writes=false\n'
  printf 'packages_installed=false\n'
  printf 'backend=%s\n' "$selected_backend"
  printf 'os_id=%s\n' "$(os_field ID || printf unknown)"
  printf 'networkmanager_active=%s\n' "$(networkmanager_active && printf yes || printf no)"
  emit_all_tools "$selected_backend"
}

cmd_plan() {
  selected_backend="$(detect_backend)"
  printf '[wifi-kit-deps] plan\n'
  printf 'mode=plan-only\n'
  printf 'module=wifi-kit\n'
  printf 'dependency_contract=declarative\n'
  printf 'install_orchestrator=seed-kit-core\n'
  printf 'packages_installed=false\n'
  printf 'backend=%s\n' "$selected_backend"
  emit_all_tools "$selected_backend" | while IFS= read -r line; do
    printf '%s\n' "$line"
    case "$line" in
      *" state=missing "*)
        class=$(printf '%s\n' "$line" | sed 's/.* class=\([^ ]*\).*/\1/')
        package=$(printf '%s\n' "$line" | sed 's/.* package=\([^ ]*\).*/\1/')
        case "$class" in
          required) printf 'would_install_required=%s\n' "$package" ;;
          future-ap) printf 'would_install_future_ap=%s\n' "$package" ;;
          optional) printf 'would_install_optional=%s\n' "$package" ;;
        esac
        ;;
    esac
  done
  printf 'install_apply=refused-until-seed-kit-core-orchestration\n'
}

cmd_install() {
  case "$mode" in
    dry-run)
      printf '[wifi-kit-deps] install --dry-run\n'
      cmd_plan
      ;;
    apply)
      fail "install --apply is intentionally refused; Seed-Kit core must orchestrate future real installs"
      ;;
    *)
      fail "install requires --dry-run; --apply is reserved for a future reviewed implementation"
      ;;
  esac
}

command_name="${1:-}"
[ -n "$command_name" ] || {
  usage
  exit 0
}
shift || true

while [ "$#" -gt 0 ]; do
  case "$1" in
    --backend)
      [ "$#" -gt 1 ] || fail "--backend requires a value"
      backend="$2"
      shift
      ;;
    --dry-run)
      mode="dry-run"
      ;;
    --apply)
      mode="apply"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
  shift
done

case "$backend" in
  auto|raspberrypi-networkmanager|raspberrypi-wpa|debian-generic|generic-readonly) ;;
  *) fail "unsupported backend: $backend" ;;
esac

case "$command_name" in
  check) cmd_check ;;
  plan) cmd_plan ;;
  install) cmd_install ;;
  -h|--help) usage ;;
  *) fail "unknown command: $command_name" ;;
esac
