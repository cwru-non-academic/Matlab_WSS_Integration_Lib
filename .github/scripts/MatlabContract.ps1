Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Universal-WssFiles.ps1"
$MatlabWrapperRepository = 'cwru-non-academic/Matlab_WSS_Integration_Lib'
$MatlabCliRepository = 'cwru-non-academic/CLI_Matlab_WSS_Application'
$MatlabApplications = [ordered]@{
    cli = [pscustomobject]@{ role='cli'; repository=$MatlabCliRepository; gitlink='external/wss-matlab-wrapper'; source_field='cli_sha'; acceptance='CLI general conformance' }
}
function Get-MatlabApplication([ValidateSet('cli')][string]$Role) {
    $MatlabApplications[$Role]
}
$MatlabGitlink = 'external/wss-matlab-wrapper'
$MatlabPluginPath = 'Cs_Libraries'
$MatlabProjectionFiles = @($WssUniversalFiles)

function Invoke-MatlabGh([string[]]$Arguments) {
    $response = & gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw "GitHub operation failed: $($Arguments[0..([Math]::Min(1,$Arguments.Count-1))] -join ' ')" }
    $response
}
function Invoke-MatlabGit([string]$Root, [string[]]$Arguments) {
    $response = & git -C $Root @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Git operation failed: $($Arguments[0])" }
    $response
}
function Assert-MatlabSha([string]$Sha) {
    if ($Sha -cnotmatch '^[0-9a-f]{40}$') { throw 'A full lowercase source SHA is required.' }
}
function Assert-MatlabCandidate($Candidate) {
    if ($Candidate.repository -cne 'cwru-non-academic/WSSCore') { throw 'Unexpected producer.' }
    Assert-MatlabSha $Candidate.commit
    foreach ($field in @('run_id','artifact_id')) {
        if ([string]$Candidate.$field -cnotmatch '^[1-9][0-9]*$') { throw "Invalid candidate $field." }
    }
    if ($Candidate.archive -cnotmatch '^WSS-Universal-[A-Za-z0-9._-]+\.zip$' -or
        $Candidate.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid archive/hash.' }
}
function Assert-MatlabSameCandidate($Actual, $Expected) {
    Assert-MatlabCandidate $Actual
    foreach ($field in @('repository','commit','run_id','artifact_id','archive','sha256')) {
        if ([string]$Actual.$field -cne [string]$Expected.$field) { throw "Candidate mismatch: $field" }
    }
}
function Get-MatlabProjectionDigest($Files) {
    $lines=[string[]]@($Files | ForEach-Object { "$($_.source)|$($_.sha256)" }); [Array]::Sort($lines,[StringComparer]::Ordinal)
    $text=$lines -join "`n"
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).ToLowerInvariant()
}
function Assert-MatlabProjection([string]$Root, $Record) {
    if ($Record.schema -cne 'wss-matlab-projection/v1') { throw 'Invalid Matlab payload schema.' }
    if (!$Record.bootstrap_reference) { Assert-MatlabCandidate $Record.candidate }
    $actual = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.FullName -cne (Join-Path $Root 'payload-source.json') } | ForEach-Object { [IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/') })
    if (@(Compare-Object $MatlabProjectionFiles $actual -CaseSensitive).Count -ne 0 -or $Record.files.Count -ne $MatlabProjectionFiles.Count -or
        @(Compare-Object $MatlabProjectionFiles @($Record.files.source) -CaseSensitive).Count -ne 0) { throw 'Exact full universal inventory required; no fallback/extra files.' }
    foreach ($item in $Record.files) {
        if ((Get-FileHash -LiteralPath (Join-Path $Root $item.source)).Hash.ToLowerInvariant() -cne $item.sha256) { throw "Payload hash mismatch: $($item.source)" }
    }
    if ((Get-MatlabProjectionDigest $Record.files) -cne $Record.projection_sha256) { throw 'Payload digest mismatch.' }
}
function New-MatlabProjection([string]$ArtifactRoot, [string]$WrapperRoot, [string]$Destination, $Candidate) {
    Assert-MatlabCandidate $Candidate
    if (Test-Path -LiteralPath $Destination) { throw 'Payload destination must be new.' }
    $inventory = @(Get-ChildItem -LiteralPath $ArtifactRoot -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($ArtifactRoot,$_.FullName).Replace('\','/') })
    if (@(Compare-Object $MatlabProjectionFiles $inventory -CaseSensitive).Count -ne 0) { throw 'Exact full universal inventory required.' }
    New-Item -ItemType Directory -Path $Destination | Out-Null
    $files = @()
    foreach ($source in $MatlabProjectionFiles) {
        $target = Join-Path $Destination $source
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath (Join-Path $ArtifactRoot $source) -Destination $target
        $files += [ordered]@{ source=$source; sha256=(Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() }
    }
    $record = [pscustomobject][ordered]@{ schema='wss-matlab-projection/v1'; bootstrap_reference=$false; candidate=$Candidate; projection_sha256=(Get-MatlabProjectionDigest $files); files=$files }
    Assert-MatlabProjection $Destination $record
    $record
}
function Read-MatlabConfig([string]$Path) {
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($config.schema -cne 'wss-matlab-ci/v1' -or $config.branch -cne 'dev' -or $config.automated_execution -cne 'matlab-native' -or
        $config.matlab_release -cne 'R2026b' -or $config.dotnet_sdk -cne '8.0.x' -or $config.expected_cases.Count -ne 10 -or
        $config.fixture_repository -cne $MatlabWrapperRepository -or $config.fixture_path -cne 'conformance/runConformance.m') { throw 'Unexpected native MATLAB CI contract.' }
    Assert-MatlabSha $config.fixture_commit
    if ($config.fixture_sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Missing native suite digest.' }
    $config
}
