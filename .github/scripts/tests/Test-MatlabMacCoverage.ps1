# Hosted metadata regression fixtures; these are not native execution evidence.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../MatlabMacCoverage.ps1"
function Deny-MacFixture([scriptblock]$Action,[string]$Name) {
    $denied=$false;try { & $Action } catch { $denied=$true }
    if (!$denied) { throw "Expected rejection: $Name" }
}
function New-MacFixture {
    $lanes=@(foreach ($arch in @('arm64','x86_64')) {
        $policy=Get-MatlabMacLane $arch
        @{schema='wss-matlab-macos-compatibility/v1';execution='matlab-native';architecture=$arch
          platform=$policy.platform;runner_architecture=$policy.runner;matlab_release=$policy.release;matlab_version="25.2 ($($policy.release))"
          serial='passed';ble='passed';backend='WSS.Transport.BLE.MacOS';hardware_connected=$false}
    })
    @{schema='wss-matlab-macos-coverage/v1';execution='matlab-native';architectures=$lanes;hardware_connected=$false} | ConvertTo-Json -Depth 7 | ConvertFrom-Json
}
Assert-MatlabMacCoverage (New-MacFixture)
foreach ($state in @('failure','cancelled','skipped','pending','')) {
    Deny-MacFixture { Assert-MatlabMacJobs @{'macos-native'=@{result=$state}} } "job result $state"
}
Assert-MatlabMacJobs @{'macos-native'=@{result='success'}}
foreach ($field in @('execution','platform','runner_architecture','matlab_release','matlab_version','ble','backend')) {
    $fixture=New-MacFixture;$fixture.architectures[1].$field='wrong'
    Deny-MacFixture { Assert-MatlabMacCoverage $fixture } "Intel $field"
}
$fixture=New-MacFixture;$fixture.architectures=@($fixture.architectures[0])
Deny-MacFixture { Assert-MatlabMacCoverage $fixture } 'missing Intel'
$fixture=New-MacFixture;$fixture.architectures[1]=$fixture.architectures[0]
Deny-MacFixture { Assert-MatlabMacCoverage $fixture } 'duplicate ARM'
$fixture=New-MacFixture;$fixture.architectures[1].hardware_connected=$true
Deny-MacFixture { Assert-MatlabMacCoverage $fixture } 'radio claim'
$fixture=New-MacFixture;$fixture.architectures[1].ble='unsupported-by-legacy-payload'
Deny-MacFixture { Assert-MatlabMacCoverage $fixture } 'legacy payload as candidate proof'
Assert-MatlabMacCoverage $fixture -AllowLegacy
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('matlab-mac-contract-'+[guid]::NewGuid().ToString('N'))
$savedNeeds=$env:MACOS_NEEDS_JSON
try {
    $fixture=New-MacFixture
    foreach ($lane in $fixture.architectures) {
        $directory=Join-Path $temporary ('inputs/proof-'+$lane.architecture)
        $null=New-Item -ItemType Directory -Force -Path $directory
        $lane | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $directory 'compatibility.json')
    }
    $env:MACOS_NEEDS_JSON='{"macos-native":{"result":"success"}}'
    $parameters=@{EvidenceRoot=(Join-Path $temporary 'inputs');ArtifactPrefix='proof';OutputPath=(Join-Path $temporary 'output/compatibility.json')}
    & "$PSScriptRoot/../Complete-MatlabMacCoverage.ps1" @parameters
    Assert-MatlabMacCoverage (Get-Content $parameters.OutputPath -Raw | ConvertFrom-Json)
    $env:MACOS_NEEDS_JSON='{"macos-native":{"result":"skipped"}}'
    Deny-MacFixture { & "$PSScriptRoot/../Complete-MatlabMacCoverage.ps1" @parameters } 'actual aggregation after a skipped lane'
    $env:MACOS_NEEDS_JSON='{"macos-native":{"result":"success"}}'
    Remove-Item -LiteralPath (Join-Path $temporary 'inputs/proof-x86_64/compatibility.json')
    Deny-MacFixture { & "$PSScriptRoot/../Complete-MatlabMacCoverage.ps1" @parameters } 'actual aggregation missing Intel evidence'
} finally {
    $env:MACOS_NEEDS_JSON=$savedNeeds
    $resolved=[IO.Path]::GetFullPath($temporary)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (!$resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture cleanup escaped the temporary root.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Output 'Dual native macOS contract rejection fixtures passed; no native runtime proof claimed.'
