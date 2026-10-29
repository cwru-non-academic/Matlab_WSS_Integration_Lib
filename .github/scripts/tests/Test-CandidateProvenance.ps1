# Synthetic rejection fixtures only; never native conformance or live receipt evidence.
. "$PSScriptRoot/../MatlabContract.ps1"
function Reject([scriptblock]$Action) { $rejected=$false;try { &$Action } catch {$rejected=$true};if (!$rejected) {throw 'Expected normalized proof rejection.'} }
$work=Join-Path ([IO.Path]::GetTempPath()) ('matlab-normalized-contract-'+[guid]::NewGuid())
$null=New-Item -ItemType Directory -Path $work
try {
    $candidate=[ordered]@{repository='cwru-non-academic/WSSCore';commit=('a'*40);run_id='1';artifact_id='2';archive='WSS-Universal-ci.zip';sha256=('b'*64)}
    $files=@($MatlabProjectionFiles | ForEach-Object { @{source=$_;sha256=('c'*64)} })
    $projection=@{schema='wss-matlab-projection/v1';bootstrap_reference=$false;candidate=$candidate;files=$files;projection_sha256=(Get-MatlabProjectionDigest $files)}
    $config=Read-MatlabConfig "$PSScriptRoot/../../matlab-ci.json"
    $summary=@{testsPassed=5;scenariosPassed=10;cases=@($config.expected_cases | ForEach-Object { @{Id=$_;Passed=$true;Failure=''} })}
    $summary | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'summary.json')
    $evidence=@{schema='wss-matlab-evidence/v1';execution='matlab-native';role='wrapper';candidate=$candidate;wrapper_sha=('d'*40);cli_sha=('e'*40);fixture_sha=$config.fixture_commit;fixture_sha256=$config.fixture_sha256;matlab_release=$config.matlab_release;summary_sha256=(Get-FileHash (Join-Path $work 'summary.json')).Hash.ToLowerInvariant();projection_sha256=$projection.projection_sha256}
    $evidence | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'evidence.json')
    $projection | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'projection.json')
    $normalizerOptions=@{CandidateJson=($candidate|ConvertTo-Json -Compress);Role='wrapper';WrapperSha=('d'*40);CliSha=('e'*40);EvidenceRoot=$work}
    & "$PSScriptRoot/../Write-CandidateProvenance.ps1" @normalizerOptions -OutputPath (Join-Path $work 'candidate.json')
    $actual=Get-Content (Join-Path $work 'candidate.json') -Raw | ConvertFrom-Json
    Assert-MatlabSameCandidate $actual ([pscustomobject]$candidate)
    if (@($actual.PSObject.Properties).Count -ne 6) {throw 'Unexpected normalized fields.'}
    Reject { & "$PSScriptRoot/../Write-CandidateProvenance.ps1" @normalizerOptions -OutputPath (Join-Path $work 'candidate.json') }
    $wrong=[ordered]@{};foreach ($key in $candidate.Keys) { $wrong[$key]=$candidate[$key] };$wrong.commit=('f'*40)
    $bad=$normalizerOptions.Clone();$bad.CandidateJson=($wrong|ConvertTo-Json -Compress)
    Reject { & "$PSScriptRoot/../Write-CandidateProvenance.ps1" @bad -OutputPath (Join-Path $work 'wrong.json') }
    $summary.cases[0].Passed=$false
    $summary | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'summary.json')
    Reject { & "$PSScriptRoot/../Write-CandidateProvenance.ps1" @normalizerOptions -OutputPath (Join-Path $work 'failed.json') }
    Write-Output 'PASS normalized candidate rejection fixtures; no live proof emitted.'
} finally {
    $path=[IO.Path]::GetFullPath($work);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (!$path.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($path) -notlike 'matlab-normalized-contract-*') {throw 'Unsafe fixture cleanup path.'}
    Remove-Item -LiteralPath $path -Recurse -Force
}
