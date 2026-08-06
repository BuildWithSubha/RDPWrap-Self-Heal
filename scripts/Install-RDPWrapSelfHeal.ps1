#Requires -Version 5.1
<#
.SYNOPSIS
  RDPWrap Self-Heal — install / repair concurrent RDP after Windows Updates.

.DESCRIPTION
  Packages RDP Wrapper + OffsetFinder and keeps multi-session working when
  termsrv.dll changes. Uses FileVersionRaw (not the lagging FileVersion string).
  Forces SLPolicy admin MaxSessions=0 (critical on Windows Server).

.PARAMETER Mode
  Install | Repair | Status | Uninstall

.EXAMPLE
  .\Install-RDPWrapSelfHeal.ps1 -Mode Install
#>
[CmdletBinding()]
param(
    [ValidateSet('Install','Repair','Status','Uninstall')]
    [string]$Mode = 'Install',
    [string]$InstallDir = "$env:ProgramFiles\RDP Wrapper",
    [switch]$Force,
    [string]$CommunityIniUrl = 'https://raw.githubusercontent.com/sebaxakerhtc/rdpwrap.ini/master/rdpwrap.ini'
)

$ErrorActionPreference = 'Stop'

# Resolve package root (repo layout) OR installed layout under Program Files
$Script:PackageRoot = $null
if (Test-Path (Join-Path $PSScriptRoot 'bin\rdpwrap.dll')) {
    $Script:PackageRoot = $PSScriptRoot
} elseif (Test-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\rdpwrap.dll')) {
    $Script:PackageRoot = Split-Path $PSScriptRoot -Parent
}

$Script:BinDir       = if ($Script:PackageRoot) { Join-Path $Script:PackageRoot 'bin' } else { $null }
$Script:FinderDir    = if ($Script:PackageRoot) { Join-Path $Script:PackageRoot 'tools\OffsetFinder\64bit' } else { $null }
$Script:TermsrvDll   = Join-Path $env:SystemRoot 'System32\termsrv.dll'
$Script:IniPath      = Join-Path $InstallDir 'rdpwrap.ini'
$Script:DllPath      = Join-Path $InstallDir 'rdpwrap.dll'
$Script:InstExe      = Join-Path $InstallDir 'RDPWInst.exe'
$Script:FinderExe    = Join-Path $InstallDir 'RDPWrapOffsetFinder.exe'
$Script:LogDir       = Join-Path $InstallDir 'logs'
$Script:StableScript = Join-Path $InstallDir 'Install-RDPWrapSelfHeal.ps1'
$Script:SelfPath     = $MyInvocation.MyCommand.Path
$Script:TaskBoot     = 'RDPWrap-SelfHeal-Boot'
$Script:TaskDaily    = 'RDPWrap-SelfHeal-Daily'

try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

function Write-Log {
    param([string]$Message,[ValidateSet('INFO','WARN','ERROR','OK')][string]$Level='INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts][$Level] $Message"
    $color = switch ($Level) { 'ERROR'{'Red'} 'WARN'{'Yellow'} 'OK'{'Green'} default{'Gray'} }
    Write-Host $line -ForegroundColor $color
    try {
        if (-not (Test-Path $Script:LogDir)) { New-Item -ItemType Directory -Force -Path $Script:LogDir | Out-Null }
        $log = Join-Path $Script:LogDir ('selfheal_{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
        Add-Content -LiteralPath $log -Value $line -ErrorAction SilentlyContinue
    } catch {}
}

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script as Administrator.'
    }
}

function Get-TermsrvVersionRaw {
    if (-not (Test-Path $Script:TermsrvDll)) { throw "termsrv.dll not found: $($Script:TermsrvDll)" }
    $vi = (Get-Item $Script:TermsrvDll).VersionInfo
    # CRITICAL: use FileVersionRaw / Private part — string FileVersion often lags
    # (e.g. shows .32684 while raw is .33158 / .32230).
    return '{0}.{1}.{2}.{3}' -f $vi.FileMajorPart, $vi.FileMinorPart, $vi.FileBuildPart, $vi.FilePrivatePart
}

