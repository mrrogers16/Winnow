#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
    Action handlers.

    Every handler implements the same three-phase contract:

      Resolve-*  read current state, decide whether work is needed. Never writes.
      Set-*      perform the change, return a journal entry containing Before.
      Undo-*     take a journal entry and restore Before.

    Adding a new action type means adding a case to each of the three
    dispatchers at the bottom of this file.
#>

# ---------------------------------------------------------------- registry ---

function Resolve-WinnowRegistry {
    [CmdletBinding()] param([Parameter(Mandatory)] $Action)

    $path = $Action.path
    $name = $Action.value
    $want = $Action.data

    $keyExists   = Test-Path -LiteralPath $path
    $valueExists = $false
    $current     = $null

    if ($keyExists) {
        $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if ($item -and ($item.GetValueNames() -contains $name)) {
            $valueExists = $true
            $current     = $item.GetValue($name)
        }
    }

    $satisfied = $valueExists -and ("$current" -eq "$want")
    [PSCustomObject]@{
        Needed   = -not $satisfied
        Detail   = if (-not $keyExists)   { "key missing -> will create, set $name=$want" }
                   elseif (-not $valueExists) { "value missing -> will create $name=$want" }
                   elseif ($satisfied)    { "already $name=$want" }
                   else                   { "$name is '$current' -> $want" }
        Current  = $current
    }
}

function Set-WinnowRegistry {
    [CmdletBinding()] param([Parameter(Mandatory)] $Action)

    $path = $Action.path
    $name = $Action.value
    $want = $Action.data
    $kind = Get-WinnowProp $Action 'kind' 'DWord'

    $keyExisted   = Test-Path -LiteralPath $path
    $valueExisted = $false
    $before       = $null
    $beforeKind   = $null

    if ($keyExisted) {
        $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if ($item -and ($item.GetValueNames() -contains $name)) {
            $valueExisted = $true
            $before       = $item.GetValue($name)
            $beforeKind   = $item.GetValueKind($name).ToString()
        }
    } else {
        [void](New-Item -Path $path -Force -ErrorAction Stop)
    }

    Set-ItemProperty -LiteralPath $path -Name $name -Value $want -Type $kind -Force -ErrorAction Stop

    [PSCustomObject]@{
        Type         = 'registry'
        Path         = $path
        Value        = $name
        KeyExisted   = $keyExisted
        ValueExisted = $valueExisted
        Before       = $before
        BeforeKind   = $beforeKind
        After        = $want
        AfterKind    = $kind
        Reversible   = $true
    }
}

function Undo-WinnowRegistry {
    [CmdletBinding()] param([Parameter(Mandatory)] $Entry)

    if (-not (Test-Path -LiteralPath $Entry.Path)) { return 'key already gone' }

    if (-not $Entry.ValueExisted) {
        Remove-ItemProperty -LiteralPath $Entry.Path -Name $Entry.Value -Force -ErrorAction SilentlyContinue
        if (-not $Entry.KeyExisted) {
            # only remove the key if we created it and it is now empty
            $item = Get-Item -LiteralPath $Entry.Path -ErrorAction SilentlyContinue
            if ($item -and $item.ValueCount -eq 0 -and $item.SubKeyCount -eq 0) {
                Remove-Item -LiteralPath $Entry.Path -Force -ErrorAction SilentlyContinue
                return "removed value and the key we created"
            }
        }
        return "removed value (did not exist before)"
    }

    $kind = if ($Entry.BeforeKind) { $Entry.BeforeKind } else { 'DWord' }
    Set-ItemProperty -LiteralPath $Entry.Path -Name $Entry.Value -Value $Entry.Before -Type $kind -Force -ErrorAction Stop
    "restored to '$($Entry.Before)'"
}

# ----------------------------------------------------------------- service ---

function Resolve-WinnowService {
    [CmdletBinding()] param([Parameter(Mandatory)] $Action)

    $svc = Get-Service -Name $Action.service -ErrorAction SilentlyContinue
    if (-not $svc) {
        return [PSCustomObject]@{ Needed = $false; Detail = 'service not present'; Current = $null }
    }
    $want = Get-WinnowProp $Action 'startupType' 'Disabled'
    $satisfied = ($svc.StartType.ToString() -eq $want) -and
                 (-not (Get-WinnowProp $Action 'stop' $true) -or $svc.Status -ne 'Running')

    [PSCustomObject]@{
        Needed  = -not $satisfied
        Detail  = "$($svc.StartType)/$($svc.Status) -> $want/Stopped"
        Current = $svc.StartType.ToString()
    }
}

function Set-WinnowService {
    [CmdletBinding()] param([Parameter(Mandatory)] $Action)

    $svc  = Get-Service -Name $Action.service -ErrorAction Stop
    $want = Get-WinnowProp $Action 'startupType' 'Disabled'
    $stop = [bool](Get-WinnowProp $Action 'stop' $true)

    $entry = [PSCustomObject]@{
        Type       = 'service'
        Service    = $Action.service
        Before     = $svc.StartType.ToString()
        BeforeState= $svc.Status.ToString()
        After      = $want
        Reversible = $true
    }

    if ($stop -and $svc.Status -eq 'Running') {
        Stop-Service -Name $Action.service -Force -ErrorAction SilentlyContinue
    }
    Set-Service -Name $Action.service -StartupType $want -ErrorAction Stop
    $entry
}

