param(
    [Parameter(Mandatory)][string]$WrapperRoot,
    [Parameter(Mandatory)][string]$DiagnosticRoot
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/MatlabContract.ps1"
$wrapper=(Resolve-Path -LiteralPath $WrapperRoot).Path
if (Test-Path -LiteralPath $DiagnosticRoot) { throw 'Diagnostic staging must be new.' }
# Bind the actual payload to this wrapper's immutable source, not a second artifact.
$head=(Invoke-MatlabGit $wrapper @('rev-parse','HEAD')).Trim()
$manifestPath='Cs_Libraries/payload-source.json'
$manifestBlob=(Invoke-MatlabGit $wrapper @('rev-parse',"${head}:$manifestPath")).Trim()
$actualBlob=(Invoke-MatlabGit $wrapper @('hash-object',"--path=$manifestPath",(Join-Path $wrapper $manifestPath))).Trim()
if ($actualBlob -cne $manifestBlob) { throw 'Source manifest differs from exact wrapper HEAD.' }
$projection=(Invoke-MatlabGit $wrapper @('show',"${head}:$manifestPath")) -join "`n" | ConvertFrom-Json
Assert-MatlabProjection (Join-Path $wrapper 'Cs_Libraries') $projection
# Strict Mac diagnostics require the real native payload; never substitute a fixture.
if ($projection.bootstrap_reference) { throw 'Mac diagnostic requires a complete actual native payload.' }
$candidate=$projection.candidate
$staged=Join-Path $DiagnosticRoot 'wrapper'
$null=New-Item -ItemType Directory -Path $staged
$archive=Join-Path $DiagnosticRoot 'wrapper-source.tar'
& git -C $wrapper archive --format=tar --output=$archive $head -- src conformance managed Config
if ($LASTEXITCODE -ne 0) { throw 'Cannot archive the exact wrapper source.' }
& tar -xf $archive -C $staged
if ($LASTEXITCODE -ne 0) { throw 'Cannot extract the disposable wrapper source.' }
Copy-Item -LiteralPath (Join-Path $wrapper 'Cs_Libraries') -Destination (Join-Path $staged 'Cs_Libraries') -Recurse
if ((Invoke-MatlabGit $wrapper @('hash-object',"--path=$manifestPath",(Join-Path $staged $manifestPath))).Trim() -cne $manifestBlob) {
    throw 'Staged manifest differs from exact wrapper HEAD.'
}
$stagedProjection=Get-Content (Join-Path $staged $manifestPath) -Raw | ConvertFrom-Json
Assert-MatlabProjectionMetadata $stagedProjection $projection
Assert-MatlabProjection (Join-Path $staged 'Cs_Libraries') $projection
# Revalidate the authoritative input after copying, including its manifest/source identity.
Assert-MatlabProjection (Join-Path $wrapper 'Cs_Libraries') $projection
if ((Invoke-MatlabGit $wrapper @('rev-parse','HEAD')).Trim() -cne $head -or
    (Invoke-MatlabGit $wrapper @('hash-object',"--path=$manifestPath",(Join-Path $wrapper $manifestPath))).Trim() -cne $manifestBlob) {
    throw 'Original source or manifest changed during diagnostic staging.'
}
$evidence=Join-Path $DiagnosticRoot 'evidence'
$null=New-Item -ItemType Directory -Path $evidence
@{
    schema='wss-matlab-mac-artifact-diagnostic/v1'
    purpose='actual-product-copy-load-and-abi; not release acceptance or propagation proof'
    source_manifest_blob=$manifestBlob
    candidate=$candidate
    projection_sha256=$projection.projection_sha256
    files=$projection.files
    wrapper_sha=$head
    tooling_sha=(Invoke-MatlabGit (Join-Path $PSScriptRoot '../..') @('rev-parse','HEAD')).Trim()
    workflow_sha=$env:GITHUB_SHA
    workflow_run=$env:GITHUB_RUN_ID
    workflow_attempt=$env:GITHUB_RUN_ATTEMPT
    runner_architecture=$env:RUNNER_ARCH
} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidence 'diagnostic-source.json')
"MAC_DIAGNOSTIC_WRAPPER=$staged" >> $env:GITHUB_ENV
"MAC_DIAGNOSTIC_EVIDENCE=$evidence" >> $env:GITHUB_ENV
