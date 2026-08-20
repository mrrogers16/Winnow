<#
    Smoke test. Runs on any platform - exercises the pure-logic paths
    (profile loading, guard rails, journal round-trip, rollback dry run)
    without touching a real Windows machine.

    Usage:  pwsh -NoProfile -File ./tests/smoke.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$env:WINNOW_HOME = Join-Path ([IO.Path]::GetTempPath()) ("winnow-smoke-" + [guid]::NewGuid().ToString('N').Substring(0,8))

$fails = 0
function Check([string] $Name, [bool] $Condition, [string] $Detail = '') {
    if ($Condition) { Write-Host "  PASS  $Name" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Name $Detail" -ForegroundColor Red; $script:fails++ }
}

Import-Module (Join-Path $root 'Winnow.psd1') -Force
Write-Host 'module import' -ForegroundColor White
Check 'module imports' $true

$cmds = (Get-Command -Module Winnow).Name
foreach ($c in 'Invoke-WinnowScan','Invoke-WinnowApply','Invoke-WinnowRollback','Get-WinnowRun','Get-WinnowProfile','Get-WinnowGuardList') {
    Check "exports $c" ($cmds -contains $c)
}

Write-Host ''
Write-Host 'profiles' -ForegroundColor White
$profiles = @(Get-WinnowProfile)
Check 'finds profiles' ($profiles.Count -ge 4) "(found $($profiles.Count))"
foreach ($p in $profiles) {
    Check "  $($p.Name) has actions" ($p.Actions -gt 0) "(got $($p.Actions))"
    Check "  $($p.Name) has description" ([bool]$p.Description)
}
$loaded = Get-WinnowProfile -Name privacy-baseline
Check 'loads by name' ($loaded.name -eq 'privacy-baseline')

$bad = $false
try { Get-WinnowProfile -Name 'does-not-exist' } catch { $bad = $true }
Check 'unknown profile throws' $bad

Write-Host ''
Write-Host 'guard rails' -ForegroundColor White
& (Get-Module Winnow) {
    $g = @(
        @{ T='service';       I='WSearch';                          S=$null; Expect=$true  }
        @{ T='service';       I='PcaSvc';                           S=$null; Expect=$true  }
        @{ T='service';       I='WinDefend';                        S=$null; Expect=$true  }
        @{ T='service';       I='DiagTrack';                        S=$null; Expect=$false }
        @{ T='appx';          I='Microsoft.DesktopAppInstaller';    S=$null; Expect=$true  }
        @{ T='appx';          I='Microsoft.HEVCVideoExtension';     S=$null; Expect=$true  }
        @{ T='appx';          I='Microsoft.MicrosoftEdge.Stable';   S=$null; Expect=$true  }
        @{ T='appx';          I='Microsoft.BingNews';               S=$null; Expect=$false }
        @{ T='scheduledTask'; I='Secure-Boot-Update';               S='\Microsoft\Windows\PI\Secure-Boot-Update'; Expect=$true }
        @{ T='scheduledTask'; I='Consolidator';                     S='\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'; Expect=$false }
    )
    foreach ($case in $g) {
        $r = Test-WinnowGuard -Type $case.T -Identity $case.I -SecondaryIdentity $case.S
        $guarded = [bool]$r
        $ok = ($guarded -eq $case.Expect)
        if ($ok) { Write-Host "  PASS  guard $($case.T)/$($case.I) = $guarded" -ForegroundColor Green }
        else     { Write-Host "  FAIL  guard $($case.T)/$($case.I) expected $($case.Expect) got $guarded" -ForegroundColor Red }
    }
}

Write-Host ''
Write-Host 'no profile asks for a guarded target' -ForegroundColor White
& (Get-Module Winnow) {
    $conflicts = 0
    foreach ($f in Get-ChildItem (Join-Path (Get-WinnowRoot) 'profiles') -Filter '*.json') {
        $p = Get-Content $f.FullName -Raw | ConvertFrom-Json
        foreach ($a in @($p.actions)) {
            $g = Test-WinnowActionGuard $a
            if ($g) { Write-Host "  FAIL  $($f.Name): '$($a.id)' is blocked - $g" -ForegroundColor Red; $conflicts++ }
        }
    }
    if ($conflicts -eq 0) { Write-Host '  PASS  every shipped profile action is allowed by the guard list' -ForegroundColor Green }
}

Write-Host ''
Write-Host 'journal round-trip' -ForegroundColor White
& (Get-Module Winnow) {
    $run = New-WinnowRun -ProfileName @('privacy-baseline')
    Add-WinnowEntry -Run $run -Entry ([PSCustomObject]@{
        Id='test-reg-new'; Type='registry'; Path='HKCU:\Software\WinnowTest'; Value='Foo'
        KeyExisted=$false; ValueExisted=$false; Before=$null; BeforeKind=$null
        After=0; AfterKind='DWord'; Reversible=$true })
    Add-WinnowEntry -Run $run -Entry ([PSCustomObject]@{
        Id='test-svc'; Type='service'; Service='DiagTrack'; Before='Automatic'
        BeforeState='Running'; After='Disabled'; Reversible=$true })
    Add-WinnowEntry -Run $run -Entry ([PSCustomObject]@{
        Id='test-appx'; Type='appx'; Package='Microsoft.BingNews'; BeforeInstalled=$true
        BeforeProvisioned=$true; BeforeVersion='1.0'; Reversible=$false })

    $path = Save-WinnowRun -Run $run
    if ($path -and (Test-Path $path)) { Write-Host "  PASS  journal written" -ForegroundColor Green }
    else { Write-Host '  FAIL  journal not written' -ForegroundColor Red }

    $back = Import-WinnowRun -Path (Get-WinnowRunFile -RunId 'latest')
    if (@($back.Entries).Count -eq 3) { Write-Host '  PASS  3 entries survive round-trip' -ForegroundColor Green }
    else { Write-Host "  FAIL  got $(@($back.Entries).Count) entries" -ForegroundColor Red }

    $appxEntry = @($back.Entries) | Where-Object { $_.Id -eq 'test-appx' }
    if (-not $appxEntry.Reversible) { Write-Host '  PASS  appx marked irreversible' -ForegroundColor Green }
    else { Write-Host '  FAIL  appx should be irreversible' -ForegroundColor Red }

    $msg = Invoke-WinnowActionUndo $appxEntry
    if ($msg -match 'NOT REVERSIBLE') { Write-Host '  PASS  appx undo returns instructions' -ForegroundColor Green }
    else { Write-Host "  FAIL  appx undo said: $msg" -ForegroundColor Red }
}

Write-Host ''
Write-Host 'dry-run writes nothing' -ForegroundColor White
$before = @(Get-ChildItem (Join-Path $env:WINNOW_HOME 'runs') -Filter '*.json' -ErrorAction SilentlyContinue).Count
& (Get-Module Winnow) {
    $r = New-WinnowRun -ProfileName @('x') -DryRun
    $p = Save-WinnowRun -Run $r
    if ($null -eq $p) { Write-Host '  PASS  dry run produces no journal' -ForegroundColor Green }
    else { Write-Host '  FAIL  dry run wrote a journal' -ForegroundColor Red }
}
$after = @(Get-ChildItem (Join-Path $env:WINNOW_HOME 'runs') -Filter '*.json' -ErrorAction SilentlyContinue).Count
Check 'run count unchanged by dry run' ($before -eq $after) "($before -> $after)"

Write-Host ''
Write-Host 'rollback dry run' -ForegroundColor White
Invoke-WinnowRollback -RunId latest

Remove-Item -LiteralPath $env:WINNOW_HOME -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($fails -eq 0) { Write-Host 'smoke test complete' -ForegroundColor Green; exit 0 }
else { Write-Host "$fails failure(s)" -ForegroundColor Red; exit 1 }
