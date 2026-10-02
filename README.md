# ru-ip-watchdog

> Don't play Russian Roulette with your accounts.

A small, independent macOS / Windows guard for people using **any VPN client**. Chapman is not required. It monitors the exit observed by two diagnostic services and blocks a configurable set of AI / fintech destinations when they report Russia, disagree, or cannot be checked.

**This is a best-effort guard, not a guarantee against account restrictions or a full VPN kill switch.** Country databases can be wrong. Periodic checks cannot prevent every packet during a route change. A domain list cannot cover every service hostname or DNS-over-HTTPS address. Service policies are determined by each provider.

## Before installing

1. Use a **full-tunnel VPN**: all traffic uses the same server. Exclude neither protected services nor the two diagnostic services. Disable application / domain split routing while relying on automatic mode.
2. Review `domains.txt`. Its exact hostnames are mapped to loopback when blocked; hosts does not support wildcard domains.
3. Expect some collateral blocking: resolved service IPs may belong to a shared CDN. Unrelated sites using those IPs can also stop working while the guard is blocking.
4. Installation needs administrator access. On macOS it adds a marked table and quick block to `/etc/pf.conf`, reloads the main ruleset, and may require reconnecting other VPNs. Windows requires all Windows Firewall profiles enabled; the installer does not change their global policies.

If you use split routing, a non-RU Cloudflare result **does not prove** that ChatGPT or Wise uses a non-RU exit. Even two matching probes cannot establish this. Choose manual mode for additional caution, or use a VPN kill switch and remove split routing.

## Install

Prefer downloading / cloning a reviewed revision and installing locally:

```sh
git clone https://github.com/tek-95/ru-ip-watchdog.git
cd ru-ip-watchdog
```

macOS:

```sh
bash install.sh
```

Windows, **PowerShell as administrator**:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

The installers stage and check downloads before stopping an existing installation. Configuration is preserved on upgrades. The Windows install directory is restricted to Administrators and SYSTEM.

One-line bootstrap (downloads current `main`, so review the repository first):

```sh
curl -fsSL https://raw.githubusercontent.com/tek-95/ru-ip-watchdog/main/install.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/tek-95/ru-ip-watchdog/main/install.ps1 | iex
```

An installer reporting success means the background task was registered; **check status to confirm enforcement**.

## What happens

- On every daemon start, block known destinations first. Do not assume the previous route is safe.
- Probe Cloudflare trace and IPinfo independently, with six-second request timeouts. **Both country AND public IP must match**. Either RU response wins; missing, malformed or inconsistent evidence means `UNKNOWN`.
- The default `auto` mode opens access only after **two consecutive matching non-RU observations**. RU, unknown or changed evidence blocks again. The interval is the sleep *between* cycles, not a maximum detection time: requests and enforcement add time.
- `manual` mode additionally requires a 15-minute approval tied to the observed IP / country. A restart, changed IP, failed probe or RU response cancels approval. This is a human acknowledgement, not proof of service routing.
- Blocking combines exact hosts entries and destination-IP firewall rules for **all protocols**, including TCP and UDP / QUIC, IPv4 and IPv6 addresses that have been discovered. On macOS, existing PF states to known targets are killed.
- DNS refresh happens in the background so a slow resolver does not delay country checks. New service addresses are added after discovery; earlier addresses are retained. Supplemental CIDRs are listed in `cidrs.txt`; this list is not exhaustive.
- Rules are reapplied / checked every cycle. Errors are recorded as `ERROR`, not silently reported as successful protection. Hosts remains the fallback when applying firewall rules fails; `ERROR` means protection is incomplete.
- Crashes leave existing hosts / firewall blocks in place. The daemon restarts with blocking. Stopping a daemon while it is `OPEN`, a disabled firewall, unknown addresses or a startup race can still leave access possible.

No processes are killed. The guard changes connectivity. It does not reset Windows connection state; behavior of existing connections needs testing on the target Windows version. Unknown subdomains, alternate DNS responses, already established unknown destinations, proxies, VPN encapsulation and per-application routes can bypass destination-based protection. Do not use `BLOCKED` as evidence that all possible connections have been prevented.

## Status and logs

macOS:

