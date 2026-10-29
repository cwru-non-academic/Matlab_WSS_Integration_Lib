param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$WorkRoot)
. "$PSScriptRoot/MatlabPromotion.ps1"
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REF -cne 'refs/heads/dev' -or !$env:MATLAB_PUSH_TOKEN) { throw 'Publication requires the trusted dev workflow and delayed scoped token.' }
$prepared=Get-Content -LiteralPath (Join-Path $WorkRoot 'prepared.json') -Raw | ConvertFrom-Json
if ($prepared.no_op) { throw 'No-op preparation must not mint a write token or publish.' }
$role=$prepared.role
if ($role -ceq 'wrapper') { $repo=$MatlabWrapperRepository }
else { $application=Get-MatlabApplication $role; $repo=$application.repository }
if ($repo -cne $env:GITHUB_REPOSITORY) { throw 'Wrong publication repository.' }
$config=Read-MatlabConfig (Join-Path $RepositoryRoot '.github/matlab-ci.json')
if (!$config.baseline_ready -or $config.automated_execution -cne 'matlab-native') { throw 'Approved .NET promotion baseline required.' }
$approval=Read-MatlabApproval (Join-Path $WorkRoot 'approval.json')
if ($role -ceq 'wrapper') { Assert-MatlabFanoutApproval $approval }
Assert-MatlabApproval $approval (Join-Path $WorkRoot 'publication-evidence') $config
Assert-MatlabSource $RepositoryRoot $prepared.source_sha -IgnoreSubmodule
if ((Get-MatlabHead $repo) -cne $prepared.source_sha) { throw 'Target dev advanced; no stale PR.' }
$branch="automation/matlab-wss-$($approval.candidate.run_id)-$($approval.candidate.sha256)"
$marker=Get-MatlabApprovalMarker $approval
if ($role -ceq 'wrapper') {
    if ($prepared.source_sha -cne $approval.wrapper.source_sha) { throw 'Untested wrapper source.' }
    $projection=Get-Content -LiteralPath (Join-Path $WorkRoot 'projection.json') -Raw | ConvertFrom-Json
    Assert-MatlabSameCandidate $projection.candidate $approval.candidate
    Assert-MatlabProjection (Join-Path $WorkRoot 'projection') $projection
    if ($projection.projection_sha256 -cne $approval.projection_sha256) { throw 'Staged projection differs from preflight.' }
    $payloadRoot=Join-Path $RepositoryRoot $MatlabPluginPath
    # Both validated roots are exact full inventories; replace only allowlisted files.
    foreach ($source in $MatlabProjectionFiles) {
        Copy-Item -LiteralPath (Join-Path $WorkRoot "projection/$source") -Destination (Join-Path $payloadRoot $source)
    }
    $projection | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $RepositoryRoot '.github/matlab-candidate.json')
    $allowed=Get-MatlabAllowedWrapperPaths
    $null=Invoke-MatlabGit $RepositoryRoot (@('add','--')+$allowed)
    Assert-MatlabProjection (Join-Path $RepositoryRoot $MatlabPluginPath) $projection
} else {
    Assert-MatlabMergedWrapper $prepared.wrapper_merge_sha $prepared.wrapper_pr $approval
    $preflightId=if ($prepared.PSObject.Properties['application_preflight_run_id']) { $prepared.application_preflight_run_id } elseif ($role -ceq 'cli') { $prepared.cli_preflight_run_id } else { throw 'Application preflight ID missing.' }
    Assert-MatlabMergedApplicationPreflight $approval $role $prepared.wrapper_merge_sha $prepared.source_sha $preflightId (Join-Path $WorkRoot ('publication-merged-'+$role+'-evidence')) $config
    $applicationMarker=Get-MatlabApplicationPreflightMarker $role $prepared.wrapper_merge_sha $prepared.source_sha $preflightId
    $allowed=@($application.gitlink)
    $null=Invoke-MatlabGit $RepositoryRoot @('update-index','--cacheinfo',"160000,$($prepared.wrapper_merge_sha),$($application.gitlink)")
    $entry=(Invoke-MatlabGit $RepositoryRoot @('ls-files','--stage','--',$application.gitlink)) -join ''
    if ($entry -cne "160000 $($prepared.wrapper_merge_sha) 0`t$($application.gitlink)") { throw 'Staged application entry is not the accepted gitlink.' }

}
$changed=@(Invoke-MatlabGit $RepositoryRoot @('diff','--cached','--name-only'))
Assert-MatlabDiff $changed $allowed
if (@(Invoke-MatlabGit $RepositoryRoot @('diff','--name-only','--ignore-submodules=all')).Count -ne 0) { throw 'Unstaged changes outside the intended promotion.' }
$tree=(Invoke-MatlabGit $RepositoryRoot @('write-tree')).Trim()
$pulls=@(Invoke-MatlabGh @('pr','list','--repo',$repo,'--state','all','--base','dev','--head',$branch,'--limit','2','--json','number,url,state,body,headRefOid') | ConvertFrom-Json)
if ($pulls.Count -gt 1 -or ($pulls.Count -eq 1 -and $pulls[0].state -cne 'OPEN')) { throw 'Ambiguous or already closed/merged candidate PR; no replacement or rollback.' }
$refs=@(Invoke-MatlabGh @('api',"repos/$repo/git/matching-refs/heads/$branch") | ConvertFrom-Json | Where-Object { $_.ref -ceq "refs/heads/$branch" })
if ($pulls.Count -eq 1) {
    if ($refs.Count -ne 1 -or $pulls[0].headRefOid -cne $refs[0].object.sha -or !(($pulls[0].body -split "`r?`n") -ccontains $marker)) { throw 'Existing PR branch/metadata conflict.' }
    if ($role -cne 'wrapper' -and !(($pulls[0].body -split "`r?`n") -ccontains $applicationMarker)) { throw 'Existing application PR does not carry the exact merged-wrapper preflight.' }
    $remoteCommit=Invoke-MatlabGh @('api',"repos/$repo/git/commits/$($refs[0].object.sha)") | ConvertFrom-Json
    if ($remoteCommit.tree.sha -cne $tree -or @($remoteCommit.parents).Count -ne 1 -or $remoteCommit.parents[0].sha -cne $prepared.source_sha) { throw 'Existing PR is not the exact intended tree/source.' }
    Write-Output "Reusing exact existing PR: $($pulls[0].url)"
    exit 0
}
if ($refs.Count -ne 0) { throw 'Orphan candidate branch exists; inspect rather than overwriting.' }
$null=Invoke-MatlabGit $RepositoryRoot @('switch','-c',$branch)
$null=Invoke-MatlabGit $RepositoryRoot @('-c','user.name=WSS Matlab automation','-c','user.email=wss-matlab-automation@users.noreply.github.com','commit','-m',"Promote verified Matlab WSS $($approval.candidate.run_id)")
# Per-command credentials only; never alter Git global/system trust or credential configuration.
$header=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('x-access-token:'+$env:MATLAB_PUSH_TOKEN))
Write-Output "::add-mask::$header"
$null=Invoke-MatlabGit $RepositoryRoot @('-c',"http.https://github.com/.extraheader=AUTHORIZATION: basic $header",'push','origin',"HEAD:refs/heads/$branch")
$bodyPath=Join-Path $WorkRoot 'pr-body.md'
$body="Promotes the exact candidate accepted by its versioned Matlab approval. Manual review/merge required; no release.`n`n<!-- $($approval.schema.Replace('/','-')) -->`n$marker`n"
if ($role -cne 'wrapper') { $body+="`nActual merged-wrapper $($role.ToUpperInvariant()) preflight: https://github.com/$repo/actions/runs/$preflightId`n$applicationMarker`n" }
[IO.File]::WriteAllText($bodyPath,$body)
$readToken=$env:GH_TOKEN
$title="Promote universal WSS run $($approval.candidate.run_id)"
if ($role -cne 'wrapper') { $title+=" / Integration $($prepared.wrapper_merge_sha.Substring(0,12))" }
try {
    $env:GH_TOKEN=$env:MATLAB_PUSH_TOKEN
    $null=Invoke-MatlabGh @('pr','create','--repo',$repo,'--base','dev','--head',$branch,'--title',$title,'--body-file',$bodyPath)
} finally { $env:GH_TOKEN=$readToken }
