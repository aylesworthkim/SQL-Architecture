<#
    NEWKS-SAGE_discovery.ps1  —  READ-ONLY discovery for the Sage FAS app host.

    HOW TO RUN
      1. RDP into NEWKS-SAGE.
      2. Right-click Start -> "Windows PowerShell (Admin)".
      3. Save this to C:\Temp\NEWKS-SAGE_discovery.ps1 and run:
             powershell -ExecutionPolicy Bypass -File C:\Temp\NEWKS-SAGE_discovery.ps1
      4. It writes  C:\Temp\NEWKS-SAGE_discovery_<date>.txt  — paste that back to Claude.

    Only READS. Starts nothing, stops nothing, changes no config.

    WHY WE'RE LOOKING
      We are moving Sage Fixed Assets off this VM (and off NEWKS-SQL) onto Cynthia's
      workstation with a local SQL Server Express, so BOTH VMs can be retired.
      Sage is the LAST blocker to retiring NEWKS-SQL.

    THE FIVE QUESTIONS THIS ANSWERS
      1. Exact Sage product, version, edition and build — the local reinstall must match
         or the restored FAS databases won't open.
      2. Where is the SERIAL NUMBER / activation code? Without it there is no reinstall.
      3. What does the app point at today (engine + system database), and where is the
         network install share other workstations pull from?
      4. Is Cynthia the only user, or is someone else still connecting?
      5. Does anything ELSE live on this box that we'd lose by deleting it?
#>

$ErrorActionPreference = 'SilentlyContinue'
$stamp  = Get-Date -Format 'yyyy-MM-dd'
$outDir = 'C:\Temp'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$out = Join-Path $outDir "NEWKS-SAGE_discovery_$stamp.txt"

function Section($title) {
    Add-Content $out ''
    Add-Content $out ('=' * 78)
    Add-Content $out "== $title"
    Add-Content $out ('=' * 78)
    Write-Host "  $title" -ForegroundColor Cyan
}
function Emit($obj) { $obj | Out-String -Width 220 | Add-Content $out }

Set-Content $out "NEWKS-SAGE discovery  --  $(Get-Date)"
Write-Host "Writing $out" -ForegroundColor Green

# ── 1. Machine ────────────────────────────────────────────────────────
Section '1. Machine identity, size and uptime'
Emit (Get-CimInstance Win32_ComputerSystem |
      Select-Object Name, Domain, Manufacturer, Model, NumberOfLogicalProcessors,
                    @{n='RAM_GB';e={[math]::Round($_.TotalPhysicalMemory/1GB,1)}})
Emit (Get-CimInstance Win32_OperatingSystem |
      Select-Object Caption, Version, OSArchitecture, InstallDate, LastBootUpTime,
                    @{n='UptimeDays';e={[math]::Round(((Get-Date)-$_.LastBootUpTime).TotalDays,1)}})
Emit (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
      Select-Object DeviceID, VolumeName,
                    @{n='Size_GB';e={[math]::Round($_.Size/1GB,1)}},
                    @{n='Free_GB';e={[math]::Round($_.FreeSpace/1GB,1)}})

# ── 2. Sage product identity ──────────────────────────────────────────
Section '2. Sage / Best Software installed products — VERSION MUST MATCH ON REINSTALL'
Emit (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                       'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
      Where-Object { $_.DisplayName -match 'Sage|Best|Fixed Asset|FAS|Depreciation|Crystal' } |
      Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation,
                    UninstallString |
      Sort-Object DisplayName)

Add-Content $out '--- SBDDESKTOP.exe / Sage binaries: exact file versions ---'
$sageDirs = @(
    'C:\Program Files (x86)\Sage Fixed Assets',
    'C:\Program Files\Sage Fixed Assets',
    'C:\Program Files (x86)\Best Software',
    'C:\Program Files\Best Software',
    'C:\Program Files (x86)\Sage',
    'C:\Program Files\Sage'
) | Where-Object { Test-Path $_ }
Add-Content $out ("Sage install roots found: " + ($(if ($sageDirs) { $sageDirs -join ' ; ' } else { 'NONE at the usual paths' })))
foreach ($d in $sageDirs) {
    Emit (Get-ChildItem $d -Recurse -Include 'SBDDESKTOP.exe','*.exe' -File -Depth 3 |
          Select-Object -First 40 FullName, Length,
                        @{n='FileVersion';e={$_.VersionInfo.FileVersion}},
                        @{n='Product';e={$_.VersionInfo.ProductName}},
                        LastWriteTime)
}
Add-Content $out '--- Fallback: any SBDDESKTOP.exe anywhere on C: ---'
Emit (Get-ChildItem C:\ -Recurse -Filter 'SBDDESKTOP.exe' -File -Depth 6 |
      Select-Object FullName, @{n='FileVersion';e={$_.VersionInfo.FileVersion}}, LastWriteTime)

