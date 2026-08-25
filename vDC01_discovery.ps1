<#
    vDC01_discovery.ps1  —  READ-ONLY discovery for the unknown VM "vDC01".

    HOW TO RUN
      1. RDP into vDC01.
      2. Right-click Start -> "Windows PowerShell (Admin)"  (or Terminal (Admin)).
      3. Paste this whole file in, or save it to C:\Temp\vDC01_discovery.ps1 and run:
             powershell -ExecutionPolicy Bypass -File C:\Temp\vDC01_discovery.ps1
      4. It writes  C:\Temp\vDC01_discovery_<date>.txt  — copy that back and paste it to Claude.

    This script only READS. It starts nothing, stops nothing, and changes no config.

    WHAT WE'RE TRYING TO ANSWER
      * Is this an Active Directory domain controller for nfc.local? (the name says so)
      * Is it the DNS server that resolves sql-prod.nfc.local / dev-jan02 / forms.nfc.local?
      * Is it running DHCP, certificate services, file shares, or anything else load-bearing?
      * WHO is still talking to it — i.e. what actually breaks if we shut it off?
#>

$ErrorActionPreference = 'SilentlyContinue'
$stamp  = Get-Date -Format 'yyyy-MM-dd'
$outDir = 'C:\Temp'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$out = Join-Path $outDir "vDC01_discovery_$stamp.txt"

function Section($title) {
    $line = '=' * 78
    Add-Content $out ''
    Add-Content $out $line
    Add-Content $out "== $title"
    Add-Content $out $line
    Write-Host "  $title" -ForegroundColor Cyan
}
function Emit($obj) { $obj | Out-String -Width 200 | Add-Content $out }

Set-Content $out "vDC01 discovery  --  $(Get-Date)"
Write-Host "Writing $out" -ForegroundColor Green

# ── 1. Identity & uptime ──────────────────────────────────────────────
Section '1. Machine identity'
Emit (Get-CimInstance Win32_ComputerSystem |
      Select-Object Name, Domain, DomainRole, Manufacturer, Model,
                    NumberOfLogicalProcessors, @{n='RAM_GB';e={[math]::Round($_.TotalPhysicalMemory/1GB,1)}})
Emit (Get-CimInstance Win32_OperatingSystem |
      Select-Object Caption, Version, BuildNumber, OSArchitecture, InstallDate,
                    @{n='LastBoot';e={$_.LastBootUpTime}},
                    @{n='UptimeDays';e={[math]::Round(((Get-Date) - $_.LastBootUpTime).TotalDays,1)}})
# DomainRole: 0/1 = workstation, 2/3 = member server, 4 = BACKUP DC, 5 = PRIMARY DC
Add-Content $out 'DomainRole key: 0-1 workstation | 2-3 member server | 4 BACKUP DC | 5 PRIMARY DC'

# ── 2. Installed roles ────────────────────────────────────────────────
Section '2. Installed Windows roles & features (installed only)'
Emit (Get-WindowsFeature | Where-Object Installed |
      Select-Object Name, DisplayName | Sort-Object Name)

# ── 3. Active Directory ───────────────────────────────────────────────
Section '3. Active Directory — is this a domain controller?'
if (Get-Command Get-ADDomain -ErrorAction SilentlyContinue) {
    Add-Content $out '--- Domain ---'
    Emit (Get-ADDomain | Select-Object DNSRoot, NetBIOSName, DomainMode, PDCEmulator,
                                       RIDMaster, InfrastructureMaster)
    Add-Content $out '--- Forest ---'
    Emit (Get-ADForest | Select-Object Name, ForestMode, SchemaMaster, DomainNamingMaster,
                                       @{n='GlobalCatalogs';e={$_.GlobalCatalogs -join ', '}})
    Add-Content $out '--- ALL domain controllers in the domain (is vDC01 the only one?) ---'
    Emit (Get-ADDomainController -Filter * |
          Select-Object Name, HostName, IPv4Address, Site, IsGlobalCatalog, IsReadOnly,
                        OperatingSystem)
    Add-Content $out '--- FSMO role holders (if vDC01 holds these, it cannot just be deleted) ---'
    Emit (netdom query fsmo)
    Add-Content $out '--- Replication health ---'
    Emit (repadmin /replsummary)
    Add-Content $out '--- Enabled user accounts (how many identities depend on this?) ---'
    Emit (Get-ADUser -Filter 'Enabled -eq $true' -Properties LastLogonDate |
          Select-Object SamAccountName, Name, LastLogonDate |
          Sort-Object LastLogonDate -Descending)
    Add-Content $out '--- Computer accounts joined to the domain ---'
    Emit (Get-ADComputer -Filter * -Properties OperatingSystem, LastLogonDate |
          Select-Object Name, OperatingSystem, LastLogonDate |
          Sort-Object LastLogonDate -Descending)
} else {
    Add-Content $out 'AD PowerShell module NOT present — this is very likely NOT a domain controller.'
    Emit (nltest /dsgetdc:$env:USERDNSDOMAIN)
}

