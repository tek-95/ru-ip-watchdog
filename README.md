# ru-ip-watchdog

МакOS-демон (и Windows-скрипт), который каждые 10 секунд проверяет страну вашего IP-выхода. Если снаружи видна Россия — мгновенно отрезает сеть сервисам, которые банят аккаунты за RU-доступ (OpenAI, Claude, Gemini, Wise, Revolut, Airbnb). Как только выход снова не RU (VPN включён, роутер с VPN, вы не в РФ) — всё само восстанавливается.

## Как это работает
1. Проверка страны через Cloudflare (фолбэк ipinfo)
2. RU-выход → домены сервисов прописываются в `/etc/hosts` на 127.0.0.1 + pf-блокировка IP-диапазонов Anthropic/OpenAI (второй слой — работает даже если браузер использует DoH)
3. Не RU → всё убирается, сеть восстанавливается без перезапуска приложений

## Установка (macOS)

Скачайте репозиторий и запустите:

```sh
bash install.sh
```

Спросит пароль sudo один раз. Всё.

## Установка (Windows)

Из admin PowerShell в папке репозитория:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install.ps1
```

## Удаление (macOS)

```sh
sudo launchctl bootout system /Library/LaunchDaemons/com.user.ru-ip-watchdog.plist
sudo rm /Library/LaunchDaemons/com.user.ru-ip-watchdog.plist "/Library/Application Support/ru-ip-watchdog" -rf
sudo sed -i '' '/^# ru-ip-watchdog:begin$/,/^# ru-ip-watchdog:end$/d' /etc/hosts
```

## Логи

`~/Library/Logs/ru-ip-watchdog.log` (macOS), `C:\ProgramData\ru-ip-watchdog\guard.log` (Windows)

## Важно
- Firefox может включать DoH сам (`doh-rollout`) — hosts его не видит, но pf-слой режет соединения на уровне IP
- Для полной защиты в Chrome выключите «Use secure DNS»
- Список доменов и CIDR — в начале скрипта, добавляйте своё
