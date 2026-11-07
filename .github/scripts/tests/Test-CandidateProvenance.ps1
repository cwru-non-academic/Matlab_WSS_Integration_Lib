# Synthetic rejection fixtures only; never native conformance or live receipt evidence.
. "$PSScriptRoot/../MatlabContract.ps1"
function Reject([scriptblock]$Action) { $rejected=$false;try { &$Action } catch {$rejected=$true};if (!$rejected) {throw 'Expected normalized proof rejection.'} }
$work=Join-Path ([IO.Path]::GetTempPath()) ('matlab-normalized-contract-'+[guid]::NewGuid())
$null=New-Item -ItemType Directory -Path $work
try {
    # Synthetic immutable source contracts, never a live producer/native proof.
    $source=Join-Path $work 'source-contracts'
    $null=New-Item -ItemType Directory -Path (Join-Path $source 'ci') -Force
    & git -C $source init -q
    $sourceShas=@{}
    foreach ($role in @('wrapper','cli')) {
        $count=if ($role -ceq 'wrapper') { 8 } else { 9 }
        $ids=@(1..$count | ForEach-Object { "TestFixture/test$_" })
        @{schema='wss-matlab-native-tests/v1';role=$role;ids=$ids} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $source 'ci/native-test-contract.json')
        & git -C $source add ci/native-test-contract.json
        & git -C $source -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm "Synthetic $role contract"
        if ($LASTEXITCODE -ne 0) { throw 'Cannot commit synthetic source contract.' }
        $sourceShas[$role]=(Invoke-MatlabGit $source @('rev-parse','HEAD')).Trim()
    }
    function New-UnitResults([int]$Count) {
        @{ids=@(1..$Count | ForEach-Object { "TestFixture/test$_" });passed=@(1..$Count | ForEach-Object {$true});failed=@(1..$Count | ForEach-Object {$false});incomplete=@(1..$Count | ForEach-Object {$false})}
    }
    $candidate=[ordered]@{repository='cwru-non-academic/WSSCore';commit=('a'*40);run_id='1';artifact_id='2';archive='WSS-Universal-ci.zip';sha256=('b'*64)}
    $files=@($MatlabProjectionFiles | ForEach-Object { @{source=$_;sha256=('c'*64)} })
    $projection=@{schema='wss-matlab-projection/v1';bootstrap_reference=$false;candidate=$candidate;files=$files;projection_sha256=(Get-MatlabProjectionDigest $files)}
    $config=Read-MatlabConfig "$PSScriptRoot/../../matlab-ci.json"
    $summary=@{testsPassed=8;scenariosPassed=16;cases=@($config.expected_cases | ForEach-Object { @{Id=$_;Passed=$true;Failure=''} })}
    $summary.nativeTests=New-UnitResults 8
    $summary.profile=@{name='layered-v1';fixture_commit=$config.fixture_commit;fixture_sha256=$config.fixture_sha256;fixture_path=$config.fixture_path;candidate=$candidate;projection_sha256=$projection.projection_sha256;core_sha256=('c'*64)}
    $summary.multiScenariosPassed=16
    $summary.multiCases=@((@($config.legacy_expected_cases)+@($config.multidevice_expected_cases)) | ForEach-Object { @{Id=$_;Passed=$true;Failure=''} })
    $summary | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'summary.json')
    $evidence=@{schema='wss-matlab-evidence/v1';execution='matlab-native';role='wrapper';candidate=$candidate;wrapper_sha=$sourceShas.wrapper;cli_sha=$sourceShas.cli;fixture_sha=$config.fixture_commit;fixture_sha256=$config.fixture_sha256;matlab_release=$config.matlab_release;summary_sha256=(Get-FileHash (Join-Path $work 'summary.json')).Hash.ToLowerInvariant();projection_sha256=$projection.projection_sha256}
    $evidence | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'evidence.json')
    $projection | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'projection.json')
    $normalizerOptions=@{CandidateJson=($candidate|ConvertTo-Json -Compress);Role='wrapper';WrapperSha=$sourceShas.wrapper;CliSha=$sourceShas.cli;EvidenceRoot=$work;SourceRoot=$source}
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
            & git clone --quiet --no-checkout $source $env:MATLAB_PREFLIGHT_ROOT
            if ($LASTEXITCODE -ne 0) { throw 'Cannot clone synthetic immutable source.' }
            $ciRoot=Join-Path $env:MATLAB_PREFLIGHT_ROOT 'artifacts/ci'
            $null=New-Item -ItemType Directory -Path $ciRoot -Force
            $staged=@{role=$case.role;candidate=$candidate;wrapper_sha=$sourceShas.wrapper;cli_sha=$sourceShas.cli;projection_sha256=$projection.projection_sha256;fixture_sha=$config.fixture_commit;fixture_sha256=$config.fixture_sha256}
            $staged | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $bindingRoot 'staged.json')
            $projection | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $bindingRoot 'projection.json')
            $boundSummary=$summary.Clone();$boundSummary.matlab=$case.version;$boundSummary.testsPassed=if ($case.role -ceq 'wrapper') {8} else {9};$boundSummary.nativeTests=New-UnitResults $boundSummary.testsPassed
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
    # Match the hosted invocation: immutable WSS_TARGET_ROOT, no SourceRoot argument/token.
    $priorTarget=$env:WSS_TARGET_ROOT;$priorGh=$env:GH_TOKEN;$priorGithub=$env:GITHUB_TOKEN
    try {
        $env:WSS_TARGET_ROOT=$source;$env:GH_TOKEN=$null;$env:GITHUB_TOKEN=$null
        function gh { throw 'Unexpected remote gh lookup in source-root normalization.' }
        $workflowOptions=$normalizerOptions.Clone();$workflowOptions.Remove('SourceRoot')
        & "$PSScriptRoot/../Write-CandidateProvenance.ps1" @workflowOptions -OutputPath (Join-Path $work 'workflow-no-token.json')
    } finally {
        Remove-Item Function:gh
        $env:WSS_TARGET_ROOT=$priorTarget;$env:GH_TOKEN=$priorGh;$env:GITHUB_TOKEN=$priorGithub
    }
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
    $summary.testsPassed=8
    $summary.cases[0].Passed=$false
    $summary | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'summary.json')
    $evidence.summary_sha256=(Get-FileHash (Join-Path $work 'summary.json')).Hash.ToLowerInvariant()
    $evidence | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'evidence.json')
    Reject { & "$PSScriptRoot/../Write-CandidateProvenance.ps1" @normalizerOptions -OutputPath (Join-Path $work 'failed.json') }
    $summary.cases[0].Passed=$true
    $summary.testsPassed=9
    $summary.nativeTests=New-UnitResults 9
    $summary | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'summary.json')
    $evidence.role='cli'
    $evidence.summary_sha256=(Get-FileHash (Join-Path $work 'summary.json')).Hash.ToLowerInvariant()
    $evidence | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $work 'evidence.json')
    $normalizerOptions.Role='cli'
    & "$PSScriptRoot/../Write-CandidateProvenance.ps1" @normalizerOptions -OutputPath (Join-Path $work 'cli.json')
    Assert-MatlabSameCandidate (Get-Content (Join-Path $work 'cli.json') -Raw | ConvertFrom-Json) ([pscustomobject]$candidate)
    $priorTarget=$env:WSS_TARGET_ROOT;$priorGh=$env:GH_TOKEN;$priorGithub=$env:GITHUB_TOKEN
    try {
        $env:WSS_TARGET_ROOT=$source;$env:GH_TOKEN=$null;$env:GITHUB_TOKEN=$null
        function gh { throw 'Unexpected remote gh lookup in CLI source-root normalization.' }
        $workflowOptions=$normalizerOptions.Clone();$workflowOptions.Remove('SourceRoot')
        & "$PSScriptRoot/../Write-CandidateProvenance.ps1" @workflowOptions -OutputPath (Join-Path $work 'cli-workflow-no-token.json')
    } finally {
        Remove-Item Function:gh
        $env:WSS_TARGET_ROOT=$priorTarget;$env:GH_TOKEN=$priorGh;$env:GITHUB_TOKEN=$priorGithub
    }
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
