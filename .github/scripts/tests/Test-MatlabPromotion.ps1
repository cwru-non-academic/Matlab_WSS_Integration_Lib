# Offline contract tests only: synthetic files/API responses never count as runtime proof.
. "$PSScriptRoot/../MatlabPromotion.ps1"
. "$PSScriptRoot/../MatlabDevStage.ps1"
& "$PSScriptRoot/Test-MatlabMacCoverage.ps1"
function Assert-Rejected([scriptblock]$Action,[string]$Because) {
    $rejected=$false
    try { & $Action } catch { $rejected=$true }
    if (!$rejected) { throw "Must reject: $Because" }
}
$candidate=[pscustomobject]@{repository='cwru-non-academic/WSSCore';commit=('a'*40);run_id='123';artifact_id='456';archive='WSS-Universal-ci.zip';sha256=('b'*64)}
$repositoryRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$installed=Get-Content (Join-Path $repositoryRoot '.github/matlab-candidate.json') -Raw | ConvertFrom-Json
Assert-MatlabProjection (Join-Path $repositoryRoot 'Cs_Libraries') $installed
Write-Output 'PASS installed payload manifest digest and full file hashes.'
# Legacy branch cases must remain independent of the installed/promoted payload.
# This synthetic metadata is never used to verify or replace installed files.
$legacyFiles=@($MatlabBootstrapProjectionFiles | ForEach-Object { @{source=$_;sha256=('0'*64)} })
$legacyBootstrap=[pscustomobject]@{schema='wss-matlab-projection/v1';bootstrap_reference=$true;candidate=$null
    reference_source=@{repository='cwru-non-academic/Python_WSS_Integration_Lib';commit='79322a82d285cc526c77ea660beb2993cb04f5d9'}
    files=$legacyFiles;projection_sha256=(Get-MatlabProjectionDigest $legacyFiles)}
