# Fresh node flow (real machine)

Use this flow on an empty/new machine after copying `seed-kit.sh`:

```sh
# on your machine
scp seed-kit.sh warzy@rpi-edge-audit:/home/warzy/seed-kit.sh
ssh warzy@rpi-edge-audit 'cd /home/warzy && rm -rf lib modules backends && sh seed-kit.sh'
```

At the `initialize local runtime structure?` prompt, answer `y`.

Re-run in the same dir:

```sh
sh seed-kit.sh --plan
sh seed-kit.sh --modules
sh seed-kit.sh --apply
```

Expected: bootstrap runtime is initialized and those commands print meaningful output.

Use this for module execution:

```sh
sh seed-kit.sh --apply --modules=git
```

`--apply --modules=git` runs a minimal git path on Debian-like systems; add `-y` for auto-confirm.

To fetch the repo-backed `wifi-kit` module without cloning the full monorepo:

```sh
sh seed-kit.sh --fetch-module=wifi-kit
cd ~/seed-kit-wifi-kit
sh seed-kit.sh --modules
sh seed-kit.sh --plan
sh seed-kit.sh --apply --modules=wifi-kit
```

This uses git sparse checkout, writes to `~/seed-kit-wifi-kit`, and does not overwrite an existing directory.

To let Seed-Kit prepare Git first when needed, then fetch `wifi-kit`:

```sh
sh seed-kit.sh --install-module=wifi-kit
```

This still uses SAFE confirmations and does not run the `wifi-kit` prototype automatically.