function Undo-WinnowService {
    [CmdletBinding()] param([Parameter(Mandatory)] $Entry)

    $svc = Get-Service -Name $Entry.Service -ErrorAction SilentlyContinue
    if (-not $svc) { return 'service no longer present' }

    Set-Service -Name $Entry.Service -StartupType $Entry.Before -ErrorAction Stop
    if ($Entry.BeforeState -eq 'Running' -and $svc.Status -ne 'Running') {
        Start-Service -Name $Entry.Service -ErrorAction SilentlyContinue
    }
    "restored to $($Entry.Before)/$($Entry.BeforeState)"
}

# ----------------------------------------------------------- scheduled task ---

function Resolve-WinnowScheduledTask {
    [CmdletBinding()] param([Parameter(Mandatory)] $Action)

    $t = Get-ScheduledTask -TaskPath $Action.taskPath -TaskName $Action.taskName -ErrorAction SilentlyContinue
    if (-not $t) {
        return [PSCustomObject]@{ Needed = $false; Detail = 'task not present'; Current = $null }
    }
    [PSCustomObject]@{
        Needed  = ($t.State -ne 'Disabled')
        Detail  = "$($t.State) -> Disabled"
        Current = $t.State.ToString()
    }
}

function Set-WinnowScheduledTask {
    [CmdletBinding()] param([Parameter(Mandatory)] $Action)

    $t = Get-ScheduledTask -TaskPath $Action.taskPath -TaskName $Action.taskName -ErrorAction Stop
    $entry = [PSCustomObject]@{
        Type       = 'scheduledTask'
        TaskPath   = $Action.taskPath
        TaskName   = $Action.taskName
        Before     = $t.State.ToString()
        After      = 'Disabled'
        Reversible = $true
    }
    if ($t.State -eq 'Running') {
        Stop-ScheduledTask -TaskPath $Action.taskPath -TaskName $Action.taskName -ErrorAction SilentlyContinue
    }
    [void](Disable-ScheduledTask -TaskPath $Action.taskPath -TaskName $Action.taskName -ErrorAction Stop)
    $entry
}

function Undo-WinnowScheduledTask {
    [CmdletBinding()] param([Parameter(Mandatory)] $Entry)

    $t = Get-ScheduledTask -TaskPath $Entry.TaskPath -TaskName $Entry.TaskName -ErrorAction SilentlyContinue
    if (-not $t) { return 'task no longer registered' }
    if ($Entry.Before -eq 'Disabled') { return 'was already disabled before the run' }
    [void](Enable-ScheduledTask -TaskPath $Entry.TaskPath -TaskName $Entry.TaskName -ErrorAction Stop)
    "re-enabled (was $($Entry.Before))"
}

# -------------------------------------------------------------------- appx ---

function Resolve-WinnowAppx {
    [CmdletBinding()] param([Parameter(Mandatory)] $Action)

    $pkg  = $Action.package
    $inst = @(Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue)
    $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
              Where-Object { $_.DisplayName -eq $pkg })

    $needed = ($inst.Count -gt 0) -or ($prov.Count -gt 0)
    $bits = @()
    if ($inst.Count) { $bits += 'installed' }
    if ($prov.Count) { $bits += 'provisioned' }

    [PSCustomObject]@{
        Needed  = $needed
        Detail  = if ($needed) { "present ($($bits -join ' + ')) -> remove" } else { 'not present' }
        Current = ($bits -join '+')
    }
}

function Set-WinnowAppx {
    [CmdletBinding()] param([Parameter(Mandatory)] $Action)

    $pkg     = $Action.package
    $doProv  = [bool](Get-WinnowProp $Action 'removeProvisioned' $true)

    $inst = @(Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue)
    $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
              Where-Object { $_.DisplayName -eq $pkg })

    $entry = [PSCustomObject]@{
        Type            = 'appx'
        Package         = $pkg
        BeforeInstalled = [bool]$inst.Count
        BeforeProvisioned = [bool]$prov.Count
        BeforeVersion   = if ($inst.Count) { $inst[0].Version.ToString() } else { $null }
        Reversible      = $false     # appx removal is not scriptable in reverse
    }

    foreach ($p in $inst) {
        Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }
    if ($doProv) {
        foreach ($p in $prov) {
            [void](Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction SilentlyContinue)
        }
    }
    $entry
}

function Undo-WinnowAppx {
    [CmdletBinding()] param([Parameter(Mandatory)] $Entry)
    "NOT REVERSIBLE - reinstall '$($Entry.Package)' from the Microsoft Store or: winget install $($Entry.Package)"
}

# ---------------------------------------------------------------- runValue ---

