param(
    [Parameter(Mandatory)][string]$InputPath,
    [Parameter(Mandatory)][ValidateSet('arm64','x86_64')][string]$Architecture,
    [Parameter(Mandatory)][string]$OutputPath,
    [switch]$AllowLegacy
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/MatlabMacCoverage.ps1"
$raw=Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json
$expected=Get-MatlabMacLane $Architecture
$lane=[ordered]@{schema='wss-matlab-macos-compatibility/v1';execution='matlab-native';architecture=$Architecture
    platform=$raw.Platform;runner_architecture=$env:RUNNER_ARCH;matlab_release=$expected.release;matlab_version=$raw.matlab
    serial=$raw.Serial;ble=$raw.Ble;backend=$raw.Backend;hardware_connected=$false}
Assert-MatlabMacLane ([pscustomobject]$lane) $Architecture -AllowLegacy:$AllowLegacy
$null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath)))
$lane | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath
Write-Output "Native macOS $Architecture/$($expected.release): $($raw.Ble); no hardware connection."
