. "$PSScriptRoot/MatlabPromotion.ps1"

function Test-MatlabStagedProducer($Candidate) {
    # A failed API call is never interpreted as a legacy producer.
    Assert-MatlabProducer $Candidate
    . "$PSScriptRoot/wss-ci/Staging.ps1"
    $tree=Invoke-MatlabGh -Arguments @('api',"repos/$($Candidate.repository)/git/trees/$($Candidate.commit)?recursive=1")|ConvertFrom-Json
    $entries=@($tree.tree|Where-Object path -CEQ 'tools/ci/dev-propagation.json')
    $file=if($entries.Count -eq 1){Invoke-MatlabGh -Arguments @('api',"repos/$($Candidate.repository)/contents/tools/ci/dev-propagation.json?ref=$($Candidate.commit)")|ConvertFrom-Json}else{$null}
    $receiver=Get-Content "$PSScriptRoot/../dev-propagation.json" -Raw|ConvertFrom-Json
    Test-WssCiStagingPolicy $tree $file $receiver matlab

}

function Get-MatlabIntegrationBarrier([string]$CoreRoot,[string]$ProducerRunId,[string]$BarrierRunId,[string]$BarrierAttempt) {
    if ($env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:GITHUB_REF -cne 'refs/heads/main' -or
        $env:GITHUB_WORKFLOW_REF -cne "$MatlabWrapperRepository/.github/workflows/dispatch-cli-promotion.yml@refs/heads/main") { throw 'Barrier resume requires the registered MATLAB main workflow.' }
    foreach ($id in @($ProducerRunId,$BarrierRunId,$BarrierAttempt)) {
        if ($id -cnotmatch '^[1-9][0-9]*$') { throw 'Exact positive producer/barrier run and attempt required.' }
    }
    $receiver=Invoke-MatlabGh -Arguments @('api',"repos/$MatlabWrapperRepository/branches/main") | ConvertFrom-Json
    if ($receiver.commit.sha -cne $env:GITHUB_SHA) { throw 'Resume must execute the current wrapper main source.' }
    $main=Invoke-MatlabGh -Arguments @('api','repos/cwru-non-academic/WSSCore/branches/main') | ConvertFrom-Json
    Assert-MatlabSource $CoreRoot $main.commit.sha
    $output=& node (Join-Path $CoreRoot 'tools/ci/dev-propagation.mjs') verify-barrier $ProducerRunId $BarrierRunId $BarrierAttempt
    if ($LASTEXITCODE -ne 0) { throw 'Trusted Core integration barrier verification failed; no application write is authorized.' }
    $barrier=($output -join "`n") | ConvertFrom-Json
    if ($barrier.schema -cne 'wss-integration-barrier/v1' -or [string]$barrier.candidate.run_id -cne $ProducerRunId -or
        $barrier.integrations.matlab.repository -cne $MatlabWrapperRepository) { throw 'Verified barrier did not authorize this MATLAB producer/receiver.' }
    return $barrier
}
