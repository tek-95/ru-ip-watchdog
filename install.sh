#!/bin/bash
set -euo pipefail
DIR='/Library/Application Support/ru-ip-watchdog'
STATE=/var/db/ru-ip-watchdog
PLIST=/Library/LaunchDaemons/com.user.ru-ip-watchdog.plist
PFCONF=/etc/pf.conf
TAG='# ru-ip-watchdog:pf'
RAW='https://raw.githubusercontent.com/tek-95/ru-ip-watchdog/main'
SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
if [ "${1:-}" = --uninstall ]; then
    sudo launchctl bootout system "$PLIST" 2>/dev/null || true
    # Installed daemon owns only its table and marked hosts section.
    sudo bash "$DIR/cleanup.sh"
    sudo rm -f "$PLIST"
    sudo rm -rf "$DIR" "$STATE"
    echo 'Removed. Logs remain in /var/log/ru-ip-watchdog.log.'
    exit
fi
[ -z "${1:-}" ] || { echo 'Usage: install.sh [--uninstall]' >&2; exit 1; }
for f in ru-ip-watchdog.sh cleanup.sh domains.txt cidrs.txt config.example com.user.ru-ip-watchdog.plist install.sh pf-config.awk; do
    if [ -f "$SRC/$f" ]; then cp "$SRC/$f" "$STAGE/$f"
    else curl --fail --silent --show-error --proto '=https' --tlsv1.2 "$RAW/$f" -o "$STAGE/$f"; fi
done
bash -n "$STAGE/ru-ip-watchdog.sh" "$STAGE/cleanup.sh"
plutil -lint "$STAGE/com.user.ru-ip-watchdog.plist"
# Prepare and validate BEFORE stopping the installed guard.
awk '!/^#/ && NF {print $1}' "$STAGE/cidrs.txt" > "$STAGE/addresses"
# Insert the direct quick block before any existing filtering rule, after NAT.
awk -f "$STAGE/pf-config.awk" "$PFCONF" > "$STAGE/pf.conf"
sudo -v
sudo mkdir -p /etc/pf.anchors "$STATE"
sudo chmod 700 "$STATE"
# Seed persistent boot rules. Keep previously resolved addresses on upgrades.
if sudo test -f "$STATE/targets"; then sudo cat "$STATE/targets" >> "$STAGE/addresses"; fi
sudo install -o root -g wheel -m 600 "$STAGE/addresses" /etc/pf.anchors/ru-ip-watchdog-addresses
sudo pfctl -nf "$STAGE/pf.conf"
echo 'Installing PF rules reloads the main ruleset. Reconnect other VPNs afterward if needed.'
sudo launchctl bootout system "$PLIST" 2>/dev/null || true
sudo mkdir -p "$DIR"
sudo chmod 755 "$DIR"
for f in ru-ip-watchdog.sh cleanup.sh install.sh domains.txt cidrs.txt; do sudo install -o root -g wheel -m 644 "$STAGE/$f" "$DIR/$f"; done
if ! sudo test -f "$DIR/config"; then sudo install -o root -g wheel -m 600 "$STAGE/config.example" "$DIR/config"; fi
sudo install -o root -g wheel -m 644 "$STAGE/com.user.ru-ip-watchdog.plist" "$PLIST"
sudo cp "$PFCONF" "$STATE/pf.conf.before-install"
sudo install -o root -g wheel -m 644 "$STAGE/pf.conf" "$PFCONF"
sudo pfctl -f "$PFCONF"
sudo rm -rf "$STATE/lock"
sudo launchctl bootstrap system "$PLIST"
echo 'Installed. Check actual health: sudo bash "/Library/Application Support/ru-ip-watchdog/ru-ip-watchdog.sh" --status'
echo 'Logs: /var/log/ru-ip-watchdog.log. Default mode: auto.'