function Ensure-PackageFiles {
    if (-not $Script:BinDir) {
        # Already installed to Program Files — require deployed binaries
        foreach ($f in @($Script:DllPath, $Script:InstExe, $Script:IniPath, $Script:FinderExe)) {
            if (-not (Test-Path $f)) { throw "Missing installed file: $f (re-run -Mode Install from the package folder)" }
        }
        return
    }
    foreach ($f in @('rdpwrap.dll','RDPWInst.exe','rdpwrap.ini')) {
        $p = Join-Path $Script:BinDir $f
        if (-not (Test-Path $p)) { throw "Missing package file: $p" }
    }
    if (-not (Test-Path (Join-Path $Script:FinderDir 'RDPWrapOffsetFinder.exe'))) {
        throw "Missing OffsetFinder: $($Script:FinderDir)\RDPWrapOffsetFinder.exe"
    }
}

function Deploy-ToInstallDir {
    if (-not $Script:BinDir) { throw 'Deploy-ToInstallDir requires running from the package folder.' }
    if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null }
    Copy-Item (Join-Path $Script:BinDir '*') -Destination $InstallDir -Force
    Copy-Item (Join-Path $Script:FinderDir 'RDPWrapOffsetFinder.exe') -Destination $Script:FinderExe -Force
    foreach ($extra in @('RDPWrapOffsetFinder_nosymbol.exe','Zydis.dll','dbghelp.dll','symsrv.dll','symsrv.yes')) {
        $src = Join-Path $Script:FinderDir $extra
        if (Test-Path $src) { Copy-Item $src (Join-Path $InstallDir $extra) -Force }
    }
    if (Test-Path $Script:SelfPath) {
        Copy-Item $Script:SelfPath $Script:StableScript -Force
    }
    Write-Log "Deployed package files to $InstallDir" 'OK'
}

function Ensure-IniMaxSessionsUnlimited {
    if (-not (Test-Path $Script:IniPath)) { return }
    $text = Get-Content -LiteralPath $Script:IniPath -Raw
    $old = 'TerminalServices-RemoteConnectionManager-45344fe7-00e6-4ac6-9f01-d01fd4ffadfb-MaxSessions=2'
    $new = 'TerminalServices-RemoteConnectionManager-45344fe7-00e6-4ac6-9f01-d01fd4ffadfb-MaxSessions=0'
    if ($text -match [regex]::Escape($old)) {
        $text = $text.Replace($old, $new)
        [IO.File]::WriteAllText($Script:IniPath, $text, [Text.Encoding]::ASCII)
        Write-Log 'SLPolicy 45344fe7 MaxSessions set to 0 (Server-critical).' 'OK'
    } elseif ($text -match '45344fe7-00e6-4ac6-9f01-d01fd4ffadfb-MaxSessions=0') {
        Write-Log 'SLPolicy MaxSessions already 0.' 'OK'
    } else {
        Write-Log 'Could not find 45344fe7 MaxSessions line in ini.' 'WARN'
    }
}

