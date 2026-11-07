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
    $summary=@{testsPassed=(Get-MatlabExpectedNativeTests 'wrapper');scenariosPassed=16;cases=@($config.expected_cases | ForEach-Object { @{Id=$_;Passed=$true;Failure=''} })}
    $summary.profile=@{name='layered-v1';candidate=$candidate;projection_sha256=$projection.projection_sha256;core_sha256=('c'*64)}
    $summary.multiScenariosPassed=16
    $summary.multiCases=@((@($config.legacy_expected_cases)+@($config.multidevice_expected_cases)) | ForEach-Object { @{Id=$_;Passed=$true;Failure=''} })
    $summary | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'summary.json')
    $evidence=@{schema='wss-matlab-evidence/v1';execution='matlab-native';role='wrapper';candidate=$candidate;wrapper_sha=('d'*40);cli_sha=('e'*40);fixture_sha=$config.fixture_commit;fixture_sha256=$config.fixture_sha256;matlab_release=$config.matlab_release;summary_sha256=(Get-FileHash (Join-Path $work 'summary.json')).Hash.ToLowerInvariant();projection_sha256=$projection.projection_sha256}
    $evidence | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'evidence.json')
    $projection | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'projection.json')
    $normalizerOptions=@{CandidateJson=($candidate|ConvertTo-Json -Compress);Role='wrapper';WrapperSha=('d'*40);CliSha=('e'*40);EvidenceRoot=$work}
    # Exercise the actual shared binder, including the official CI Update suffix.
    $previousRoot=$env:MATLAB_PREFLIGHT_ROOT
    try {
        $releaseCases=@(
            @{role='wrapper';version='26.2.0.3386108 (R2026b)';accepted=$true},
            @{role='wrapper';version='26.2.0.3433840 (R2026b) Update 1';accepted=$true},
            @{role='cli';version='26.2.0.3433840 (R2026b) Update 1';accepted=$true},
            @{role='wrapper';version='26.1.0.3433840 (R2026a) Update 1';accepted=$false},
            @{role='wrapper';version='26.2.0.3433840 (R2026b) Update 1 extra';accepted=$false},
            @{role='wrapper';version='26.2.0.3433840 (R2026b) Update 0';accepted=$false}
        )
        foreach ($case in $releaseCases) {
            $bindingRoot=Join-Path $work ([guid]::NewGuid().ToString())
            $env:MATLAB_PREFLIGHT_ROOT=Join-Path $bindingRoot 'source'
            $ciRoot=Join-Path $env:MATLAB_PREFLIGHT_ROOT 'artifacts/ci'
            $null=New-Item -ItemType Directory -Path $ciRoot -Force
            $staged=@{role=$case.role;candidate=$candidate;wrapper_sha=('d'*40);cli_sha=('e'*40);projection_sha256=$projection.projection_sha256;fixture_sha=$config.fixture_commit;fixture_sha256=$config.fixture_sha256}
            $staged | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $bindingRoot 'staged.json')
            $projection | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $bindingRoot 'projection.json')
            $boundSummary=$summary.Clone();$boundSummary.matlab=$case.version;$boundSummary.testsPassed=Get-MatlabExpectedNativeTests $case.role
            $summaryFile=Join-Path $ciRoot $(if ($case.role -ceq 'wrapper') {'behavioral.json'} else {'general.json'})
            $boundSummary | ConvertTo-Json -Depth 8 | Set-Content $summaryFile
            if ($case.accepted) {
                & "$PSScriptRoot/../Complete-MatlabPreflight.ps1" -WorkRoot $bindingRoot
                $bound=Get-Content (Join-Path $bindingRoot 'evidence/evidence.json') -Raw | ConvertFrom-Json
                if ($bound.matlab_release -cne 'R2026b' -or $bound.summary_sha256 -cne (Get-FileHash $summaryFile).Hash.ToLowerInvariant()) {throw 'Release binding changed the exact release or summary hash.'}
            } else {
                Reject { & "$PSScriptRoot/../Complete-MatlabPreflight.ps1" -WorkRoot $bindingRoot }
                if (Test-Path (Join-Path $bindingRoot 'evidence/evidence.json')) {throw 'Rejected release emitted bound evidence.'}
            }
        }
    } finally { $env:MATLAB_PREFLIGHT_ROOT=$previousRoot }
    & "$PSScriptRoot/../Write-CandidateProvenance.ps1" @normalizerOptions -OutputPath (Join-Path $work 'candidate.json')
    $actual=Get-Content (Join-Path $work 'candidate.json') -Raw | ConvertFrom-Json
    Assert-MatlabSameCandidate $actual ([pscustomobject]$candidate)
    if (@($actual.PSObject.Properties).Count -ne 6) {throw 'Unexpected normalized fields.'}
    Reject { & "$PSScriptRoot/../Write-CandidateProvenance.ps1" @normalizerOptions -OutputPath (Join-Path $work 'candidate.json') }
    $wrong=[ordered]@{};foreach ($key in $candidate.Keys) { $wrong[$key]=$candidate[$key] };$wrong.commit=('f'*40)
    $bad=$normalizerOptions.Clone();$bad.CandidateJson=($wrong|ConvertTo-Json -Compress)
    Reject { & "$PSScriptRoot/../Write-CandidateProvenance.ps1" @bad -OutputPath (Join-Path $work 'wrong.json') }
    $summary.testsPassed=5
    $summary | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'summary.json')
    $evidence.summary_sha256=(Get-FileHash (Join-Path $work 'summary.json')).Hash.ToLowerInvariant()
    $evidence | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'evidence.json')
    Reject { & "$PSScriptRoot/../Write-CandidateProvenance.ps1" @normalizerOptions -OutputPath (Join-Path $work 'stale-wrapper-count.json') }
    $summary.testsPassed=Get-MatlabExpectedNativeTests 'wrapper'
    $summary.cases[0].Passed=$false
    $summary | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'summary.json')
    $evidence.summary_sha256=(Get-FileHash (Join-Path $work 'summary.json')).Hash.ToLowerInvariant()
    $evidence | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'evidence.json')
    Reject { & "$PSScriptRoot/../Write-CandidateProvenance.ps1" @normalizerOptions -OutputPath (Join-Path $work 'failed.json') }
    $summary.cases[0].Passed=$true
    $summary.testsPassed=Get-MatlabExpectedNativeTests 'cli'
    $summary | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'summary.json')
    $evidence.role='cli'
    $evidence.summary_sha256=(Get-FileHash (Join-Path $work 'summary.json')).Hash.ToLowerInvariant()
    $evidence | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'evidence.json')
    $normalizerOptions.Role='cli'
    & "$PSScriptRoot/../Write-CandidateProvenance.ps1" @normalizerOptions -OutputPath (Join-Path $work 'cli.json')
    Assert-MatlabSameCandidate (Get-Content (Join-Path $work 'cli.json') -Raw | ConvertFrom-Json) ([pscustomobject]$candidate)
    $summary.testsPassed=4
    $summary | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'summary.json')
    $evidence.summary_sha256=(Get-FileHash (Join-Path $work 'summary.json')).Hash.ToLowerInvariant()
    $evidence | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'evidence.json')
    Reject { & "$PSScriptRoot/../Write-CandidateProvenance.ps1" @normalizerOptions -OutputPath (Join-Path $work 'stale-cli-count.json') }
    Write-Output 'PASS normalized candidate rejection fixtures; no live proof emitted.'
} finally {
    $path=[IO.Path]::GetFullPath($work);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (!$path.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($path) -notlike 'matlab-normalized-contract-*') {throw 'Unsafe fixture cleanup path.'}
    Remove-Item -LiteralPath $path -Recurse -Force
}
