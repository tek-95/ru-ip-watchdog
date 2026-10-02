$ErrorActionPreference = 'Stop'
# Environment fallback permits pure-function tests on macOS/Linux too.
if (-not $env:ProgramData) { $env:ProgramData = [IO.Path]::GetTempPath() }
if (-not $env:SystemRoot) { $env:SystemRoot = [IO.Path]::GetTempPath() }
. (Join-Path $PSScriptRoot '../ru-ip-watchdog.ps1')
function Assert-Equal($Actual, $Expected) { if ($Actual -cne $Expected) { throw "Expected [$Expected], got [$Actual]" } }
Assert-Equal (Get-Consensus 'DE|203.0.113.1' 'DE|203.0.113.1') 'DE|203.0.113.1'
Assert-Equal (Get-Consensus 'DE|203.0.113.1' 'TR|203.0.113.1') 'UNKNOWN'
Assert-Equal (Get-Consensus 'DE|203.0.113.1' 'DE|203.0.113.2') 'UNKNOWN'
Assert-Equal (Get-Consensus 'DE|203.0.113.1' $null) 'UNKNOWN'
Assert-Equal (Get-Consensus $null 'RU|203.0.113.1') 'RU'
$Mode = 'auto'
Assert-Equal (Test-NeedsBlock 'UNKNOWN' 'UNKNOWN') $true
Assert-Equal (Test-NeedsBlock 'RU' 'RU') $true
Assert-Equal (Test-NeedsBlock 'DE|203.0.113.1' 'TR|203.0.113.1') $true
Assert-Equal (Test-NeedsBlock 'DE|203.0.113.1' 'DE|203.0.113.1') $false
$temp = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
New-Item -ItemType Directory $temp | Out-Null
try {
    $Dir = $temp; $HostsPath = Join-Path $temp 'hosts'
    $Mode = 'manual'
    Assert-Equal (Test-NeedsBlock 'DE|203.0.113.1' 'DE|203.0.113.1') $true
    @{timestamp=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); evidence='DE|203.0.113.1'} | ConvertTo-Json | Set-Content (Join-Path $Dir 'approval.json')
    Assert-Equal (Test-NeedsBlock 'DE|203.0.113.1' 'DE|203.0.113.1') $false
    Assert-Equal (Test-NeedsBlock 'DE|203.0.113.2' 'DE|203.0.113.2') $true
    @{timestamp=1; evidence='DE|203.0.113.1'} | ConvertTo-Json | Set-Content (Join-Path $Dir 'approval.json')
    Assert-Equal (Test-NeedsBlock 'DE|203.0.113.1' 'DE|203.0.113.1') $true
    function Clear-DnsClientCache { }
    $original = "127.0.0.1 localhost`r`n203.0.113.2 user.example`r`n"
    [IO.File]::WriteAllText($HostsPath, $original)
    Set-Hosts $true; Set-Hosts $true
    $raw = [IO.File]::ReadAllText($HostsPath)
    Assert-Equal ([regex]::Matches($raw, [regex]::Escape($BeginTag)).Count) 1
    Set-Hosts $false
    Assert-Equal ([IO.File]::ReadAllText($HostsPath)) $original
    $broken = "$BeginTag`r`n203.0.113.1 keep.this`r`n"
    [IO.File]::WriteAllText($HostsPath, $broken)
    $failed = $false
    try { Set-Hosts $false } catch { $failed = $true }
    Assert-Equal $failed $true
    Assert-Equal ([IO.File]::ReadAllText($HostsPath)) $broken
    Write-Host 'All PowerShell policy and hosts preservation tests passed.'
} finally { Remove-Item $temp -Recurse -Force }
# Parse every PowerShell script, including this test and installer.
foreach ($file in (Get-ChildItem (Join-Path $PSScriptRoot '..') -Filter '*.ps1' -Recurse)) {
    $tokens = $null; $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count) { throw "Syntax error in $($file.Name): $errors" }
}