function Ensure-Registry {
    $ts = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    New-ItemProperty -Path $ts -Name 'fDenyTSConnections' -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $ts -Name 'fSingleSessionPerUser' -Value 0 -PropertyType DWord -Force | Out-Null
    $pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    if (-not (Test-Path $pol)) { New-Item -Path $pol -Force | Out-Null }
    New-ItemProperty -Path $pol -Name 'fSingleSessionPerUser' -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $pol -Name 'MaxInstanceCount' -Value 999999 -PropertyType DWord -Force | Out-Null
    $rdp = Join-Path $ts 'WinStations\RDP-Tcp'
    if (Test-Path $rdp) {
        New-ItemProperty -Path $rdp -Name 'MaxInstanceCount' -Value 999999 -PropertyType DWord -Force | Out-Null
    }
    Write-Log 'Registry: RDP enabled, single-session off, high MaxInstanceCount.' 'OK'
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

function Install-WrapperHook {
    $sd = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\TermService\Parameters').ServiceDll
    if ($sd -like '*rdpwrap.dll' -and (Test-Path $Script:DllPath)) {
        if (Test-WrapperLoaded) { Write-Log 'RDP Wrapper already hooked and loaded.' 'OK'; return }
    }
    Write-Log 'Installing / re-hooking RDP Wrapper (RDPWInst -i)...'
    $out = & $Script:InstExe -i 2>&1 | Out-String
    Write-Log ($out.Trim() -replace '\s+', ' ')
    Start-Sleep -Seconds 2
}

function Backup-Ini {
    if (Test-Path $Script:IniPath) {
        $bak = '{0}.{1}.bak' -f $Script:IniPath, (Get-Date -Format 'yyyyMMdd_HHmmss')
        Copy-Item $Script:IniPath $bak -Force
        Write-Log "Backed up ini -> $bak" 'OK'
    }
}

function Parse-IniSections {
    param([string]$Text)
    $result = [ordered]@{}
    $current = $null
    foreach ($line in ($Text -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -match '^\[(.+)\]$') {
            $current = $Matches[1]
            $result[$current] = New-Object System.Collections.Generic.List[string]
        } elseif ($current -and $t.Length -gt 0 -and $t -notmatch '^;') {
            $result[$current].Add($t)
        }
    }
    return $result
}

function Get-OffsetsFromFinder {
    param([string]$Version)
    $exe = $Script:FinderExe
    if (-not (Test-Path $exe)) { $exe = Join-Path $Script:FinderDir 'RDPWrapOffsetFinder.exe' }
    Write-Log "Running OffsetFinder against termsrv.dll ($Version)..."
    $out = & $exe $Script:TermsrvDll 2>&1 | Out-String
    if ($out -notmatch '\[\d+\.\d+\.\d+\.\d+') {
        $nosym = Join-Path (Split-Path $exe) 'RDPWrapOffsetFinder_nosymbol.exe'
        if (Test-Path $nosym) { $out = & $nosym $Script:TermsrvDll 2>&1 | Out-String }
    }
    if ($out -notmatch '\[\d+\.\d+\.\d+\.\d+') {
        Write-Log 'OffsetFinder produced no usable sections.' 'WARN'
        return $null
    }
    $all = Parse-IniSections -Text $out
    $keep = [ordered]@{}
    foreach ($k in $all.Keys) {
        if ($k -eq $Version -or $k -eq "$Version-SLInit") { $keep[$k] = $all[$k] }
    }
    # If finder keyed different version string, take all numeric sections it emitted
    if ($keep.Count -eq 0) {
        foreach ($k in $all.Keys) {
            if ($k -match '^\d+\.\d+\.\d+\.\d+') { $keep[$k] = $all[$k] }
        }
    }
    if ($keep.Count -eq 0) { return $null }
    Write-Log ("OffsetFinder sections: {0}" -f ($keep.Keys -join ', ')) 'OK'
    return $keep
}

function Get-OffsetsFromCommunity {
    param([string]$Version)
    try {
        $tmp = Join-Path $env:TEMP 'community_rdpwrap.ini'
        Write-Log "Downloading community ini..."
        Invoke-WebRequest -Uri $CommunityIniUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 90
        $all = Parse-IniSections -Text (Get-Content $tmp -Raw)
        $keep = [ordered]@{}
        foreach ($k in @($Version, "$Version-SLInit")) {
            if ($all.Contains($k)) { $keep[$k] = $all[$k] }
        }
        if ($keep.Count -eq 0) { Write-Log "Community ini has no [$Version]." 'WARN'; return $null }
        Write-Log 'Community ini sections found.' 'OK'
        return $keep
    } catch {
        Write-Log "Community ini download failed: $_" 'WARN'
        return $null
    }
}

function Set-IniSectionText {
    param([string]$IniText,[string]$Section,[string[]]$Body)
    $lines = $IniText -split "`r?`n"
    $header = "[$Section]"
    $bodyText = ($Body -join [Environment]::NewLine)
    $sb = New-Object System.Text.StringBuilder
    $i = 0; $replaced = $false
    while ($i -lt $lines.Count) {
        if ($lines[$i].Trim() -eq $header) {
            [void]$sb.AppendLine($header)
            [void]$sb.AppendLine($bodyText)
            $replaced = $true
            $i++
            while ($i -lt $lines.Count -and $lines[$i].Trim() -notmatch '^\[') { $i++ }
            [void]$sb.AppendLine('')
            continue
        }
        [void]$sb.AppendLine($lines[$i])
        $i++
    }
    if (-not $replaced) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine($header)
        [void]$sb.AppendLine($bodyText)
    }
    return $sb.ToString()
}

