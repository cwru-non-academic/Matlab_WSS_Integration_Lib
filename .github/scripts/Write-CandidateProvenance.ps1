param(
    [Parameter(Mandatory)][string]$CandidateJson,
    [Parameter(Mandatory)][ValidateSet('wrapper','cli')][string]$Role,
    [Parameter(Mandatory)][string]$WrapperSha,
    [Parameter(Mandatory)][string]$CliSha,
    [Parameter(Mandatory)][string]$EvidenceRoot,
    [Parameter(Mandatory)][string]$OutputPath
)
. "$PSScriptRoot/MatlabContract.ps1"
$candidate=$CandidateJson | ConvertFrom-Json
Assert-MatlabCandidate $candidate
Assert-MatlabSha $WrapperSha
Assert-MatlabSha $CliSha
$keys=@('repository','commit','run_id','artifact_id','archive','sha256')
if (@($candidate.PSObject.Properties.Name | Where-Object { $_ -cnotin ($keys+@('release_tag')) }).Count -or
    ($candidate.PSObject.Properties['release_tag'] -and $candidate.release_tag -cne '') -or $candidate.archive -cne 'WSS-Universal-ci.zip') { throw 'Only the canonical six-field dev candidate may be normalized.' }
$e=Get-Content (Join-Path $EvidenceRoot 'evidence.json') -Raw | ConvertFrom-Json
$projection=Get-Content (Join-Path $EvidenceRoot 'projection.json') -Raw | ConvertFrom-Json
$summaryPath=Join-Path $EvidenceRoot 'summary.json'
$summary=Get-Content $summaryPath -Raw | ConvertFrom-Json
$config=Read-MatlabConfig "$PSScriptRoot/../matlab-ci.json"
Assert-MatlabSameCandidate $e.candidate $candidate
Assert-MatlabSameCandidate $projection.candidate $candidate
$expectedTests=if ($Role -ceq 'wrapper') { 5 } else { 4 }
if ($e.schema -cne 'wss-matlab-evidence/v1' -or $e.execution -cne 'matlab-native' -or $e.role -cne $Role -or
    $e.wrapper_sha -cne $WrapperSha -or $e.cli_sha -cne $CliSha -or $e.fixture_sha -cne $config.fixture_commit -or $e.fixture_sha256 -cne $config.fixture_sha256 -or
    $e.matlab_release -cne $config.matlab_release -or (Get-FileHash $summaryPath).Hash.ToLowerInvariant() -cne $e.summary_sha256 -or
    $summary.testsPassed -ne $expectedTests -or $summary.scenariosPassed -ne 10 -or $summary.cases.Count -ne 10 -or
    @($summary.cases | Where-Object { $_.Passed -cne $true -or $_.Failure }).Count -or
    @(Compare-Object @($config.expected_cases) @($summary.cases.Id) -CaseSensitive).Count) { throw 'Normalized binding requires the full successful source-bound native proof.' }
if ($projection.bootstrap_reference -cne $false -or $projection.schema -cne 'wss-matlab-projection/v1' -or $projection.files.Count -ne $MatlabProjectionFiles.Count -or
    @(Compare-Object $MatlabProjectionFiles @($projection.files.source) -CaseSensitive).Count -or
    $projection.projection_sha256 -cne $e.projection_sha256 -or (Get-MatlabProjectionDigest $projection.files) -cne $projection.projection_sha256) { throw 'Rich native projection binding differs.' }
if (Test-Path -LiteralPath $OutputPath) { throw 'Normalized output must be new.' }
$normalized=[ordered]@{}
foreach ($key in $keys) { $normalized[$key]=[string]$candidate.$key }
$null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath)))
$normalized | ConvertTo-Json -Compress | Set-Content -LiteralPath $OutputPath
Write-Output 'Normalized the exact successful native candidate; richer proof remains mandatory.'
