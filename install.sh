#!/bin/bash
# install.sh — установка ru-ip-watchdog на macOS одной командой.
# Работает двумя способами:
#   1) bash install.sh из корня склонированного репозитория
#   2) curl -fsSL <raw>/install.sh | bash — сам скачает остальные файлы
# Требует sudo (спросит пароль один раз).

set -e
DIR="/Library/Application Support/ru-ip-watchdog"
PLIST="/Library/LaunchDaemons/com.user.ru-ip-watchdog.plist"
REPO_RAW="https://raw.githubusercontent.com/tek-95/ru-ip-watchdog/main"

# определить, где лежат файлы: рядом со скриптом или качать из репо
SRC="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
if [ -f "$SRC/ru-ip-watchdog.sh" ] && [ -f "$SRC/com.user.ru-ip-watchdog.plist" ]; then
    GET_SH()    { cat "$SRC/ru-ip-watchdog.sh"; }
    GET_PLIST() { cat "$SRC/com.user.ru-ip-watchdog.plist"; }
else
    command -v curl >/dev/null || { echo "нужен curl"; exit 1; }
    GET_SH()    { curl -fsSL "$REPO_RAW/ru-ip-watchdog.sh"; }
    GET_PLIST() { curl -fsSL "$REPO_RAW/com.user.ru-ip-watchdog.plist"; }
fi

# снести старую версию, если была
sudo launchctl bootout system "$PLIST" 2>/dev/null || true
sudo rm -f "$PLIST"

# почистить hosts от возможных старых секций
sudo sed -i '' '/^# ru-ip-watchdog:begin$/,/^# ru-ip-watchdog:end$/d' /etc/hosts 2>/dev/null || true

sudo mkdir -p "$DIR"
GET_SH    | sudo tee "$DIR/ru-ip-watchdog.sh" >/dev/null
GET_PLIST | sudo tee "$PLIST" >/dev/null
sudo chmod +x "$DIR/ru-ip-watchdog.sh"
sudo launchctl bootstrap system "$PLIST"

echo "Установлено и запущено. Лог: ~/Library/Logs/ru-ip-watchdog.log"
echo "Удалить: bash $(basename "$0") --uninstall (или см. README)"
