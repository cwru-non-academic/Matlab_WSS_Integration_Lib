param([ValidateSet('cli')][string]$Role='cli',[Parameter(Mandatory)][string]$EventPath,[Parameter(Mandatory)][string]$WorkRoot,[switch]$ValidateOnly,
    [string]$ProducerRunId='', [string]$BarrierRunId='', [string]$BarrierAttempt='', [string]$CoreRoot='')
. "$PSScriptRoot/MatlabDevStage.ps1"
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne $MatlabWrapperRepository) { throw 'Trusted wrapper dispatcher required.' }
$application=Get-MatlabApplication $Role
$barrier=$null
if ($env:GITHUB_EVENT_NAME -ceq 'workflow_dispatch') {
    $barrier=Get-MatlabIntegrationBarrier $CoreRoot $ProducerRunId $BarrierRunId $BarrierAttempt
    $pr=Invoke-MatlabGh -Arguments @('api',"repos/$MatlabWrapperRepository/pulls/$($barrier.integrations.matlab.pr_number)") | ConvertFrom-Json
    if ($pr.merge_commit_sha -cne $barrier.integrations.matlab.head_sha) { throw 'Wrapper merge differs from the verified barrier.' }
} elseif ($env:GITHUB_EVENT_NAME -ceq 'pull_request_target') {
    $event=Get-Content -LiteralPath $EventPath -Raw | ConvertFrom-Json
    $pr=$event.pull_request
} else { throw 'Only a reviewed merge event or trusted main barrier resume is supported.' }
Assert-MatlabHumanMerge $pr
if (!$pr.merged -or $pr.base.ref -cne (Get-WssCiChannel) -or $pr.head.repo.full_name -cne $MatlabWrapperRepository -or $pr.user.type -cne 'Bot' -or $pr.head.ref -cnotlike 'automation/matlab-wss-*') { throw 'Not a reviewed Matlab dependency promotion.' }
if (Test-Path -LiteralPath $WorkRoot) { throw 'Dispatcher workspace must be new.' }
New-Item -ItemType Directory -Path $WorkRoot | Out-Null
$approval=Read-MatlabApprovalMarker $pr.body (Join-Path $WorkRoot 'approval.json')
if ($pr.head.ref -cne "automation/matlab-wss-$($approval.candidate.run_id)-$($approval.candidate.sha256)") { throw 'Promotion branch/candidate mismatch.' }
$config=Read-MatlabConfig "$PSScriptRoot/../matlab-ci.json"
if (!$config.baseline_ready -or $config.automated_execution -cne 'matlab-native') { throw 'Approved .NET promotion baseline required.' }
if ($barrier) { Assert-MatlabSameCandidate $barrier.candidate $approval.candidate }
Assert-MatlabApproval $approval (Join-Path $WorkRoot 'evidence') $config
Assert-MatlabMergedWrapper $pr.merge_commit_sha ([string]$pr.number) $approval
$staged=Test-MatlabStagedProducer $approval.candidate
if ($staged -and !$barrier) {
    'dispatch_needed=false' >> $env:GITHUB_OUTPUT
    Write-Output 'Staged producer: wait for the Core all-integration barrier; no application write token is needed.'
    exit 0
}
if (!$staged -and $barrier) { throw 'Barrier resume cannot substitute for a legacy producer merge event.' }
$body=@{ref=(Get-WssCiChannel);inputs=@{wrapper_sha=$pr.merge_commit_sha;wrapper_pr=[string]$pr.number;approval_json=($approval | ConvertTo-Json -Depth 8 -Compress)}} | ConvertTo-Json -Depth 6 -Compress
$pages=Invoke-MatlabGh -Arguments @('api','--paginate','--slurp',"repos/$($application.repository)/actions/workflows/promote-integration.yml/runs?event=workflow_dispatch&per_page=100") | ConvertFrom-Json
$existing=@($pages | ForEach-Object { $_.workflow_runs } | Where-Object { $_.display_title -ceq "Promote Integration $($pr.merge_commit_sha) / wss-$($approval.candidate.run_id)-$($approval.candidate.artifact_id)" })
. "$PSScriptRoot/wss-ci/DispatchProof.ps1"
$run=if($existing.Count -eq 1 -and [string]$existing[0].id -cmatch '^[1-9][0-9]*$'){Invoke-MatlabGh -Arguments @('api',"repos/$($application.repository)/actions/runs/$($existing[0].id)")|ConvertFrom-Json}else{$null}
$reuse=Invoke-WssCiDispatchProof @{operation='reuse';runs=$existing;run=$run;expected=@{repository=$application.repository;source_sha=$approval.$Role.source_sha;title="Promote Integration $($pr.merge_commit_sha) / wss-$($approval.candidate.run_id)-$($approval.candidate.artifact_id)"}}
if($reuse){'dispatch_needed=false' >> $env:GITHUB_OUTPUT; exit 0}
$intentName="matlab-$Role-dispatch-$($pr.merge_commit_sha)"
Assert-WssCiDispatchArtifacts $env:GITHUB_REPOSITORY $intentName
$sources=@{};$sources[$env:GITHUB_REPOSITORY]=$pr.merge_commit_sha;$sources[$application.repository]=$approval.$Role.source_sha
@{owner=$env:GITHUB_REPOSITORY;repository=$application.repository;name=$intentName;sources=$sources}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $WorkRoot 'dispatch-sources.json')
"intent_name=$intentName" >> $env:GITHUB_OUTPUT
[IO.File]::WriteAllText((Join-Path $WorkRoot ($Role+'-dispatch.json')),$body)
'dispatch_needed=true' >> $env:GITHUB_OUTPUT
if ($ValidateOnly) { exit 0 }
throw 'Dispatch must pass the shared durable-intent workflow gate; use ValidateOnly and the common sender.'
