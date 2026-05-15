# Wifi-Kit candidate matching plan

Status: fixture-only and plan-only. No network action is performed.

Candidate matching compares two local data sources:

- the Wifi-Kit runtime registry fixture;
- a read-only scan fixture.

The goal is to identify which known or validated networks are currently visible
and which one would be the best boot/connect-safe candidate later.

## Inputs

Registry fixture:

```text
modules/wifi-kit/fixtures/registry/known-networks.fixture.json
```

Scan fixture:

```text
modules/wifi-kit/fixtures/scan/scan-results.fixture.json
```

Both fixtures are repository-local test data. They are not runtime state and are
not installed under `/etc`.

## Matching rules

The prototype intentionally stays simple:

1. Ignore hidden scan entries without an SSID.
2. Match visible scan entries against registry entries by `ssid`.
3. Report known visible networks.
4. Report validated visible networks.
5. Sort validated visible candidates by priority, then favorite flag, then signal.
6. Report the first sorted candidate as the best candidate.
7. Report whether the fallback network is visible.
8. Report inconsistencies instead of fixing data.

## Safety guarantees

The prototype:

- reads only local fixtures;
- does not scan Wi-Fi;
- does not call wpa_cli;
- does not call hostapd or dnsmasq;
- does not connect to Wi-Fi;
- does not write configuration;
- does not store or print secrets;
- does not expose UI actions.
## Real scan export conversion

A future field test can use an already exported `wpa_cli scan_results` text file
without triggering a new scan. The converter is intentionally file-only:

```sh
wpa_cli -i wlan0 scan_results > /tmp/wifi-kit-scan-results.txt
sh modules/wifi-kit/prototype/wpa-cli-scan-results-to-json.sh \
  --input /tmp/wifi-kit-scan-results.txt \
  > /tmp/wifi-kit-scan-results.json
sh modules/wifi-kit/prototype/candidate-match-plan.sh \
  --scan /tmp/wifi-kit-scan-results.json
```

The converter does not call `wpa_cli`, does not trigger `wpa_cli scan`, does not
read `/etc`, and does not modify networking. It only parses a text file that was
exported beforehand.
