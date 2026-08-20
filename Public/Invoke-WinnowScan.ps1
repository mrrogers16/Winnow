#Requires -Version 5.1
Set-StrictMode -Version Latest

function Invoke-WinnowScan {
    <#
        .SYNOPSIS
            Read-only inventory of a Windows machine.

        .DESCRIPTION
            Collects apps, services, scheduled tasks, startup entries, privacy
            registry state, listening ports, and security posture into CSV/TXT
            files you can diff between runs.

            This function never writes outside -OutputPath. It contains no
            Remove-, Stop-, Disable-, Uninstall-, or Set-ItemProperty calls.

            Run elevated for full coverage - provisioned packages and some
            service detail are invisible otherwise.

        .PARAMETER OutputPath
            Directory to write into. Created if missing.
            Defaults to .\WinnowScan-<timestamp>.

        .PARAMETER PassThru
            Return the output directory path.

        .EXAMPLE
            Invoke-WinnowScan

        .EXAMPLE
            Invoke-WinnowScan -OutputPath C:\scans\before
    #>
    [CmdletBinding()]
    param(
        [string] $OutputPath,
        [switch] $PassThru
    )

    if (-not $OutputPath) {
        $OutputPath = Join-Path (Get-Location).Path ("WinnowScan-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        [void][System.IO.Directory]::CreateDirectory($OutputPath)
    }

    $ErrorActionPreference = 'Continue'
    $log      = New-Object System.Collections.Generic.List[string]
    $elevated = Test-WinnowElevated

    function Write-ScanNote([string] $m) {
        $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $m
        Write-Host $line
        $log.Add($line)
    }

    function Save-ScanFile($Data, [string] $FileName) {
        $p = Join-Path $OutputPath $FileName
        try {
            if ($null -eq $Data) { Write-ScanNote "  -> $FileName : no data"; return }
            if ($FileName -like '*.csv') {
                $Data | Export-Csv -LiteralPath $p -NoTypeInformation -Encoding UTF8
            } else {
                $Data | Out-File -LiteralPath $p -Encoding UTF8 -Width 500
            }
            Write-ScanNote ("  -> {0} ({1} rows)" -f $FileName, @($Data).Count)
        } catch {
            Write-ScanNote "  !! $FileName : $($_.Exception.Message)"
        }
    }

    Write-ScanNote 'Winnow read-only scan starting'
    Write-ScanNote "Elevated: $elevated"
    Write-ScanNote "Output:   $OutputPath"
    if (-not $elevated) { Write-ScanNote 'WARNING: not elevated - results will be incomplete.' }

    # 1 system -----------------------------------------------------------------
    Write-ScanNote '1/11 System identity'
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $bb = Get-CimInstance Win32_BaseBoard
        $bi = Get-CimInstance Win32_BIOS
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            Caption        = $os.Caption
            DisplayVersion = (Get-WinnowProp $cv 'DisplayVersion')
            Build          = $os.BuildNumber
            UBR            = (Get-WinnowProp $cv 'UBR')
            InstallDate    = $os.InstallDate
            LastBootUpTime = $os.LastBootUpTime
            Manufacturer   = $cs.Manufacturer
            Model          = $cs.Model
            BaseBoard      = "$($bb.Manufacturer) $($bb.Product)"
            BIOSVersion    = $bi.SMBIOSBIOSVersion
            TotalRAM_GB    = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
            PSVersion      = $PSVersionTable.PSVersion.ToString()
            Elevated       = $elevated
        } | Format-List | Out-String |
            Set-Content -LiteralPath (Join-Path $OutputPath '01_system.txt') -Encoding UTF8
        Write-ScanNote '  -> 01_system.txt'
    } catch { Write-ScanNote "  !! system: $($_.Exception.Message)" }

    # 2 appx installed ---------------------------------------------------------
    Write-ScanNote '2/11 Appx packages (installed)'
    try {
        $appx = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | ForEach-Object {
            [PSCustomObject]@{
                Name          = $_.Name
                Version       = $_.Version
                Publisher     = ($_.Publisher -replace '^CN=([^,]+).*', '$1')
                IsFramework   = $_.IsFramework
                NonRemovable  = $_.NonRemovable
                SignatureKind = $_.SignatureKind
                FullName      = $_.PackageFullName
            }
        } | Sort-Object Name
        Save-ScanFile $appx '02_appx_installed.csv'
    } catch { Write-ScanNote "  !! appx: $($_.Exception.Message)" }

    # 3 appx provisioned -------------------------------------------------------
    Write-ScanNote '3/11 Appx packages (provisioned)'
    try {
        Save-ScanFile (Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
              Select-Object DisplayName, PackageName, Version | Sort-Object DisplayName) '03_appx_provisioned.csv'
    } catch { Write-ScanNote "  !! provisioned: $($_.Exception.Message)" }

    # 4 installed programs -----------------------------------------------------
    Write-ScanNote '4/11 Installed programs'
    try {
        $keys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        $progs = foreach ($k in $keys) {
            Get-ItemProperty $k -ErrorAction SilentlyContinue |
                Where-Object { $_.PSObject.Properties.Name -contains 'DisplayName' -and $_.DisplayName } |
                ForEach-Object {
                    [PSCustomObject]@{
                        DisplayName     = $_.DisplayName
                        DisplayVersion  = (Get-WinnowProp $_ 'DisplayVersion')
                        Publisher       = (Get-WinnowProp $_ 'Publisher')
                        InstallDate     = (Get-WinnowProp $_ 'InstallDate')
                        EstimatedSizeMB = if (Get-WinnowProp $_ 'EstimatedSize') { [math]::Round((Get-WinnowProp $_ 'EstimatedSize') / 1024, 1) } else { $null }
                        InstallLocation = (Get-WinnowProp $_ 'InstallLocation')
                        UninstallString = (Get-WinnowProp $_ 'UninstallString')
                        SystemComponent = (Get-WinnowProp $_ 'SystemComponent')
                        Hive            = $k.Split(':')[0]
                    }
                }
        }
        Save-ScanFile ($progs | Sort-Object DisplayName) '04_programs.csv'
    } catch { Write-ScanNote "  !! programs: $($_.Exception.Message)" }

    # 5 services ---------------------------------------------------------------
    Write-ScanNote '5/11 Services'
    try {
        $svc = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | ForEach-Object {
            [PSCustomObject]@{
                Name        = $_.Name
                DisplayName = $_.DisplayName
                State       = $_.State
                StartMode   = $_.StartMode
                StartName   = $_.StartName
                PathName    = $_.PathName
                # OEM vendors drop binaries into C:\Windows; do not filter on path
                IsSystemPath= ($_.PathName -like '*C:\Windows\*')
                Description = $_.Description
            }
        }
        Save-ScanFile ($svc | Sort-Object Name) '05_services.csv'
    } catch { Write-ScanNote "  !! services: $($_.Exception.Message)" }

    # 6 scheduled tasks --------------------------------------------------------
    Write-ScanNote '6/11 Scheduled tasks'
    try {
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
            [PSCustomObject]@{
                TaskPath    = $_.TaskPath
                TaskName    = $_.TaskName
                State       = $_.State
                Author      = $_.Author
                Description = ($_.Description -replace '\r?\n', ' ')
                Actions     = (($_.Actions | ForEach-Object {
                                  "$(Get-WinnowProp $_ 'Execute') $(Get-WinnowProp $_ 'Arguments')" }) -join ' | ')
            }
        }
        Save-ScanFile ($tasks | Sort-Object TaskPath, TaskName) '06_scheduled_tasks.csv'
    } catch { Write-ScanNote "  !! tasks: $($_.Exception.Message)" }

    # 7 startup ----------------------------------------------------------------
    Write-ScanNote '7/11 Startup / autorun'
    try {
        $runKeys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
        )
        $startup = foreach ($rk in $runKeys) {
            $p = Get-ItemProperty $rk -ErrorAction SilentlyContinue
            if ($p) {
                $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } |
                    ForEach-Object { [PSCustomObject]@{ Source = $rk; Name = $_.Name; Command = $_.Value } }
            }
        }
        foreach ($f in @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
                         "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup")) {
            $startup += Get-ChildItem -LiteralPath $f -ErrorAction SilentlyContinue |
                ForEach-Object { [PSCustomObject]@{ Source = $f; Name = $_.Name; Command = $_.FullName } }
        }
        Save-ScanFile $startup '07_startup.csv'
    } catch { Write-ScanNote "  !! startup: $($_.Exception.Message)" }

    # 8 privacy registry -------------------------------------------------------
    Write-ScanNote '8/11 Privacy / telemetry registry state'
    $privPaths = @(
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'
        'HKLM:\SOFTWARE\Microsoft\SQMClient\Windows'
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
        'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy'
        'HKCU:\SOFTWARE\Microsoft\InputPersonalization'
        'HKCU:\SOFTWARE\Microsoft\Siuf\Rules'
    )
    try {
        $priv = foreach ($p in $privPaths) {
            if (Test-Path -LiteralPath $p) {
                (Get-ItemProperty $p -ErrorAction SilentlyContinue).PSObject.Properties |
                    Where-Object { $_.Name -notlike 'PS*' } |
                    ForEach-Object { [PSCustomObject]@{ Path = $p; Value = $_.Name; Data = "$($_.Value)" } }
            } else {
                [PSCustomObject]@{ Path = $p; Value = '(key does not exist)'; Data = '' }
            }
        }
        Save-ScanFile $priv '08_privacy_registry.csv'
    } catch { Write-ScanNote "  !! privacy: $($_.Exception.Message)" }

    # 9 network ----------------------------------------------------------------
    Write-ScanNote '9/11 Listening ports'
    try {
        $procs = @{}
        Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $procs[$_.Id] = $_.ProcessName }
        Save-ScanFile (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
                [PSCustomObject]@{
                    LocalAddress = $_.LocalAddress
                    LocalPort    = $_.LocalPort
                    ProcessId    = $_.OwningProcess
                    Process      = $procs[[int]$_.OwningProcess]
                }
              } | Sort-Object LocalPort) '09_listening_ports.csv'
    } catch { Write-ScanNote "  !! network: $($_.Exception.Message)" }

    # 10 security --------------------------------------------------------------
    Write-ScanNote '10/11 Security posture'
    try {
        $sec = New-Object System.Collections.Generic.List[object]
        try {
            $d = Get-MpComputerStatus -ErrorAction SilentlyContinue
            if ($d) {
                $sec.Add([PSCustomObject]@{ Item = 'Defender AntivirusEnabled';   Value = $d.AntivirusEnabled })
                $sec.Add([PSCustomObject]@{ Item = 'Defender RealTimeProtection'; Value = $d.RealTimeProtectionEnabled })
                $sec.Add([PSCustomObject]@{ Item = 'Defender TamperProtection';   Value = $d.IsTamperProtected })
                $sec.Add([PSCustomObject]@{ Item = 'Defender SigVersion';         Value = $d.AntivirusSignatureVersion })
            }
        } catch { }
        try {
            Get-NetFirewallProfile -ErrorAction SilentlyContinue | ForEach-Object {
                $sec.Add([PSCustomObject]@{ Item = "Firewall $($_.Name)"; Value = $_.Enabled })
            }
        } catch { }
        try {
            $bl = Get-BitLockerVolume -ErrorAction SilentlyContinue | Where-Object { $_.MountPoint -eq 'C:' }
            if ($bl) { $sec.Add([PSCustomObject]@{ Item = 'BitLocker C:'; Value = $bl.ProtectionStatus }) }
        } catch { }
        $sb = 'unknown'
        try { $sb = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue } catch { $sb = 'unknown' }
        $sec.Add([PSCustomObject]@{ Item = 'SecureBoot'; Value = $sb })
        try {
            $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
            if ($dg) { $sec.Add([PSCustomObject]@{ Item = 'VBS status'; Value = $dg.VirtualizationBasedSecurityStatus }) }
        } catch { }

        # normalise: mixed bool/enum/int types make Export-Csv throw
        Save-ScanFile ($sec | ForEach-Object {
            [PSCustomObject]@{ Item = [string]$_.Item; Value = [string]$_.Value }
        }) '10_security.csv'
    } catch { Write-ScanNote "  !! security: $($_.Exception.Message)" }

    # 11 winget ----------------------------------------------------------------
    Write-ScanNote '11/11 winget inventory'
    try {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget list --accept-source-agreements 2>$null |
                Out-File -LiteralPath (Join-Path $OutputPath '11_winget.txt') -Encoding UTF8
            Write-ScanNote '  -> 11_winget.txt'
        } else { Write-ScanNote '  winget not available' }
    } catch { Write-ScanNote "  !! winget: $($_.Exception.Message)" }

    $log | Out-File -LiteralPath (Join-Path $OutputPath '00_scanlog.txt') -Encoding UTF8

    Write-Host ''
    Write-Host 'Scan complete. No changes were made.' -ForegroundColor Green
    Write-Host "Output: $OutputPath"
    Write-Host ''

    if ($PassThru) { $OutputPath }
}
