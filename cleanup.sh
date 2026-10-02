#!/bin/bash
# Explicit uninstall only; do not run this on daemon failure.
set -euo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BASE/ru-ip-watchdog.sh"
[ "$(id -u)" = 0 ] || exit 1
write_hosts 0
# Leave unrelated PF rules/anchors alone; never pfctl -d or -F all.
pfctl -t "$TABLE" -T flush
TMP=$(mktemp /etc/pf.conf.watchdog.XXXXXX)
trap 'rm -f "$TMP"' EXIT
awk '!/# ru-ip-watchdog:pf$/' /etc/pf.conf > "$TMP"
pfctl -nf "$TMP"
cat "$TMP" > /etc/pf.conf
# Keep the empty live table until reboot to avoid reloading other VPN anchors.
if [ -f "$STATE_DIR/pf-token" ]; then
    token=$(head -1 "$STATE_DIR/pf-token")
    [[ "$token" =~ ^[0-9]+$ ]] || exit 1
    if ! pfctl -X "$token"; then echo 'PF token is no longer valid (for example, after reboot); other firewall references were preserved.' >&2; fi
fi
rm -f /etc/pf.anchors/ru-ip-watchdog-addresses
