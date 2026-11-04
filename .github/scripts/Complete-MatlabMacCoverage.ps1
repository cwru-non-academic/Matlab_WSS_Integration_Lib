param(
    [Parameter(Mandatory)][string]$EvidenceRoot,
    [Parameter(Mandatory)][string]$ArtifactPrefix,
    [Parameter(Mandatory)][string]$OutputPath,
    [switch]$AllowLegacy
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/MatlabMacCoverage.ps1"
Assert-MatlabMacJobs ($env:MACOS_NEEDS_JSON | ConvertFrom-Json)
$entries=@(Get-ChildItem -LiteralPath $EvidenceRoot -Force)
$expected=@('arm64','x86_64' | ForEach-Object { "$ArtifactPrefix-$_" })
if ($entries.Count -ne 2 -or @($entries | Where-Object { !$_.PSIsContainer }).Count -or
    @(Compare-Object $expected @($entries.Name) -CaseSensitive).Count) { throw 'Missing, ambiguous or extra architecture evidence.' }
$lanes=@()
foreach ($arch in @('arm64','x86_64')) {
    $directory=Join-Path $EvidenceRoot "$ArtifactPrefix-$arch"
    $files=@(Get-ChildItem -LiteralPath $directory -Force)
    if ($files.Count -ne 1 -or $files[0].PSIsContainer -or $files[0].Name -cne 'compatibility.json') { throw "Incomplete native evidence: $arch" }
    $lane=Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
    Assert-MatlabMacLane $lane $arch -AllowLegacy:$AllowLegacy
    $lanes+= $lane
}
$coverage=[ordered]@{schema='wss-matlab-macos-coverage/v1';execution='matlab-native';architectures=$lanes;hardware_connected=$false}
Assert-MatlabMacCoverage ([pscustomobject]$coverage) -AllowLegacy:$AllowLegacy
$null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath)))
$coverage | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $OutputPath
foreach ($lane in $lanes) { Write-Output "$($lane.architecture) / $($lane.matlab_release): $($lane.ble)" }
