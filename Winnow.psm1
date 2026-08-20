#Requires -Version 5.1
Set-StrictMode -Version Latest

# Dot-source Private first (helpers), then Public (exported commands).
foreach ($folder in 'Private', 'Public') {
    $dir = Join-Path $PSScriptRoot $folder
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -ErrorAction SilentlyContinue |
        Sort-Object Name | ForEach-Object {
            try { . $_.FullName }
            catch { throw "Failed to load $($_.FullName): $($_.Exception.Message)" }
        }
}

Export-ModuleMember -Function @(
    'Invoke-WinnowScan'
    'Invoke-WinnowApply'
    'Invoke-WinnowRollback'
    'Get-WinnowRun'
    'Get-WinnowProfile'
    'Get-WinnowGuardList'
)
