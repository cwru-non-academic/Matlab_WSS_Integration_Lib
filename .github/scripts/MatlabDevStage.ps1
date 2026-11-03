. "$PSScriptRoot/MatlabPromotion.ps1"

function Test-MatlabStagedProducer($Candidate) {
    # A failed API call is never interpreted as a legacy producer.
    Assert-MatlabProducer $Candidate
    $tree=Invoke-MatlabGh @('api',"repos/$($Candidate.repository)/git/trees/$($Candidate.commit)?recursive=1") | ConvertFrom-Json
    if ($tree.truncated -cne $false) { throw 'Complete verified producer tree required.' }
    $entries=@($tree.tree | Where-Object { $_.path -ceq 'tools/ci/dev-propagation.json' })
    if (!$entries.Count) { return $false }
    if ($entries.Count -ne 1 -or $entries[0].type -cne 'blob') { throw 'Invalid immutable producer staging policy.' }
    $file=Invoke-MatlabGh @('api',"repos/$($Candidate.repository)/contents/tools/ci/dev-propagation.json?ref=$($Candidate.commit)") | ConvertFrom-Json
    if ($file.type -cne 'file' -or $file.encoding -cne 'base64') { throw 'Cannot read producer staging policy.' }
    $policy=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($file.content)) | ConvertFrom-Json
    $target=@($policy.libraries | Where-Object { $_.id -ceq 'matlab' })
    if ($policy.schema -cne 'wss-dev-stage/v1' -or $policy.channel -cne 'dev' -or $target.Count -ne 1 -or
        $target[0].repository -cne $MatlabWrapperRepository -or $target[0].fanout -cne 'dispatch-cli-promotion.yml' -or
        $target[0].applications.Count -ne 1 -or $target[0].applications[0] -cne $MatlabCliRepository) { throw 'Producer staging policy does not match the MATLAB receiver.' }
    return $true
}

function Get-MatlabIntegrationBarrier([string]$CoreRoot,[string]$ProducerRunId,[string]$BarrierRunId,[string]$BarrierAttempt) {
    if ($env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:GITHUB_REF -cne 'refs/heads/main' -or
        $env:GITHUB_WORKFLOW_REF -cne "$MatlabWrapperRepository/.github/workflows/dispatch-cli-promotion.yml@refs/heads/main") { throw 'Barrier resume requires the registered MATLAB main workflow.' }
    foreach ($id in @($ProducerRunId,$BarrierRunId,$BarrierAttempt)) {
        if ($id -cnotmatch '^[1-9][0-9]*$') { throw 'Exact positive producer/barrier run and attempt required.' }
    }
    $receiver=Invoke-MatlabGh @('api',"repos/$MatlabWrapperRepository/branches/main") | ConvertFrom-Json
    if ($receiver.commit.sha -cne $env:GITHUB_SHA) { throw 'Resume must execute the current wrapper main source.' }
    $main=Invoke-MatlabGh @('api','repos/cwru-non-academic/WSSCore/branches/main') | ConvertFrom-Json
    Assert-MatlabSource $CoreRoot $main.commit.sha
    $output=& node (Join-Path $CoreRoot 'tools/ci/dev-propagation.mjs') verify-barrier $ProducerRunId $BarrierRunId $BarrierAttempt
    if ($LASTEXITCODE -ne 0) { throw 'Trusted Core integration barrier verification failed; no application write is authorized.' }
    $barrier=($output -join "`n") | ConvertFrom-Json
    if ($barrier.schema -cne 'wss-integration-barrier/v1' -or [string]$barrier.candidate.run_id -cne $ProducerRunId -or
        $barrier.integrations.matlab.repository -cne $MatlabWrapperRepository) { throw 'Verified barrier did not authorize this MATLAB producer/receiver.' }
    return $barrier
}