# ── 4. DNS ────────────────────────────────────────────────────────────
Section '4. DNS server — does nfc.local name resolution live here?'
if (Get-Command Get-DnsServerZone -ErrorAction SilentlyContinue) {
    Emit (Get-DnsServerZone | Select-Object ZoneName, ZoneType, IsDsIntegrated,
                                            IsReverseLookupZone, DynamicUpdate)
    Add-Content $out '--- A records in the primary forward zone(s) ---'
    foreach ($z in (Get-DnsServerZone | Where-Object { -not $_.IsReverseLookupZone -and $_.ZoneType -eq 'Primary' })) {
        Add-Content $out "  ZONE: $($z.ZoneName)"
        Emit (Get-DnsServerResourceRecord -ZoneName $z.ZoneName -RRType A |
              Select-Object HostName, @{n='IP';e={$_.RecordData.IPv4Address}})
    }
    Add-Content $out '--- Forwarders ---'
    Emit (Get-DnsServerForwarder)
} else {
    Add-Content $out 'DNS Server role not installed.'
}
Add-Content $out '--- What DNS servers do this box''s own NICs point at? ---'
Emit (Get-DnsClientServerAddress -AddressFamily IPv4 |
      Select-Object InterfaceAlias, @{n='DnsServers';e={$_.ServerAddresses -join ', '}})

# ── 5. DHCP / CA / other infrastructure roles ─────────────────────────
Section '5. DHCP, Certificate Services, and other infrastructure roles'
if (Get-Command Get-DhcpServerv4Scope -ErrorAction SilentlyContinue) {
    Add-Content $out '--- DHCP scopes (if this serves DHCP, killing it drops client leases) ---'
    Emit (Get-DhcpServerv4Scope | Select-Object ScopeId, Name, State, StartRange, EndRange, LeaseDuration)
    Emit (Get-DhcpServerv4Statistics)
} else { Add-Content $out 'DHCP Server role not installed.' }

if (Get-Command Get-CertificationAuthority -ErrorAction SilentlyContinue) {
    Emit (Get-CertificationAuthority)
} else {
    Add-Content $out 'No AD Certificate Services cmdlets. Checking service...'
    Emit (Get-Service certsvc | Select-Object Name, DisplayName, Status, StartType)
}

# ── 6. Services ───────────────────────────────────────────────────────
Section '6. Running services that are NOT stock Microsoft'
Emit (Get-CimInstance Win32_Service | Where-Object {
        $_.State -eq 'Running' -and
        $_.PathName -notmatch 'C:\\Windows\\(system32|SysWOW64)\\' } |
      Select-Object Name, DisplayName, StartMode, PathName, StartName |
      Sort-Object Name)

# ── 7. Scheduled tasks ────────────────────────────────────────────────
Section '7. Non-Microsoft scheduled tasks (the usual home for orphaned jobs)'
Emit (Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } |
      ForEach-Object {
        $i = $_ | Get-ScheduledTaskInfo
        [pscustomobject]@{
            Task     = $_.TaskName
            Path     = $_.TaskPath
            State    = $_.State
            RunAs    = $_.Principal.UserId
            LastRun  = $i.LastRunTime
            LastRC   = $i.LastTaskResult
            NextRun  = $i.NextRunTime
            Action   = ($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' ; '
        }
      } | Sort-Object LastRun -Descending)

