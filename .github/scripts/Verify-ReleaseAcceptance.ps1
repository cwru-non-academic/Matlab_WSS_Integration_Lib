param(
    [Parameter(Mandatory)][string]$ContextPath,
    [Parameter(Mandatory)][string]$ToolsRoot,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$OutputPath
)
. (Join-Path $ToolsRoot '.github/scripts/ReleaseReceiptContract.ps1')
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:GITHUB_REF -cne 'refs/heads/dev') { throw 'Read-only receipt validation requires the actual dev emitter.' }
$ctx=Get-Content -LiteralPath $ContextPath -Raw | ConvertFrom-Json
if ($ctx.head -cne $env:GITHUB_SHA -or $ctx.target.repository -cne $env:GITHUB_REPOSITORY) { throw 'Receipt context source mismatch.' }
if (Test-Path -LiteralPath $WorkRoot) { throw 'Receipt validation workspace must be new.' }
$null=New-Item -ItemType Directory -Path $WorkRoot
$approval=Read-MatlabApprovalMarker $ctx.pr.body (Join-Path $WorkRoot 'approval.json')
Assert-MatlabFanoutApproval $approval
Assert-MatlabSameCandidate $approval.candidate $ctx.plan.candidate
Assert-MatlabReceiptSnapshots $approval $ctx.plan
$config=Read-MatlabConfig (Join-Path $ToolsRoot '.github/matlab-ci.json')
$preflights=@()
foreach ($role in @('wrapper','cli')) {
    $targetId=if ($role -ceq 'wrapper') { 'matlab-wrapper' } else { 'matlab-'+$role }
    $repo=if ($role -ceq 'wrapper') { $MatlabWrapperRepository } else { (Get-MatlabApplication $role).repository }
    $preflights += [pscustomobject]@{repository=$repo;run_id=[string]$approval.$role.preflight_run_id;source_sha=$approval.$role.source_sha;workflow='.github/workflows/wss-preflight.yml'}
}
# Preserve all existing rich, native, platform and paired-source proof checks.
Assert-MatlabProducer $approval.candidate
& (Join-Path $ToolsRoot '.github/scripts/Resolve-WssRelease.ps1') -RunId $approval.candidate.run_id -ExpectedArtifactId $approval.candidate.artifact_id -ExpectedCommit $approval.candidate.commit -ArchiveName $approval.candidate.archive -ExpectedSha256 $approval.candidate.sha256 -OutputRoot (Join-Path $WorkRoot 'resolved')
if (!$?) { throw 'Exact candidate archive validation failed.' }
Assert-MatlabApproval $approval (Join-Path $WorkRoot 'approval-evidence') $config
if ($ctx.target.role -ceq 'wrapper') {
    Assert-MatlabMergedWrapper $ctx.head ([string]$ctx.pr.number) $approval
} else {
    $role=$ctx.target.role
    $application=Get-MatlabApplication $role
    $fresh=Read-MatlabReceiptApplicationMarker $ctx.pr.body $role
    $source=$fresh.($application.source_field)
    $targetId='matlab-'+$role
    if ($source -cne $ctx.plan.target_snapshots.$targetId.head_sha -or $fresh.wrapper_sha -cne $ctx.parents.'matlab-wrapper') { throw 'Post-merge application proof differs from frozen source/actual parent pin.' }
    $parentPrs=@(Invoke-MatlabGh @('api','--paginate','--slurp',"repos/$MatlabWrapperRepository/commits/$($fresh.wrapper_sha)/pulls?per_page=100") | ConvertFrom-Json | ForEach-Object { $_ } | Where-Object { $_.merge_commit_sha -ceq $fresh.wrapper_sha -and $_.merged_at -and $_.base.ref -ceq 'dev' })
    if ($parentPrs.Count -ne 1) { throw 'Actual wrapper parent does not identify a unique reviewed merge.' }
    $parent=Invoke-MatlabGh @('api',"repos/$MatlabWrapperRepository/pulls/$($parentPrs[0].number)") | ConvertFrom-Json
    if ($parent.merged_by.type -cne 'User') { throw 'Wrapper parent merge must be human reviewed.' }
    Assert-MatlabMergedWrapper $fresh.wrapper_sha ([string]$parent.number) $approval
    Assert-MatlabMergedApplicationPreflight $approval $role $fresh.wrapper_sha $source ([string]$fresh.preflight_run_id) (Join-Path $WorkRoot 'merged-application-evidence') $config
    $delta=Invoke-MatlabGh @('api',"repos/$($application.repository)/compare/${source}...$($ctx.head)") | ConvertFrom-Json
    if ($delta.status -cne 'ahead' -or $delta.total_commits -lt 1 -or $delta.files.Count -ne 1) { throw 'Application merge is not the exact frozen-source gitlink update.' }
    Assert-MatlabDiff @($delta.files.filename) @($application.gitlink)
    $preflights += [pscustomobject]@{repository=$application.repository;run_id=[string]$fresh.preflight_run_id;source_sha=$source;workflow='.github/workflows/wss-preflight.yml'}
}
ConvertTo-Json -InputObject $preflights -Depth 5 | Set-Content -LiteralPath $OutputPath
Write-Output 'Existing native paired approval, canonical bytes, actual reviewed merge and full receiver-specific proofs verified; no publication mutation performed.'
