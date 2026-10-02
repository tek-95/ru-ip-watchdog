[CmdletBinding()]
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'
$Dir = Join-Path $env:ProgramData 'ru-ip-watchdog'
$RepoRaw = 'https://raw.githubusercontent.com/tek-95/ru-ip-watchdog/main'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run PowerShell as administrator.' }
function Stop-InstalledGuard {
    $task = Get-ScheduledTask -TaskName 'ru-ip-watchdog' -ErrorAction SilentlyContinue
    if (-not $task) { return }
    Stop-ScheduledTask -TaskName 'ru-ip-watchdog'
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        if ((Get-ScheduledTask -TaskName 'ru-ip-watchdog').State -ne 'Running') { return }
        Start-Sleep -Milliseconds 100
    }
    throw 'Guard did not stop; installation files were not changed.'
}
if ($Uninstall) {
    Stop-InstalledGuard
    Unregister-ScheduledTask -TaskName 'ru-ip-watchdog' -Confirm:$false -ErrorAction SilentlyContinue
    . (Join-Path $Dir 'ru-ip-watchdog.ps1')
    Set-Hosts $false
    Get-NetFirewallRule -PolicyStore PersistentStore | Where-Object Name -eq $RuleName | Remove-NetFirewallRule
    Remove-Item $Dir -Recurse -Force
    Write-Host 'Removed hosts entries, firewall rule, task and files.'; return
}
$stage = Join-Path $env:TEMP ([guid]::NewGuid().ToString())
New-Item -ItemType Directory $stage | Out-Null
try {
    foreach ($file in @('ru-ip-watchdog.ps1','domains.txt','cidrs.txt','config.example','install.ps1')) {
        if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot $file))) { Copy-Item (Join-Path $PSScriptRoot $file) (Join-Path $stage $file) }
        else { Invoke-WebRequest "$RepoRaw/$file" -OutFile (Join-Path $stage $file) -UseBasicParsing }
    }
    $tokens = $null; $errors = $null
    [Management.Automation.Language.Parser]::ParseFile((Join-Path $stage 'ru-ip-watchdog.ps1'), [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count) { throw "Downloaded script is invalid: $errors" }
    Stop-InstalledGuard
    New-Item -ItemType Directory $Dir -Force | Out-Null
    # Scripts executed as SYSTEM must not be writable by ordinary users.
    & icacls.exe $Dir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to secure installation directory.' }
    foreach ($file in @('ru-ip-watchdog.ps1','domains.txt','cidrs.txt','install.ps1')) { Copy-Item (Join-Path $stage $file) (Join-Path $Dir $file) -Force }
    if (-not (Test-Path (Join-Path $Dir 'config'))) { Copy-Item (Join-Path $stage 'config.example') (Join-Path $Dir 'config') }
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Dir\ru-ip-watchdog.ps1`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
    Register-ScheduledTask -TaskName 'ru-ip-watchdog' -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName 'ru-ip-watchdog'
    Write-Host "Installed. Check health: & '$Dir\ru-ip-watchdog.ps1' -Status"
    Write-Host "Log: $Dir\guard.log. Default mode: auto."
} finally { Remove-Item $stage -Recurse -Force }
