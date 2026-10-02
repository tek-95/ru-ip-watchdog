#!/bin/bash
# ru-ip-watchdog: если снаружи виден русский IP — отрезать AI-клиентам и финтехам сеть
# (домены -> 127.0.0.1 в /etc/hosts + pf-блок IP-диапазонов), не убивая процессы.
# Запускается launchd (root). Проверка каждые CHECK_INTERVAL секунд.
# Лог: /Users/macbook/Library/Logs/ru-ip-watchdog.log

LOG="/Users/macbook/Library/Logs/ru-ip-watchdog.log"
LOGERR="/Users/macbook/Library/Logs/ru-ip-watchdog.err"
HOSTS=/etc/hosts
BEGIN="# ru-ip-watchdog:begin"
END="# ru-ip-watchdog:end"
CHECK_INTERVAL=10
DOMAINS="openai.com api.openai.com auth.openai.com auth0.openai.com platform.openai.com status.openai.com cdn.openai.com chatgpt.com ab.chatgpt.com chatgpt-live.fastedge.io oaistatic.com oaiusercontent.com anthropic.com api.anthropic.com console.anthropic.com claude.ai claude.com claude.site statsig.anthropic.com statsig.com api.statsig.com sentry.io o1137834.ingest.sentry.io gemini.google.com bard.google.com aistudio.google.com generativelanguage.googleapis.com alkalimakersuite-pa.googleapis.com wise.com transferwise.com airbnb.com api.zebra.airbnb.com muscache.com revolut.com www.revolut.com api.revolut.com app.revolut.com"

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"Codex Guard\"" >/dev/null 2>&1; }

exit_country() {
    local loc
    loc=$(curl -s --max-time 6 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | awk -F= '/^loc=/{print $2}')
    [ -z "$loc" ] && loc=$(curl -s --max-time 6 https://ipinfo.io/json 2>/dev/null | sed -n 's/.*"country": "\([A-Z]*\)".*/\1/p' | head -1)
    echo "$loc"
}

is_blocked() { grep -qF "$BEGIN" "$HOSTS" 2>/dev/null; }

# Выход RU: hosts-блок + (второй слой) pf-блокировка IP-диапазонов сервисов,
# чтобы DoH-браузеры и живые соединения тоже не проходили.
PF_ANCHOR="ru-ip-watchdog"
# Anthropic (AS399358, 160.79.104.0/21), OpenAI (8.47.69.0/24, 8.6.112.0/24 и их AS20473-диапазоны),
# Wise (104.18.x via Cloudflare — общий, не блокируем), поэтому только прямые диапазоны:
BLOCK_CIDRS="160.79.104.0/21 8.47.69.0/24 8.6.112.0/24"

pf_block_on() {
    pfctl -a "$PF_ANCHOR" -f - 2>/dev/null <<EOF
block drop out quick proto tcp from any to { $BLOCK_CIDRS }
EOF
    log "pf: BLOCK $BLOCK_CIDRS"
}

pf_block_off() {
    echo "" | pfctl -a "$PF_ANCHOR" -f - 2>/dev/null
    log "pf: rules flushed"
}

block_on() {
    cp "$HOSTS" /etc/hosts.ru-ip-watchdog.bak
    {
        echo "$BEGIN"
        for d in $DOMAINS; do
            echo "127.0.0.1 $d"
            echo "::1 $d"
        done
        echo "$END"
    } >> "$HOSTS"
    dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null
    pf_block_on
    log "exit=RU — BLOCKED (hosts+pf)"
    notify "Русский IP — сеть OpenAI/Anthropic отрезана"
}

block_off() {
    sed -i '' "/^# ru-ip-watchdog:begin$/,/^# ru-ip-watchdog:end$/d" "$HOSTS"
    dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null
    pf_block_off
    log "exit not RU — UNBLOCKED (hosts+pf)"
    notify "Выход не RU — сеть восстановлена"
}

log "ru-ip-watchdog started (pid $$, mode: hosts+pf)"
notify "Страж запущен"

while true; do
    LOC=$(exit_country)

    if [ -z "$LOC" ]; then
        log "no connectivity, idle"
        sleep "$CHECK_INTERVAL"
        continue
    fi

    if [ "$LOC" != "RU" ]; then
        # выход не русский: все 3 разрешённых случая — сеть открыта
        is_blocked && block_off
    else
        is_blocked || block_on
    fi
    sleep "$CHECK_INTERVAL"
done