function Get-WinnowRunKeyPath {
    [CmdletBinding()] param([string] $Hive = 'HKCU')
    if ($Hive -eq 'HKLM') { 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' }
    else                  { 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' }
}

function Resolve-WinnowRunValue {
    [CmdletBinding()] param([Parameter(Mandatory)] $Action)

    $path  = Get-WinnowRunKeyPath (Get-WinnowProp $Action 'hive' 'HKCU')
    $match = $Action.match
    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]@{ Needed = $false; Detail = 'Run key missing'; Current = $null }
    }
    $item = Get-Item -LiteralPath $path
    $hits = @($item.GetValueNames() | Where-Object { $_ -like $match })

    [PSCustomObject]@{
        Needed  = ($hits.Count -gt 0)
        Detail  = if ($hits.Count) { "matches: $($hits -join ', ')" } else { "no value matching '$match'" }
        Current = ($hits -join ',')
    }
}

function Set-WinnowRunValue {
    [CmdletBinding()] param([Parameter(Mandatory)] $Action)

    $path  = Get-WinnowRunKeyPath (Get-WinnowProp $Action 'hive' 'HKCU')
    $match = $Action.match
    $item  = Get-Item -LiteralPath $path -ErrorAction Stop
    $hits  = @($item.GetValueNames() | Where-Object { $_ -like $match })

    $removed = @()
    foreach ($h in $hits) {
        $removed += [PSCustomObject]@{ Name = $h; Data = [string]$item.GetValue($h) }
        Remove-ItemProperty -LiteralPath $path -Name $h -Force -ErrorAction SilentlyContinue
    }

    [PSCustomObject]@{
        Type       = 'runValue'
        Path       = $path
        Match      = $match
        Removed    = $removed
        Reversible = $true
    }
}

function Undo-WinnowRunValue {
    [CmdletBinding()] param([Parameter(Mandatory)] $Entry)

    if (-not $Entry.Removed -or @($Entry.Removed).Count -eq 0) { return 'nothing was removed' }
    foreach ($r in @($Entry.Removed)) {
        Set-ItemProperty -LiteralPath $Entry.Path -Name $r.Name -Value $r.Data -Type String -Force -ErrorAction SilentlyContinue
    }
    "restored $(@($Entry.Removed).Count) value(s)"
}

# --------------------------------------------------------------- dispatch ---

function Get-WinnowActionTarget {
    <#  .SYNOPSIS Human-readable target, also used for guard checks. #>
    [CmdletBinding()] param([Parameter(Mandatory)] $Action)
    switch ($Action.type) {
        'registry'      { "$($Action.path)\$($Action.value)" }
        'service'       { $Action.service }
        'scheduledTask' { "$($Action.taskPath)$($Action.taskName)" }
        'appx'          { $Action.package }
        'runValue'      { "$(Get-WinnowProp $Action 'hive' 'HKCU'):Run\$($Action.match)" }
        default         { '<unknown>' }
    }
}

function Test-WinnowActionGuard {
    [CmdletBinding()] param([Parameter(Mandatory)] $Action)
    switch ($Action.type) {
        'registry'      { Test-WinnowGuard -Type 'registry'      -Identity $Action.path }
        'service'       { Test-WinnowGuard -Type 'service'       -Identity $Action.service }
        'scheduledTask' { Test-WinnowGuard -Type 'scheduledTask' -Identity $Action.taskName -SecondaryIdentity "$($Action.taskPath)$($Action.taskName)" }
        'appx'          { Test-WinnowGuard -Type 'appx'          -Identity $Action.package }
        default         { $null }
    }
}

function Resolve-WinnowAction {
    [CmdletBinding()] param([Parameter(Mandatory)] $Action)
    switch ($Action.type) {
        'registry'      { Resolve-WinnowRegistry      $Action }
        'service'       { Resolve-WinnowService       $Action }
        'scheduledTask' { Resolve-WinnowScheduledTask $Action }
        'appx'          { Resolve-WinnowAppx          $Action }
        'runValue'      { Resolve-WinnowRunValue      $Action }
        default         { [PSCustomObject]@{ Needed = $false; Detail = "unknown action type '$($Action.type)'"; Current = $null } }
    }
}

function Invoke-WinnowActionApply {
    [CmdletBinding()] param([Parameter(Mandatory)] $Action)
    switch ($Action.type) {
        'registry'      { Set-WinnowRegistry      $Action }
        'service'       { Set-WinnowService       $Action }
        'scheduledTask' { Set-WinnowScheduledTask $Action }
        'appx'          { Set-WinnowAppx          $Action }
        'runValue'      { Set-WinnowRunValue      $Action }
        default         { throw "unknown action type '$($Action.type)'" }
    }
}

function Invoke-WinnowActionUndo {
    [CmdletBinding()] param([Parameter(Mandatory)] $Entry)
    switch ($Entry.Type) {
        'registry'      { Undo-WinnowRegistry      $Entry }
        'service'       { Undo-WinnowService       $Entry }
        'scheduledTask' { Undo-WinnowScheduledTask $Entry }
        'appx'          { Undo-WinnowAppx          $Entry }
        'runValue'      { Undo-WinnowRunValue      $Entry }
        default         { "unknown entry type '$($Entry.Type)'" }
    }
}
