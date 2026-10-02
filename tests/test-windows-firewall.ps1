# Opt-in integration smoke test, only for disposable administrator CI runners.
# Touches a named test firewall rule and a temporary hosts file, never real hosts.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../ru-ip-watchdog.ps1')
$temp = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
New-Item -ItemType Directory $temp | Out-Null
$Dir = $temp
$HostsPath = Join-Path $temp 'hosts'
$RuleName = 'ru-ip-watchdog-ci-' + [Guid]::NewGuid().ToString()
[IO.File]::WriteAllText($HostsPath, "127.0.0.1 localhost`r`n")
try {
    $addresses = @('203.0.113.99', '2001:db8::99')
    Set-Block $true $addresses
    $rule = Get-NetFirewallRule -PolicyStore ActiveStore -Name $RuleName
    if (($rule | Get-NetFirewallPortFilter).Protocol -ne 'Any') { throw 'Must block all protocols including UDP.' }
    Set-Block $true $addresses
    Set-Block $false $addresses
    if (([IO.File]::ReadAllText($HostsPath)).Contains($BeginTag)) { throw 'Hosts block was not removed.' }
    Write-Host 'Windows firewall rule creation, verification, repeated enforcement and removal passed.'
} finally {
    Get-NetFirewallRule -PolicyStore PersistentStore | Where-Object Name -eq $RuleName | Remove-NetFirewallRule
    Remove-Item $temp -Recurse -Force
}
