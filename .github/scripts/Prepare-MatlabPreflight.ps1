param(
    [Parameter(Mandatory)][ValidateSet('wrapper','cli')][string]$Role,
    [Parameter(Mandatory)][string]$WrapperRoot,
    [Parameter(Mandatory)][string]$CliRoot,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$CandidateJson,
    [Parameter(Mandatory)][string]$WrapperSha,
    [Parameter(Mandatory)][string]$CliSha
)
. "$PSScriptRoot/MatlabPromotion.ps1"
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REF -cne 'refs/heads/dev' -or $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch') { throw 'Only trusted dev dispatch may stage a candidate.' }
$own=if ($Role -ceq 'wrapper') { $WrapperRoot } else { $CliRoot }
$source=if ($Role -ceq 'wrapper') { $WrapperSha } else { $CliSha }
$repository=if ($Role -ceq 'wrapper') { $MatlabWrapperRepository } else { $MatlabCliRepository }
if ($env:GITHUB_REPOSITORY -cne $repository -or $env:GITHUB_SHA -cne $source) { throw 'Workflow/source identity mismatch.' }
$config=Read-MatlabConfig (Join-Path $own '.github/matlab-ci.json')
if (!$config.baseline_ready) { throw 'Candidate baseline activation remains pending.' }
Assert-MatlabSource $WrapperRoot $WrapperSha
Assert-MatlabSource $CliRoot $CliSha -IgnoreSubmodule
if ((Get-MatlabHead $MatlabWrapperRepository) -cne $WrapperSha -or (Get-MatlabHead $MatlabCliRepository) -cne $CliSha) { throw 'Source dev advanced before candidate validation.' }
if (Test-Path -LiteralPath $WorkRoot) { throw 'Preflight work root must be new.' }
New-Item -ItemType Directory -Path $WorkRoot | Out-Null
$candidate=$CandidateJson | ConvertFrom-Json
Assert-MatlabProducer $candidate
& "$PSScriptRoot/Resolve-WssRelease.ps1" -RunId $candidate.run_id -ExpectedArtifactId $candidate.artifact_id -ExpectedCommit $candidate.commit -ArchiveName $candidate.archive -ExpectedSha256 $candidate.sha256 -OutputRoot (Join-Path $WorkRoot 'resolved')
$resolved=Get-Content (Join-Path $WorkRoot 'resolved/candidate.json') -Raw | ConvertFrom-Json
Assert-MatlabSameCandidate $resolved $candidate
# The native suite is pinned by normalized UTF-8 source hash, independent of checkout EOL.
$suite=[IO.File]::ReadAllText((Join-Path $WrapperRoot $config.fixture_path)).Replace("`r`n","`n")
$suiteHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($suite))).ToLowerInvariant()
if ($suiteHash -cne $config.fixture_sha256) { throw 'Native canonical suite differs from the reviewed baseline.' }
$projection=New-MatlabProjection (Join-Path $WorkRoot 'resolved/extracted/WSS-Universal') $WrapperRoot (Join-Path $WorkRoot 'projection') $candidate
$projection | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $WorkRoot 'projection.json')
foreach ($file in $MatlabProjectionFiles) { Copy-Item -LiteralPath (Join-Path $WorkRoot "projection/$file") -Destination (Join-Path $WrapperRoot "$MatlabPluginPath/$file") }
Assert-MatlabProjection (Join-Path $WrapperRoot $MatlabPluginPath) $projection
# App tests use their real default submodule path, staged from an exact source checkout.
# Never rewrite the CLI index/gitlink: this disposable worktree change is validation only.
$link=Join-Path $CliRoot $MatlabGitlink
if (Test-Path -LiteralPath $link) {
    if (@(Get-ChildItem -LiteralPath $link -Force).Count) { throw 'Candidate CLI wrapper directory must be absent or empty before staging.' }
    Remove-Item -LiteralPath $link
}
$null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent $link)
Copy-Item -LiteralPath $WrapperRoot -Destination $link -Recurse
if ((Invoke-MatlabGit $link @('rev-parse','HEAD')).Trim() -cne $WrapperSha) { throw 'Staged CLI wrapper source mismatch.' }
$nativeRoot=if ($Role -ceq 'wrapper') { $WrapperRoot } else { $CliRoot }
"MATLAB_PREFLIGHT_ROOT=$nativeRoot" >> $env:GITHUB_ENV
"MATLAB_PREFLIGHT_ROLE=$Role" >> $env:GITHUB_ENV
"MATLAB_PREFLIGHT_WORK=$WorkRoot" >> $env:GITHUB_ENV
@{role=$Role;wrapper_sha=$WrapperSha;cli_sha=$CliSha;candidate=$candidate;projection_sha256=$projection.projection_sha256;fixture_sha=$config.fixture_commit;fixture_sha256=$suiteHash} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $WorkRoot 'staged.json')
