. "$PSScriptRoot/MatlabPromotion.ps1"
function Assert-MatlabReceiptSnapshots($Approval,$Plan) {
    foreach ($role in @('wrapper','cli')) {
        $targetId=if ($role -ceq 'wrapper') { 'matlab-wrapper' } else { 'matlab-'+$role }
        if ($Approval.$role.source_sha -cne $Plan.target_snapshots.$targetId.head_sha) { throw 'Approval source differs from frozen target snapshot.' }
    }
}
function Read-MatlabReceiptApplicationMarker([string]$Body,[ValidateSet('cli')][string]$Role) {
    $lines=@($Body -split "`r?`n" | Where-Object { $_.StartsWith('<!-- wss-matlab-',[StringComparison]::Ordinal) -and $_.Contains('-preflight:') })
    $pattern='^<!-- wss-matlab-'+$Role+'-preflight:v1 ([A-Za-z0-9+/=]+) -->$'
    if ($lines.Count -ne 1 -or $lines[0] -cnotmatch $pattern) { throw 'Expected one unambiguous actual merged-wrapper application marker.' }
    $fresh=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1])) | ConvertFrom-Json
    $source=$fresh.((Get-MatlabApplication $Role).source_field)
    $canonical=Get-MatlabApplicationPreflightMarker $Role $fresh.wrapper_sha $source ([string]$fresh.preflight_run_id)
    if ($lines[0] -cne $canonical) { throw 'Application marker is not the canonical existing proof contract.' }
    $fresh
}

# A receipt rechecks existing proof only; never dispatch, publish or merge.
function Invoke-MatlabGh([string[]]$Arguments) {
    $get=$false
    if ($Arguments.Count -ge 2 -and $Arguments[0] -ceq 'api') {
        $paths=@($Arguments | Where-Object { $_ -cnotin @('api','--paginate','--slurp') })
        $get=$paths.Count -eq 1 -and $paths[0] -cmatch '^repos/cwru-non-academic/'
    }
    $download=$Arguments.Count -eq 9 -and $Arguments[0] -ceq 'run' -and $Arguments[1] -ceq 'download' -and $Arguments[2] -cmatch '^[1-9][0-9]*$' -and $Arguments[3] -ceq '--repo' -and $Arguments[5] -ceq '--name' -and $Arguments[7] -ceq '--dir'
    if (!$get -and !$download) { throw 'Receipt transport accepts only repository GET and artifact download.' }
    $result=& gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Read-only receipt proof retrieval failed.' }
    $result
}
