[CmdletBinding()]
param([switch]$Status, [switch]$Approve)
$ErrorActionPreference = 'Stop'
$Dir = Join-Path $env:ProgramData 'ru-ip-watchdog'
$HostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$BeginTag = '# ru-ip-watchdog:begin'
$EndTag = '# ru-ip-watchdog:end'
$RuleName = 'ru-ip-watchdog-block'
$Mode = 'auto'
$Interval = 10

function Write-Log([string]$Message) {
    $path = Join-Path $Dir 'guard.log'
    if ((Test-Path $path) -and (Get-Item $path).Length -gt 1MB) { Move-Item $path "$path.1" -Force }
    "$(Get-Date -Format o) $Message" | Out-File $path -Append -Encoding utf8
}
function Get-List([string]$Name) {
    @(Get-Content (Join-Path $PSScriptRoot $Name) | Where-Object { $_ -match '^[^#\s]' } | ForEach-Object { $_.Trim() })
}
function Get-Probe([string]$Provider) {
    try {
        if ($Provider -eq 'cloudflare') {
            $body = (Invoke-WebRequest 'https://www.cloudflare.com/cdn-cgi/trace' -UseBasicParsing -TimeoutSec 6).Content
            if ($body -notmatch '(?m)^loc=([A-Z]{2})\r?$') { return $null }; $country = $Matches[1]
            if ($body -notmatch '(?m)^ip=([^\r\n]+)\r?$') { return $null }; $ip = $Matches[1]
        } else {
            $body = Invoke-RestMethod 'https://ipinfo.io/json' -TimeoutSec 6
            $country = $body.country; $ip = $body.ip
        }
        $parsed = $null
        if ($country -cnotmatch '^[A-Z]{2}$' -or $country -in @('XX', 'ZZ') -or -not [Net.IPAddress]::TryParse($ip, [ref]$parsed)) { return $null }
        return "$country|$ip"
    } catch { Write-Log "probe=$Provider failed: $($_.Exception.Message)"; return $null }
}
function Get-Consensus($A, $B) {
    if ($A -like 'RU|*' -or $B -like 'RU|*') { return 'RU' }
    if ($A -and $A -ceq $B) { return $A }
    return 'UNKNOWN'
}
function Remove-HostsSection([string]$Raw) {
    $inside = $false; $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in ($Raw -split '\r?\n')) {
        if ($line -eq $BeginTag) { $inside = $true; continue }
        if ($line -eq $EndTag) { $inside = $false; continue }
        if (-not $inside) { $lines.Add($line) }
    }
    if ($inside) { throw 'Unterminated watchdog section in hosts; refusing to discard user entries.' }
    return ($lines -join "`r`n").TrimEnd("`r", "`n") + "`r`n"
}
function Set-Hosts([bool]$On) {
    $raw = [IO.File]::ReadAllText($HostsPath)
    $clean = Remove-HostsSection $raw
    if ($On) {
        $clean += "$BeginTag`r`n"
        foreach ($domain in (Get-List 'domains.txt')) { $clean += "127.0.0.1 $domain`r`n::1 $domain`r`n" }
        $clean += "$EndTag`r`n"
    }
    # Do not replace the inode/ACL; exceptions propagate to ERROR status.
    [IO.File]::WriteAllText($HostsPath, $clean, [Text.UTF8Encoding]::new($false))
    $check = [IO.File]::ReadAllText($HostsPath)
    if (($On -and -not $check.Contains($BeginTag)) -or (-not $On -and $check.Contains($BeginTag))) { throw 'Hosts verification failed.' }
    Clear-DnsClientCache
}
function Start-DnsRefresh {
    Start-Job -ArgumentList (,@(Get-List 'domains.txt')) -ScriptBlock {
        param([string[]]$Domains)
        foreach ($domain in $Domains) {
            try {
                Resolve-DnsName $domain -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop |
                    Where-Object { $_.Type -in @('A', 'AAAA') } | ForEach-Object { $_.IPAddress }
            } catch { Write-Warning "DNS refresh failed for $domain" }
        }
    }
}
function Receive-DnsRefresh($Job, [string[]]$Addresses) {
    foreach ($address in @(Receive-Job $Job -ErrorAction Stop)) {
        $parsed = $null
        if ($address -notin @('127.0.0.1', '::1') -and [Net.IPAddress]::TryParse($address, [ref]$parsed)) { $Addresses += $address }
    }
    $Addresses = @($Addresses | Sort-Object -Unique)
    $cache = Join-Path $Dir 'targets.txt'
    $Addresses | Set-Content "$cache.new" -Encoding ascii
    Move-Item "$cache.new" $cache -Force
    Remove-Job $Job
    return $Addresses
}
function Set-Block([bool]$On, [string[]]$Addresses) {
    if ($On) {
        Set-Hosts $true
        if (@(Get-NetFirewallProfile | Where-Object { $_.Enabled -ne 'True' }).Count -gt 0) { throw 'All Windows Firewall profiles must be enabled.' }
        $rule = @(Get-NetFirewallRule -PolicyStore PersistentStore -ErrorAction Stop | Where-Object Name -eq $RuleName)
        if ($rule.Count -eq 0) {
            New-NetFirewallRule -Name $RuleName -DisplayName 'ru-ip-watchdog protected destinations' -Group 'ru-ip-watchdog' -Direction Outbound -Action Block -Protocol Any -RemoteAddress $Addresses -Profile Any -Enabled True | Out-Null
        } else {
            Set-NetFirewallRule -Name $RuleName -Direction Outbound -Action Block -Protocol Any -RemoteAddress $Addresses -Profile Any -Enabled True | Out-Null
        }
        $live = Get-NetFirewallRule -Name $RuleName -PolicyStore ActiveStore
        if ($live.Enabled -ne 'True' -or $live.Action -ne 'Block' -or $live.Direction -ne 'Outbound') { throw 'Firewall rule is not active.' }
        if (($live | Get-NetFirewallPortFilter).Protocol -ne 'Any' -or $live.Profile -ne 'Any') { throw 'Firewall protocol or profile is incomplete.' }
        $actual = @(($live | Get-NetFirewallAddressFilter).RemoteAddress | Sort-Object -Unique)
        if (Compare-Object (@($Addresses | Sort-Object -Unique)) $actual) { throw 'Active firewall addresses differ from requested addresses.' }
    } else {
        # Hosts first, firewall last: errors should preserve the network block.
        Set-Hosts $false
        Get-NetFirewallRule -PolicyStore PersistentStore | Where-Object Name -eq $RuleName | Remove-NetFirewallRule
        if (@(Get-NetFirewallRule -PolicyStore ActiveStore | Where-Object Name -eq $RuleName).Count) { throw 'Firewall block still present.' }
    }
}
function Test-Approval([string]$Evidence) {
    try {
        $a = Get-Content (Join-Path $Dir 'approval.json') -Raw | ConvertFrom-Json
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$a.timestamp
        return $age -ge 0 -and $age -lt 900 -and $a.evidence -ceq $Evidence
    } catch { return $false }
}
function Test-NeedsBlock([string]$Evidence, [string]$Previous) {
    if ($Evidence -in @('RU', 'UNKNOWN') -or $Evidence -cne $Previous) { return $true }
    return -not ($Mode -eq 'auto' -or (Test-Approval $Evidence))
}
function Write-Status([string]$State, [string]$Evidence, [string]$Reason) {
    @{ state=$State; evidence=$Evidence; reason=$Reason; mode=$Mode; checkedAt=[DateTime]::UtcNow.ToString('o') } |
        ConvertTo-Json | Set-Content (Join-Path $Dir 'status.new') -Encoding utf8
    Move-Item (Join-Path $Dir 'status.new') (Join-Path $Dir 'status.json') -Force
}
function Start-Guard {
    if ($Status) {
        Get-Content (Join-Path $Dir 'status.json')
        Get-NetFirewallProfile | Format-Table Name, Enabled
        Get-NetFirewallRule -PolicyStore ActiveStore | Where-Object Name -eq $RuleName | Format-List
        return
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as administrator.' }
    New-Item -ItemType Directory $Dir -Force | Out-Null
    if (Test-Path (Join-Path $PSScriptRoot 'config')) {
        foreach ($line in (Get-Content (Join-Path $PSScriptRoot 'config'))) {
            if ($line -match '^MODE=(manual|auto)$') { $script:Mode = $Matches[1] }
            elseif ($line -match '^INTERVAL=(\d+)$') { $script:Interval = [int]$Matches[1] }
            elseif ($line -match '^\s*(#.*)?$') { continue }
            else { throw 'Invalid configuration.' }
        }
    }
    if ($Interval -lt 2 -or $Interval -gt 300) { throw 'Interval must be 2..300 seconds.' }
    if ($Approve) {
        $evidence = Get-Consensus (Get-Probe 'cloudflare') (Get-Probe 'ipinfo')
        if ($evidence -in @('UNKNOWN', 'RU')) { throw 'Approval refused: probes fail, disagree, or report RU.' }
        @{timestamp=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); evidence=$evidence} | ConvertTo-Json | Set-Content (Join-Path $Dir 'approval.new') -Encoding utf8
        Move-Item (Join-Path $Dir 'approval.new') (Join-Path $Dir 'approval.json') -Force
        Write-Host 'Approved for at most 15 minutes. Probe routes are not proof of every service route.'; return
    }
    $mutex = [Threading.Mutex]::new($false, 'Global\ru-ip-watchdog')
    $held = $false; $dnsJob = $null
    try {
        try { $held = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $held = $true }
        if (-not $held) { throw 'Another guard is already running.' }
        $addresses = @(Get-List 'cidrs.txt')
        if (Test-Path (Join-Path $Dir 'targets.txt')) { $addresses += @(Get-Content (Join-Path $Dir 'targets.txt')) }
        Set-Block $true $addresses
        Write-Status 'BLOCKED' 'UNKNOWN' 'startup'
        $previous = ''; $last = ''; $count = 0
        while ($true) {
            $evidence = Get-Consensus (Get-Probe 'cloudflare') (Get-Probe 'ipinfo')
            $on = Test-NeedsBlock $evidence $previous
            if ($evidence -in @('RU', 'UNKNOWN') -or $evidence -cne $previous) { Remove-Item (Join-Path $Dir 'approval.json') -ErrorAction SilentlyContinue }
            Set-Block $on $addresses
            $state = if ($on) { 'BLOCKED' } else { 'OPEN' }
            Write-Status $state $evidence 'checked'
            if ($last -cne "$state/$evidence") { Write-Log "$state evidence=$evidence mode=$Mode"; $last = "$state/$evidence" }
            if ($dnsJob -and $dnsJob.State -ne 'Running') {
                $addresses = @(Receive-DnsRefresh $dnsJob $addresses); $dnsJob = $null
            }
            if ($count % 6 -eq 0 -and -not $dnsJob) { $dnsJob = Start-DnsRefresh }
            $count++; $previous = $evidence
            Start-Sleep -Seconds $Interval
        }
    } catch {
        if ($held) { Write-Status 'ERROR' 'UNKNOWN' $_.Exception.Message; Write-Log "ERROR: $($_.Exception.Message)" }
        throw
    } finally { if ($dnsJob) { Stop-Job $dnsJob; Remove-Job $dnsJob }; if ($held) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}
if ($MyInvocation.InvocationName -ne '.') { Start-Guard }
