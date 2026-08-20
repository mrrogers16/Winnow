#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
    A run journal is the record of what one Apply actually changed on one
    machine, including the prior value of every setting it touched. Rollback
    replays it backwards. Without this, "undo" is guesswork - especially for
    registry values that did not exist before, where the correct undo is
    deletion rather than writing a zero back.
#>

function New-WinnowRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $ProfileName,
        [switch] $DryRun
    )
    [PSCustomObject]@{
        SchemaVersion = 1
        RunId         = (Get-Date -Format 'yyyyMMdd-HHmmss')
        StartedUtc    = (Get-Date).ToUniversalTime().ToString('o')
        DryRun        = [bool]$DryRun
        Profiles      = @($ProfileName)
        System        = (Get-WinnowSystemInfo)
        Entries       = @()
    }
}

function Add-WinnowEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Run,
        [Parameter(Mandatory)] $Entry
    )
    $Run.Entries = @($Run.Entries) + @($Entry)
}

function Save-WinnowRun {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] $Run)

    if ($Run.DryRun) { return $null }   # dry runs are never journalled

    $dir = Join-Path (Get-WinnowDataPath) 'runs'
    if (-not (Test-Path -LiteralPath $dir)) {
        [void][System.IO.Directory]::CreateDirectory($dir)
    }
    $path = Join-Path $dir ("{0}.json" -f $Run.RunId)
    $Run | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
    $path
}

function Get-WinnowRunFile {
    <#  .SYNOPSIS Resolve a run id (or 'latest') to a journal file path. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $RunId)

    $dir = Join-Path (Get-WinnowDataPath) 'runs'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }

    if ($RunId -and $RunId -ne 'latest') {
        $p = Join-Path $dir "$RunId.json"
        if (Test-Path -LiteralPath $p) { return $p }
        return $null
    }
    $newest = Get-ChildItem -LiteralPath $dir -Filter '*.json' -ErrorAction SilentlyContinue |
              Sort-Object Name -Descending | Select-Object -First 1
    if ($newest) { return $newest.FullName }
    return $null
}

function Import-WinnowRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