# ── 8. Shares ─────────────────────────────────────────────────────────
Section '8. File shares (non-administrative)'
Emit (Get-SmbShare | Where-Object { $_.Name -notmatch '^\w\$$|^ADMIN\$|^IPC\$' } |
      Select-Object Name, Path, Description)
Add-Content $out '--- Open sessions right now (who is USING this box?) ---'
Emit (Get-SmbSession | Select-Object ClientComputerName, ClientUserName, NumOpens)
Emit (Get-SmbOpenFile | Select-Object ClientComputerName, ClientUserName, Path)

# ── 9. Network — who is connected ─────────────────────────────────────
Section '9. Network: listening ports and established connections'
Emit (Get-NetIPAddress -AddressFamily IPv4 |
      Where-Object { $_.IPAddress -ne '127.0.0.1' } |
      Select-Object InterfaceAlias, IPAddress, PrefixLength)
Add-Content $out '--- Listening ports (with owning process) ---'
Emit (Get-NetTCPConnection -State Listen |
      Select-Object LocalAddress, LocalPort,
                    @{n='Process';e={(Get-Process -Id $_.OwningProcess).ProcessName}} |
      Sort-Object LocalPort -Unique)
Add-Content $out '--- Established connections — THIS is what breaks if the box goes away ---'
Emit (Get-NetTCPConnection -State Established |
      Where-Object { $_.RemoteAddress -notin '127.0.0.1','::1' } |
      Select-Object LocalPort, RemoteAddress, RemotePort,
                    @{n='Process';e={(Get-Process -Id $_.OwningProcess).ProcessName}} |
      Sort-Object RemoteAddress)

# ── 10. Who has been authenticating ───────────────────────────────────
Section '10. Recent successful logons (last 7 days) — the real dependency list'
$since = (Get-Date).AddDays(-7)
Emit (Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4624; StartTime=$since} -MaxEvents 4000 |
      ForEach-Object {
        $x = [xml]$_.ToXml()
        [pscustomobject]@{
            User = ($x.Event.EventData.Data | Where-Object Name -eq 'TargetUserName').'#text'
            Type = ($x.Event.EventData.Data | Where-Object Name -eq 'LogonType').'#text'
            From = ($x.Event.EventData.Data | Where-Object Name -eq 'IpAddress').'#text'
            Proc = ($x.Event.EventData.Data | Where-Object Name -eq 'ProcessName').'#text'
        }
      } |
      Where-Object { $_.User -notmatch '\$$|^SYSTEM$|^LOCAL SERVICE$|^NETWORK SERVICE$|^ANONYMOUS' } |
      Group-Object User, From |
      Select-Object @{n='User_From';e={$_.Name}}, Count |
      Sort-Object Count -Descending)

# ── 11. Installed software ────────────────────────────────────────────
Section '11. Installed software'
Emit (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                       'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
      Where-Object DisplayName |
      Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
      Sort-Object DisplayName -Unique)

# ── 12. Disks & recently-changed files ────────────────────────────────
Section '12. Disks'
Emit (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
      Select-Object DeviceID, VolumeName,
                    @{n='Size_GB';e={[math]::Round($_.Size/1GB,1)}},
                    @{n='Free_GB';e={[math]::Round($_.FreeSpace/1GB,1)}})

Section '13. Files changed in the last 30 days outside Windows (is anything still working here?)'
$cut = (Get-Date).AddDays(-30)
Emit (Get-ChildItem C:\ -Recurse -File -Depth 4 |
      Where-Object { $_.LastWriteTime -gt $cut -and
                     $_.FullName -notmatch '\\Windows\\|\\Program Files\\|\\ProgramData\\Microsoft\\|\\Users\\.*\\AppData\\' } |
      Select-Object FullName, LastWriteTime, @{n='KB';e={[math]::Round($_.Length/1KB,1)}} |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 120)

Add-Content $out ''
Add-Content $out "Done: $(Get-Date)"
Write-Host ''
Write-Host "FINISHED. Send this file to Claude:" -ForegroundColor Green
Write-Host "  $out" -ForegroundColor Yellow