# ── 3. LICENSE / ACTIVATION — the thing that blocks a reinstall ───────
Section '3. LICENSE / SERIAL / ACTIVATION (critical for reinstalling on Cynthia''s PC)'
Add-Content $out '--- Sage registry hives (serial, customer number, activation code often live here) ---'
foreach ($hive in @('HKLM:\SOFTWARE\WOW6432Node\Best Software',
                    'HKLM:\SOFTWARE\Best Software',
                    'HKLM:\SOFTWARE\WOW6432Node\Sage',
                    'HKLM:\SOFTWARE\Sage')) {
    if (Test-Path $hive) {
        Add-Content $out "  HIVE: $hive"
        Emit (Get-ChildItem $hive -Recurse -ErrorAction SilentlyContinue |
              ForEach-Object {
                  $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                  foreach ($n in $props.PSObject.Properties.Name) {
                      if ($n -notmatch '^PS') {
                          [pscustomobject]@{ Key = $_.PSPath -replace '.*CurrentControlSet|.*SOFTWARE',''
                                             Name = $n; Value = $props.$n }
                      }
                  }
              } | Where-Object { $_.Name -match 'Serial|License|Activat|Customer|Reg|Version|Path|Server|Edition|Key' })
    } else { Add-Content $out "  (absent) $hive" }
}
Add-Content $out '--- Sage .INI / config files (BEST.INI, SAGEFAS.INI, *.config) ---'
Emit (Get-ChildItem C:\ -Recurse -Include 'BEST.INI','SAGEFAS.INI','FAS.INI','*.ini' -File -Depth 5 |
      Where-Object { $_.DirectoryName -match 'Sage|Best|FAS' } |
      Select-Object FullName, Length, LastWriteTime)
Add-Content $out '--- Contents of any Sage .INI found (connection + license settings live here) ---'
Get-ChildItem C:\ -Recurse -Include '*.ini' -File -Depth 5 |
  Where-Object { $_.DirectoryName -match 'Sage|Best|FAS' } |
  Select-Object -First 10 |
  ForEach-Object {
      Add-Content $out ''
      Add-Content $out ("--- FILE: " + $_.FullName + " ---")
      Get-Content $_.FullName -TotalCount 120 | Add-Content $out
  }

# ── 4. What DB server does it point at? ───────────────────────────────
Section '4. Database connection — engine + system DB it uses today'
Add-Content $out 'Expected from prior investigation: Engine = newks-SQL, System DB = BESTSYS.'
Add-Content $out '--- SQL client aliases (we removed a bad newks-sql->sql-prod alias here before; confirm it is gone) ---'
foreach ($k in @('HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\MSSQLServer\Client\ConnectTo')) {
    Add-Content $out "  $k"
    if (Test-Path $k) { Emit (Get-ItemProperty $k) } else { Add-Content $out '    (no aliases defined - good)' }
}
Add-Content $out '--- Is a SQL Server engine installed ON this box, or is it purely the app host? ---'
Emit (Get-Service | Where-Object { $_.Name -match '^MSSQL|^SQLAgent|^SQLBrowser' } |
      Select-Object Name, DisplayName, Status, StartType)
Add-Content $out '--- ODBC data sources ---'
foreach ($k in @('HKLM:\SOFTWARE\ODBC\ODBC.INI',
                 'HKLM:\SOFTWARE\WOW6432Node\ODBC\ODBC.INI')) {
    if (Test-Path $k) { Emit (Get-ChildItem $k | Select-Object PSChildName) }
}

# ── 5. The network install share ──────────────────────────────────────
Section '5. Shares — the client/server install point other workstations use'
Emit (Get-SmbShare | Where-Object { $_.Name -notmatch '^\w\$$|^ADMIN\$|^IPC\$' } |
      Select-Object Name, Path, Description)
Add-Content $out '--- Share permissions (who can reach the install point) ---'
Get-SmbShare | Where-Object { $_.Name -notmatch '^\w\$$|^ADMIN\$|^IPC\$' } | ForEach-Object {
    Add-Content $out "  SHARE: $($_.Name)  ->  $($_.Path)"
    Emit (Get-SmbShareAccess -Name $_.Name)
}
Add-Content $out '--- Open sessions / files RIGHT NOW (is anyone using this box?) ---'
Emit (Get-SmbSession | Select-Object ClientComputerName, ClientUserName, NumOpens)
Emit (Get-SmbOpenFile | Select-Object ClientComputerName, ClientUserName, Path)

