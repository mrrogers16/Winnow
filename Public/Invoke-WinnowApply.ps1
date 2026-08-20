#Requires -Version 5.1
Set-StrictMode -Version Latest

function Invoke-WinnowApply {
    <#
        .SYNOPSIS
            Apply one or more profiles. Dry-run unless -Apply is given.

        .DESCRIPTION
            Reads each profile, resolves the current state of every action, and
            reports what would change. Nothing is written without -Apply.

            With -Apply, every change is recorded to a run journal under
            %ProgramData%\Winnow\runs\ including the prior value, so
            Invoke-WinnowRollback can reverse exactly this machine's changes.

            Actions matching the guard list are refused unconditionally. See
            Get-WinnowGuardList.

        .PARAMETER Name
            One or more profile names. See Get-WinnowProfile.

        .PARAMETER Apply
            Actually make the changes. Without this, the command is read-only.

        .PARAMETER Include
            Only run actions whose id matches one of these wildcards.

        .PARAMETER Exclude
            Skip actions whose id matches one of these wildcards.

        .EXAMPLE
            Invoke-WinnowApply privacy-baseline
            Dry run. Shows what would change.

        .EXAMPLE
            Invoke-WinnowApply privacy-baseline, debloat-microsoft -Apply

        .EXAMPLE
            Invoke-WinnowApply debloat-microsoft -Exclude 'appx-sticky*' -Apply
    #>
    # ConfirmImpact is deliberately Medium, not High: -Apply is already the
    # explicit opt-in, and High would prompt per action against the default
    # $ConfirmPreference. Pass -Confirm if you want per-item prompts anyway.
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string[]] $Name,
        [switch]   $Apply,
        [string[]] $Include,
        [string[]] $Exclude
    )

    if ($Apply -and -not (Test-WinnowElevated)) {
        throw 'Winnow needs an elevated PowerShell session to apply changes.'
    }

    $run     = New-WinnowRun -ProfileName $Name -DryRun:(-not $Apply)
    $mode    = if ($Apply) { 'APPLY' } else { 'DRY RUN' }
    $counts  = @{ would = 0; changed = 0; skipped = 0; blocked = 0; failed = 0 }

    Write-Host ''
    Write-Host "Winnow  [$mode]" -ForegroundColor White
    Write-Host "  profiles : $($Name -join ', ')"
    Write-Host "  machine  : $($run.System.ComputerName)  $($run.System.ProductName) $($run.System.DisplayVersion) ($($run.System.Build).$($run.System.UBR))"
    if (-not $Apply) {
        Write-Host '  no changes will be made - re-run with -Apply to commit' -ForegroundColor Cyan
    }
    Write-Host ''

    foreach ($profileName in $Name) {
        $prof = Get-WinnowProfile -Name $profileName
        Write-Host "-- $($prof.name)" -ForegroundColor White
        if (Get-WinnowProp $prof 'description') {
            Write-Host "   $($prof.description)" -ForegroundColor DarkGray
        }

        foreach ($action in @($prof.actions)) {

            if ($Include -and -not ($Include | Where-Object { $action.id -like $_ })) { continue }
            if ($Exclude -and     ($Exclude | Where-Object { $action.id -like $_ })) {
                $counts.skipped++
                Write-WinnowLine skip "$($action.id) (excluded)"
                continue
            }

            $target = Get-WinnowActionTarget $action
            $guard  = Test-WinnowActionGuard $action
            if ($guard) {
                $counts.blocked++
                Write-WinnowLine block "$($action.id) - $guard"
                continue
            }

            $state = $null
            try {
                $state = Resolve-WinnowAction $action
            } catch {
                $counts.failed++
                Write-WinnowLine fail "$($action.id) - resolve error: $($_.Exception.Message)"
                continue
            }

            if (-not $state.Needed) {
                $counts.skipped++
                Write-WinnowLine skip "$($action.id) - $($state.Detail)"
                continue
            }

            $desc = Get-WinnowProp $action 'description' $target

            if (-not $Apply) {
                $counts.would++
                Write-WinnowLine would "$($action.id) - $($state.Detail)"
                Write-WinnowLine info "  $desc"
                continue
            }

            if (-not $PSCmdlet.ShouldProcess($target, "Winnow: $($action.id)")) {
                $counts.skipped++
                continue
            }

            try {
                $entry = Invoke-WinnowActionApply $action
                Add-Member -InputObject $entry -NotePropertyName 'Id'          -NotePropertyValue $action.id -Force
                Add-Member -InputObject $entry -NotePropertyName 'Profile'     -NotePropertyValue $prof.name -Force
                Add-Member -InputObject $entry -NotePropertyName 'Description' -NotePropertyValue $desc      -Force
                Add-WinnowEntry -Run $run -Entry $entry
                $counts.changed++
                Write-WinnowLine change "$($action.id) - $($state.Detail)"
            } catch {
                $counts.failed++
                Write-WinnowLine fail "$($action.id) - $($_.Exception.Message)"
            }
        }
        Write-Host ''
    }

    $journalPath = Save-WinnowRun -Run $run

    Write-Host 'Summary' -ForegroundColor White
    if ($Apply) {
        Write-Host ("  changed {0}   skipped {1}   blocked {2}   failed {3}" -f `
            $counts.changed, $counts.skipped, $counts.blocked, $counts.failed)
        if ($journalPath) {
            Write-Host "  journal : $journalPath"
            Write-Host "  rollback: Invoke-WinnowRollback -RunId $($run.RunId)"
        }
        $irreversible = @($run.Entries | Where-Object { -not $_.Reversible })
        if ($irreversible.Count) {
            Write-Host ''
            Write-Host "  $($irreversible.Count) change(s) cannot be rolled back automatically:" -ForegroundColor Yellow
            $irreversible | ForEach-Object { Write-Host "    - $($_.Id)" -ForegroundColor Yellow }
        }
    } else {
        Write-Host ("  would change {0}   already ok {1}   blocked {2}   failed {3}" -f `
            $counts.would, $counts.skipped, $counts.blocked, $counts.failed)
        Write-Host '  re-run with -Apply to commit' -ForegroundColor Cyan
    }
    Write-Host ''
}