Assert-MatlabCandidate $candidate
$bad=$candidate | ConvertTo-Json | ConvertFrom-Json
$bad.repository='someone/other'
Assert-Rejected { Assert-MatlabCandidate $bad } 'untrusted producer'
$bad=$candidate | ConvertTo-Json | ConvertFrom-Json
$bad.run_id='latest'
Assert-Rejected { Assert-MatlabCandidate $bad } 'floating producer run'
$bad=$candidate | ConvertTo-Json | ConvertFrom-Json
$bad.sha256=''
Assert-Rejected { Assert-MatlabCandidate $bad } 'missing artifact checksum'
$bad=$candidate | ConvertTo-Json | ConvertFrom-Json
$bad.commit=('c'*40)
Assert-Rejected { Assert-MatlabSameCandidate $bad $candidate } 'different producer tuple'
Assert-Rejected { Assert-MatlabDiff @('src/+wss/StimulationController.m') (Get-MatlabAllowedWrapperPaths) } 'implementation changes in dependency PR'
Assert-Rejected { Assert-MatlabDiff @() (Get-MatlabAllowedWrapperPaths) } 'empty promotion'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('wss-matlab-contract-'+[guid]::NewGuid())
$null=New-Item -ItemType Directory -Path $directory
try {
    foreach ($file in $MatlabProjectionFiles) {
        $target=Join-Path $directory $file
        $null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)
        [IO.File]::WriteAllText($target,'synthetic contract fixture: '+$file)
    }
    $files=@($MatlabProjectionFiles | ForEach-Object { @{source=$_;sha256=(Get-FileHash (Join-Path $directory $_)).Hash.ToLowerInvariant()} })
    $record=[pscustomobject]@{schema='wss-matlab-projection/v1';bootstrap_reference=$false;candidate=$candidate;files=$files;projection_sha256=(Get-MatlabProjectionDigest $files)}
    Assert-MatlabProjection $directory $record
    Assert-MatlabProjectionMetadata $record $record
    Assert-Rejected { Assert-MatlabProjectionMetadata $legacyBootstrap $record } 'legacy metadata alongside a declared candidate'
    $staleMetadata=$record | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $staleMetadata.files[0].sha256=('d'*64)
    Assert-Rejected { Assert-MatlabProjectionMetadata $staleMetadata $record } 'payload metadata hash mismatch'
    $oldFiles=@($record.files | Where-Object { $_.source -cnotlike 'backends/macos/*' })
    $oldCandidate=[pscustomobject]@{schema=$record.schema;bootstrap_reference=$false;candidate=$candidate;files=$oldFiles;projection_sha256=(Get-MatlabProjectionDigest $oldFiles)}
    $macFiles=@($MatlabProjectionFiles | Where-Object { $_ -clike 'backends/macos/*' })
    foreach ($file in $macFiles) { Remove-Item -LiteralPath (Join-Path $directory $file) }
    Assert-Rejected { Assert-MatlabProjection $directory $oldCandidate } 'new 25-file candidate omits macOS universal files'
    foreach ($file in $macFiles) { [IO.File]::WriteAllText((Join-Path $directory $file), 'synthetic contract fixture: '+$file) }
    [IO.File]::WriteAllText((Join-Path $directory 'WSS_Core_Interface.dll'),'altered')
    Assert-Rejected { Assert-MatlabProjection $directory $record } 'changed DLL hash'
    [IO.File]::WriteAllText((Join-Path $directory 'WSS_Core_Interface.dll'),'synthetic contract fixture: WSS_Core_Interface.dll')
    [IO.File]::WriteAllText((Join-Path $directory 'extra.dll'),'extra')
    Assert-Rejected { Assert-MatlabProjection $directory $record } 'extra DLL outside full inventory'
    Remove-Item -LiteralPath (Join-Path $directory 'extra.dll')
    Remove-Item -LiteralPath (Join-Path $directory $MatlabProjectionFiles[-1])
    Assert-Rejected { Assert-MatlabProjection $directory $record } 'missing runtime file'
} finally {
    $resolved=[IO.Path]::GetFullPath($directory)
    $temporary=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (!$resolved.StartsWith($temporary,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'wss-matlab-contract-*') { throw 'Unsafe temporary cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
$script:producerEvent='push'; $script:producerJob='success'; $script:artifactExpired=$false; $script:comparisonStatus='identical'; $script:coreHead=$candidate.commit
function Invoke-MatlabGh([string[]]$Arguments) {
    $uri=$Arguments[-1]
    if ($uri -like '*/actions/runs/123') {
        @{repository=@{full_name=$candidate.repository};head_repository=@{full_name=$candidate.repository};path='.github/workflows/artifacts.yml';head_sha=$candidate.commit;event=$script:producerEvent;head_branch='dev';status='completed';conclusion='success';run_attempt=1} | ConvertTo-Json -Depth 4
    } elseif ($uri -like '*/compare/*') { @{status=$script:comparisonStatus} | ConvertTo-Json }
    elseif ($uri -like '*/branches/dev') { @{commit=@{sha=$script:coreHead}} | ConvertTo-Json -Depth 3 }
    elseif ($uri -like '*/jobs*') {
        $names=@('Build and validate artifacts','Core conformance','Serial consumer (Windows)','Serial consumer (macOS)','Serial consumer (Linux)','BLE consumer (Windows)','BLE consumer (Linux)','Build macOS universal BLE bridge','BLE consumer (macOS x86_64)','BLE consumer (macOS arm64)','Core consumer (Windows)','Core consumer (macOS)','Core consumer (Linux)','Start routine downstream validation','BLE Consumer for Windows','BLE Consumer for Linux','BLE Consumer for Mac')
        @(@{jobs=@($names | ForEach-Object { @{name=$_;status='completed';conclusion=$script:producerJob} })}) | ConvertTo-Json -Depth 6 -AsArray
    } elseif ($uri -like '*/actions/artifacts/456') {
        @{expired=$script:artifactExpired;name='universal-release-assets';workflow_run=@{id='123';head_sha=$candidate.commit}} | ConvertTo-Json -Depth 4
    } elseif ($uri -like '*/actions/workflows/wss-compatibility.yml/runs*') {
        @(@{workflow_runs=$script:reviewedCiRuns}) | ConvertTo-Json -Depth 12 -AsArray
    } elseif ($uri -like '*/commits/*/pulls*') {
        $associationPages=[object[]]::new(1);$associationPages[0]=@($script:reviewedCommitPrs)
        ConvertTo-Json -InputObject $associationPages -Depth 12
    } elseif ($uri -like '*/git/trees/*') {
        @{sha=('7'*40);truncated=$script:stageTruncated;tree=$script:stageEntries} | ConvertTo-Json -Depth 5
    } elseif ($uri -like '*/contents/tools/ci/dev-propagation.json*') {
        if ($script:stageDenied) { throw 'Synthetic API denial must fail closed.' }
        @{type='file';encoding='base64';sha=('8'*40);content=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($script:stagePolicy | ConvertTo-Json -Depth 6)))} | ConvertTo-Json
    } else { throw "Unexpected offline API call: $uri" }
}
# The shared engine's exact-run event/source rejection is tested in Node. Feed
# this producer adapter its explicit requested run through the existing fixture.
function Wait-WssCiRun($Repository,$RunId,$SourceSha,$Workflow,$Event,$TimeoutSeconds) {
    $run=Invoke-MatlabGh -Arguments @('api',"repos/$Repository/actions/runs/$RunId")|ConvertFrom-Json
    if($Repository -cne $candidate.repository -or $RunId -cne $candidate.run_id -or $SourceSha -cne $candidate.commit -or $Workflow -cne 'artifacts.yml' -or $Event -cne $run.event){throw 'Synthetic shared producer boundary mismatch.'}
    $run
}
Assert-MatlabProducer $candidate
$script:producerEvent='pull_request'
Assert-Rejected { Assert-MatlabProducer $candidate } 'PR artifact as canonical dev evidence'
$script:producerEvent='push'; $script:producerJob='skipped'
Assert-Rejected { Assert-MatlabProducer $candidate } 'skipped producer context'
$script:producerJob='success'; $script:artifactExpired=$true
Assert-Rejected { Assert-MatlabProducer $candidate } 'expired producer artifact'
$previous=[pscustomobject]@{bootstrap_reference=$false;candidate=($candidate | ConvertTo-Json | ConvertFrom-Json);projection_sha256=('1'*64)}
$previous.candidate.commit=('c'*40)
$script:comparisonStatus='ahead'
Assert-MatlabForwardCandidate $previous $candidate ('2'*64)
$script:comparisonStatus='behind'
Assert-Rejected { Assert-MatlabForwardCandidate $previous $candidate ('2'*64) } 'older candidate rollback'
$script:comparisonStatus='diverged'
Assert-Rejected { Assert-MatlabForwardCandidate $previous $candidate ('2'*64) } 'conflicting candidate history'
$previous.candidate.commit=$candidate.commit
Assert-Rejected { Assert-MatlabForwardCandidate $previous $candidate ('2'*64) } 'same source with different payload'
Assert-MatlabForwardCandidate $previous $candidate $previous.projection_sha256
Assert-MatlabForwardCandidate $legacyBootstrap $candidate ('2'*64)
$script:coreHead=('d'*40)
Assert-Rejected { Assert-MatlabForwardCandidate $legacyBootstrap $candidate ('2'*64) } 'stale initial reference-copy promotion'
$human=[pscustomobject]@{merged=$true;merged_by=[pscustomobject]@{type='User';login='reviewer'};auto_merge=$null}
Assert-MatlabHumanMerge $human
$human.merged_by=[pscustomobject]@{type='Bot';login='automation[bot]'}
Assert-Rejected { Assert-MatlabHumanMerge $human } 'bot merge as human acceptance'
$human.merged_by=$null
Assert-Rejected { Assert-MatlabHumanMerge $human } 'missing merger identity'
$human.merged_by=[pscustomobject]@{type='User';login='reviewer'}; $human.auto_merge=@{enabled_by='reviewer'}
Assert-Rejected { Assert-MatlabHumanMerge $human } 'automatic merge configuration'
$script:producerEvent='push'; $script:producerJob='success'; $script:artifactExpired=$false; $script:comparisonStatus='identical'
$script:stageTruncated=$false; $script:stageEntries=@(); $script:stageDenied=$false
if (Test-MatlabStagedProducer $candidate) { throw 'A verified producer without policy must retain legacy fanout.' }
$script:stageEntries=@(@{path='tools/ci/dev-propagation.json';type='blob';sha=('8'*40)})
$script:stagePolicy=@{schema='wss-dev-stage/v1';channel='dev';libraries=@(@{id='matlab';repository=$MatlabWrapperRepository;fanout='dispatch-cli-promotion.yml';applications=@($MatlabCliRepository)})}
if (!(Test-MatlabStagedProducer $candidate)) { throw 'A staged producer must wait for the Core barrier.' }
$script:stageDenied=$true
Assert-Rejected { Test-MatlabStagedProducer $candidate } 'policy API denial as legacy fallback'
$script:stageDenied=$false; $script:stageTruncated=$true
Assert-Rejected { Test-MatlabStagedProducer $candidate } 'truncated producer tree as policy absence'
$script:stageTruncated=$false; $script:stagePolicy.libraries[0].applications=@('cwru-non-academic/OTHER')
Assert-Rejected { Test-MatlabStagedProducer $candidate } 'mismatched staged application receiver'
$reviewed=[pscustomobject]@{number=20;state='closed';merged_at='2026-11-03T20:24:25Z';merge_commit_sha=('f'*40)
    head=@{sha=('d'*40);ref='automation/matlab-wss-fixture';repo=@{full_name=$MatlabWrapperRepository}}
    base=@{ref='dev';repo=@{full_name=$MatlabWrapperRepository}}}
$success=[pscustomobject]@{id=789;repository=@{full_name=$MatlabWrapperRepository};head_repository=@{full_name=$MatlabWrapperRepository}
    path='.github/workflows/wss-compatibility.yml';event='pull_request';head_sha=$reviewed.head.sha;head_branch=$reviewed.head.ref
    status='completed';conclusion='success';pull_requests=@(@{number=20})}
$script:reviewedCiRuns=@($success);$script:reviewedCommitPrs=@($reviewed)
if ((Get-MatlabReviewedPullRequestRun $reviewed).id -ne 789) {throw 'Direct reviewed PR CI association failed.'}
$success.pull_requests=@()
if ((Get-MatlabReviewedPullRequestRun $reviewed).id -ne 789) {throw 'Unique immutable-commit association must survive an empty postmerge run array.'}
$script:reviewedCommitPrs=@()
Assert-Rejected { Get-MatlabReviewedPullRequestRun $reviewed } 'missing commit association'
$script:reviewedCommitPrs=@($reviewed,$reviewed)
Assert-Rejected { Get-MatlabReviewedPullRequestRun $reviewed } 'ambiguous commit association'
$mismatch=$reviewed | ConvertTo-Json -Depth 8 | ConvertFrom-Json;$mismatch.merge_commit_sha=('c'*40)
$script:reviewedCommitPrs=@($mismatch)
Assert-Rejected { Get-MatlabReviewedPullRequestRun $reviewed } 'association to another merge'
$script:reviewedCommitPrs=@($reviewed)
foreach ($field in @('head_sha','head_branch','path','event')) {
    $badRun=$success | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $badRun.$field='wrong'
    $script:reviewedCiRuns=@($badRun)
    Assert-Rejected { Get-MatlabReviewedPullRequestRun $reviewed } "wrong CI $field"
}
$newer=$success | ConvertTo-Json -Depth 8 | ConvertFrom-Json;$newer.id=790;$newer.conclusion='failure'
$script:reviewedCiRuns=@($success,$newer)
Assert-Rejected { Get-MatlabReviewedPullRequestRun $reviewed } 'older green CI hiding a newer failed exact-head run'
# Execute the actual late workflow command with metadata-only command stubs.
$workflow=Get-Content "$PSScriptRoot/../../workflows/dispatch-cli-promotion.yml" -Raw
$stepName='Recheck integration barrier immediately before application writes'
$step=[regex]::Match($workflow,"(?ms)^      - name: $stepName\r?\n(?<body>.*?)(?=^      - )")
$validateAt=$workflow.IndexOf('name: Verify actual reviewed wrapper merge')
$checkAt=$workflow.IndexOf("name: $stepName")
$tokenAt=$workflow.IndexOf('id: dispatch')
$postAt=$workflow.IndexOf('name: Dispatch through common durable-intent sender')
if (!$step.Success -or $validateAt -lt 0 -or $checkAt -le $validateAt -or $tokenAt -le $checkAt -or $postAt -le $tokenAt -or
    !$step.Groups['body'].Value.Contains("if: github.event_name == 'workflow_dispatch' && steps.validate.outputs.dispatch_needed == 'true'")) {
    throw 'The staged late barrier must gate write credentials after proof validation, preserving legacy/no-op skips.'
}
$run=[regex]::Match($step.Groups['body'].Value,'(?s)        run: \|\r?\n(?<command>.*)')
if (!$run.Success) { throw 'Late barrier command missing.' }
$lateCheck=[scriptblock]::Create($run.Groups['command'].Value)
$savedEnvironment=@{}
foreach ($key in @('GITHUB_EVENT_NAME','GITHUB_REF','GITHUB_WORKFLOW_REF','GITHUB_SHA','GITHUB_WORKSPACE','PRODUCER_RUN_ID','BARRIER_RUN_ID','BARRIER_ATTEMPT','GH_TOKEN','MATLAB_PREFLIGHT_TOKEN')) {
    $savedEnvironment[$key]=[Environment]::GetEnvironmentVariable($key)
}
$script:lateCore='a'*40; $script:lateInvalid=$false; $script:lateDenied=$false
$script:lateCalls=0; $script:lateWrites=0
function gh {
    $global:LASTEXITCODE=0
    if ('POST' -cin $args) { $script:lateWrites++; throw 'Barrier metadata checks must never write.' }
    if ($script:lateDenied) { $global:LASTEXITCODE=1; return '{}' }
    switch ($args[-1]) {
        'repos/cwru-non-academic/Matlab_WSS_Integration_Lib/branches/main' { @{commit=@{sha=$env:GITHUB_SHA}} | ConvertTo-Json -Depth 4 }
        'repos/cwru-non-academic/WSSCore/branches/main' { @{commit=@{sha=$script:lateCore}} | ConvertTo-Json -Depth 4 }
        default { throw "Unexpected late-check read: $($args[-1])" }
    }
}
function git { $global:LASTEXITCODE=0; if ('rev-parse' -cin $args) { $script:lateCore } }
$nativeNodePath=@(& node --print process.execPath)
if($LASTEXITCODE -ne 0 -or $nativeNodePath.Count -ne 1 -or $nativeNodePath[0] -isnot [string] -or
   ![IO.Path]::IsPathFullyQualified($nativeNodePath[0]) -or !(Test-Path -LiteralPath $nativeNodePath[0] -PathType Leaf)){
    throw 'Late-barrier fixture requires one successfully resolved absolute Node executable.'
}
$global:wssMatlabLateRealNode=$nativeNodePath[0]
function node {
    if($args[0] -cmatch '(channels|staging)\.mjs$'){ & $global:wssMatlabLateRealNode @args;return }
    $script:lateCalls++
    if (($args[1..4] -join ',') -cne 'verify-barrier,123,456,1') { throw 'Late barrier changed producer/correlation inputs.' }
    $global:LASTEXITCODE=if ($script:lateInvalid) {1} else {0}
    @{schema='wss-integration-barrier/v1';candidate=@{run_id='123'};
        integrations=@{matlab=@{repository='cwru-non-academic/Matlab_WSS_Integration_Lib'}}} | ConvertTo-Json -Depth 6
}
Push-Location $repositoryRoot
try {
    $env:GITHUB_EVENT_NAME='workflow_dispatch'; $env:GITHUB_REF='refs/heads/main'; $env:GITHUB_SHA='e'*40
    $env:GITHUB_WORKFLOW_REF="$MatlabWrapperRepository/.github/workflows/dispatch-cli-promotion.yml@refs/heads/main"
    $env:GITHUB_WORKSPACE=$repositoryRoot
    $env:PRODUCER_RUN_ID='123'; $env:BARRIER_RUN_ID='456'; $env:BARRIER_ATTEMPT='1'
    & $lateCheck
    $script:lateInvalid=$true
    Assert-Rejected { & $lateCheck } 'barrier moved after initial proof validation'
    $script:lateInvalid=$false; $script:lateDenied=$true
    Assert-Rejected { & $lateCheck } 'read token/API denial before write authorization'
    if ($script:lateCalls -ne 2 -or $script:lateWrites -ne 0) { throw 'Late barrier rejection retried verification or attempted a write.' }
} finally {
    Pop-Location
    Remove-Item Function:gh,Function:git,Function:node
    foreach ($key in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($key,$savedEnvironment[$key]) }
    $global:LASTEXITCODE=0
}

# Shared Node reference contracts cover the HTTP/discovery safety boundary on
# three hosted OSes. Retain MATLAB's adapter and queued-is-not-proof checks here.
$script:adapterRequest=$null
function Start-WssCiPreflight([string]$Repository,$Candidate,[string]$WrapperSha,[string]$ApplicationSha,[string]$DispatchToken) {
    $script:adapterRequest=@{repository=$Repository;candidate=$Candidate;wrapper_sha=$WrapperSha;application_sha=$ApplicationSha;token=$DispatchToken}
    [pscustomobject]@{id='900';status='queued';head_sha=$ApplicationSha}
}
function Wait-WssCiRun($Repository,$RunId,$SourceSha,$Workflow,$Event,$TimeoutSeconds){throw 'Shared fixture run remains queued; no conformance proof.'}
try {
    $env:GH_TOKEN='unit-only-reader';$env:MATLAB_PREFLIGHT_TOKEN='unit-only-scoped-token'
    foreach($role in @('wrapper','cli')){
        $script:adapterRequest=$null
        $repo=if($role -ceq 'wrapper'){$MatlabWrapperRepository}else{$MatlabCliRepository}
        $queued=Start-MatlabPreflight $repo $candidate ('c'*40) ('d'*40) -NoWait
        if($queued.status -cne 'queued' -or $script:adapterRequest.repository -cne $repo -or $script:adapterRequest.wrapper_sha -cne ('c'*40) -or $script:adapterRequest.application_sha -cne ('d'*40) -or $script:adapterRequest.token -cne 'unit-only-scoped-token' -or $env:GH_TOKEN -cne 'unit-only-reader'){throw 'MATLAB adapter changed source, queued state or scoped credentials.'}
        Assert-MatlabSameCandidate $script:adapterRequest.candidate $candidate
    }
    Assert-Rejected {Start-MatlabPreflight $MatlabCliRepository $candidate ('c'*40) ('d'*40)} 'queued is not successful acceptance'
    $script:adapterRequest=$null
    Assert-Rejected {Start-MatlabPreflight 'foreign/repository' $candidate ('c'*40) ('d'*40) -NoWait} 'foreign repository cannot dispatch'
    if($script:adapterRequest){throw 'Foreign repository reached the shared boundary.'}
}finally{
    Remove-Item Function:Start-WssCiPreflight,Function:Wait-WssCiRun
    . "$PSScriptRoot/../wss-ci/Preflight.ps1"
    foreach($key in $savedEnvironment.Keys){[Environment]::SetEnvironmentVariable($key,$savedEnvironment[$key])}
    $global:LASTEXITCODE=0
}
Write-Output 'PASS offline MATLAB provenance, exact inventory, hash, correlation and late barrier contracts. No runtime simulation is counted as conformance.'

$global:LASTEXITCODE=0 # Expected shared-validator rejection fixtures completed.
