param([Parameter(Mandatory)][string]$WorkRoot)
. "$PSScriptRoot/MatlabPromotion.ps1"
$staged=Get-Content (Join-Path $WorkRoot 'staged.json') -Raw | ConvertFrom-Json
$summaryPath=Join-Path $env:MATLAB_PREFLIGHT_ROOT ('artifacts/ci/'+$(if ($staged.role -ceq 'wrapper') { 'behavioral' } else { 'general' })+'.json')
$summary=Get-Content $summaryPath -Raw | ConvertFrom-Json
if ($summary.scenariosPassed -ne 10 -or $summary.cases.Count -ne 10 -or @($summary.cases | Where-Object { !$_.Passed -or $_.Failure }).Count) { throw 'Native candidate conformance incomplete.' }
$output=Join-Path $WorkRoot 'evidence'
New-Item -ItemType Directory -Path $output | Out-Null
Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $output 'summary.json')
Copy-Item -LiteralPath (Join-Path $WorkRoot 'projection.json') -Destination (Join-Path $output 'projection.json')
$e=[ordered]@{schema='wss-matlab-evidence/v1';execution='matlab-native';role=$staged.role;candidate=$staged.candidate
    wrapper_sha=$staged.wrapper_sha;cli_sha=$staged.cli_sha;projection_sha256=$staged.projection_sha256
    fixture_sha=$staged.fixture_sha;fixture_sha256=$staged.fixture_sha256;matlab_release='R2026b'
    run_repository=$env:GITHUB_REPOSITORY;run_id=$env:GITHUB_RUN_ID;run_sha=$env:GITHUB_SHA
    summary_sha256=(Get-FileHash (Join-Path $output 'summary.json')).Hash.ToLowerInvariant()}
if ($summary.matlab -cnotmatch '\(R2026b\)$') { throw 'Unexpected MATLAB release.' }
$e | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $output 'evidence.json')
