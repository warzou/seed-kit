#!/bin/sh

module_homer_plan() {
  echo "- lightweight static dashboard for minimal resilient nodes"
  echo "- host-level path: no Docker and no Homepage dependency"
  echo "- intended for low-RAM, rescue, nomadic, and Raspberry Pi Zero 2 W nodes"
  echo "- V1 static placeholder path: /srv/seed-kit/homer/index.html"
  echo "- no Caddy config, no DNS, no certificates, no firewall changes"
}

module_homer_apply() {
  homer_dir="/srv/seed-kit/homer"
  homer_index="$homer_dir/index.html"

  apply_step "homer: checking static placeholder"
  if [ -f "$homer_index" ]; then
    apply_skip "homer placeholder already present at $homer_index"
    ui_line "Next manual step: configure Caddy manually with root * /srv/seed-kit/homer and file_server"
    return 0
  fi

  if ! apply_safe_confirm; then
    return 2
  fi

  if ! require_sudo_for_system_action "homer static dashboard deploy" "sh seed-kit.sh --apply --modules=homer"; then
    return 2
  fi

  if [ "$(id -u)" -eq 0 ]; then
    SUDO=
  else
    SUDO=sudo
  fi

  apply_step "homer: create static directory"
  if ! $SUDO mkdir -p "$homer_dir"; then
    echo "[homer] failed to create $homer_dir" >&2
    return 3
  fi

  apply_step "homer: write static placeholder"
  if ! $SUDO sh -c 'cat > "$1"' sh "$homer_index" <<'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Seed-Kit Homer placeholder</title>
  <style>
    body { margin: 2rem; font-family: sans-serif; line-height: 1.5; color: #1f2933; background: #f7f4ed; }
    main { max-width: 42rem; }
    h1 { margin-bottom: 0.25rem; }
    .muted { color: #52606d; }
    code { background: #e8e2d4; padding: 0.1rem 0.25rem; border-radius: 0.25rem; }
  </style>
</head>
<body>
  <main>
    <h1>Seed-Kit Homer placeholder</h1>
    <p class="muted">Minimal resilient node</p>
    <p>This local static page marks the future Homer dashboard location.</p>
    <p>No external assets, no Docker, no DNS, and no certificate automation are configured here.</p>
    <p>Static root: <code>/srv/seed-kit/homer</code></p>
  </main>
</body>
</html>
EOF
  then
    echo "[homer] failed to write $homer_index" >&2
    return 4
  fi

  apply_step "homer: set safe permissions"
  if ! $SUDO chmod 755 /srv/seed-kit "$homer_dir"; then
    echo "[homer] failed to set directory permissions" >&2
    return 5
  fi
  if ! $SUDO chmod 644 "$homer_index"; then
    echo "[homer] failed to set file permissions" >&2
    return 6
  fi

  apply_step "homer: deployed static placeholder at $homer_index"
  ui_line "Next manual step: configure Caddy manually with root * /srv/seed-kit/homer and file_server"
}
