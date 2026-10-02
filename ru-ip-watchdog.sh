#!/bin/bash
# macOS guard. Sourceable for isolated tests; requires root only for mutations.
set -euo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR=${STATE_DIR:-/var/db/ru-ip-watchdog}
HOSTS=${HOSTS:-/etc/hosts}
LOG=${LOG:-/var/log/ru-ip-watchdog.log}
TABLE=ru_ip_watchdog
BEGIN='# ru-ip-watchdog:begin'
END='# ru-ip-watchdog:end'
MODE=auto
INTERVAL=10

log() {
    # Bounded log, with one previous generation retained.
    if [ -f "$LOG" ] && [ "$(stat -f %z "$LOG")" -gt 1048576 ]; then mv -f "$LOG" "$LOG.1"; fi
    printf '%s %s\n' "$(date -u '+%FT%TZ')" "$*" >> "$LOG"
}
load_config() {
    # Never source configuration into a root shell.
    if [ -f "$BASE/config" ]; then
        MODE=$(awk -F= '$1=="MODE" {print $2}' "$BASE/config" | tail -1)
        INTERVAL=$(awk -F= '$1=="INTERVAL" {print $2}' "$BASE/config" | tail -1)
    fi
    case "$MODE" in manual|auto) ;; *) return 1;; esac
    case "$INTERVAL" in ''|*[!0-9]*) return 1;; esac
    [ "$INTERVAL" -ge 2 ] && [ "$INTERVAL" -le 300 ]
}
domains() { awk '!/^#/ && NF {print $1}' "$BASE/domains.txt"; }
base_targets() { awk '!/^#/ && NF {print $1}' "$BASE/cidrs.txt"; }
valid_ip() {
    # plutil parses JSON; address syntax is checked before entering any rule.
    printf '%s\n' "$1" | awk '
      /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {n=split($0,a,"."); for(i=1;i<=n;i++) if(a[i]>255) exit 1; exit 0}
      /^[0-9a-fA-F:]+$/ {if(index($0,":") && length($0)<=39) exit 0; exit 1}
      {exit 1}'
}
probe_cf() {
    local body country ip
    body=$(curl --fail --silent --show-error --noproxy '*' --connect-timeout 3 --max-time 6 https://www.cloudflare.com/cdn-cgi/trace) || return 1
    country=$(printf '%s\n' "$body" | awk -F= '$1=="loc" {print $2}')
    ip=$(printf '%s\n' "$body" | awk -F= '$1=="ip" {print $2}')
    [[ "$country" =~ ^[A-Z]{2}$ ]] && [ "$country" != XX ] && [ "$country" != ZZ ] && valid_ip "$ip" || return 1
    printf '%s|%s\n' "$country" "$ip"
}
probe_ipinfo() {
    local body country ip
    body=$(curl --fail --silent --show-error --noproxy '*' --connect-timeout 3 --max-time 6 https://ipinfo.io/json) || return 1
    country=$(printf '%s' "$body" | plutil -extract country raw -o - -) || return 1
    ip=$(printf '%s' "$body" | plutil -extract ip raw -o - -) || return 1
    [[ "$country" =~ ^[A-Z]{2}$ ]] && [ "$country" != XX ] && [ "$country" != ZZ ] && valid_ip "$ip" || return 1
    printf '%s|%s\n' "$country" "$ip"
}
consensus() {
    local a="$1" b="$2"
    if [[ "$a" == RU\|* || "$b" == RU\|* ]]; then echo RU
    elif [ -n "$a" ] && [ "$a" = "$b" ] && [[ "$a" =~ ^[A-Z]{2}\| ]]; then echo "$a"
    else echo UNKNOWN; fi
}
write_hosts() {
    local on="$1" tmp d
    tmp=$(mktemp "${HOSTS}.watchdog.XXXXXX") || return 1
    if ! awk -v begin="$BEGIN" -v end="$END" '
       $0==begin {skip=1;next} $0==end {skip=0;next} !skip {print}
       END {if(skip) exit 2}' "$HOSTS" > "$tmp"; then rm -f "$tmp"; return 1; fi
    if [ "$on" = 1 ]; then
        { echo "$BEGIN"; while IFS= read -r d; do printf '127.0.0.1 %s\n::1 %s\n' "$d" "$d"; done < <(domains); echo "$END"; } >> "$tmp"
    fi
    # Preserve existing inode, owner, ACL and mode. Daemon is serialized by lock.
    cat "$tmp" > "$HOSTS" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
    if [ "$on" = 1 ]; then grep -qF "$BEGIN" "$HOSTS" || return 1
    else ! grep -qF "$BEGIN" "$HOSTS" || return 1; fi
    dscacheutil -flushcache
    killall -HUP mDNSResponder 2>/dev/null || true
}
collect_targets() {
    local d address tmp
    tmp=$(mktemp "$STATE_DIR/targets.XXXXXX") || return 1
    { base_targets; [ ! -f "$STATE_DIR/targets" ] || cat "$STATE_DIR/targets"; } > "$tmp"
    # dig bypasses hosts. Keep earlier addresses to cover established connections.
    while IFS= read -r d; do
        for family in A AAAA; do
            while IFS= read -r address; do
                if valid_ip "$address" && [ "$address" != '127.0.0.1' ] && [ "$address" != '::1' ]; then printf '%s\n' "$address" >> "$tmp"; fi
            done < <(dig +time=1 +tries=1 +short "$d" "$family" 2>/dev/null || true)
        done
    done < <(domains)
    sort -u "$tmp" > "$STATE_DIR/targets.new"
    rm -f "$tmp"
    mv "$STATE_DIR/targets.new" "$STATE_DIR/targets"
    # Persist discovered addresses for the next boot's initial rules.
    cat "$STATE_DIR/targets" > /etc/pf.anchors/ru-ip-watchdog-addresses
}
ensure_pf() {
    local output token boot saved_boot
    pfctl -sr 2>/dev/null | grep -Eq '^block drop out quick from any to <ru_ip_watchdog>' || {
        log 'ERROR: watchdog rule is absent from active main PF ruleset'; return 1;
    }
    boot=$(sysctl -n kern.boottime)
    saved_boot=''
    if [ -f "$STATE_DIR/pf-token" ]; then saved_boot=$(sed -n '2p' "$STATE_DIR/pf-token"); fi
    if [ "$saved_boot" != "$boot" ] || ! pfctl -s info 2>/dev/null | grep -q 'Status: Enabled'; then
        output=$(pfctl -E 2>&1) || return 1
        token=$(printf '%s\n' "$output" | awk '/Token/ {print $NF}')
        [ -n "$token" ] || return 1
        printf '%s\n%s\n' "$token" "$boot" > "$STATE_DIR/pf-token"
    fi
}
set_block() {
    local on="$1"
    if [ "$on" = 1 ]; then
        # Hosts still blocks new system-DNS requests if PF is broken.
        write_hosts 1 || return 1
        ensure_pf || return 1
        pfctl -t "$TABLE" -T replace -f "$STATE_DIR/targets" || return 1
        # All protocols, both address families. Kill destination states only.
        while IFS= read -r address; do
            if [[ "$address" == *:* ]]; then pfctl -k ::/0 -k "$address" >/dev/null
            else pfctl -k 0.0.0.0/0 -k "$address" >/dev/null; fi
        done < "$STATE_DIR/targets"
        pfctl -t "$TABLE" -T show 2>/dev/null | grep -q '[0-9a-f]' || return 1
    else
        ensure_pf || return 1
        # Remove hosts first, PF last; a partial failure stays blocked.
        write_hosts 0 || return 1
        pfctl -t "$TABLE" -T flush >/dev/null || return 1
        [ -z "$(pfctl -t "$TABLE" -T show 2>/dev/null)" ] || return 1
    fi
}
write_status() {
    local state="$1" reason="$2" evidence="$3"
    printf 'state=%s\nreason=%s\nevidence=%s\nmode=%s\nchecked_at=%s\n' "$state" "$reason" "$evidence" "$MODE" "$(date -u '+%FT%TZ')" > "$STATE_DIR/status.new"
    mv "$STATE_DIR/status.new" "$STATE_DIR/status"
}
approved() {
    local evidence="$1" stamp proof now
    [ -f "$STATE_DIR/approval" ] || return 1
    read -r stamp proof < "$STATE_DIR/approval" || return 1
    now=$(date +%s)
    [[ "$stamp" =~ ^[0-9]+$ ]] && [ "$proof" = "$evidence" ] && [ "$now" -ge "$stamp" ] && [ $((now-stamp)) -lt 900 ]
}
needs_block() {
    local evidence="$1" previous="$2"
    [ "$evidence" != UNKNOWN ] && [ "$evidence" != RU ] && [ "$evidence" = "$previous" ] || return 0
    if [ "$MODE" = auto ] || approved "$evidence"; then return 1; fi
    return 0
}
main() {
    local command=${1:---run} previous='' last='' evidence a b on reason count=0 refresh_pid=''
    if [ "$command" = --status ]; then
        cat "$STATE_DIR/status"; echo 'Live PF:'; pfctl -s info; pfctl -t "$TABLE" -T show; return
    fi
    [ "$(id -u)" = 0 ] || { echo 'Run with sudo.' >&2; return 1; }
    umask 077
    mkdir -p "$STATE_DIR"
    load_config || { echo 'Invalid configuration' >&2; return 1; }
    if [ "$command" = --approve ]; then
        a=$(probe_cf || true); b=$(probe_ipinfo || true); evidence=$(consensus "$a" "$b")
        [ "$evidence" != UNKNOWN ] && [ "$evidence" != RU ] || { echo 'Approval refused: probes fail, disagree, or report RU.' >&2; return 1; }
        printf '%s %s\n' "$(date +%s)" "$evidence" > "$STATE_DIR/approval.new"
        mv "$STATE_DIR/approval.new" "$STATE_DIR/approval"
        echo 'Approved for at most 15 minutes. This verifies probe routes, not every service route.'; return
    fi
    [ "$command" = --run ] || { echo 'Usage: --run | --status | --approve' >&2; return 1; }
    if ! mkdir "$STATE_DIR/lock" 2>/dev/null; then
        # Remove only a lock whose recorded process no longer exists.
        local owner=''
        [ ! -f "$STATE_DIR/lock/pid" ] || owner=$(cat "$STATE_DIR/lock/pid")
        [[ "$owner" =~ ^[0-9]+$ ]] && ! kill -0 "$owner" 2>/dev/null || { echo 'Another guard holds the lock.' >&2; return 1; }
        rm -f "$STATE_DIR/lock/pid"; rmdir "$STATE_DIR/lock"; mkdir "$STATE_DIR/lock"
    fi
    echo "$$" > "$STATE_DIR/lock/pid"
    trap '[ -z "$refresh_pid" ] || kill "$refresh_pid" 2>/dev/null || true; rm -f "$STATE_DIR/lock/pid"; rmdir "$STATE_DIR/lock"' EXIT
    # Never begin in an assumed-safe state. Restore block after crashes/restarts.
    [ -f "$STATE_DIR/targets" ] || base_targets > "$STATE_DIR/targets"
    set_block 1 || { write_status ERROR startup UNKNOWN; return 1; }
    write_status BLOCKED startup UNKNOWN
    while :; do
        a=$(probe_cf || true); b=$(probe_ipinfo || true); evidence=$(consensus "$a" "$b")
        on=1; reason=unverified
        if ! needs_block "$evidence" "$previous"; then on=0; reason=approved; fi
        if [ "$evidence" = RU ] || [ "$evidence" = UNKNOWN ] || [ "$evidence" != "$previous" ]; then rm -f "$STATE_DIR/approval"; fi
        # Enforce rules every cycle (not just when a hosts marker changes).
        if ! set_block "$on"; then
            write_status ERROR enforcement "$evidence"; log 'ERROR: enforcement failed; service will restart with block'; return 1
        fi
        if [ "$on" = 1 ]; then state=BLOCKED; else state=OPEN; fi
        write_status "$state" "$reason" "$evidence"
        if [ "$last" != "$state:$evidence" ]; then log "$state evidence=$evidence mode=$MODE"; last="$state:$evidence"; fi
        # Refresh after blocking is installed. Failures do not erase old addresses.
        if [ $((count%6)) = 0 ] && { [ -z "$refresh_pid" ] || ! kill -0 "$refresh_pid" 2>/dev/null; }; then
            collect_targets & refresh_pid=$!
        fi
        count=$((count+1)); previous="$evidence"
        sleep "$INTERVAL"
    done
}
if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
