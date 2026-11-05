. "$PSScriptRoot/wss-ci/Evidence.ps1"
# Native compatibility evidence only; never a radio/device acceptance claim.
function Get-MatlabMacLane([ValidateSet('arm64','x86_64')][string]$Architecture) {
    if ($Architecture -ceq 'arm64') { return @{platform='MACA64';release='R2026b';runner='ARM64'} }
    @{platform='MACI64';release='R2025b';runner='X64'}
}
function Assert-MatlabMacLane($Lane,[ValidateSet('arm64','x86_64')][string]$Architecture,[switch]$AllowLegacy) {
    $expected=Get-MatlabMacLane $Architecture
    Assert-WssCiEvidenceFields $Lane @{schema='wss-matlab-macos-compatibility/v1';execution='matlab-native';architecture=$Architecture;platform=$expected.platform;runner_architecture=$expected.runner;matlab_release=$expected.release;serial='passed';hardware_connected=$false}
    if ($Lane.matlab_version -cnotmatch ('\('+[regex]::Escape($expected.release)+'\)(?: Update [1-9][0-9]*)?\z')) {throw "Wrong native macOS runtime version: $Architecture"}
    if ($Lane.ble -ceq 'passed' -and $Lane.backend -ceq 'WSS.Transport.BLE.MacOS') { return }
    if ($AllowLegacy -and $Lane.ble -ceq 'unsupported-by-legacy-payload') { return }
    throw "Packaged BLE compatibility did not pass: $Architecture"
}
function Assert-MatlabMacCoverage($Coverage,[switch]$AllowLegacy) {
    if ($Coverage.schema -cne 'wss-matlab-macos-coverage/v1' -or $Coverage.execution -cne 'matlab-native' -or
        $Coverage.hardware_connected -cne $false -or @($Coverage.architectures).Count -ne 2) { throw 'Both native macOS architectures are required.' }
    Assert-WssCiArchitecturePair $Coverage.architectures @('arm64','x86_64')
    foreach ($arch in @('arm64','x86_64')) {
        $lane=@($Coverage.architectures | Where-Object architecture -CEQ $arch)
        if ($lane.Count -ne 1) { throw "Missing or duplicate native macOS lane: $arch" }
        Assert-MatlabMacLane $lane[0] $arch -AllowLegacy:$AllowLegacy
    }
}
function Assert-MatlabMacJobs($Needs) {
    if ($Needs.'macos-native'.result -cne 'success') { throw 'A native macOS job failed, was cancelled, or was skipped.' }
}
