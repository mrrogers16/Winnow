#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
    Guard rails.

    These are refused unconditionally. There is no override switch, by design:
    the point is to protect you from a profile you wrote at 2am. If you truly
    need to change one, edit this file in a commit you can see in `git log`.

    Rationale for the notable entries:
      WSearch          - Start menu and File Explorer search. Not telemetry.
      PcaSvc           - Program Compatibility Assistant. Breaks old installers.
      *WebView2*       - Windows Search itself runs on WebView2 on Win11.
      DesktopAppInstaller - this IS winget.
      *VideoExtension / *ImageExtension - codecs. Removing breaks media playback.
      Secure-Boot-Update - delivers Secure Boot DBX revocations.
      PcaPatchDbTask / SdbinstMergeDbTask - app compatibility shim database.
#>

$script:WinnowGuardedServices = @(
    # Security
    'WinDefend','WdNisSvc','MDCoreSvc','SecurityHealthService','wscsvc','Sense','webthreatdefsvc'
    'mpssvc','BFE','SgrmBroker','TPMVscMgr','TrustedInstaller'
    # Update chain
    'wuauserv','UsoSvc','WaaSMedicSvc','BITS','CryptSvc','msiserver','DoSvc'
    # Core OS
    'RpcSs','DcomLaunch','RpcEptMapper','LSM','SamSs','EventLog','Schedule','Power'
    'ProfSvc','gpsvc','Themes','nsi','BrokerInfrastructure','SystemEventsBroker'
    'CoreMessagingRegistrar','StateRepository','AppXSvc','ClipSVC','TokenBroker'
    # Networking
    'Dhcp','Dnscache','NlaSvc','netprofm','WlanSvc','LanmanWorkstation','LanmanServer','Netman'
    # Storage / licensing / audio / input
    'StorSvc','LicenseManager','sppsvc','Audiosrv','AudioEndpointBuilder','UserManager'
    # Deliberately kept: not telemetry, cost more than they give
    'WSearch','PcaSvc'
)

$script:WinnowGuardedTaskPaths = @(
    '\Microsoft\Windows\Windows Defender\*'
    '\Microsoft\Windows\BitLocker\*'
    '\Microsoft\Windows\TPM\*'
    '\Microsoft\Windows\UpdateOrchestrator\*'
    '\Microsoft\Windows\WindowsUpdate\*'
    '\Microsoft\Windows\ExploitGuard\*'
    '\Microsoft\Windows\DeviceGuard\*'
    '\Microsoft\Windows\SystemRestore\*'
)

$script:WinnowGuardedTaskNames = @(
    'Secure-Boot-Update'
    'PcaPatchDbTask'
    'SdbinstMergeDbTask'
    'IndexerAutomaticMaintenance'
)

$script:WinnowGuardedAppx = @(
    'Microsoft.DesktopAppInstaller'      # winget
    'Microsoft.Winget.Source'
    'Microsoft.WindowsStore'
    'Microsoft.StorePurchaseApp'
    'Microsoft.SecHealthUI'              # Defender UI
    'Microsoft.WindowsTerminal'
    'Microsoft.ScreenSketch'             # Snipping Tool / PrtSc
    'Microsoft.WindowsNotepad'
    'Microsoft.Paint'
    'Microsoft.WindowsCalculator'
    'Microsoft.AAD.BrokerPlugin'
    'Microsoft.AccountsControl'
    'Microsoft.CredDialogHost'
    'Microsoft.LockApp'
    'Microsoft.BioEnrollment'
    'Microsoft.UI.Xaml.*'
    'Microsoft.VCLibs.*'
    'Microsoft.NET.*'
    'Microsoft.WindowsAppRuntime.*'
    'Microsoft.Services.Store.Engagement*'
    '*VideoExtension*'
    '*ImageExtension*'
    '*WebMediaExtensions*'
    'MicrosoftWindows.Client.Core'
    'MicrosoftWindows.Client.CBS'
    'MicrosoftWindows.Client.FileExp'
    'MicrosoftWindows.Client.OOBE'
    'MicrosoftWindows.LKG.*'
    'Microsoft.Windows.ShellExperienceHost'
    'Microsoft.Windows.StartMenuExperienceHost'
    'Microsoft.Windows.CloudExperienceHost'
    'Microsoft.Win32WebViewHost'
    'Microsoft.MicrosoftEdge.Stable'      # WebView2 shares this stack
    'Microsoft.MicrosoftEdgeDevToolsClient'
)

$script:WinnowGuardedRegistryPaths = @(
    '*\Policies\Microsoft\Windows Defender*'
    '*\Microsoft\Windows Defender*'
    '*\Policies\Microsoft\FVE*'                 # BitLocker
    '*\Policies\Microsoft\Windows\WindowsUpdate*'
    '*\Microsoft\Windows\CurrentVersion\WINEVT*'
    '*\CurrentControlSet\Control\DeviceGuard*'
    '*\SYSTEM\CurrentControlSet\Services\*'     # service config belongs in a service action
)

function Test-WinnowGuard {
    <#
        .SYNOPSIS
            Returns a reason string if the target is protected, otherwise $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [ValidateSet('service','scheduledTask','appx','registry')]
        [string] $Type,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Identity,
        [string] $SecondaryIdentity
    )

    switch ($Type) {
        'service' {
            foreach ($p in $script:WinnowGuardedServices) {
                if ($Identity -like $p) { return "service '$Identity' is on the protected list" }
            }
        }
        'scheduledTask' {
            foreach ($p in $script:WinnowGuardedTaskPaths) {
                if ($SecondaryIdentity -like $p) { return "task path '$SecondaryIdentity' is protected" }
            }
            foreach ($p in $script:WinnowGuardedTaskNames) {
                if ($Identity -like $p) { return "task '$Identity' is on the protected list" }
            }
        }
        'appx' {
            foreach ($p in $script:WinnowGuardedAppx) {
                if ($Identity -like $p) { return "package '$Identity' is on the protected list" }
            }
        }
        'registry' {
            foreach ($p in $script:WinnowGuardedRegistryPaths) {
                if ($Identity -like $p) { return "registry path '$Identity' is protected" }
            }
        }
    }
    return $null
}

function Get-WinnowGuardList {
    <#  .SYNOPSIS Show everything Winnow refuses to touch. #>
    [CmdletBinding()]
    param()
    [PSCustomObject]@{
        Services       = $script:WinnowGuardedServices
        TaskPaths      = $script:WinnowGuardedTaskPaths
        TaskNames      = $script:WinnowGuardedTaskNames
        AppxPackages   = $script:WinnowGuardedAppx
        RegistryPaths  = $script:WinnowGuardedRegistryPaths
    }
}