function Apply-Offsets {
    param($Sections)
    Backup-Ini
    $text = Get-Content -LiteralPath $Script:IniPath -Raw
    foreach ($sec in $Sections.Keys) {
        $text = Set-IniSectionText -IniText $text -Section $sec -Body @($Sections[$sec])
    }
    [IO.File]::WriteAllText($Script:IniPath, $text, [Text.Encoding]::ASCII)
    Ensure-IniMaxSessionsUnlimited
    Write-Log ("Applied sections: {0}" -f ($Sections.Keys -join ', ')) 'OK'
}

function Restart-TermService {
    Write-Log 'Restarting TermService (active RDP sessions may drop briefly)...' 'WARN'
    try { Stop-Service UmRdpService -Force -EA SilentlyContinue } catch {}
    Stop-Service TermService -Force
    Start-Sleep -Seconds 2
    Start-Service TermService
    try { Start-Service UmRdpService -EA SilentlyContinue } catch {}
    Start-Sleep -Seconds 3
    Write-Log 'TermService restarted.' 'OK'
}

function Invoke-Repair {
    Assert-Admin
    Ensure-PackageFiles
    if (-not (Test-Path $Script:DllPath)) { Deploy-ToInstallDir }
    $ver = Get-TermsrvVersionRaw
    Write-Log "termsrv FileVersionRaw = $ver"
    Ensure-Registry
    Ensure-IniMaxSessionsUnlimited
    Install-WrapperHook

    $iniText = if (Test-Path $Script:IniPath) { Get-Content $Script:IniPath -Raw } else { '' }
    $has = $iniText -match ('(?m)^\[' + [regex]::Escape($ver) + '\]')
    $need = $Force -or (-not $has) -or (-not (Test-WrapperLoaded)) -or (-not (Test-Listener))

    if ($need) {
        $sections = Get-OffsetsFromFinder -Version $ver
        if (-not $sections) { $sections = Get-OffsetsFromCommunity -Version $ver }
        if (-not $sections) { throw "No offsets for $ver (OffsetFinder + community failed)." }
        Apply-Offsets -Sections $sections
        Restart-TermService
    } else {
        Write-Log "Build $ver already present; wrapper loaded. Use -Force to regenerate." 'OK'
        # Still enforce MaxSessions and registry
        Ensure-IniMaxSessionsUnlimited
    }

    $loaded = Test-WrapperLoaded
    $listen = Test-Listener
    Write-Log ("Verify: wrapper_loaded=$loaded listener_3389=$listen") ($(if ($loaded -and $listen) {'OK'} else {'WARN'}))
    Write-Log 'Test with: query user   (need 3+ Active users). RDPConf green alone is not proof.' 'INFO'
    Write-Log 'If still capped at 2 on Windows Server after patches: that may be SKU licensing — see README.' 'WARN'
}

