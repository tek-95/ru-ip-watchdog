#!/bin/bash
set -euo pipefail
BASE="$(cd "$(dirname "$0")/.." && pwd)"
source "$BASE/ru-ip-watchdog.sh"
BASE="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
HOSTS="$TMP/hosts"
STATE_DIR="$TMP/state"
mkdir "$STATE_DIR"
dscacheutil() { :; }
killall() { :; }
date() { if [ "${1:-}" = +%s ]; then echo 1000; else command date "$@"; fi; }
assert_eq() { [ "$1" = "$2" ] || { echo "FAIL expected '$2' got '$1'"; exit 1; }; }
assert_eq "$(consensus 'DE|1.2.3.4' 'DE|1.2.3.4')" 'DE|1.2.3.4'
assert_eq "$(consensus 'DE|1.2.3.4' 'TR|1.2.3.4')" UNKNOWN
assert_eq "$(consensus 'DE|1.2.3.4' 'DE|1.2.3.5')" UNKNOWN
assert_eq "$(consensus 'DE|1.2.3.4' '')" UNKNOWN
assert_eq "$(consensus 'RU|1.2.3.4' '')" RU
assert_eq "$(consensus '' 'RU|1.2.3.4')" RU
MODE=auto
needs_block UNKNOWN UNKNOWN || exit 1
needs_block RU RU || exit 1
needs_block 'DE|1.2.3.4' 'TR|1.2.3.4' || exit 1
if needs_block 'DE|1.2.3.4' 'DE|1.2.3.4'; then echo 'FAIL auto must release matching evidence'; exit 1; fi
MODE=manual
needs_block 'DE|1.2.3.4' 'DE|1.2.3.4' || exit 1
echo '950 DE|1.2.3.4' > "$STATE_DIR/approval"
if needs_block 'DE|1.2.3.4' 'DE|1.2.3.4'; then exit 1; fi
needs_block 'DE|1.2.3.5' 'DE|1.2.3.5' || exit 1
echo '100 DE|1.2.3.4' > "$STATE_DIR/approval"
needs_block 'DE|1.2.3.4' 'DE|1.2.3.4' || exit 1
echo '2000 DE|1.2.3.4' > "$STATE_DIR/approval"
needs_block 'DE|1.2.3.4' 'DE|1.2.3.4' || exit 1
printf '127.0.0.1 localhost\n192.0.2.1 user.example\n' > "$HOSTS"
cp "$HOSTS" "$TMP/original"
write_hosts 1
write_hosts 1
assert_eq "$(grep -c '^# ru-ip-watchdog:begin$' "$HOSTS")" 1
write_hosts 0
cmp "$HOSTS" "$TMP/original"
printf '\n# ru-ip-watchdog:begin\n192.0.2.2 important.user\n' >> "$HOSTS"
cp "$HOSTS" "$TMP/invalid"
if write_hosts 0; then echo 'FAIL malformed section must not be removed'; exit 1; fi
cmp "$HOSTS" "$TMP/invalid"
# An enforcement failure must not report BLOCKED or attempt to flush firewall.
printf '127.0.0.1 localhost\n' > "$HOSTS"
ensure_pf() { return 1; }
pfctl() { echo 'FAIL firewall should not be reached'; exit 1; }
if set_block 1; then echo 'FAIL enforcement error was suppressed'; exit 1; fi
grep -qF "$BEGIN" "$HOSTS"
valid_ip 203.0.113.1
valid_ip 2001:db8::1
if valid_ip 999.0.0.1 || valid_ip '1.2.3.4; echo bad'; then exit 1; fi
printf 'All shell policy, hosts preservation and enforcement-failure checks passed.\n'
# PF insertion is idempotent and precedes quick passes without discarding NAT.
printf 'nat-anchor "vendor/*"\npass out quick all\n' > "$TMP/pf"
awk -f "$BASE/pf-config.awk" "$TMP/pf" > "$TMP/pf.once"
awk -f "$BASE/pf-config.awk" "$TMP/pf.once" > "$TMP/pf.twice"
cmp "$TMP/pf.once" "$TMP/pf.twice"
assert_eq "$(sed -n '1p' "$TMP/pf.once")" 'nat-anchor "vendor/*"'
assert_eq "$(sed -n '3p' "$TMP/pf.once")" 'block drop out quick from any to <ru_ip_watchdog> # ru-ip-watchdog:pf'
