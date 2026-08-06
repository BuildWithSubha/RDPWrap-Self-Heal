#Requires -Version 5.1
<#
.SYNOPSIS
  RDPWrap Self-Heal — Lightweight Web Dashboard REST API & Web Server.
.DESCRIPTION
  Runs a native System.Net.HttpListener on http://localhost:8888 (no Node/npm required).
  Exposes status, active sessions, log viewer, and 1-click repair endpoints.
#>
[CmdletBinding()]
param(
    [int]$Port = 8888,
    [string]$Prefix = "http://localhost:$Port/"
)

$ErrorActionPreference = 'Stop'

# Path resolution
$ScriptDir   = $PSScriptRoot
$RepoRoot    = Split-Path $ScriptDir -Parent
$ScriptPath  = Join-Path $RepoRoot 'scripts\Install-RDPWrapSelfHeal.ps1'
$InstallDir  = "$env:ProgramFiles\RDP Wrapper"
$LogDir      = Join-Path $InstallDir 'logs'

function Get-TermsrvVersionRaw {
    $dll = Join-Path $env:SystemRoot 'System32\termsrv.dll'
    if (-not (Test-Path $dll)) { return 'unknown' }
    $vi = (Get-Item $dll).VersionInfo
    return '{0}.{1}.{2}.{3}' -f $vi.FileMajorPart, $vi.FileMinorPart, $vi.FileBuildPart, $vi.FilePrivatePart
}

function Test-WrapperLoaded {
    try {
        $svc = Get-CimInstance Win32_Service -Filter "Name='TermService'"
        if (-not $svc -or $svc.ProcessId -eq 0) { return $false }
        $mods = Get-Process -Id $svc.ProcessId -Module -ErrorAction SilentlyContinue
        return [bool]($mods | Where-Object { $_.ModuleName -eq 'rdpwrap.dll' })
    } catch { return $false }
}

function Test-Listener {
    try { return [bool](Get-NetTCPConnection -State Listen -LocalPort 3389 -EA Stop) }
    catch { return [bool]((netstat -an | Select-String ':3389\s+' | Select-String 'LISTENING')) }
}

function Get-ActiveSessions {
    $sessions = @()
    try {
        $raw = & query user 2>$null
        if ($raw) {
            # Skip header line
            foreach ($line in ($raw | Select-Object -Skip 1)) {
                $t = $line.Trim()
                if ($t.Length -eq 0) { continue }
                # Parse query user output columns: USERNAME, SESSIONNAME, ID, STATE, IDLE TIME, LOGON TIME
                $clean = $t -replace '^>', ''
                $parts = -split $clean
                if ($parts.Count -ge 4) {
                    $user = $parts[0]
                    if ($parts[1] -match '^\d+$') {
                        # No session name (e.g. Disconnected state)
                        $sessId = $parts[1]
                        $state  = $parts[2]
                        $name   = 'none'
                    } else {
                        $name   = $parts[1]
                        $sessId = $parts[2]
                        $state  = $parts[3]
                    }
                    $sessions += [pscustomobject]@{
                        id    = $sessId
                        user  = $user
                        name  = $name
                        state = $state
                    }
                }
            }
        }
    } catch {}
    return $sessions
}

