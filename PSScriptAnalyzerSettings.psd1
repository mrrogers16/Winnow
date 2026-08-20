@{
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # Winnow is an interactive CLI. Its console output IS the product:
        # the dry-run report is what the user reads before deciding to apply.
        # Write-Output would pollute the pipeline for callers who want objects.
        'PSAvoidUsingWriteHost'

        # The Set-Winnow* handlers in Private/Actions.ps1 are internal and are
        # only ever reached through Invoke-WinnowApply, which does declare
        # SupportsShouldProcess and gates every call through ShouldProcess.
        # Declaring it again on the private handlers would double-prompt.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
