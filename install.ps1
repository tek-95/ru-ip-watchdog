# install.ps1 — ставить из admin PowerShell:
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\install.ps1
# Создаёт C:\ProgramData\ru-ip-watchdog, копирует скрипт, регистрирует
# задачу планировщика от SYSTEM, запускает.

$ErrorActionPreference = 'Stop'
$Dir = 'C:\ProgramData\ru-ip-watchdog'
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Copy-Item "$PSScriptRoot\ru-ip-watchdog.ps1" "$Dir\ru-ip-watchdog.ps1" -Force

$Action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
           -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\ProgramData\ru-ip-watchdog\ru-ip-watchdog.ps1"'
$Trigger = New-ScheduledTaskTrigger -AtBoot
$Settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
            -ExecutionTimeLimit (New-TimeSpan -Days 3650) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$Principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest

Register-ScheduledTask -TaskName 'ru-ip-watchdog' -Action $Action -Trigger $Trigger `
    -Settings $Settings -Principal $Principal -Force | Out-Null
Start-ScheduledTask -TaskName 'ru-ip-watchdog'
Write-Host 'Installed and started. Log: C:\ProgramData\ru-ip-watchdog\guard.log'
Write-Host 'Uninstall: Unregister-ScheduledTask -TaskName ru-ip-watchdog -Confirm:$false'

# NB: MessageBox из SYSTEM-сессии пользователь не увидит — уведомлений на Windows нет,
# состояние видно только в логе и в hosts. Это нормально: разница с macOS только в notify.
