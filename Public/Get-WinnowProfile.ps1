#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-WinnowProfile {
    <#
        .SYNOPSIS
            List available profiles, or load one by name.

        .DESCRIPTION
            Profiles are JSON files under the module's profiles/ directory, or
            any directory listed in $env:WINNOW_PROFILE_PATH (semicolon
            separated). Loading validates the schema and reports which actions
            are blocked by guard rails.

        .PARAMETER Name
            Profile name (file name without .json). Omit to list all.

        .EXAMPLE
            Get-WinnowProfile

        .EXAMPLE
            Get-WinnowProfile -Name privacy-baseline | Select-Object -ExpandProperty actions
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [string] $Name
    )

    $dirs = @(Join-Path (Get-WinnowRoot) 'profiles')
    if ($env:WINNOW_PROFILE_PATH) {
        $dirs += $env:WINNOW_PROFILE_PATH.Split(';') | Where-Object { $_ }
    }

    $files = foreach ($d in $dirs) {
        if (Test-Path -LiteralPath $d) {
            Get-ChildItem -LiteralPath $d -Filter '*.json' -ErrorAction SilentlyContinue
        }
    }

    if (-not $Name) {
        return $files | ForEach-Object {
            $json = $null
            try { $json = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
            [PSCustomObject]@{
                Name        = [IO.Path]::GetFileNameWithoutExtension($_.Name)
                Actions     = @(Get-WinnowProp $json 'actions' @()).Count
                Description = if ($json) { Get-WinnowProp $json 'description' '' } else { '(unreadable)' }
                Path        = $_.FullName
            }
        } | Sort-Object Name
    }

    $file = $files | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $Name } | Select-Object -First 1
    if (-not $file) { throw "Profile '$Name' not found. Try: Get-WinnowProfile" }

    $p = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json

    foreach ($required in 'name','actions') {
        if ($p.PSObject.Properties.Name -notcontains $required) {
            throw "Profile '$Name' is missing required field '$required'"
        }
    }
    $i = 0
    foreach ($a in @($p.actions)) {
        $i++
        foreach ($required in 'id','type') {
            if ($a.PSObject.Properties.Name -notcontains $required) {
                throw "Profile '$Name' action #$i is missing required field '$required'"
            }
        }
    }
    $p
}
