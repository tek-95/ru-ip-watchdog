# ru-ip-watchdog

> **Don't play Russian Roulette with your accounts.**

[🇷🇺 Русская версия](#ru-ip-watchdog-по-русски)

Traveling to Russia? OpenAI, Claude, Gemini, Wise, Revolut and Airbnb all restrict access from Russian IPs — and some terminate accounts over it. ru-ip-watchdog lets you comply with those restrictions without risking your accounts: while your exit IP is Russian, these services are simply unreachable from your machine; the moment it's not, everything unblocks itself. No apps are killed — they just lose connectivity until it's safe.

## Install (macOS) — one line

Open **Terminal** (press `Cmd + Space`, type "Terminal", press Enter), copy-paste this line and press Enter:

```sh
curl -fsSL https://raw.githubusercontent.com/tek-95/ru-ip-watchdog/main/install.sh | bash
```

Asks for your Mac password once (typing is invisible — that's normal). Done.

## Install (Windows) — one line

Open **PowerShell as administrator** (press `Win`, type "PowerShell", right-click → Run as administrator), copy-paste this line and press Enter:

```powershell
irm https://raw.githubusercontent.com/tek-95/ru-ip-watchdog/main/install.ps1 | iex
```

### One more small thing (optional, but recommended)

In Chrome, turn off "Use secure DNS" — it's one toggle: Settings → Privacy and security → Security → Use secure DNS → off. Without it, Chrome may still reach blocked sites. Firefox users: see the note at the [bottom of the page](#how-it-works--как-это-работает).

<br>

---

<br>

# ru-ip-watchdog (по-русски)

> **Не играйте в русскую рулетку со своими аккаунтами.**

Одна случайно открытая вкладка ChatGPT, Claude или Wise с российского IP — и сервис может забанить аккаунт навсегда. ru-ip-watchdog спасает от этого: пока ваш IP-выход русский, эти сайты просто не откроются; как только выход станет другим — всё заработает снова, само. Приложения не убиваются — просто теряют сеть, пока это небезопасно.

## Установка (macOS) — одной строкой

Откройте **Терминал** (`Cmd + Пробел`, наберите «Терминал», Enter), скопируйте эту строку туда и нажмите Enter:

```sh
curl -fsSL https://raw.githubusercontent.com/tek-95/ru-ip-watchdog/main/install.sh | bash
```

Один раз спросит пароль от Mac (при вводе он невидим — это нормально). Всё.

## Установка (Windows) — одной строкой

Откройте **PowerShell от администратора** (нажмите клавишу Windows, наберите «PowerShell», правый клик → «Запуск от имени администратора»), скопируйте эту строку туда и нажмите Enter:

```powershell
irm https://raw.githubusercontent.com/tek-95/ru-ip-watchdog/main/install.ps1 | iex
```

### И ещё один маленький шаг (не обязателен, но лучше сделать)

В Chrome выключите «Использовать безопасный DNS-сервер» — это один переключатель: Настройки → Конфиденциальность и защита → Безопасность → «Использовать безопасный DNS-сервер» → выкл. Без этого Chrome иногда может открывать заблокированные сайты. Для Firefox — заметка [внизу страницы](#how-it-works--как-это-работает).

<br>

---

<br>

## How it works / Как это работает

*(technical details and uninstall — English only)*

1. **Country check** — every 10 s via Cloudflare (`cdn-cgi/trace`), fallback ipinfo.io. No network = nothing leaks, idle.
2. **Layer 1: hosts.** RU exit → blocked domains are pinned to `127.0.0.1`/`::1` in `/etc/hosts` (macOS) or `C:\Windows\System32\drivers\etc\hosts` (Windows), DNS cache flushed. Everything on system DNS stops resolving them instantly.
3. **Layer 2: pf (macOS).** Browsers with DNS-over-HTTPS ignore hosts, so a pf anchor also blocks outbound TCP to Anthropic's and OpenAI's own IP ranges (160.79.104.0/21 etc.). DoH or not — packets never reach the servers; live connections die on the next packet.
4. **Restore** — exit becomes non-RU → hosts section and pf rules removed, cache flushed, apps reconnect by themselves.

| Service | hosts | pf (macOS) |
|---|---|---|
| OpenAI / ChatGPT | ✅ | ✅ direct ranges |
| Anthropic / Claude | ✅ | ✅ 160.79.104.0/21 |
| Gemini | ✅ | — (shared Google IPs) |
| Wise / Revolut / Airbnb | ✅ | — (behind Cloudflare, shared IPs) |

**Firefox** may enable DoH by itself (`doh-rollout`). Quit Firefox and run:
```sh
for p in ~/Library/Application\ Support/Firefox/Profiles/*/prefs.js; do
  echo 'user_pref("network.trr.mode", 5);' >> "$p"
  echo 'user_pref("doh-rollout.enabled", false);' >> "$p"
done
```

## Uninstall

macOS:
```sh
sudo launchctl bootout system /Library/LaunchDaemons/com.user.ru-ip-watchdog.plist
sudo rm -rf /Library/LaunchDaemons/com.user.ru-ip-watchdog.plist "/Library/Application Support/ru-ip-watchdog"
sudo sed -i '' '/^# ru-ip-watchdog:begin$/,/^# ru-ip-watchdog:end$/d' /etc/hosts
```

Windows (admin PowerShell):
```powershell
Stop-ScheduledTask ru-ip-watchdog -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName ru-ip-watchdog -Confirm:$false; Remove-Item C:\ProgramData\ru-ip-watchdog -Recurse -Force; (Get-Content $env:SystemRoot\System32\drivers\etc\hosts -Raw) -replace '(?s)\r?\n?# ru-ip-watchdog:begin.*?# ru-ip-watchdog:end\r?\n?', '' | Set-Content $env:SystemRoot\System32\drivers\etc\hosts -Encoding ascii -NoNewline; ipconfig /flushdns
```

## Logs

macOS: `~/Library/Logs/ru-ip-watchdog.log` · Windows: `C:\ProgramData\ru-ip-watchdog\guard.log`

The domain list and pf CIDR ranges are plain variables at the top of the scripts — add your own services one line each.