# ── 6. Who actually uses it ───────────────────────────────────────────
Section '6. WHO USES THIS BOX — is Cynthia the only one? (last 30 days)'
$since = (Get-Date).AddDays(-30)
Emit (Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4624; StartTime=$since} -MaxEvents 6000 |
      ForEach-Object {
        $x = [xml]$_.ToXml()
        [pscustomobject]@{
            User = ($x.Event.EventData.Data | Where-Object Name -eq 'TargetUserName').'#text'
            Type = ($x.Event.EventData.Data | Where-Object Name -eq 'LogonType').'#text'
            From = ($x.Event.EventData.Data | Where-Object Name -eq 'IpAddress').'#text'
            When = $_.TimeCreated
        }
      } |
      Where-Object { $_.User -notmatch '\$$|^SYSTEM$|^LOCAL SERVICE$|^NETWORK SERVICE$|^DWM-|^UMFD-|^ANONYMOUS' } |
      Group-Object User |
      Select-Object @{n='User';e={$_.Name}}, Count,
                    @{n='LastSeen';e={($_.Group | Sort-Object When -Descending | Select-Object -First 1).When}},
                    @{n='LogonTypes';e={($_.Group.Type | Sort-Object -Unique) -join ','}} |
      Sort-Object Count -Descending)
Add-Content $out 'LogonType key: 2=interactive/console 3=network(share) 10=RDP 5=service'

Add-Content $out '--- User profiles that exist on this box (who has ever logged in) ---'
Emit (Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special } |
      Select-Object LocalPath, LastUseTime | Sort-Object LastUseTime -Descending)

# ── 7. Anything ELSE on this box? ─────────────────────────────────────
Section '7. Is Sage really all this box does?'
Add-Content $out '--- Running services that are NOT stock Microsoft ---'
Emit (Get-CimInstance Win32_Service |
      Where-Object { $_.State -eq 'Running' -and $_.PathName -notmatch 'C:\\Windows\\(system32|SysWOW64)\\' } |
      Select-Object Name, DisplayName, StartMode, PathName, StartName | Sort-Object Name)
Add-Content $out '--- Non-Microsoft scheduled tasks ---'
Emit (Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } |
      ForEach-Object {
        $i = $_ | Get-ScheduledTaskInfo
        [pscustomobject]@{
            Task = $_.TaskName; State = $_.State; RunAs = $_.Principal.UserId
            LastRun = $i.LastRunTime; LastRC = $i.LastTaskResult; NextRun = $i.NextRunTime
            Action = ($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' ; '
        }
      } | Sort-Object LastRun -Descending)
Add-Content $out '--- Listening ports ---'
Emit (Get-NetTCPConnection -State Listen |
      Select-Object LocalAddress, LocalPort,
                    @{n='Process';e={(Get-Process -Id $_.OwningProcess).ProcessName}} |
      Sort-Object LocalPort -Unique)
Add-Content $out '--- Established connections (what this box talks to) ---'
Emit (Get-NetTCPConnection -State Established |
      Where-Object { $_.RemoteAddress -notin '127.0.0.1','::1' } |
      Select-Object LocalPort, RemoteAddress, RemotePort,
                    @{n='Process';e={(Get-Process -Id $_.OwningProcess).ProcessName}})
Add-Content $out '--- ALL installed software (confirm nothing else of value lives here) ---'
Emit (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                       'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
      Where-Object DisplayName |
      Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
      Sort-Object DisplayName -Unique)

# ── 8. Data on the box ────────────────────────────────────────────────
Section '8. Files changed in the last 90 days outside Windows (is data being written HERE?)'
$cut = (Get-Date).AddDays(-90)
Emit (Get-ChildItem C:\, D:\ -Recurse -File -Depth 5 |
      Where-Object { $_.LastWriteTime -gt $cut -and
                     $_.FullName -notmatch '\\Windows\\|\\Program Files( \(x86\))?\\Microsoft|\\ProgramData\\Microsoft\\|\\AppData\\Local\\(Temp|Microsoft)\\' } |
      Select-Object FullName, LastWriteTime, @{n='KB';e={[math]::Round($_.Length/1KB,1)}} |
      Sort-Object LastWriteTime -Descending | Select-Object -First 150)

Add-Content $out ''
Add-Content $out "Done: $(Get-Date)"
Write-Host ''
Write-Host 'FINISHED. Send this file to Claude:' -ForegroundColor Green
Write-Host "  $out" -ForegroundColor Yellow
Write-Host ''
Write-Host 'ALSO, by hand while you are in there:' -ForegroundColor Magenta
Write-Host '  * Open Sage FAS -> Help -> About. Screenshot it (version + serial number).' -ForegroundColor Gray
Write-Host '  * Open the "Configure System Database" dialog. Screenshot the engine + system DB.' -ForegroundColor Gray
