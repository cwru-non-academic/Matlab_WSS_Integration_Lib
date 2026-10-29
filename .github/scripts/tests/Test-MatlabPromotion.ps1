# Offline contract tests only: synthetic files/API responses never count as runtime proof.
. "$PSScriptRoot/../MatlabPromotion.ps1"
function Assert-Rejected([scriptblock]$Action,[string]$Because) {
    $rejected=$false
    try { & $Action } catch { $rejected=$true }
    if (!$rejected) { throw "Must reject: $Because" }
}
$candidate=[pscustomobject]@{repository='cwru-non-academic/WSSCore';commit=('a'*40);run_id='123';artifact_id='456';archive='WSS-Universal-ci.zip';sha256=('b'*64)}
$repositoryRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$bootstrap=Get-Content (Join-Path $repositoryRoot '.github/matlab-candidate.json') -Raw | ConvertFrom-Json
Assert-MatlabProjection (Join-Path $repositoryRoot 'Cs_Libraries') $bootstrap
Write-Output 'PASS actual bootstrap payload manifest digest and full file hashes.'
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
        @{repository=@{full_name=$candidate.repository};head_repository=@{full_name=$candidate.repository};path='.github/workflows/artifacts.yml';head_sha=$candidate.commit;event=$script:producerEvent;head_branch='dev';status='completed';conclusion='success'} | ConvertTo-Json -Depth 4
    } elseif ($uri -like '*/compare/*') { @{status=$script:comparisonStatus} | ConvertTo-Json }
    elseif ($uri -like '*/branches/dev') { @{commit=@{sha=$script:coreHead}} | ConvertTo-Json -Depth 3 }
    elseif ($uri -like '*/jobs*') {
        $names=@('Build and validate artifacts','Core conformance','Serial consumer (Windows)','Serial consumer (macOS)','Serial consumer (Linux)','BLE consumer (Windows)','BLE consumer (Linux)','Build macOS universal BLE bridge','BLE consumer (macOS x86_64)','BLE consumer (macOS arm64)','Core consumer (Windows)','Core consumer (macOS)','Core consumer (Linux)','Start routine downstream validation')
        @(@{jobs=@($names | ForEach-Object { @{name=$_;conclusion=$script:producerJob} })}) | ConvertTo-Json -Depth 6 -AsArray
    } elseif ($uri -like '*/actions/artifacts/456') {
        @{expired=$script:artifactExpired;name='universal-release-assets';workflow_run=@{id='123';head_sha=$candidate.commit}} | ConvertTo-Json -Depth 4
    } else { throw "Unexpected offline API call: $uri" }
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
Assert-MatlabForwardCandidate $bootstrap $candidate ('2'*64)
$script:coreHead=('d'*40)
Assert-Rejected { Assert-MatlabForwardCandidate $bootstrap $candidate ('2'*64) } 'stale initial reference-copy promotion'
$human=[pscustomobject]@{merged=$true;merged_by=[pscustomobject]@{type='User';login='reviewer'};auto_merge=$null}
Assert-MatlabHumanMerge $human
$human.merged_by=[pscustomobject]@{type='Bot';login='automation[bot]'}
Assert-Rejected { Assert-MatlabHumanMerge $human } 'bot merge as human acceptance'
$human.merged_by=$null
Assert-Rejected { Assert-MatlabHumanMerge $human } 'missing merger identity'
$human.merged_by=[pscustomobject]@{type='User';login='reviewer'}; $human.auto_merge=@{enabled_by='reviewer'}
Assert-Rejected { Assert-MatlabHumanMerge $human } 'automatic merge configuration'
Write-Output 'PASS offline MATLAB provenance, exact inventory, hash and constrained-diff contracts. No runtime simulation is counted as conformance.'
