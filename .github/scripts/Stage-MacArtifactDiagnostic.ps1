param(
    [Parameter(Mandatory)][string]$WrapperRoot,
    [Parameter(Mandatory)][string]$DiagnosticRoot
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/MatlabContract.ps1"
$wrapper=(Resolve-Path -LiteralPath $WrapperRoot).Path
if (Test-Path -LiteralPath $DiagnosticRoot) { throw 'Diagnostic staging must be new.' }
$candidate=[pscustomobject]@{
    repository='cwru-non-academic/WSSCore'
    commit='0fb9ae74504e03dc63777ed70a6ec51c4369d5ab'
    run_id='40815407554'
    artifact_id='12872028256'
    archive='WSS-Universal-ci.zip'
    sha256='daa943d139a940a5fcf13d5162e04b033656270e4630af8adc99547d85692e7f'
}
& "$PSScriptRoot/Resolve-WssRelease.ps1" -RunId $candidate.run_id -ExpectedArtifactId $candidate.artifact_id -ExpectedCommit $candidate.commit -ArchiveName $candidate.archive -ExpectedSha256 $candidate.sha256 -OutputRoot (Join-Path $DiagnosticRoot 'resolved')
$resolved=Get-Content (Join-Path $DiagnosticRoot 'resolved/candidate.json') -Raw | ConvertFrom-Json
Assert-MatlabSameCandidate $resolved $candidate
$staged=Join-Path $DiagnosticRoot 'wrapper'
$null=New-Item -ItemType Directory -Path $staged
$archive=Join-Path $DiagnosticRoot 'wrapper-source.tar'
& git -C $wrapper archive --format=tar --output=$archive HEAD -- src conformance managed Config
if ($LASTEXITCODE -ne 0) { throw 'Cannot archive the exact wrapper source.' }
& tar -xf $archive -C $staged
if ($LASTEXITCODE -ne 0) { throw 'Cannot extract the disposable wrapper source.' }
$projection=New-MatlabProjection (Join-Path $DiagnosticRoot 'resolved/extracted/WSS-Universal') $wrapper (Join-Path $staged 'Cs_Libraries') $candidate
$projection | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $staged 'Cs_Libraries/payload-source.json')
Assert-MatlabProjection (Join-Path $staged 'Cs_Libraries') $projection
$evidence=Join-Path $DiagnosticRoot 'evidence'
$null=New-Item -ItemType Directory -Path $evidence
@{
    schema='wss-matlab-mac-artifact-diagnostic/v1'
    purpose='preparation-only-load-and-abi; not release acceptance or propagation proof'
    candidate=$candidate
    projection_sha256=$projection.projection_sha256
    files=$projection.files
    wrapper_sha=(Invoke-MatlabGit $wrapper @('rev-parse','HEAD')).Trim()
    tooling_sha=(Invoke-MatlabGit (Join-Path $PSScriptRoot '../..') @('rev-parse','HEAD')).Trim()
    workflow_sha=$env:GITHUB_SHA
    workflow_run=$env:GITHUB_RUN_ID
    workflow_attempt=$env:GITHUB_RUN_ATTEMPT
    runner_architecture=$env:RUNNER_ARCH
} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidence 'diagnostic-source.json')
"MAC_DIAGNOSTIC_WRAPPER=$staged" >> $env:GITHUB_ENV
"MAC_DIAGNOSTIC_EVIDENCE=$evidence" >> $env:GITHUB_ENV
