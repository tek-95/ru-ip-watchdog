# install.ps1 — установка ru-ip-watchdog на Windows.
# Два способа:
#   1) из корня склонированного репозитория (admin PowerShell):
#      Set-ExecutionPolicy Bypass -Scope Process -Force
#      .\install.ps1
#   2) одной строкой без скачивания репо (см. README)
# Удаление: .\uninstall.ps1 или Unregister-ScheduledTask -TaskName ru-ip-watchdog -Confirm:$false

$ErrorActionPreference = 'Stop'
$Dir = 'C:\ProgramData\ru-ip-watchdog'
$RepoRaw = 'https://raw.githubusercontent.com/tek-95/ru-ip-watchdog/main'

if (Test-Path "$PSScriptRoot\ru-ip-watchdog.ps1") {
    Copy-Item "$PSScriptRoot\ru-ip-watchdog.ps1" "$Dir\ru-ip-watchdog.ps1" -Force
} else {
    if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
    Invoke-WebRequest "$RepoRaw/ru-ip-watchdog.ps1" -OutFile "$Dir\ru-ip-watchdog.ps1" -UseBasicParsing
}
if (-not (Test-Path "$Dir")) { New-Item -ItemType Directory -Force -Path $Dir | Out-Null }

$Action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
           -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Dir\ru-ip-watchdog.ps1`""
$Trigger = New-ScheduledTaskTrigger -AtBoot
$Settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
            -ExecutionTimeLimit (New-TimeSpan -Days 3650) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$Principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest

Register-ScheduledTask -TaskName 'ru-ip-watchdog' -Action $Action -Trigger $Trigger `
    -Settings $Settings -Principal $Principal -Force | Out-Null
Start-ScheduledTask -TaskName 'ru-ip-watchdog'
Write-Host "Installed and started. Log: $Dir\guard.log"
Write-Host 'Uninstall: run uninstall.ps1 (or Unregister-ScheduledTask -TaskName ru-ip-watchdog -Confirm:$false)'