function Install-All {
    Assert-Admin
    Ensure-PackageFiles
    Deploy-ToInstallDir
    Ensure-IniMaxSessionsUnlimited

    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$Script:StableScript`" -Mode Repair"
    $action = New-ScheduledTaskAction -Execute $ps -Argument $arg
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

    $boot = New-ScheduledTaskTrigger -AtStartup
    try { $boot.Delay = 'PT2M' } catch {}
    Register-ScheduledTask -TaskName $Script:TaskBoot -Action $action -Principal $principal -Settings $settings -Trigger $boot -Force | Out-Null
    Write-Log "Registered task $Script:TaskBoot (~2 min after every reboot)." 'OK'

    $daily = New-ScheduledTaskTrigger -Daily -At 3am
    Register-ScheduledTask -TaskName $Script:TaskDaily -Action $action -Principal $principal -Settings $settings -Trigger $daily -Force | Out-Null
    Write-Log "Registered task $Script:TaskDaily (daily 03:00)." 'OK'

    Invoke-Repair
    Write-Log 'INSTALL COMPLETE.' 'OK'
}

function Uninstall-Tasks {
    Assert-Admin
    foreach ($t in @($Script:TaskBoot, $Script:TaskDaily)) {
        try { Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction Stop; Write-Log "Removed $t" 'OK' }
        catch { Write-Log "Task not found: $t" 'WARN' }
    }
    Write-Log 'Self-heal tasks removed. To fully remove RDP Wrapper run: RDPWInst.exe -u' 'OK'
}

function Show-Status {
    $ver = try { Get-TermsrvVersionRaw } catch { 'unknown' }
    $ini = if (Test-Path $Script:IniPath) { Get-Content $Script:IniPath -Raw } else { '' }
    $has = $ini -match ('(?m)^\[' + [regex]::Escape($ver) + '\]')
    $max = if ($ini -match '45344fe7-00e6-4ac6-9f01-d01fd4ffadfb-MaxSessions=(\d+)') { $Matches[1] } else { 'n/a' }
    $pt = try { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions').ProductType } catch { '?' }
    $lic = try { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\RCM\Licensing Core').LicensingMode } catch { '?' }
    Write-Host ''
    Write-Host '==== RDPWrap Self-Heal Status ====' -ForegroundColor Cyan
    Write-Host "ProductType            : $pt  (WinNT=client, ServerNT=server)"
    Write-Host "LicensingMode          : $lic  (1=Remote Admin / 2-session native on Server)"
    Write-Host "termsrv FileVersionRaw : $ver"
    Write-Host "ini has [$ver]         : $has"
    Write-Host "SLPolicy MaxSessions   : $max  (should be 0)"
    Write-Host "ServiceDll             : $((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\TermService\Parameters' -EA SilentlyContinue).ServiceDll)"
    Write-Host "rdpwrap.dll loaded     : $(Test-WrapperLoaded)"
    Write-Host "Listener :3389         : $(Test-Listener)"
    Write-Host "Boot task              : $([bool](Get-ScheduledTask -TaskName $Script:TaskBoot -EA SilentlyContinue))"
    Write-Host "Daily task             : $([bool](Get-ScheduledTask -TaskName $Script:TaskDaily -EA SilentlyContinue))"
    Write-Host ''
    Write-Host 'Active sessions:' -ForegroundColor Cyan
    try {
        & query user 2>$null
    } catch {
        Write-Host "  (query.exe not available or failed: $($_.Exception.Message))" -ForegroundColor Gray
    }
    Write-Host ''
}

try {
    Write-Log "=== start Mode=$Mode PackageRoot=$($Script:PackageRoot) ==="
    switch ($Mode) {
        'Install'   { Install-All }
        'Repair'    { Invoke-Repair }
        'Status'    { Show-Status }
        'Uninstall' { Uninstall-Tasks }
    }
    Write-Log "=== done Mode=$Mode ==="
} catch {
    Write-Log "FATAL: $($_.Exception.Message)" 'ERROR'
    exit 1
}
