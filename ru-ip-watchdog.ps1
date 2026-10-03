# ru-ip-watchdog.ps1 — Windows-аналог macOS-стража
# Если снаружи виден русский IP — домены OpenAI/Anthropic/Gemini/Wise/Airbnb/Revolut
# -> 127.0.0.1 в hosts. Выход не RU — записи убираются.
# Запуск: планировщик от SYSTEM (см. install.ps1). Лог: C:\ProgramData\ru-ip-watchdog\guard.log

$ErrorActionPreference = 'SilentlyContinue'
$HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$LogFile   = 'C:\ProgramData\ru-ip-watchdog\guard.log'
$BeginTag  = '# ru-ip-watchdog:begin'
$EndTag    = '# ru-ip-watchdog:end'
$Interval  = 5

$Domains = @(
    'openai.com','api.openai.com','auth.openai.com','auth0.openai.com',
    'platform.openai.com','status.openai.com','cdn.openai.com',
    'chatgpt.com','ab.chatgpt.com','chatgpt-live.fastedge.io',
    'oaistatic.com','oaiusercontent.com',
    'anthropic.com','api.anthropic.com','console.anthropic.com',
    'claude.ai','claude.com','claude.site',
    'statsig.anthropic.com','statsig.com','api.statsig.com',
    'sentry.io','o1137834.ingest.sentry.io',
    'gemini.google.com','bard.google.com','aistudio.google.com',
    'generativelanguage.googleapis.com','alkalimakersuite-pa.googleapis.com',
    'wise.com','transferwise.com',
    'airbnb.com','api.zebra.airbnb.com','muscache.com',
    'revolut.com','www.revolut.com','api.revolut.com','app.revolut.com'
)

function Log($msg) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg" | Out-File $LogFile -Append -Encoding utf8 }

function Get-ExitCountry {
    try {
        $r = Invoke-RestMethod -Uri 'https://www.cloudflare.com/cdn-cgi/trace' -TimeoutSec 6
        if ($r -match '(?m)^loc=([A-Z]{2})') { return $Matches[1] }
    } catch {}
    try {
        $j = Invoke-RestMethod -Uri 'https://ipinfo.io/json' -TimeoutSec 6
        return $j.country
    } catch {}
    return $null
}

function Test-Blocked {
    (Get-Content $HostsPath -Raw) -match [regex]::Escape($BeginTag)
}

function Set-Block([bool]$On) {
    $raw = Get-Content $HostsPath -Raw
    if ($On) {
        Copy-Item $HostsPath "$HostsPath.ru-ip-watchdog.bak" -Force
        $section = "$BeginTag`r`n" + (($Domains | ForEach-Object { "127.0.0.1 $_`r`n::1 $_" }) -join "`r`n") + "`r`n$EndTag"
        ($raw.TrimEnd("`r`n") + "`r`n" + $section + "`r`n") | Set-Content $HostsPath -Encoding ascii -NoNewline
        Log "exit=RU - BLOCKED (hosts)"
    } else {
        $pattern = "(?s)\r?\n?" + [regex]::Escape($BeginTag) + ".*?" + [regex]::Escape($EndTag) + "\r?\n?"
        ($raw -replace $pattern, '') | Set-Content $HostsPath -Encoding ascii -NoNewline
        Log "exit not RU - UNBLOCKED (hosts)"
    }
    # сброс DNS-кэша
    ipconfig /flushdns | Out-Null
    # уведомлений из SYSTEM-сессии пользователь не увидит; MessageBox нельзя —
    # он блокирует цикл. Состояние видно в логе и в hosts.
}

Log "ru-ip-watchdog started (pid $PID, mode: hosts-block)"
while ($true) {
    $loc = Get-ExitCountry
    if (-not $loc) {
        Log 'no connectivity, idle'
    } elseif ($loc -ne 'RU') {
        if (Test-Blocked) { Set-Block $false }
    } else {
        if (-not (Test-Blocked)) { Set-Block $true }
    }
    Start-Sleep -Seconds $Interval
}
