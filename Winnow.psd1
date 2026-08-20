@{
    RootModule        = 'Winnow.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b7c3f2a1-9d64-4e58-8a71-2f0c5d3e9b44'
    Author            = 'mrrogers16'
    CompanyName       = 'Unknown'
    Copyright         = '(c) mrrogers16. MIT licensed.'
    Description       = 'Audit-first Windows debloat and telemetry control. Inventories a machine, applies declarative JSON profiles, and keeps a rollback journal of every change.'

    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Invoke-WinnowScan'
        'Invoke-WinnowApply'
        'Invoke-WinnowRollback'
        'Get-WinnowRun'
        'Get-WinnowProfile'
        'Get-WinnowGuardList'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Windows','Debloat','Telemetry','Privacy','Sysadmin','Provisioning')
            LicenseUri   = 'https://github.com/mrrogers16/Winnow/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/mrrogers16/Winnow'
            ReleaseNotes = 'See CHANGELOG.md'
        }
    }
}