```sh
sudo bash "/Library/Application Support/ru-ip-watchdog/ru-ip-watchdog.sh" --status
tail -f /var/log/ru-ip-watchdog.log
```

Windows, administrator PowerShell:

```powershell
& "$env:ProgramData\ru-ip-watchdog\ru-ip-watchdog.ps1" -Status
Get-Content "$env:ProgramData\ru-ip-watchdog\guard.log" -Wait
```

Status includes the observation time, country / IP evidence, `OPEN`, `BLOCKED` or `ERROR`, and actual firewall output. A stale timestamp indicates a stopped or unhealthy daemon. Logs rotate at approximately 1 MiB with one previous generation. Country probes are sent to Cloudflare and IPinfo; each sees your exit IP. No account credentials are collected.

## Configuration and manual approval

Edit `config` as administrator, then restart the task:

```ini
MODE=auto
INTERVAL=10
```

`MODE=manual` requires approval as well. `INTERVAL` accepts 2–300 seconds. Lists are `domains.txt` and `cidrs.txt` in the installation directory. No configuration file is executed as code.

macOS:

```sh
sudo launchctl kickstart -k system/com.user.ru-ip-watchdog
sudo bash "/Library/Application Support/ru-ip-watchdog/ru-ip-watchdog.sh" --approve
```

Windows:

```powershell
Stop-ScheduledTask ru-ip-watchdog
Start-ScheduledTask ru-ip-watchdog
& "$env:ProgramData\ru-ip-watchdog\ru-ip-watchdog.ps1" -Approve
```

Do not open protected services until status is healthy and the VPN routing configuration has been checked. Automatic mode does not require the approval command.

## Uninstall

macOS:

```sh
bash "/Library/Application Support/ru-ip-watchdog/install.sh" --uninstall
```

Windows, administrator PowerShell:

```powershell
& "$env:ProgramData\ru-ip-watchdog\install.ps1" -Uninstall
```

Uninstall removes only this project's marked hosts section, PF configuration lines / table contents or named Windows firewall rule, task, and installed files. It does not disable the whole firewall or flush unrelated rules. macOS intentionally leaves the empty live PF rule until reboot, avoiding a main-ruleset reload that could affect other VPNs; the on-disk lines are removed immediately. Logs on macOS are retained.

## Development checks

```sh
bash -n ru-ip-watchdog.sh install.sh cleanup.sh tests/test-shell.sh
bash tests/test-shell.sh
```

```powershell
powershell.exe -NoProfile -File .\tests\test-powershell.ps1
```

CI runs shell policy / hosts tests and Windows PowerShell 5.1 policy / hosts tests on standard runners. Tests never edit system hosts. Windows CI also creates, verifies and removes a temporary firewall rule for documentation-only IPs; macOS CI parses the PF configuration without loading it. These tests do not replace administrator-level firewall and VPN integration checks on real devices.

---

## По-русски

Утилита работает **с любым VPN**, без Chapman. Она проверяет страну и IP через Cloudflare и IPinfo. Если хоть один ответ сообщает RU, проверки не совпадают или недоступны — включает блокировку известных адресов и доменов. Открывает доступ автоматически после двух подряд совпавших ответов с нероссийским IP.

Для автоматического режима настройте VPN так, чтобы **весь трафик шёл через один сервер**, без раздельного роутинга для защищаемых сервисов и сайтов проверки. Иначе Cloudflare может видеть Турцию, а ChatGPT — Россию. Две проверки этот случай не исключают.

Установка: на Mac — `bash install.sh`; на Windows — `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1` из PowerShell администратора. Команды проверки состояния и удаления приведены выше. По умолчанию `MODE=auto`; дополнительный `MODE=manual` требует ручного разрешения на 15 минут.

`BLOCKED` означает блокировку **известного набора** адресов, `OPEN` — доступ открыт, `ERROR` — защита неполная: нужно проверить лог. Старое время проверки означает, что фоновая задача не работает.

Это дополнительная защита, а не гарантия от банов. Между проверками есть задержка; у сервисов появляются новые адреса и поддомены; общие CDN могут приводить к блокировке посторонних сайтов. Для полного запрета выхода мимо VPN нужен kill switch самого VPN. Ни страна IP, ни эта утилита не определяют правила использования вашего аккаунта.
