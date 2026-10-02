#!/bin/bash
# Parse only. NEVER enable PF or load live rules.
set -euo pipefail
BASE="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '203.0.113.99\n2001:db8::99\n' > "$TMP/targets"
awk -f "$BASE/pf-config.awk" /etc/pf.conf | sed "s|/etc/pf.anchors/ru-ip-watchdog-addresses|$TMP/targets|g" > "$TMP/pf.conf"
sudo -n pfctl -nf "$TMP/pf.conf"
