#Requires -Version 5.1
Set-StrictMode -Version Latest

function Invoke-WinnowRollback {
    <#
        .SYNOPSIS
            Reverse the changes recorded in a run journal.

        .DESCRIPTION
            Replays a run backwards, restoring each setting to the value it had
            before Winnow touched it. Registry values that did not exist before
            are deleted rather than zeroed, which is the distinction a
            hand-written "undo script" almost always gets wrong.

            Appx removals cannot be reversed programmatically; those entries are
            reported with reinstall instructions instead.

            Dry-run unless -Apply is given.

        .PARAMETER RunId
            Run id to reverse. Defaults to the most recent run.

        .PARAMETER Apply
            Actually perform the rollback.

        .PARAMETER Include
            Only roll back entries whose id matches one of these wildcards.

        .EXAMPLE
            Invoke-WinnowRollback
            Dry run against the latest run.

        .EXAMPLE
            Invoke-WinnowRollback -RunId 20260819-185834 -Apply

        .EXAMPLE
            Invoke-WinnowRollback -Include 'svc-*' -Apply
            Put the services back, leave everything else alone.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string]   $RunId = 'latest',
        [switch]   $Apply,
        [string[]] $Include
    )

    if ($Apply -and -not (Test-WinnowElevated)) {
        throw 'Winnow needs an elevated PowerShell session to roll back changes.'
    }

    $file = Get-WinnowRunFile -RunId $RunId
    if (-not $file) { throw "No run journal found for '$RunId'. Try: Get-WinnowRun" }

    $run  = Import-WinnowRun -Path $file
    $mode = if ($Apply) { 'ROLLBACK' } else { 'DRY RUN' }

    Write-Host ''
    Write-Host "Winnow  [$mode]" -ForegroundColor White
    Write-Host "  run     : $($run.RunId)  ($($run.StartedUtc))"
    Write-Host "  machine : $($run.System.ComputerName)"
    Write-Host "  entries : $(@($run.Entries).Count)"
    if ($run.System.ComputerName -ne $env:COMPUTERNAME) {
        Write-Host "  WARNING: this journal was recorded on '$($run.System.ComputerName)', not this machine" -ForegroundColor Yellow
    }
    if (-not $Apply) {
        Write-Host '  no changes will be made - re-run with -Apply to commit' -ForegroundColor Cyan
    }
    Write-Host ''

    $done = 0; $manual = 0; $failed = 0; $skipped = 0

    # reverse order so dependent changes unwind cleanly
    $entries = @($run.Entries)
    [array]::Reverse($entries)

    foreach ($entry in $entries) {
        $id = Get-WinnowProp $entry 'Id' '<no id>'

        if ($Include -and -not ($Include | Where-Object { $id -like $_ })) { $skipped++; continue }

        if (-not $entry.Reversible) {
            $manual++
            Write-WinnowLine block "$id - $(Invoke-WinnowActionUndo $entry)"
            continue
        }

        if (-not $Apply) {
            $plan = switch ($entry.Type) {
                'registry' {
                    if (-not $entry.ValueExisted) { "delete $($entry.Path)\$($entry.Value) (did not exist before)" }
                    else { "set $($entry.Value) back to '$($entry.Before)'" }
                }
                'service'       { "set $($entry.Service) back to $($entry.Before)/$($entry.BeforeState)" }
                'scheduledTask' { if ($entry.Before -eq 'Disabled') { "leave $($entry.TaskName) disabled (already was)" } else { "re-enable $($entry.TaskName)" } }
                'runValue'      { "restore $(@($entry.Removed).Count) Run value(s)" }
                default         { "restore $($entry.Type)" }
            }
            Write-WinnowLine would "$id - $plan"
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($id, 'Winnow rollback')) { $skipped++; continue }

        try {
            $result = Invoke-WinnowActionUndo $entry
            $done++
            Write-WinnowLine ok "$id - $result"
        } catch {
            $failed++
            Write-WinnowLine fail "$id - $($_.Exception.Message)"
        }
    }

    Write-Host ''
    Write-Host 'Summary' -ForegroundColor White
    if ($Apply) {
        Write-Host ("  restored {0}   manual {1}   skipped {2}   failed {3}" -f $done, $manual, $skipped, $failed)
        Write-Host '  a reboot is recommended so services and tasks settle'
    } else {
        Write-Host ("  {0} entr(ies) would be restored, {1} need manual reinstall" -f `
            (@($entries).Count - $manual - $skipped), $manual)
        Write-Host '  re-run with -Apply to commit' -ForegroundColor Cyan
    }
    Write-Host ''
}

function Get-WinnowRun {
    <#
        .SYNOPSIS
            List recorded runs, newest first.

        .EXAMPLE
            Get-WinnowRun

        .EXAMPLE
            Get-WinnowRun -RunId latest | Select-Object -ExpandProperty Entries
    #>
    [CmdletBinding()]
    param([string] $RunId)

    if ($RunId) {
        $f = Get-WinnowRunFile -RunId $RunId
        if (-not $f) { throw "No run journal found for '$RunId'" }
        return Import-WinnowRun -Path $f
    }

    $dir = Join-Path (Get-WinnowDataPath) 'runs'
    if (-not (Test-Path -LiteralPath $dir)) { return }

    Get-ChildItem -LiteralPath $dir -Filter '*.json' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object {
            $r = $null
            try { $r = Import-WinnowRun -Path $_.FullName } catch { }
            if ($r) {
                [PSCustomObject]@{
                    RunId    = $r.RunId
                    Started  = $r.StartedUtc
                    Machine  = $r.System.ComputerName
                    Profiles = ($r.Profiles -join ', ')
                    Changes  = @($r.Entries).Count
                }
            }
        }
}
