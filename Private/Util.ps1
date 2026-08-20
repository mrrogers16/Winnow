#Requires -Version 5.1
Set-StrictMode -Version Latest

function Test-WinnowElevated {
    <#  .SYNOPSIS Returns $true when the current session is elevated. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WinnowProp {
    <#  .SYNOPSIS Safely read an optional property from a JSON-derived object. #>
    # $Object is explicitly nullable: callers pass the result of a registry or
    # CIM read that may legitimately be $null, and a Mandatory parameter would
    # throw a binding error instead of returning the default.
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [AllowNull()] $Object,
        [Parameter(Mandatory, Position = 1)] [string] $Name,
        [Parameter(Position = 2)] $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    $props = $Object.PSObject.Properties
    if ($props.Name -contains $Name) {
        $v = $Object.$Name
        if ($null -eq $v) { return $Default }
        return $v
    }
    return $Default
}

function Write-WinnowLine {
    <#  .SYNOPSIS Consistent console output with a status tag. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('ok','skip','change','would','block','fail','info')]
        [string] $Status,
        [Parameter(Mandatory)] [string] $Message
    )
    $map = @{
        ok     = @{ Text = 'OK     '; Colour = 'Green'      }
        skip   = @{ Text = 'SKIP   '; Colour = 'DarkGray'   }
        change = @{ Text = 'CHANGED'; Colour = 'Green'      }
        would  = @{ Text = 'WOULD  '; Colour = 'Cyan'       }
        block  = @{ Text = 'BLOCKED'; Colour = 'Yellow'     }
        fail   = @{ Text = 'FAIL   '; Colour = 'Red'        }
        info   = @{ Text = '       '; Colour = 'Gray'       }
    }
    $e = $map[$Status]
    Write-Host $e.Text -ForegroundColor $e.Colour -NoNewline
    Write-Host " $Message"
}

function Get-WinnowRoot {
    <#  .SYNOPSIS Module root directory. #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    Split-Path -Parent $PSScriptRoot
}

function Get-WinnowDataPath {
    <#  .SYNOPSIS Where run journals live. Override with $env:WINNOW_HOME. #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $base = if ($env:WINNOW_HOME) { $env:WINNOW_HOME }
            else { Join-Path $env:ProgramData 'Winnow' }
    if (-not (Test-Path -LiteralPath $base)) {
        [void][System.IO.Directory]::CreateDirectory($base)
    }
    $base
}

function Get-WinnowSystemInfo {
    <#  .SYNOPSIS Minimal machine fingerprint recorded into each run journal. #>
    [CmdletBinding()]
    param()
    # Degrade rather than throw: this is metadata for the journal, not the
    # point of the run. Missing CIM (Server Core, constrained language,
    # non-Windows during tests) must not abort an apply.
    $cv = $null; $cs = $null
    try { $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue } catch { }
    try { $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue } catch { }

    [PSCustomObject]@{
        ComputerName   = $env:COMPUTERNAME
        UserName       = $env:USERNAME
        ProductName    = (Get-WinnowProp $cv 'ProductName')
        DisplayVersion = (Get-WinnowProp $cv 'DisplayVersion')
        Build          = (Get-WinnowProp $cv 'CurrentBuildNumber')
        UBR            = (Get-WinnowProp $cv 'UBR')
        Manufacturer   = (Get-WinnowProp $cs 'Manufacturer')
        Model          = (Get-WinnowProp $cs 'Model')
    }
}
