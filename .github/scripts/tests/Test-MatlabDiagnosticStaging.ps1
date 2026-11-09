# Actual-package copy and separate synthetic inventory fixtures; no native Mac execution.
param([string]$ActualWrapperRoot)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../MatlabContract.ps1"
$source=if ($ActualWrapperRoot) { (Resolve-Path $ActualWrapperRoot).Path } else { (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path }
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('matlab-diagnostic-'+[guid]::NewGuid().ToString('N'))
$fixture=Join-Path $temporary 'source'
$savedEnvironment=$env:GITHUB_ENV
$global:MatlabDiagnosticTestCopyMutation=$null
function Copy-Item {
    param([string]$LiteralPath,[string]$Destination,[switch]$Recurse)
    Microsoft.PowerShell.Management\Copy-Item @PSBoundParameters
    if ($global:MatlabDiagnosticTestCopyMutation) { & $global:MatlabDiagnosticTestCopyMutation $LiteralPath $Destination }
}
function Deny-Diagnostic([scriptblock]$Action,[string]$Expected) {
    $message=$null
    try { & $Action } catch { $message=$_.Exception.Message }
    if (!$message -or $message -notlike "*$Expected*") { throw "Expected '$Expected', got '$message'." }
}
function Stage-Diagnostic([string]$Name) {
    & "$PSScriptRoot/../Stage-MacArtifactDiagnostic.ps1" -WrapperRoot $fixture -DiagnosticRoot (Join-Path $temporary $Name)
}
function Restore-Payload {
    & git -C $fixture restore --source=HEAD -- Cs_Libraries
    if ($LASTEXITCODE -ne 0) { throw 'Fixture reset failed.' }
}
try {
    $null=New-Item -ItemType Directory -Path $temporary
    & git clone --quiet --shared $source $fixture
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create isolated source fixture.' }
    $env:GITHUB_ENV=Join-Path $temporary 'environment'
    $manifest=Join-Path $fixture 'Cs_Libraries/payload-source.json'
    $record=Get-Content $manifest -Raw | ConvertFrom-Json
    $originalManifest=(Get-FileHash $manifest).Hash
    Stage-Diagnostic 'valid'
    $copy=Join-Path $temporary 'valid/wrapper/Cs_Libraries'
    Assert-MatlabProjection $copy $record
    $evidence=Get-Content (Join-Path $temporary 'valid/evidence/diagnostic-source.json') -Raw | ConvertFrom-Json
    Assert-MatlabSameCandidate $evidence.candidate $record.candidate
    if ($evidence.wrapper_sha -cne (Invoke-MatlabGit $fixture @('rev-parse','HEAD')).Trim()) { throw 'Wrong source evidence.' }
    $hostPath='managed/ControllerHost.cs'
    $expectedHost=(Invoke-MatlabGit $fixture @('rev-parse',"HEAD:$hostPath")).Trim()
    $copiedHost=(Invoke-MatlabGit $fixture @('hash-object',"--path=$hostPath",(Join-Path $temporary "valid/wrapper/$hostPath"))).Trim()
    if ($copiedHost -cne $expectedHost) { throw 'Staged host is not the actual product owner source.' }
    $toolsHead=(Invoke-MatlabGit (Join-Path $PSScriptRoot '../../..') @('rev-parse','HEAD')).Trim()
    if ($evidence.tooling_sha -cne $toolsHead) { throw 'Tooling identity confused with product owner.' }
    # Mutating the staged copy must not change the authoritative original.
    [IO.File]::AppendAllText((Join-Path $copy 'backends/macos/libwss_macos_ble.dylib'),'mutation')
    Deny-Diagnostic { Assert-MatlabProjection $copy $record } 'Payload hash mismatch'
    Assert-MatlabProjection (Join-Path $fixture 'Cs_Libraries') $record
    if ((Get-FileHash $manifest).Hash -cne $originalManifest) { throw 'Original manifest changed.' }
    Deny-Diagnostic { Stage-Diagnostic 'valid' } 'staging must be new'
    Remove-Item -LiteralPath (Join-Path $fixture 'Cs_Libraries/backends/macos/libwss_macos_ble.dylib')
    Deny-Diagnostic { Stage-Diagnostic 'missing-native' } 'Exact full universal inventory'
    Restore-Payload
    [IO.File]::AppendAllText((Join-Path $fixture 'Cs_Libraries/backends/macos/libwss_macos_ble.dylib'),'mutation')
    Deny-Diagnostic { Stage-Diagnostic 'invalid-native' } 'Payload hash mismatch'
    # Even a self-consistent forged manifest cannot change the source-bound payload.
    foreach ($item in $record.files) { $item.sha256=(Get-FileHash (Join-Path $fixture "Cs_Libraries/$($item.source)")).Hash.ToLowerInvariant() }
    $record.projection_sha256=Get-MatlabProjectionDigest $record.files
    $record | ConvertTo-Json -Depth 8 | Set-Content $manifest
    Deny-Diagnostic { Stage-Diagnostic 'forged-manifest' } 'Source manifest differs'
    Restore-Payload
    $record=Get-Content $manifest -Raw | ConvertFrom-Json
    $record.candidate.commit='a'*40
    $record | ConvertTo-Json -Depth 8 | Set-Content $manifest
    Deny-Diagnostic { Stage-Diagnostic 'source-mismatch' } 'Source manifest differs'
    Restore-Payload
    $global:MatlabDiagnosticTestCopyMutation={ param($original,$destination) [IO.File]::AppendAllText((Join-Path $destination 'WSS_Core_Interface.dll'),'mutation') }
    Deny-Diagnostic { Stage-Diagnostic 'copy-corrupted' } 'Payload hash mismatch'
    $global:MatlabDiagnosticTestCopyMutation={ param($original,$destination) [IO.File]::AppendAllText((Join-Path $destination 'payload-source.json'),' ') }
    Deny-Diagnostic { Stage-Diagnostic 'staged-manifest-raced' } 'Staged manifest differs'
    $global:MatlabDiagnosticTestCopyMutation={ param($original,$destination) [IO.File]::AppendAllText((Join-Path $original 'WSS_Core_Interface.dll'),'mutation') }
    Deny-Diagnostic { Stage-Diagnostic 'original-raced' } 'Payload hash mismatch'
    Restore-Payload
    $global:MatlabDiagnosticTestCopyMutation={ param($original,$destination) [IO.File]::AppendAllText((Join-Path $original 'payload-source.json'),' ') }
    Deny-Diagnostic { Stage-Diagnostic 'manifest-raced' } 'Original source or manifest changed'
    Restore-Payload
    $global:MatlabDiagnosticTestCopyMutation=$null
    Assert-MatlabProjection (Join-Path $fixture 'Cs_Libraries') (Get-Content $manifest -Raw | ConvertFrom-Json)
    Write-Output 'Actual payload staging, source binding, mutation rejection and copy isolation passed; native Mac gates remain required.'
    # Separate synthetic inventory fixtures: never staged as actual-package evidence.
    $directory=Join-Path $temporary 'synthetic projection alias fixture'
    $null=New-Item -ItemType Directory -Path $directory
    foreach ($file in $MatlabProjectionFiles) {
        $target=Join-Path $directory $file
        $null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)
        [IO.File]::WriteAllText($target,'synthetic contract fixture: '+$file)
    }
    $candidate=[pscustomobject]@{repository='cwru-non-academic/WSSCore';commit=('a'*40);run_id='123';artifact_id='456';archive='WSS-Universal-ci.zip';sha256=('b'*64)}
    $files=@($MatlabProjectionFiles | ForEach-Object { @{source=$_;sha256=(Get-FileHash (Join-Path $directory $_)).Hash.ToLowerInvariant()} })
    $record=[pscustomobject]@{schema='wss-matlab-projection/v1';bootstrap_reference=$false;candidate=$candidate;files=$files;projection_sha256=(Get-MatlabProjectionDigest $files)}
    # Exercise the existing verifier, with staging and installed-sidecar inventories.
    $roots=@($directory,(Join-Path $directory '.'))
    if ($IsWindows) {
        $fileSystem=New-Object -ComObject Scripting.FileSystemObject
        try { $shortRoot=$fileSystem.GetFolder($directory).ShortPath }
        finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($fileSystem) }
        if ($shortRoot -cne $directory) { $roots+=@($shortRoot,(Resolve-Path -LiteralPath $shortRoot).Path) }
        else { Write-Output 'SKIP Windows 8.3 alias: short names unavailable on fixture volume.' }
    }
    foreach ($root in $roots) {
        Assert-MatlabProjection $root $record
        $sidecar=Join-Path $directory 'payload-source.json'
        [IO.File]::WriteAllText($sidecar,($record | ConvertTo-Json -Depth 8))
        try {
            Assert-MatlabProjection $root $record
            Assert-MatlabProjectionMetadata (Get-Content -LiteralPath $sidecar -Raw | ConvertFrom-Json) $record
            [IO.File]::WriteAllText((Join-Path $directory 'extra.dll'),'extra')
            try { Deny-Diagnostic { Assert-MatlabProjection $root $record } 'Exact full universal inventory' }
            finally { Remove-Item -LiteralPath (Join-Path $directory 'extra.dll') }
            $payload=Join-Path $directory $MatlabProjectionFiles[0]
            $original=[IO.File]::ReadAllBytes($payload)
            try {
                [IO.File]::WriteAllText($payload,'altered')
                Deny-Diagnostic { Assert-MatlabProjection $root $record } 'Payload hash mismatch'
            } finally { [IO.File]::WriteAllBytes($payload,$original) }
            Rename-Item -LiteralPath $sidecar -NewName 'PAYLOAD-SOURCE.JSON'
            Deny-Diagnostic { Assert-MatlabProjection $root $record } 'Exact full universal inventory'
            Rename-Item -LiteralPath (Join-Path $directory 'PAYLOAD-SOURCE.JSON') -NewName 'payload-source.json'
            $caseRecord=$record | ConvertTo-Json -Depth 8 | ConvertFrom-Json
            $caseRecord.files[0].source=$caseRecord.files[0].source.ToUpperInvariant()
            Deny-Diagnostic { Assert-MatlabProjection $root $caseRecord } 'Exact full universal inventory'
            Write-Output "PASS projection inventory path: $root"
        } finally {
            foreach ($name in @('payload-source.json','PAYLOAD-SOURCE.JSON')) {
                $path=Join-Path $directory $name
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
            }
        }
    }

} finally {
    $env:GITHUB_ENV=$savedEnvironment
    Remove-Item Function:Copy-Item
    Remove-Variable MatlabDiagnosticTestCopyMutation -Scope Global
    $resolved=[IO.Path]::GetFullPath($temporary)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (!$resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture cleanup escaped temporary root.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