function Get-SystemStatusJson {
    $ver = Get-TermsrvVersionRaw
    $iniPath = Join-Path $InstallDir 'rdpwrap.ini'
    if (-not (Test-Path $iniPath)) { $iniPath = Join-Path $RepoRoot 'bin\rdpwrap.ini' }
    
    $iniContent = if (Test-Path $iniPath) { Get-Content $iniPath -Raw -ErrorAction SilentlyContinue } else { '' }
    $hasIni = $iniContent -match ('(?m)^\[' + [regex]::Escape($ver) + '\]')
    $maxSess = if ($iniContent -match '45344fe7-00e6-4ac6-9f01-d01fd4ffadfb-MaxSessions=(\d+)') { $Matches[1] } else { 'n/a' }
    
    $pt  = try { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions' -EA SilentlyContinue).ProductType } catch { '?' }
    $lic = try { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\RCM\Licensing Core' -EA SilentlyContinue).LicensingMode } catch { '?' }
    
    $loaded   = Test-WrapperLoaded
    $listening = Test-Listener
    $bootTask  = [bool](Get-ScheduledTask -TaskName 'RDPWrap-SelfHeal-Boot' -EA SilentlyContinue)
    $dailyTask = [bool](Get-ScheduledTask -TaskName 'RDPWrap-SelfHeal-Daily' -EA SilentlyContinue)
    $sessions  = Get-ActiveSessions

    $overall = 'Healthy'
    if (-not $loaded -or -not $listening -or -not $hasIni) {
        $overall = 'Repair Needed'
    }

    $obj = [ordered]@{
        overallStatus  = $overall
        productType    = $pt
        licensingMode  = $lic
        termsrvVersion = $ver
        iniHasBuild    = $hasIni
        maxSessions    = $maxSess
        wrapperLoaded  = $loaded
        listener3389   = $listening
        bootTask       = $bootTask
        dailyTask      = $dailyTask
        sessions       = $sessions
        timestamp      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }
    return ($obj | ConvertTo-Json -Depth 4)
}

function Get-LogContent {
    if (-not (Test-Path $LogDir)) { return "No log directory found at $LogDir" }
    $latest = Get-ChildItem -Path $LogDir -Filter '*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { return "No log files found in $LogDir" }
    return Get-Content -LiteralPath $latest.FullName -Raw -Tail 150 -ErrorAction SilentlyContinue
}

# Start HttpListener
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($Prefix)

try {
    $listener.Start()
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "  RDPWrap Self-Heal Dashboard Server Active!" -ForegroundColor Cyan
    Write-Host "  URL: $Prefix" -ForegroundColor Yellow
    Write-Host "  Press Ctrl+C in this window to stop the server." -ForegroundColor Gray
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "Failed to start listener on $Prefix : $_" -ForegroundColor Red
    Write-Host "Ensure you run as Administrator or reserve the URL prefix." -ForegroundColor Yellow
    exit 1
}

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        
        $path = $request.Url.AbsolutePath
        $method = $request.HttpMethod

        # CORS Headers
        $response.AddHeader("Access-Control-Allow-Origin", "*")
        $response.AddHeader("Access-Control-Allow-Headers", "Content-Type")
        $response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")

        if ($method -eq "OPTIONS") {
            $response.StatusCode = 200
            $response.Close()
            continue
        }

        # Routing
        if ($path -eq "/api/status" -and $method -eq "GET") {
            $json = Get-SystemStatusJson
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq "/api/repair" -and $method -eq "POST") {
            Write-Host "Dashboard repair triggered..." -ForegroundColor Yellow
            $out = powershell -ExecutionPolicy Bypass -File "$ScriptPath" -Mode Repair -Force 2>&1 | Out-String
            $resObj = @{ success = $true; output = $out } | ConvertTo-Json
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($resObj)
            $response.ContentType = "application/json"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq "/api/disconnect" -and $method -eq "POST") {
            $id = $request.QueryString["id"]
            if ($id) {
                Write-Host "Disconnecting session $id..." -ForegroundColor Yellow
                & logoff $id 2>&1 | Out-Null
                $resObj = @{ success = $true; message = "Logged off session $id" } | ConvertTo-Json
            } else {
                $resObj = @{ success = $false; message = "Session ID missing" } | ConvertTo-Json
            }
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($resObj)
            $response.ContentType = "application/json"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq "/api/logs" -and $method -eq "GET") {
            $logsText = Get-LogContent
            $resObj = @{ logs = $logsText } | ConvertTo-Json
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($resObj)
            $response.ContentType = "application/json"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        else {
            # Static File Serving
            $fileRelative = if ($path -eq "/") { "index.html" } else { $path.TrimStart('/') }
            $filePath = Join-Path $ScriptDir $fileRelative
            
            if (Test-Path $filePath -PathType Leaf) {
                $bytes = [System.IO.File]::ReadAllBytes($filePath)
                $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
                $mime = switch ($ext) {
                    ".html" { "text/html" }
                    ".css"  { "text/css" }
                    ".js"   { "application/javascript" }
                    ".png"  { "image/png" }
                    ".jpg"  { "image/jpeg" }
                    ".svg"  { "image/svg+xml" }
                    ".ico"  { "image/x-icon" }
                    default { "application/octet-stream" }
                }
                $response.ContentType = $mime
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $response.StatusCode = 404
                $msg = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
                $response.OutputStream.Write($msg, 0, $msg.Length)
            }
        }
        $response.Close()
    } catch {
        Write-Host "Error handling request: $_" -ForegroundColor Red
    }
}
